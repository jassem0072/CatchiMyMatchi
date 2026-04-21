from __future__ import annotations

import json
import logging
import os
import tempfile
import time
from typing import Any

import cv2
import numpy as np
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from deep_sort_realtime.deepsort_tracker import DeepSort
from ultralytics import YOLO

from .calibration import CalibrationModel, build_calibration
from .cuts import frame_histogram, is_cut
from .logging_utils import setup_logging
from .metrics import compute_metrics
from .schemas import MergeRequest, MergeResponse, ProcessChunkRequest, ProcessChunkResponse
from .tracking import TargetState, iou_xywh, reattach_by_iou, xyxy_to_xywh
from .video_io import resolve_local_video

logger = logging.getLogger(__name__)

YOLO_MODEL_NAME = os.getenv("SCOUTAI_YOLO_MODEL", "yolov8s.pt")
YOLO_CONF = float(os.getenv("SCOUTAI_YOLO_CONF", "0.15"))
YOLO_IMG_SIZE_ENV = os.getenv("SCOUTAI_YOLO_IMG_SIZE", "").strip()
YOLO_IMG_SIZE = int(YOLO_IMG_SIZE_ENV) if YOLO_IMG_SIZE_ENV else None

# Singleton model — loaded once at startup, reused across all requests.
_yolo_model: YOLO | None = None


def _get_model() -> YOLO:
    global _yolo_model
    if _yolo_model is None:
        _yolo_model = YOLO(YOLO_MODEL_NAME)
    return _yolo_model

origins_env = os.getenv("SCOUTAI_ALLOWED_ORIGINS", "*").strip()
if origins_env == "*":
    allow_origins = ["*"]
else:
    allow_origins = [o.strip() for o in origins_env.split(",") if o.strip()]

app = FastAPI(title="ScoutAI Video Analysis", version="0.1.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=allow_origins,
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
def _startup() -> None:
    setup_logging()
    _get_model()  # pre-warm: load weights once so first request isn't slow


def _get_video_fps(cap: cv2.VideoCapture) -> float:
    fps = cap.get(cv2.CAP_PROP_FPS)
    if fps is None or fps <= 1e-3:
        return 25.0
    return float(fps)


def _run_detection(model: YOLO, frame_bgr: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    # returns (xyxy Nx4, conf Nx1)
    predict_kwargs: dict[str, Any] = {"verbose": False, "conf": YOLO_CONF}
    if YOLO_IMG_SIZE:
        predict_kwargs["imgsz"] = YOLO_IMG_SIZE
    res = model.predict(frame_bgr, **predict_kwargs)[0]
    if res.boxes is None or res.boxes.xyxy is None:
        return np.zeros((0, 4), dtype=float), np.zeros((0,), dtype=float)

    xyxy = res.boxes.xyxy.cpu().numpy().astype(float)
    conf = res.boxes.conf.cpu().numpy().astype(float)
    cls = res.boxes.cls.cpu().numpy().astype(int)

    # keep "person" class (0 in COCO)
    keep = cls == 0
    xyxy = xyxy[keep]
    conf = conf[keep]
    return xyxy, conf


def _new_deepsort() -> DeepSort:
    # embedder=None disables the MobileNet appearance CNN — the code does its own
    # histogram-based re-ID, so the built-in embedder is redundant and very slow.
    # max_cosine_distance=999 effectively disables cosine matching (IoU + Kalman only).
    return DeepSort(max_age=90, n_init=1, embedder=None, max_cosine_distance=999.0)


def _reset_deepsort(tracker: DeepSort) -> DeepSort:
    # Reset tracks/metric without re-initializing the embedder (much faster).
    try:
        tracker.tracker.tracks = []
        tracker.tracker.del_tracks_ids = []
        tracker.tracker._next_id = 1
        tracker.tracker.metric.samples = {}
        return tracker
    except Exception:
        return _new_deepsort()


def _run_tracking(model: YOLO, tracker: DeepSort, frame_bgr: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    det_xyxy, det_conf = _run_detection(model, frame_bgr)
    bbs = []
    for bb, conf in zip(det_xyxy, det_conf):
        x1, y1, x2, y2 = bb
        bbs.append(([float(x1), float(y1), float(x2 - x1), float(y2 - y1)], float(conf), "person"))

    # Use bbox coordinates as lightweight embeddings (non-zero to avoid NaN in cosine).
    # Cosine matching is disabled via max_cosine_distance=999, so these just satisfy the API.
    embeds = [np.array(bb[0], dtype=np.float32) for bb in bbs] if bbs else []
    tracks = tracker.update_tracks(bbs, embeds=embeds, frame=frame_bgr)
    if not tracks:
        if det_xyxy.size:
            ids = np.arange(det_xyxy.shape[0], dtype=int) + 1
            return det_xyxy, det_conf, ids
        return np.zeros((0, 4), dtype=float), np.zeros((0,), dtype=float), np.zeros((0,), dtype=int)

    xyxy_list: list[list[float]] = []
    conf_list: list[float] = []
    ids_list: list[int] = []
    for trk in tracks:
        is_recent = getattr(trk, "time_since_update", 0) <= 1
        if not trk.is_confirmed() and not is_recent:
            continue
        ltrb = trk.to_ltrb()
        xyxy_list.append([float(ltrb[0]), float(ltrb[1]), float(ltrb[2]), float(ltrb[3])])
        det_conf = getattr(trk, "det_conf", None)
        conf_list.append(float(det_conf) if det_conf is not None else 0.2)
        ids_list.append(int(trk.track_id))

    if not xyxy_list:
        if det_xyxy.size:
            ids = np.arange(det_xyxy.shape[0], dtype=int) + 1
            return det_xyxy, det_conf, ids
        return np.zeros((0, 4), dtype=float), np.zeros((0,), dtype=float), np.zeros((0,), dtype=int)
    return np.array(xyxy_list, dtype=float), np.array(conf_list, dtype=float), np.array(ids_list, dtype=int)


def _compute_hist(frame_bgr: np.ndarray, bb_xyxy: np.ndarray) -> np.ndarray | None:
    h, w = frame_bgr.shape[:2]
    x1, y1, x2, y2 = bb_xyxy.astype(int)
    x1 = max(0, min(w - 1, x1))
    x2 = max(0, min(w, x2))
    y1 = max(0, min(h - 1, y1))
    y2 = max(0, min(h, y2))
    if x2 <= x1 + 2 or y2 <= y1 + 2:
        return None
    crop = frame_bgr[y1:y2, x1:x2]
    if crop.size == 0:
        return None
    hsv = cv2.cvtColor(crop, cv2.COLOR_BGR2HSV)
    hist = cv2.calcHist([hsv], [0, 1], None, [16, 16], [0, 180, 0, 256])
    cv2.normalize(hist, hist)
    return hist.flatten().astype(np.float32)


def _hist_similarity(a: np.ndarray | None, b: np.ndarray | None) -> float:
    if a is None or b is None:
        return -1.0
    return float(cv2.compareHist(a, b, cv2.HISTCMP_CORREL))


def _hist_bank_best_sim(bank: list[np.ndarray], candidate: np.ndarray | None, fallback: np.ndarray | None = None) -> float:
    """Return the best similarity between *candidate* and any histogram in *bank* (or *fallback*)."""
    if candidate is None:
        return -1.0
    best = -1.0
    for bh in bank:
        s = _hist_similarity(bh, candidate)
        if s > best:
            best = s
    # Also check the running-average fallback
    if fallback is not None:
        s = _hist_similarity(fallback, candidate)
        if s > best:
            best = s
    return best


def _to_sv_detections(xyxy: np.ndarray, conf: np.ndarray) -> sv.Detections:
    if xyxy.size == 0:
        return sv.Detections(
            xyxy=np.zeros((0, 4), dtype=np.float32),
            confidence=np.zeros((0,), dtype=np.float32),
            class_id=np.zeros((0,), dtype=int),
        )
    return sv.Detections(
        xyxy=xyxy.astype(np.float32),
        confidence=conf.astype(np.float32),
        class_id=np.zeros((xyxy.shape[0],), dtype=int),
    )


def _process_local_video(path: str, req: ProcessChunkRequest) -> dict[str, Any]:
    cap = cv2.VideoCapture(path)
    if not cap.isOpened():
        raise HTTPException(status_code=400, detail="Cannot open video")

    orig_fps = _get_video_fps(cap)
    step = max(1, int(round(orig_fps / float(req.samplingFps))))
    effective_sampling = orig_fps / float(step)

    t_start = time.perf_counter()

    model = _get_model()
    calibration_model = build_calibration(req.calibration)

    auto_calib = bool(int(os.getenv("SCOUTAI_AUTO_CALIBRATION", "1")))
    auto_calib_pending = False
    if calibration_model is None and auto_calib:
        frame_w = float(cap.get(cv2.CAP_PROP_FRAME_WIDTH) or 0.0)
        if frame_w <= 0:
            auto_calib_pending = True
        # Rough estimate: assume full pitch length spans the frame width.
        if frame_w > 0:
            calibration_model = CalibrationModel(kind="auto_frame", meter_per_px=105.0 / max(1.0, frame_w))

    logger.info(
        "process: fps=%.3f samplingFps=%.3f step=%d effective=%.3f model=%s conf=%.3f imgsz=%s calibrated=%s",
        orig_fps,
        float(req.samplingFps),
        step,
        effective_sampling,
        YOLO_MODEL_NAME,
        YOLO_CONF,
        str(YOLO_IMG_SIZE),
        "yes" if calibration_model is not None else "no",
    )

    state = TargetState()
    tracker = _new_deepsort()

    selection_xywh = None
    selection_t0 = None
    selection_window_s = 6.0
    # Process the full video by default for consistent results.
    # Window mode clips different segments depending on selection time,
    # causing the same player to get different stats.
    window_mode = bool(int(os.getenv("SCOUTAI_WINDOW_MODE", "0")))
    window_seconds = float(os.getenv("SCOUTAI_WINDOW_SECONDS", "120"))
    window_start_s = 0.0
    window_end_s = float("inf")
    if req.selection is not None:
        selection_xywh = np.array([req.selection.x, req.selection.y, req.selection.w, req.selection.h], dtype=float)
        selection_t0 = float(req.selection.t0)
        state.last_xywh = selection_xywh.copy()
        if window_mode and window_seconds > 0:
            window_start_s = max(0.0, selection_t0 - window_seconds / 2.0)
            window_end_s = selection_t0 + window_seconds / 2.0

    if window_mode and selection_t0 is not None:
        logger.info("process: window_mode=on window=[%.2fs..%.2fs]", window_start_s, window_end_s)
    else:
        logger.info("process: window_mode=off")

    positions: list[dict[str, float]] = []
    cuts: list[float] = []

    prev_hist = None
    frame_idx = 0
    lost_limit = 90

    # ── Histogram bank: stores multiple confirmed histograms for robust identity ──
    hist_bank: list[np.ndarray] = []  # top-K confirmed histograms
    HIST_BANK_MAX = 12  # keep at most 12 diverse histograms
    HIST_BANK_MIN_DIFF = 0.15  # min difference to add a new histogram (avoid duplicates)

    # ── Zoom detection state ──
    prev_median_area: float = 0.0
    zoom_scale: float = 1.0  # cumulative zoom factor vs first frame
    zoom_cooldown: int = 0   # frames to wait after zoom before trusting IoU
    ZOOM_AREA_RATIO = 0.35   # >35% change in median BB area = zoom event

    processed_frames = 0
    total_frames = 0
    det_frames = 0
    any_det = 0
    frame_h: float = 0.0
    frame_w: float = 0.0
    while True:
        ok, frame = cap.read()
        if not ok:
            break

        if auto_calib_pending and calibration_model is None:
            fw = float(frame.shape[1]) if frame is not None and hasattr(frame, "shape") else 0.0
            if fw > 0:
                calibration_model = CalibrationModel(kind="auto_frame", meter_per_px=105.0 / max(1.0, fw))
            auto_calib_pending = False

        # Cache frame dimensions for normalization
        if frame is not None and hasattr(frame, "shape"):
            frame_h = float(frame.shape[0])
            frame_w = float(frame.shape[1])

        total_frames += 1

        if frame_idx % step != 0:
            frame_idx += 1
            continue

        t = frame_idx / orig_fps

        # Skip frames outside the time window (if enabled)
        if t < window_start_s:
            frame_idx += 1
            continue
        if t > window_end_s:
            break

        hist = frame_histogram(frame)
        if is_cut(prev_hist, hist):
            cuts.append(float(t))
            state.target_track_id = None
            # Keep last_xywh — we need the spatial prior for re-acquisition
            state.lost_count = 0
            tracker = _reset_deepsort(tracker)
            prev_median_area = 0.0
            zoom_cooldown = 0
        prev_hist = hist

        if selection_xywh is not None and selection_t0 is not None and state.target_hist is None:
            if abs(t - selection_t0) <= selection_window_s:
                sx, sy, sw, sh = selection_xywh
                sel_xyxy = np.array([sx, sy, sx + sw, sy + sh], dtype=float)
                state.target_hist = _compute_hist(frame, sel_xyxy)

        tracked_xyxy, tracked_conf, track_ids = _run_tracking(model, tracker, frame)
        det_frames += 1
        if tracked_xyxy.size:
            any_det += 1

        # ── Zoom detection: compare median BB area across frames ──
        if zoom_cooldown > 0:
            zoom_cooldown -= 1
        if tracked_xyxy.size >= 1:
            areas = (tracked_xyxy[:, 2] - tracked_xyxy[:, 0]) * (tracked_xyxy[:, 3] - tracked_xyxy[:, 1])
            cur_median_area = float(np.median(areas))
            if prev_median_area > 0 and cur_median_area > 0:
                area_ratio = cur_median_area / prev_median_area
                if abs(area_ratio - 1.0) > ZOOM_AREA_RATIO:
                    # Zoom event detected — scale last_xywh to match new scale
                    scale_factor = float(np.sqrt(area_ratio))
                    zoom_scale *= scale_factor
                    if state.last_xywh is not None:
                        ox, oy, ow, oh = state.last_xywh
                        # Scale box size, keep center roughly in place
                        ncx = ox + ow / 2.0
                        ncy = oy + oh / 2.0
                        nw = ow * scale_factor
                        nh = oh * scale_factor
                        state.last_xywh = np.array(
                            [ncx - nw / 2, ncy - nh / 2, nw, nh], dtype=float
                        )
                    # Reset tracker ID so we rely on histogram + IoU re-matching
                    state.target_track_id = None
                    state.lost_count = 0
                    tracker = _reset_deepsort(tracker)
                    zoom_cooldown = 5  # grace period: rely on histogram, not IoU
                    logger.info("process: zoom detected at t=%.2f scale_factor=%.2f", t, scale_factor)
            prev_median_area = cur_median_area

        # ── After zoom, prefer histogram matching for re-acquisition ──
        hist_min_sim = 0.10 if zoom_cooldown > 0 else 0.15

        if selection_xywh is not None and state.target_track_id is None and selection_t0 is not None:
            if abs(t - selection_t0) <= selection_window_s:
                if tracked_xyxy.size and track_ids.size:
                    best_iou = -1.0
                    best_idx = None
                    for i, bb in enumerate(tracked_xyxy):
                        iou = iou_xywh(xyxy_to_xywh(bb.astype(float)), selection_xywh)
                        if iou > best_iou:
                            best_iou = iou
                            best_idx = i
                    if best_idx is None or best_iou < 0.01:
                        sx, sy, sw, sh = selection_xywh
                        scx = sx + sw / 2.0
                        scy = sy + sh / 2.0
                        best_dist = None
                        best_dist_idx = None
                        for i, bb in enumerate(tracked_xyxy):
                            cx = float((bb[0] + bb[2]) / 2.0)
                            cy = float((bb[1] + bb[3]) / 2.0)
                            dist = (cx - scx) ** 2 + (cy - scy) ** 2
                            if best_dist is None or dist < best_dist:
                                best_dist = dist
                                best_dist_idx = i
                        max_dist = max(sw, sh) * 1.5
                        if best_dist_idx is not None and best_dist is not None and best_dist <= max_dist * max_dist:
                            best_idx = best_dist_idx
                            best_iou = 0.0
                    if best_idx is not None and best_iou >= 0.0:
                        state.target_track_id = int(track_ids[best_idx])
                        bb = tracked_xyxy[best_idx].astype(float)
                        state.last_xywh = np.array([bb[0], bb[1], bb[2] - bb[0], bb[3] - bb[1]], dtype=float)
                        state.target_hist = _compute_hist(frame, bb)
                        state.lost_count = 0
        elif state.target_track_id is None and tracked_xyxy.size:
            # ── Combined histogram + proximity re-acquisition ──
            best_score = -1.0
            best_idx = None
            has_hist = state.target_hist is not None or bool(hist_bank)
            for i, bb in enumerate(tracked_xyxy):
                score = 0.0
                # Histogram score component
                if has_hist:
                    cand_hist = _compute_hist(frame, bb)
                    sim = _hist_bank_best_sim(hist_bank, cand_hist, state.target_hist)
                    score += max(0.0, sim) * 0.6  # 60% weight on histogram
                # Proximity score component (if we have a last known position)
                if state.last_xywh is not None:
                    lx, ly, lw, lh = state.last_xywh
                    lcx, lcy = lx + lw / 2.0, ly + lh / 2.0
                    bcx = float((bb[0] + bb[2]) / 2.0)
                    bcy = float((bb[1] + bb[3]) / 2.0)
                    dist = np.sqrt((bcx - lcx) ** 2 + (bcy - lcy) ** 2)
                    max_search = max(lw, lh, 100.0) * 4.0  # generous search radius
                    prox = max(0.0, 1.0 - dist / max_search)
                    score += prox * 0.4  # 40% weight on proximity
                elif not has_hist:
                    continue  # no histogram and no position — can't match
                if score > best_score:
                    best_score = score
                    best_idx = i
            min_reacq_score = 0.08 if has_hist else 0.15
            if best_idx is not None and best_score >= min_reacq_score and track_ids.size:
                state.target_track_id = int(track_ids[best_idx])
                bb = tracked_xyxy[best_idx].astype(float)
                state.last_xywh = np.array([bb[0], bb[1], bb[2] - bb[0], bb[3] - bb[1]], dtype=float)
                state.lost_count = 0

        chosen = None
        chosen_conf = 0.0

        if state.target_track_id is not None and tracked_xyxy.size:
            match = np.where(track_ids == state.target_track_id)[0] if track_ids.size else np.array([], dtype=int)
            if match.size:
                bb = tracked_xyxy[int(match[0])].astype(float)
                chosen = bb
                chosen_conf = 1.0
            else:
                # IoU reattach (use lower threshold during zoom cooldown)
                iou_thresh = 0.10 if zoom_cooldown > 0 else 0.15
                if state.last_xywh is not None:
                    ridx = reattach_by_iou(tracked_xyxy.astype(float), state.last_xywh, min_iou=iou_thresh)
                    if ridx is not None and track_ids.size:
                        state.target_track_id = int(track_ids[ridx])
                        bb = tracked_xyxy[ridx].astype(float)
                        chosen = bb
                        chosen_conf = 1.0
                # Histogram + proximity fallback
                if chosen is None and (state.target_hist is not None or hist_bank):
                    best_sim = -1.0
                    best_idx = None
                    for i, bb in enumerate(tracked_xyxy):
                        cand_hist = _compute_hist(frame, bb)
                        sim = _hist_bank_best_sim(hist_bank, cand_hist, state.target_hist)
                        if sim > best_sim:
                            best_sim = sim
                            best_idx = i
                    if best_idx is not None and best_sim >= hist_min_sim and track_ids.size:
                        state.target_track_id = int(track_ids[best_idx])
                        bb = tracked_xyxy[best_idx].astype(float)
                        chosen = bb
                        chosen_conf = 1.0
                # Distance fallback: nearest detection to last known position
                if chosen is None and state.last_xywh is not None:
                    lx, ly, lw, lh = state.last_xywh
                    lcx, lcy = lx + lw / 2.0, ly + lh / 2.0
                    best_dist = float("inf")
                    best_didx = None
                    for i, bb in enumerate(tracked_xyxy):
                        bcx = float((bb[0] + bb[2]) / 2.0)
                        bcy = float((bb[1] + bb[3]) / 2.0)
                        d = np.sqrt((bcx - lcx) ** 2 + (bcy - lcy) ** 2)
                        if d < best_dist:
                            best_dist = d
                            best_didx = i
                    max_search_dist = max(lw, lh, 80.0) * 3.0
                    if best_didx is not None and best_dist <= max_search_dist and track_ids.size:
                        state.target_track_id = int(track_ids[best_didx])
                        bb = tracked_xyxy[best_didx].astype(float)
                        chosen = bb
                        chosen_conf = 0.7  # lower confidence for distance-only match

        elif tracked_xyxy.size:
            if state.last_xywh is not None:
                ridx = reattach_by_iou(tracked_xyxy.astype(float), state.last_xywh, min_iou=0.05)
                if ridx is not None:
                    bb = tracked_xyxy[int(ridx)].astype(float)
                    chosen = bb
                    chosen_conf = float(tracked_conf[ridx]) if tracked_conf.size else 0.5
                    if track_ids.size:
                        state.target_track_id = int(track_ids[ridx])

            if chosen is None and selection_xywh is not None and selection_t0 is not None:
                if abs(t - selection_t0) <= selection_window_s:
                    best_iou = -1.0
                    best_idx = None
                    for i, bb in enumerate(tracked_xyxy):
                        iou = iou_xywh(xyxy_to_xywh(bb.astype(float)), selection_xywh)
                        if iou > best_iou:
                            best_iou = iou
                            best_idx = i
                    if best_idx is None or best_iou < 0.01:
                        sx, sy, sw, sh = selection_xywh
                        scx = sx + sw / 2.0
                        scy = sy + sh / 2.0
                        best_dist = None
                        best_dist_idx = None
                        for i, bb in enumerate(tracked_xyxy):
                            cx = float((bb[0] + bb[2]) / 2.0)
                            cy = float((bb[1] + bb[3]) / 2.0)
                            dist = (cx - scx) ** 2 + (cy - scy) ** 2
                            if best_dist is None or dist < best_dist:
                                best_dist = dist
                                best_dist_idx = i
                        max_dist = max(sw, sh) * 1.5
                        if best_dist_idx is not None and best_dist is not None and best_dist <= max_dist * max_dist:
                            best_idx = best_dist_idx
                            best_iou = 0.0
                    if best_idx is not None and best_iou >= 0.0:
                        bb = tracked_xyxy[best_idx].astype(float)
                        chosen = bb
                        chosen_conf = float(tracked_conf[best_idx]) if tracked_conf.size else 0.5
                        if track_ids.size:
                            state.target_track_id = int(track_ids[best_idx])

        if chosen is None:
            if state.target_track_id is not None:
                state.lost_count += 1
                # ── Velocity prediction for short gaps (≤3 sampled frames) ──
                # Use last known velocity to predict position instead of losing data.
                if state.lost_count <= 3 and len(positions) >= 2:
                    p_prev = positions[-1]
                    p_prev2 = positions[-2]
                    dt_pred = p_prev["t"] - p_prev2["t"]
                    if dt_pred > 1e-6:
                        vx = (p_prev["cx"] - p_prev2["cx"]) / dt_pred
                        vy = (p_prev["cy"] - p_prev2["cy"]) / dt_pred
                        dt_now = t - p_prev["t"]
                        if 0 < dt_now < 3.0:  # max 3s gap
                            pred_cx = p_prev["cx"] + vx * dt_now
                            pred_cy = p_prev["cy"] + vy * dt_now
                            pred_ncx = pred_cx / max(1.0, frame_w)
                            pred_ncy = pred_cy / max(1.0, frame_h)
                            positions.append({
                                "t": float(t),
                                "cx": pred_cx,
                                "cy": pred_cy,
                                "ncx": pred_ncx,
                                "ncy": pred_ncy,
                                "conf": 0.3,  # low confidence for predicted
                                "bbox": None,
                                "trackId": int(state.target_track_id) if state.target_track_id else None,
                            })
                if state.lost_count >= lost_limit:
                    state.target_track_id = None
                    state.last_xywh = None
                    state.lost_count = 0
            frame_idx += 1
            continue

        state.lost_count = 0
        x1, y1, x2, y2 = chosen
        cx = float((x1 + x2) / 2.0)
        cy = float((y1 + y2) / 2.0)
        state.last_xywh = np.array([x1, y1, x2 - x1, y2 - y1], dtype=float)
        hist = _compute_hist(frame, chosen)
        if hist is not None:
            if state.target_hist is None:
                state.target_hist = hist
            else:
                state.target_hist = (0.9 * state.target_hist + 0.1 * hist).astype(np.float32)
            # ── Add to histogram bank for robust re-acquisition ──
            if len(hist_bank) < HIST_BANK_MAX:
                # Only add if sufficiently different from existing bank entries
                is_novel = True
                for bh in hist_bank:
                    if _hist_similarity(hist, bh) > (1.0 - HIST_BANK_MIN_DIFF):
                        is_novel = False
                        break
                if is_novel:
                    hist_bank.append(hist.copy())

        # Store both pixel and normalized (frame-relative) coordinates.
        # Normalized coords eliminate zoom-induced false motion.
        ncx = cx / max(1.0, frame_w) if frame_w > 0 else cx
        ncy = cy / max(1.0, frame_h) if frame_h > 0 else cy

        positions.append(
            {
                "t": float(t),
                "cx": cx,
                "cy": cy,
                "ncx": ncx,
                "ncy": ncy,
                "conf": float(chosen_conf),
                "bbox": [float(x1), float(y1), float(x2), float(y2)],
                "trackId": int(state.target_track_id) if state.target_track_id is not None else None,
            }
        )

        processed_frames += 1

        if processed_frames and processed_frames % 50 == 0:
            elapsed = time.perf_counter() - t_start
            logger.info(
                "process: frames=%d detections_frames=%d any_det=%d positions=%d elapsed=%.2fs",
                processed_frames,
                det_frames,
                any_det,
                len(positions),
                elapsed,
            )

        frame_idx += 1

    cap.release()

    # ── Post-loop gap interpolation ──
    # Fill short time gaps (up to max_gap_s seconds) with linearly interpolated positions.
    # This recovers data from periods where the tracker briefly lost the player.
    max_gap_s = 2.0  # max gap duration to interpolate
    sample_interval = 1.0 / max(1.0, float(req.samplingFps))
    if len(positions) >= 2:
        interpolated: list[dict] = []
        for i in range(len(positions) - 1):
            interpolated.append(positions[i])
            p0 = positions[i]
            p1 = positions[i + 1]
            gap = p1["t"] - p0["t"]
            if gap > sample_interval * 1.8 and gap <= max_gap_s:
                # Number of intermediate points to insert
                n_fill = max(1, int(round(gap / sample_interval)) - 1)
                for k in range(1, n_fill + 1):
                    frac = k / (n_fill + 1)
                    interp_t = p0["t"] + gap * frac
                    interp_cx = p0["cx"] + (p1["cx"] - p0["cx"]) * frac
                    interp_cy = p0["cy"] + (p1["cy"] - p0["cy"]) * frac
                    interp_ncx = p0.get("ncx", interp_cx) + (p1.get("ncx", p1["cx"]) - p0.get("ncx", p0["cx"])) * frac
                    interp_ncy = p0.get("ncy", interp_cy) + (p1.get("ncy", p1["cy"]) - p0.get("ncy", p0["cy"])) * frac
                    interpolated.append({
                        "t": float(interp_t),
                        "cx": float(interp_cx),
                        "cy": float(interp_cy),
                        "ncx": float(interp_ncx),
                        "ncy": float(interp_ncy),
                        "conf": 0.25,  # low confidence for interpolated
                        "bbox": None,
                        "trackId": None,
                    })
        interpolated.append(positions[-1])
        positions = interpolated
        logger.info("process: interpolation added %d points (total now %d)",
                     len(positions) - len([p for p in positions if p["conf"] > 0.25]),
                     len(positions))

    elapsed_total = time.perf_counter() - t_start
    logger.info(
        "process: done total_read=%d sampled=%d positions=%d cuts=%d any_det=%d elapsed=%.2fs",
        total_frames,
        processed_frames,
        len(positions),
        len(cuts),
        any_det,
        elapsed_total,
    )

    ts = np.array([p["t"] for p in positions], dtype=float)
    cxs = np.array([p["cx"] for p in positions], dtype=float)
    cys = np.array([p["cy"] for p in positions], dtype=float)
    # Normalized coordinates (0-1 range) — zoom-invariant
    ncxs = np.array([p.get("ncx", p["cx"]) for p in positions], dtype=float)
    ncys = np.array([p.get("ncy", p["cy"]) for p in positions], dtype=float)

    metrics = compute_metrics(ts, cxs, cys, calibration_model, norm_xs=ncxs, norm_ys=ncys)

    debug: dict[str, Any] = {
        "elapsedSeconds": float(elapsed_total),
        "origFps": float(orig_fps),
        "samplingFps": float(req.samplingFps),
        "step": int(step),
        "effectiveSamplingFps": float(effective_sampling),
        "windowMode": bool(window_mode),
        "windowSeconds": float(window_seconds),
        "windowStart": float(window_start_s),
        "windowEnd": float(window_end_s) if window_end_s != float("inf") else None,
        "calibrated": bool(calibration_model is not None),
        "calibrationKind": calibration_model.kind if calibration_model is not None else None,
        "meterPerPx": float(calibration_model.meter_per_px) if calibration_model is not None and calibration_model.meter_per_px is not None else None,
        "framesRead": int(total_frames),
        "framesSampled": int(processed_frames),
        "framesWithAnyDetections": int(any_det),
        "positions": int(len(positions)),
        "cuts": int(len(cuts)),
    }

    return {
        "chunkIndex": int(req.chunkIndex),
        "frameSamplingFps": float(effective_sampling),
        "positions": positions,
        "cuts": cuts,
        "metrics": metrics,
        "debug": debug,
    }


@app.post("/process-chunk", response_model=ProcessChunkResponse)
def process_chunk(req: ProcessChunkRequest) -> Any:
    local_path, cleanup = resolve_local_video(req.chunkPathOrUrl)

    try:
        return _process_local_video(local_path, req)

    finally:
        cleanup()


@app.post("/process-upload", response_model=ProcessChunkResponse)
async def process_upload(
    file: UploadFile = File(...),
    chunkIndex: int = Form(...),
    samplingFps: float = Form(3.0),
    selection: str | None = Form(None),
    calibration: str | None = Form(None),
) -> Any:
    suffix = os.path.splitext(file.filename or "")[1] or ".mp4"
    fd, tmp_path = tempfile.mkstemp(prefix="scoutai_upload_", suffix=suffix)
    os.close(fd)

    try:
        with open(tmp_path, "wb") as out:
            while True:
                chunk = await file.read(1024 * 1024)
                if not chunk:
                    break
                out.write(chunk)

        payload: dict[str, Any] = {
            "chunkPathOrUrl": tmp_path,
            "chunkIndex": int(chunkIndex),
            "samplingFps": float(samplingFps),
            "selection": None,
            "calibration": None,
        }
        if selection:
            payload["selection"] = json.loads(selection)
        if calibration:
            payload["calibration"] = json.loads(calibration)

        req = ProcessChunkRequest(**payload)
        return _process_local_video(tmp_path, req)

    finally:
        try:
            os.remove(tmp_path)
        except OSError:
            pass


@app.post("/merge", response_model=MergeResponse)
def merge(req: MergeRequest) -> Any:
    # keep logic here minimal; recompute metrics on merged series
    from .merge_logic import merge_chunks

    merged = merge_chunks([c.model_dump() for c in req.chunks])
    return merged
