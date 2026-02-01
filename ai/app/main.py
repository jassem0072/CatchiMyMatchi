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
YOLO_CONF = float(os.getenv("SCOUTAI_YOLO_CONF", "0.2"))
YOLO_IMG_SIZE_ENV = os.getenv("SCOUTAI_YOLO_IMG_SIZE", "").strip()
YOLO_IMG_SIZE = int(YOLO_IMG_SIZE_ENV) if YOLO_IMG_SIZE_ENV else None

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
    return DeepSort(max_age=45, n_init=1)


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

    tracks = tracker.update_tracks(bbs, frame=frame_bgr)
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

    model = YOLO(YOLO_MODEL_NAME)
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
    selection_window_s = 3.0
    # For speed: process only a window around selection time.
    window_mode = bool(int(os.getenv("SCOUTAI_WINDOW_MODE", "1")))
    window_seconds = float(os.getenv("SCOUTAI_WINDOW_SECONDS", "20"))
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
    lost_limit = 30

    processed_frames = 0
    total_frames = 0
    det_frames = 0
    any_det = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break

        if auto_calib_pending and calibration_model is None:
            frame_w = float(frame.shape[1]) if frame is not None and hasattr(frame, "shape") else 0.0
            if frame_w > 0:
                calibration_model = CalibrationModel(kind="auto_frame", meter_per_px=105.0 / max(1.0, frame_w))
            auto_calib_pending = False

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
            state.last_xywh = None
            state.lost_count = 0
            tracker = _reset_deepsort(tracker)
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
        elif state.target_track_id is None and state.target_hist is not None and tracked_xyxy.size:
            best_sim = -1.0
            best_idx = None
            for i, bb in enumerate(tracked_xyxy):
                sim = _hist_similarity(state.target_hist, _compute_hist(frame, bb))
                if sim > best_sim:
                    best_sim = sim
                    best_idx = i
            if best_idx is not None and best_sim >= 0.2 and track_ids.size:
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
                if state.last_xywh is not None:
                    ridx = reattach_by_iou(tracked_xyxy.astype(float), state.last_xywh, min_iou=0.25)
                    if ridx is not None and track_ids.size:
                        state.target_track_id = int(track_ids[ridx])
                        bb = tracked_xyxy[ridx].astype(float)
                        chosen = bb
                        chosen_conf = 1.0
                if chosen is None and state.target_hist is not None:
                    best_sim = -1.0
                    best_idx = None
                    for i, bb in enumerate(tracked_xyxy):
                        sim = _hist_similarity(state.target_hist, _compute_hist(frame, bb))
                        if sim > best_sim:
                            best_sim = sim
                            best_idx = i
                    if best_idx is not None and best_sim >= 0.2 and track_ids.size:
                        state.target_track_id = int(track_ids[best_idx])
                        bb = tracked_xyxy[best_idx].astype(float)
                        chosen = bb
                        chosen_conf = 1.0

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

        positions.append(
            {
                "t": float(t),
                "cx": cx,
                "cy": cy,
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

    metrics = compute_metrics(ts, cxs, cys, calibration_model)

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
