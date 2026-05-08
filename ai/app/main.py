from __future__ import annotations

import json
import logging
import os
import tempfile
import time
from typing import Any

import cv2
import numpy as np
from deep_sort_realtime.deepsort_tracker import DeepSort
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from ultralytics import YOLO

try:
    import supervision as sv
except Exception:  # pragma: no cover - optional import fallback
    sv = None  # type: ignore[assignment]

from .calibration import CalibrationModel, build_calibration
from .cuts import frame_histogram, is_cut
from .logging_utils import setup_logging
from .metrics import compute_metrics
from .schemas import (
    MergeRequest,
    MergeResponse,
    ProcessChunkRequest,
    ProcessChunkResponse,
    ProfilePlayerRequest,
    ProfilePlayerResponse,
    SelectionBBox,
)
from .tracking import TargetState, iou_xywh, reattach_by_iou, xyxy_to_xywh
from .kalman_target import KalmanTarget
from .video_io import resolve_local_video
from .claude_profiler import (
    profile_player_from_video,
    compute_profile_hsv_range,
)

logger = logging.getLogger(__name__)

# yolov8n is ~2-3x faster than yolov8s on CPU with acceptable accuracy.
# Override with SCOUTAI_YOLO_MODEL=yolov8s.pt for higher accuracy if GPU available.
YOLO_MODEL_NAME = os.getenv("SCOUTAI_YOLO_MODEL", "yolov8n.pt")
# Lowered from 0.15 → 0.08: real-case sandy/dirt-pitch videos have much lower
# YOLO confidence scores because players blend into the background.
YOLO_CONF = float(os.getenv("SCOUTAI_YOLO_CONF", "0.08"))
# 416 is ~2x faster than 640 on CPU with minimal accuracy loss for person detection.
YOLO_IMG_SIZE_ENV = os.getenv("SCOUTAI_YOLO_IMG_SIZE", "416").strip()
YOLO_IMG_SIZE = int(YOLO_IMG_SIZE_ENV) if YOLO_IMG_SIZE_ENV else None
# Cap detections per frame: a football pitch has at most ~25 players + staff.
# Sandy-pitch videos with spectators can produce 100+ detections, making
# DeepSort and histogram matching extremely slow.
YOLO_MAX_DET = int(os.getenv("SCOUTAI_MAX_DET", "30"))
TRACKER_BACKEND = os.getenv("SCOUTAI_TRACKER", "bytetrack").strip().lower()
DEEPSORT_EMBEDDER_ENV = os.getenv("SCOUTAI_DEEPSORT_EMBEDDER", "none").strip().lower()
DEEPSORT_EMBEDDER: str | None = None if DEEPSORT_EMBEDDER_ENV in {"", "none", "off"} else DEEPSORT_EMBEDDER_ENV
DEEPSORT_MAX_COSINE = float(os.getenv("SCOUTAI_DEEPSORT_MAX_COSINE", "0.35"))

# Singleton model — loaded once at startup, reused across all requests.
_yolo_model: YOLO | None = None


def _should_terminate_tracking(
    enhanced_mode: bool, 
    identity_break_count: int, 
    max_identity_break_frames: int,
    strict_no_reacquire: bool
) -> bool:
    """
    Determine if tracking should be terminated based on enhanced tracking mode.
    
    In enhanced mode, tracking is never terminated due to identity breaks,
    which fixes the 7-second tracking limitation bug.
    """
    if enhanced_mode:
        # Enhanced mode: never terminate due to identity breaks
        # This is the core fix for the 7-second limitation bug
        return False
    else:
        # Legacy mode: terminate after max identity break frames
        return strict_no_reacquire and identity_break_count >= max_identity_break_frames


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
    if os.getenv("SCOUTAI_PRELOAD_MODEL", "0") == "1":
        _get_model()  # optional pre-warm for environments with fast model access


def _get_video_fps(cap: cv2.VideoCapture) -> float:
    fps = cap.get(cv2.CAP_PROP_FPS)
    if fps is None or fps <= 1e-3:
        return 25.0
    return float(fps)


def _resolve_tracker_backend(name: str | None) -> str:
    requested = (name or TRACKER_BACKEND).strip().lower()
    if requested not in {"bytetrack", "deepsort"}:
        logger.warning(
            "tracker: unsupported backend '%s', falling back to deepsort",
            requested,
        )
        requested = "deepsort"

    if requested == "bytetrack" and (sv is None or not hasattr(sv, "ByteTrack")):
        logger.warning(
            "tracker: supervision.ByteTrack unavailable, falling back to deepsort"
        )
        return "deepsort"

    return requested


def _run_detection(model: YOLO, frame_bgr: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    # returns (xyxy Nx4, conf Nx1)
    predict_kwargs: dict[str, Any] = {
        "verbose": False,
        "conf": YOLO_CONF,
        "max_det": YOLO_MAX_DET,  # cap detections — spectators inflate this to 100+
    }
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

    # ── Spectator filter: remove very small boxes (distant crowd in stands) ──
    # On sandy-pitch videos the crowd surrounds the pitch on all sides.
    # Spectators produce tiny bounding boxes (< 0.3% of frame area); real players
    # are much larger. Filtering them reduces per-frame work dramatically.
    if xyxy.shape[0] > 0:
        fh, fw = float(frame_bgr.shape[0]), float(frame_bgr.shape[1])
        frame_area = fh * fw
        widths = xyxy[:, 2] - xyxy[:, 0]
        heights = xyxy[:, 3] - xyxy[:, 1]
        areas = widths * heights
        # Keep boxes that are at least 0.15% of frame area (eliminates distant crowd)
        # and not taller than 60% of the frame (eliminates giant false-positives).
        size_keep = (areas > frame_area * 0.0015) & (heights < fh * 0.60)
        xyxy = xyxy[size_keep]
        conf = conf[size_keep]

    return xyxy, conf


def _new_deepsort() -> DeepSort:
    # Configure embedder via env:
    # - none/off: IoU+Kalman only (faster)
    # - mobilenet/torchreid/clip_*: stronger re-ID (slower, more stable IDs)
    max_cos = 999.0 if DEEPSORT_EMBEDDER is None else DEEPSORT_MAX_COSINE
    max_age = int(os.getenv("SCOUTAI_DEEPSORT_MAX_AGE", "300"))  # 300 frames ≈ 10s at 30fps
    return DeepSort(
        max_age=max_age,
        n_init=1,
        embedder=DEEPSORT_EMBEDDER,
        max_cosine_distance=max_cos,
        nn_budget=150,  # appearance memory bank: store 150 embeddings per track
    )


def _new_bytetrack(frame_rate: float) -> Any:
    if sv is None or not hasattr(sv, "ByteTrack"):
        raise RuntimeError(
            "ByteTrack backend requested but supervision.ByteTrack is unavailable"
        )
    return sv.ByteTrack(
        frame_rate=max(1, int(round(frame_rate))),
        track_activation_threshold=max(0.05, YOLO_CONF),
        minimum_matching_threshold=0.7,
        lost_track_buffer=90,
    )


def _new_tracker(backend: str, frame_rate: float) -> Any:
    if backend == "bytetrack":
        return _new_bytetrack(frame_rate)
    return _new_deepsort()


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


def _reset_tracker(tracker: Any, backend: str, frame_rate: float) -> Any:
    if backend == "deepsort":
        return _reset_deepsort(tracker)
    return _new_tracker(backend, frame_rate)


def _run_deepsort_tracking(
    tracker: DeepSort,
    frame_bgr: np.ndarray,
    det_xyxy: np.ndarray,
    det_conf: np.ndarray,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    bbs = []
    for bb, conf in zip(det_xyxy, det_conf):
        x1, y1, x2, y2 = bb
        bbs.append(
            (
                [float(x1), float(y1), float(x2 - x1), float(y2 - y1)],
                float(conf),
                "person",
            )
        )

    # Provide lightweight embeddings only when built-in embedder is disabled.
    # When embedder=None, DeepSort requires embeddings to always be provided
    # (even as an empty list) — never pass embeds=None in that case.
    if DEEPSORT_EMBEDDER is None:
        embeds = [np.array(bb[0], dtype=np.float32) for bb in bbs]  # empty list when bbs is empty
    else:
        embeds = None
    tracks = tracker.update_tracks(bbs, embeds=embeds, frame=frame_bgr)
    if not tracks:
        if det_xyxy.size:
            ids = np.arange(det_xyxy.shape[0], dtype=int) + 1
            return det_xyxy, det_conf, ids
        return (
            np.zeros((0, 4), dtype=float),
            np.zeros((0,), dtype=float),
            np.zeros((0,), dtype=int),
        )

    xyxy_list: list[list[float]] = []
    conf_list: list[float] = []
    ids_list: list[int] = []
    for trk in tracks:
        is_recent = getattr(trk, "time_since_update", 0) <= 1
        if not trk.is_confirmed() and not is_recent:
            continue
        ltrb = trk.to_ltrb()
        xyxy_list.append(
            [float(ltrb[0]), float(ltrb[1]), float(ltrb[2]), float(ltrb[3])]
        )
        det_confidence = getattr(trk, "det_conf", None)
        conf_list.append(float(det_confidence) if det_confidence is not None else 0.2)
        ids_list.append(int(trk.track_id))

    if not xyxy_list:
        if det_xyxy.size:
            ids = np.arange(det_xyxy.shape[0], dtype=int) + 1
            return det_xyxy, det_conf, ids
        return (
            np.zeros((0, 4), dtype=float),
            np.zeros((0,), dtype=float),
            np.zeros((0,), dtype=int),
        )

    return (
        np.array(xyxy_list, dtype=float),
        np.array(conf_list, dtype=float),
        np.array(ids_list, dtype=int),
    )


def _run_bytetrack_tracking(
    tracker: Any,
    det_xyxy: np.ndarray,
    det_conf: np.ndarray,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    if sv is None:
        return (
            np.zeros((0, 4), dtype=float),
            np.zeros((0,), dtype=float),
            np.zeros((0,), dtype=int),
        )

    detections = _to_sv_detections(det_xyxy, det_conf)
    tracked = tracker.update_with_detections(detections)
    if tracked is None:
        return (
            np.zeros((0, 4), dtype=float),
            np.zeros((0,), dtype=float),
            np.zeros((0,), dtype=int),
        )

    xyxy = np.asarray(getattr(tracked, "xyxy", np.zeros((0, 4))), dtype=float)
    conf = np.asarray(
        getattr(tracked, "confidence", np.zeros((xyxy.shape[0],))), dtype=float
    )
    ids_raw = getattr(tracked, "tracker_id", None)
    ids = (
        np.asarray(ids_raw, dtype=int)
        if ids_raw is not None
        else np.zeros((xyxy.shape[0],), dtype=int)
    )

    keep = ids >= 0
    if keep.size and not np.all(keep):
        xyxy = xyxy[keep]
        conf = conf[keep]
        ids = ids[keep]

    if xyxy.size == 0 and det_xyxy.size:
        ids = np.arange(det_xyxy.shape[0], dtype=int) + 1
        return det_xyxy, det_conf, ids

    return xyxy, conf, ids


def _run_tracking(
    model: YOLO, tracker: Any, frame_bgr: np.ndarray, backend: str
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    det_xyxy, det_conf = _run_detection(model, frame_bgr)
    if backend == "bytetrack":
        return _run_bytetrack_tracking(tracker, det_xyxy, det_conf)
    return _run_deepsort_tracking(tracker, frame_bgr, det_xyxy, det_conf)


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


def _crop_player(frame_bgr: np.ndarray, bb_xyxy: np.ndarray, target_size: tuple = (32, 64)) -> np.ndarray | None:
    """Crop a player from the frame and resize to a standard size for comparison."""
    h, w = frame_bgr.shape[:2]
    x1, y1, x2, y2 = bb_xyxy.astype(int)
    x1 = max(0, min(w - 1, x1))
    x2 = max(x1 + 1, min(w, x2))
    y1 = max(0, min(h - 1, y1))
    y2 = max(y1 + 1, min(h, y2))
    crop = frame_bgr[y1:y2, x1:x2]
    if crop.size == 0 or crop.shape[0] < 3 or crop.shape[1] < 3:
        return None
    resized = cv2.resize(crop, target_size, interpolation=cv2.INTER_AREA)
    return resized


def _jersey_fingerprint(frame_bgr: np.ndarray, bb_xyxy: np.ndarray) -> np.ndarray | None:
    """Extract a color fingerprint from the TORSO area (top 60%) of a player detection.
    Uses fine-grained HSV histogram focused on jersey, ignoring legs/ground."""
    h, w = frame_bgr.shape[:2]
    x1, y1, x2, y2 = bb_xyxy.astype(int)
    x1 = max(0, min(w - 1, x1))
    x2 = max(x1 + 1, min(w, x2))
    y1 = max(0, min(h - 1, y1))
    y2 = max(y1 + 1, min(h, y2))
    bh = y2 - y1
    if bh < 4:
        return None
    # Take top 60% = torso/jersey area (exclude legs and ground)
    torso_y2 = y1 + int(bh * 0.6)
    crop = frame_bgr[y1:torso_y2, x1:x2]
    if crop.size == 0 or crop.shape[0] < 2 or crop.shape[1] < 2:
        return None
    hsv = cv2.cvtColor(crop, cv2.COLOR_BGR2HSV)
    # Fine-grained histogram: 32 hue x 16 sat x 8 val bins
    hist = cv2.calcHist([hsv], [0, 1, 2], None, [32, 16, 8], [0, 180, 0, 256, 0, 256])
    cv2.normalize(hist, hist)
    return hist.flatten().astype(np.float32)


def _crop_similarity(crop_a: np.ndarray | None, crop_b: np.ndarray | None) -> float:
    """Compare two jersey fingerprints using histogram intersection.
    Returns value in [0, 1], higher is more similar."""
    if crop_a is None or crop_b is None:
        return 0.0
    if crop_a.shape != crop_b.shape:
        return 0.0
    # Histogram intersection = sum of min values
    sim = float(np.minimum(crop_a, crop_b).sum())
    return max(0.0, min(1.0, sim))


def _enhanced_hist_similarity(a: np.ndarray | None, b: np.ndarray | None) -> float:
    """
    Enhanced histogram similarity calculation with multiple comparison methods.
    
    Uses correlation, chi-square, and intersection methods for robust matching.
    This improves reacquisition accuracy in the enhanced tracking mode.
    """
    if a is None or b is None:
        return -1.0
    
    # Correlation method (primary)
    correl = float(cv2.compareHist(a, b, cv2.HISTCMP_CORREL))
    
    # Chi-square method (secondary) - lower is better, so invert
    chi_square = float(cv2.compareHist(a, b, cv2.HISTCMP_CHISQR))
    chi_square_norm = max(0.0, 1.0 - (chi_square / 100.0))  # Normalize and invert
    
    # Intersection method (tertiary)
    intersection = float(cv2.compareHist(a, b, cv2.HISTCMP_INTERSECT))
    
    # Combined score with weights
    combined_score = (correl * 0.6) + (chi_square_norm * 0.2) + (intersection * 0.2)
    
    return max(-1.0, min(1.0, combined_score))


def _profile_boosted_hist_similarity(
    a: np.ndarray | None,
    b: np.ndarray | None,
    frame: np.ndarray | None,
    bb_xyxy: np.ndarray | None,
    profile_hsv_range: tuple[np.ndarray, np.ndarray] | None,
) -> float:
    """Histogram similarity with optional Claude profile HSV boost.

    When a Claude player profile is available, candidates whose jersey color
    matches the profile's HSV range get a similarity bonus, making
    reacquisition more accurate.
    """
    base_sim = _enhanced_hist_similarity(a, b)
    if profile_hsv_range is None or frame is None or bb_xyxy is None:
        return base_sim

    # Compute how well the candidate's jersey matches the Claude profile
    try:
        h, w = frame.shape[:2]
        x1, y1, x2, y2 = bb_xyxy.astype(int)
        x1 = max(0, min(w - 1, x1))
        x2 = max(0, min(w, x2))
        y1 = max(0, min(h - 1, y1))
        y2 = max(0, min(h, y2))
        if x2 <= x1 + 4 or y2 <= y1 + 4:
            return base_sim

        crop = frame[y1:y2, x1:x2]
        if crop.size == 0:
            return base_sim

        hsv = cv2.cvtColor(crop, cv2.COLOR_BGR2HSV)
        lower, upper = profile_hsv_range
        mask = cv2.inRange(hsv, lower, upper)
        match_ratio = float(np.count_nonzero(mask)) / float(mask.size)

        # Boost similarity if jersey color matches Claude's profile
        # A match_ratio > 0.15 means significant color match
        if match_ratio > 0.15:
            boost = min(0.25, match_ratio * 0.5)
            return min(1.0, base_sim + boost)
    except Exception:
        pass

    return base_sim


def _hist_similarity(a: np.ndarray | None, b: np.ndarray | None) -> float:
    if a is None or b is None:
        return -1.0
    return float(cv2.compareHist(a, b, cv2.HISTCMP_CORREL))


def _enhanced_hist_bank_best_sim(
    bank: list[np.ndarray],
    candidate: np.ndarray | None,
    fallback: np.ndarray | None = None,
    use_enhanced_similarity: bool = True,
) -> float:
    """
    Enhanced histogram bank similarity with improved matching algorithm.
    
    Returns the best similarity between candidate and any histogram in bank.
    Uses enhanced similarity calculation for better reacquisition accuracy.
    """
    if candidate is None:
        return -1.0
    
    best = -1.0
    similarity_func = _enhanced_hist_similarity if use_enhanced_similarity else _hist_similarity
    
    for bh in bank:
        s = similarity_func(bh, candidate)
        if s > best:
            best = s
    
    # Also check the running-average fallback
    if fallback is not None:
        s = similarity_func(fallback, candidate)
        if s > best:
            best = s
    
    return best


def _hist_bank_best_sim(
    bank: list[np.ndarray],
    candidate: np.ndarray | None,
    fallback: np.ndarray | None = None,
) -> float:
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


def _enhanced_reacquisition(
    frame: np.ndarray,
    tracked_xyxy: np.ndarray,
    track_ids: np.ndarray,
    hist_bank: list[np.ndarray],
    target_hist: np.ndarray | None,
    last_xywh: np.ndarray | None,
    selection_xywh: np.ndarray | None,
    config: dict,
) -> tuple[int | None, float]:
    """
    Enhanced reacquisition algorithm with combined appearance, spatial, and temporal scoring.
    
    This is a key component of the enhanced tracking system that fixes the 7-second limitation
    by providing robust player re-identification after tracking gaps.
    
    Returns: (best_candidate_index, confidence_score)
    """
    if tracked_xyxy.size == 0:
        return None, 0.0
    
    best_score = -1.0
    best_idx = None
    
    has_hist = target_hist is not None or bool(hist_bank)
    ref_xywh = last_xywh if last_xywh is not None else selection_xywh
    
    enhanced_mode = config.get('enhanced_tracking_mode', True)
    search_radius = config.get('reacquisition_search_radius', 4.0)
    
    for i, bb in enumerate(tracked_xyxy):
        score = 0.0
        
        # 1. Appearance similarity component (60% weight)
        if has_hist:
            cand_hist = _compute_hist(frame, bb)
            sim = _enhanced_hist_bank_best_sim(
                hist_bank, cand_hist, target_hist, 
                use_enhanced_similarity=enhanced_mode
            )
            appearance_score = max(0.0, sim)
            score += appearance_score * 0.6
        
        # 2. Spatial proximity component (30% weight)
        if ref_xywh is not None:
            lx, ly, lw, lh = ref_xywh
            lcx, lcy = lx + lw / 2.0, ly + lh / 2.0
            bcx = float((bb[0] + bb[2]) / 2.0)
            bcy = float((bb[1] + bb[3]) / 2.0)
            dist = np.sqrt((bcx - lcx) ** 2 + (bcy - lcy) ** 2)
            
            # Enhanced search radius for better reacquisition
            max_search = max(lw, lh, 100.0) * search_radius
            proximity_score = max(0.0, 1.0 - dist / max_search)
            score += proximity_score * 0.3
        
        # 3. Size consistency component (10% weight)
        if ref_xywh is not None:
            lw, lh = ref_xywh[2], ref_xywh[3]
            bw = bb[2] - bb[0]
            bh = bb[3] - bb[1]
            
            # Size ratio consistency (prefer similar-sized detections)
            size_ratio_w = min(lw, bw) / max(lw, bw) if max(lw, bw) > 0 else 0.0
            size_ratio_h = min(lh, bh) / max(lh, bh) if max(lh, bh) > 0 else 0.0
            size_score = (size_ratio_w + size_ratio_h) / 2.0
            score += size_score * 0.1
        
        if score > best_score:
            best_score = score
            best_idx = i
    
    # Enhanced thresholds based on mode
    min_reacq_score = 0.04 if has_hist else 0.10
    if enhanced_mode:
        min_reacq_score *= 0.8  # Lower threshold in enhanced mode for better reacquisition
    
    if best_idx is not None and best_score >= min_reacq_score:
        return best_idx, best_score
    
    return None, 0.0


def _to_sv_detections(xyxy: np.ndarray, conf: np.ndarray) -> sv.Detections:
    if sv is None:
        raise RuntimeError("supervision is required for ByteTrack backend")
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
    min_sampling_fps = float(os.getenv("SCOUTAI_MIN_SAMPLING_FPS", "3"))
    requested_sampling = max(float(req.samplingFps), min_sampling_fps)
    step = max(1, int(round(orig_fps / requested_sampling)))
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
            calibration_model = CalibrationModel(
                kind="auto_frame", meter_per_px=105.0 / max(1.0, frame_w)
            )

    tracker_backend = _resolve_tracker_backend(req.tracker)

    # Enhanced tracking mode flag - when enabled, disables premature termination
    enhanced_tracking_mode = bool(int(os.getenv("SCOUTAI_ENHANCED_TRACKING_MODE", "1")))
    
    # Claude player profile integration
    player_profile = req.player_profile
    profile_hsv_range = None
    if player_profile and player_profile.get("confidence", 0) > 0:
        profile_hsv_range = compute_profile_hsv_range(player_profile)
        logger.info(
            "Claude player profile active — jersey=%s, number=%s, confidence=%.2f, hsv_range=%s",
            player_profile.get("jersey_color", "?"),
            player_profile.get("jersey_number", "?"),
            player_profile.get("confidence", 0),
            "yes" if profile_hsv_range is not None else "no",
        )
    else:
        logger.info("No Claude player profile — using standard tracking")
    
    # Log enhanced tracking mode status
    if enhanced_tracking_mode:
        logger.info("Enhanced tracking mode ENABLED - 7-second limitation bug fix active")
    else:
        logger.info("Enhanced tracking mode DISABLED - using legacy tracking behavior")
    strict_target_lock = bool(int(os.getenv("SCOUTAI_STRICT_TARGET_LOCK", "1")))
    strict_no_reacquire = bool(int(os.getenv("SCOUTAI_STRICT_NO_REACQUIRE", "0")))  # Disabled by default in enhanced mode
    max_identity_break_frames = int(os.getenv("SCOUTAI_MAX_IDENTITY_BREAK_FRAMES", "300"))  # Increased from 60
    
    # Enhanced reacquisition settings
    histogram_bank_size = int(os.getenv("SCOUTAI_HISTOGRAM_BANK_SIZE", "15"))  # Increased from 12
    reacquisition_search_radius = float(os.getenv("SCOUTAI_REACQUISITION_SEARCH_RADIUS", "4.0"))  # Increased from 2.8
    
    # Gap handling settings
    allow_predicted_points = bool(int(os.getenv("SCOUTAI_ALLOW_PREDICTED_POINTS", "1")))  # Enabled by default
    allow_gap_interpolation = bool(int(os.getenv("SCOUTAI_ALLOW_GAP_INTERPOLATION", "1")))  # Enabled by default
    velocity_prediction_frames = int(os.getenv("SCOUTAI_VELOCITY_PREDICTION_FRAMES", "30"))  # Increased from 20

    logger.info(
        "process: fps=%.3f samplingFps=%.3f (requested=%.3f min=%.3f) step=%d effective=%.3f model=%s conf=%.3f imgsz=%s tracker=%s strictLock=%s enhanced=%s calibrated=%s",
        orig_fps,
        requested_sampling,
        float(req.samplingFps),
        min_sampling_fps,
        step,
        effective_sampling,
        YOLO_MODEL_NAME,
        YOLO_CONF,
        str(YOLO_IMG_SIZE),
        tracker_backend,
        "on" if strict_target_lock else "off",
        "on" if enhanced_tracking_mode else "off",
        "yes" if calibration_model is not None else "no",
    )

    state = TargetState()
    # Per-target Kalman filter — initialized when player is first locked
    kalman: KalmanTarget | None = None
    tracker = _new_tracker(tracker_backend, orig_fps)
    target_locked_once = False
    max_locked_norm_speed = float(
        os.getenv("SCOUTAI_MAX_LOCKED_NORM_SPEED", "0.75")
    )
    same_id_max_dist_factor = float(
        os.getenv("SCOUTAI_SAME_ID_MAX_DIST_FACTOR", "4.0")
    )
    same_id_min_hist_sim = float(os.getenv("SCOUTAI_SAME_ID_MIN_HIST_SIM", "0.02"))
    safe_reacquire = bool(int(os.getenv("SCOUTAI_SAFE_REACQUIRE", "1")))
    safe_reacquire_min_hist = float(
        os.getenv("SCOUTAI_SAFE_REACQUIRE_MIN_HIST", "0.14")
    )
    safe_reacquire_dist_factor = float(
        os.getenv("SCOUTAI_SAFE_REACQUIRE_DIST_FACTOR", "1.6")
    )

    selection_xywh = None
    selection_t0 = None
    # Increased from 6 → 30 s: on sandy/low-contrast pitches YOLO may miss the
    # player for many seconds at a time. A 6-second window is far too short.
    selection_window_s = 30.0
    window_start_s = 0.0
    window_end_s = float("inf")

    # ── Multi-anchor re-acquisition: build sorted anchor list ──
    # Each anchor is a checkpoint where the tracker re-acquires the player.
    # This fixes the 7-second tracking loss by giving the tracker multiple
    # known player positions throughout the video.
    anchors: list[SelectionBBox] = []
    if req.multi_selections and len(req.multi_selections) > 0:
        anchors = sorted(req.multi_selections, key=lambda s: s.t0)
    if req.selection is not None:
        # Insert the primary selection as the first anchor if not already present
        primary_t0 = req.selection.t0
        if not anchors or abs(anchors[0].t0 - primary_t0) > 0.5:
            anchors.insert(0, req.selection)

    # Use first anchor as the primary selection
    if anchors:
        first = anchors[0]
        selection_xywh = np.array(
            [first.x, first.y, first.w, first.h], dtype=float,
        )
        selection_t0 = float(first.t0)
        state.last_xywh = selection_xywh.copy()

        # Auto-window: only process from first anchor to last anchor + 30s
        # This is the key speed fix — no need to process the entire video
        window_start_s = max(0.0, selection_t0 - 2.0)  # 2s before first anchor
        if len(anchors) > 1:
            window_end_s = anchors[-1].t0 + 30.0  # 30s after last anchor
        else:
            window_end_s = selection_t0 + 60.0  # single click: 60s window
    elif req.selection is not None:
        # Backward compat: single selection, no anchors
        selection_xywh = np.array(
            [req.selection.x, req.selection.y, req.selection.w, req.selection.h],
            dtype=float,
        )
        selection_t0 = float(req.selection.t0)
        state.last_xywh = selection_xywh.copy()
        window_start_s = max(0.0, selection_t0 - 2.0)
        window_end_s = selection_t0 + 60.0

    # Anchor tracking state: which anchor to re-acquire next
    next_anchor_idx = 1  # start from anchor[1] since anchor[0] is the primary
    anchor_reacquire_window_s = 5.0  # seconds around anchor to attempt re-lock
    anchor_lock_time = None  # timestamp when the current anchor locked on
    # IMPORTANT: anchor_expired is ONLY used to gate the initial 2-second
    # "guaranteed display" window. After that, continuous tracking takes over.
    # We do NOT stop tracking when anchor expires — we keep following the player.
    ANCHOR_DISPLAY_DURATION = 2.0  # seconds for guaranteed display after anchor pick

    if len(anchors) > 1:
        logger.info(
            "process: multi-anchor mode with %d anchors, window=[%.2fs..%.2fs]",
            len(anchors), window_start_s, window_end_s,
        )
    elif selection_t0 is not None:
        logger.info(
            "process: single-anchor mode, window=[%.2fs..%.2fs]",
            window_start_s, window_end_s,
        )
    else:
        logger.info("process: no selection — full video mode")

    positions: list[dict[str, float]] = []
    cuts: list[float] = []

    prev_hist = None
    frame_idx = 0
    # Enhanced tracking: use configurable identity break limit instead of fixed 300
    # In enhanced mode, this can be much higher to prevent 7-second termination bug
    lost_limit = max_identity_break_frames

    # ── Histogram bank: stores multiple confirmed histograms for robust identity ──
    hist_bank: list[np.ndarray] = []  # top-K confirmed histograms
    HIST_BANK_MAX = histogram_bank_size  # Use enhanced configuration
    HIST_BANK_MIN_DIFF = (
        0.15  # min difference to add a new histogram (avoid duplicates)
    )

    # ── Zoom detection state ──
    prev_median_area: float = 0.0
    zoom_scale: float = 1.0  # cumulative zoom factor vs first frame
    zoom_cooldown: int = 0  # frames to wait after zoom before trusting IoU
    ZOOM_AREA_RATIO = 0.50  # >50% change in median BB area = zoom event (0.35 was too sensitive)

    processed_frames = 0
    total_frames = 0
    det_frames = 0
    any_det = 0
    frame_h: float = 0.0
    frame_w: float = 0.0
    tracking_terminated = False
    identity_break_count = 0
    canonical_output_track_id: int | None = None
    while True:
        ok, frame = cap.read()
        if not ok:
            break

        if auto_calib_pending and calibration_model is None:
            fw = (
                float(frame.shape[1])
                if frame is not None and hasattr(frame, "shape")
                else 0.0
            )
            if fw > 0:
                calibration_model = CalibrationModel(
                    kind="auto_frame", meter_per_px=105.0 / max(1.0, fw)
                )
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

        # Strictly start tracking at the user-selected moment.
        if selection_t0 is not None and t < selection_t0:
            frame_idx += 1
            continue

        if tracking_terminated:
            frame_idx += 1
            continue

        # Skip frames outside the time window (if enabled)
        if t < window_start_s:
            frame_idx += 1
            continue
        if t > window_end_s:
            break

        # ── Multi-anchor re-acquisition checkpoint ──
        # When we reach the next anchor's timestamp, force the tracker to
        # re-acquire the player at the known position. This is the core fix
        # for the 7-second tracking loss: each anchor acts as a "correction"
        # that puts the cursor back on the right player.
        if next_anchor_idx < len(anchors):
            anchor = anchors[next_anchor_idx]
            if t >= anchor.t0 - 0.5:  # 0.5s before anchor — prepare to re-lock
                logger.info(
                    "Re-anchoring to selection %d/%d at t=%.2f (anchor_t=%.2f)",
                    next_anchor_idx + 1, len(anchors), t, anchor.t0,
                )
                # Reset target to anchor's known position
                selection_xywh = np.array(
                    [anchor.x, anchor.y, anchor.w, anchor.h], dtype=float,
                )
                selection_t0 = float(anchor.t0)
                # Set last_xywh to a SMALL box centered on the click
                # (not the oversized click box). This ensures the centroid
                # tracker uses realistic movement thresholds.
                acx = anchor.x + anchor.w / 2.0
                acy = anchor.y + anchor.h / 2.0
                # Use typical player size for this video resolution
                est_pw, est_ph = 14.0, 35.0
                state.last_xywh = np.array(
                    [acx - est_pw / 2, acy - est_ph / 2, est_pw, est_ph], dtype=float,
                )
                # Force re-acquisition by clearing target identity
                state.target_track_id = None
                state.target_hist = None  # will be recomputed from anchor crop
                state._ref_crop = None    # will be recomputed at lock-on
                state.lost_count = 0
                target_locked_once = False  # allow re-locking to new track ID
                identity_break_count = 0
                # Reset DeepSort so old track IDs don't interfere
                tracker = _reset_tracker(tracker, tracker_backend, orig_fps)
                next_anchor_idx += 1

        hist = frame_histogram(frame)
        if is_cut(prev_hist, hist):
            cuts.append(float(t))
            if not (strict_target_lock and target_locked_once):
                state.target_track_id = None
            # Keep last_xywh — we need the spatial prior for re-acquisition
            state.lost_count = 0
            tracker = _reset_tracker(tracker, tracker_backend, orig_fps)
            prev_median_area = 0.0
            zoom_cooldown = 0
        prev_hist = hist

        if (
            selection_xywh is not None
            and selection_t0 is not None
            and state.target_hist is None
        ):
            if abs(t - selection_t0) <= selection_window_s:
                sx, sy, sw, sh = selection_xywh
                sel_xyxy = np.array([sx, sy, sx + sw, sy + sh], dtype=float)
                state.target_hist = _compute_hist(frame, sel_xyxy)

        tracked_xyxy, tracked_conf, track_ids = _run_tracking(
            model, tracker, frame, tracker_backend
        )
        det_frames += 1
        if tracked_xyxy.size:
            any_det += 1

        # ── Zoom detection: compare median BB area across frames ──
        if zoom_cooldown > 0:
            zoom_cooldown -= 1
        if tracked_xyxy.size >= 1:
            areas = (tracked_xyxy[:, 2] - tracked_xyxy[:, 0]) * (
                tracked_xyxy[:, 3] - tracked_xyxy[:, 1]
            )
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
                    # When target is locked, do NOT reset the tracker — that
                    # destroys all track IDs and forces re-acquisition which
                    # picks the wrong player. Just scale the box and continue.
                    if strict_target_lock and target_locked_once:
                        # Keep tracking with current IDs — just update box size
                        zoom_cooldown = 3
                        logger.info(
                            "process: zoom detected at t=%.2f scale=%.2f (keeping locked target)",
                            t, scale_factor,
                        )
                    else:
                        state.target_track_id = None
                        state.lost_count = 0
                        tracker = _reset_tracker(tracker, tracker_backend, orig_fps)
                        zoom_cooldown = 5
                        logger.info(
                            "process: zoom detected at t=%.2f scale=%.2f (tracker reset)",
                            t, scale_factor,
                        )
            prev_median_area = cur_median_area

        # ── After zoom, prefer histogram matching for re-acquisition ──
        # Lowered thresholds: sandy/dirt backgrounds make histogram similarity
        # noisier than clean-grass professional footage.
        hist_min_sim = 0.05 if zoom_cooldown > 0 else 0.08

        if (
            selection_xywh is not None
            and state.target_track_id is None
            and selection_t0 is not None
        ):
            if abs(t - selection_t0) <= selection_window_s:
                if tracked_xyxy.size and track_ids.size:
                    # Find the detection whose CENTER is closest to the CENTER
                    # of the user's click. IoU matching is unreliable because
                    # the click box (51x53) is much larger than the player
                    # bounding box (~15x35) at low resolutions.
                    sx, sy, sw, sh = selection_xywh
                    click_cx = sx + sw / 2.0
                    click_cy = sy + sh / 2.0
                    
                    best_dist = float("inf")
                    best_idx = None
                    for i, bb in enumerate(tracked_xyxy):
                        cx = float((bb[0] + bb[2]) / 2.0)
                        cy = float((bb[1] + bb[3]) / 2.0)
                        dist = (cx - click_cx) ** 2 + (cy - click_cy) ** 2
                        if dist < best_dist:
                            best_dist = dist
                            best_idx = i
                    
                    # Accept if within reasonable range of click center
                    max_accept_dist = max(sw, sh, 60.0) * 1.5
                    if (
                        best_idx is not None
                        and best_dist <= max_accept_dist * max_accept_dist
                    ):
                        if (
                            (not strict_target_lock)
                            or (not target_locked_once)
                        ):
                            state.target_track_id = int(track_ids[best_idx])
                            target_locked_once = True
                        bb = tracked_xyxy[best_idx].astype(float)
                        det_cx = float((bb[0] + bb[2]) / 2.0)
                        det_cy = float((bb[1] + bb[3]) / 2.0)
                        logger.info(
                            "Target LOCKED at t=%.2f: click=(%.0f,%.0f) → detection=(%.0f,%.0f) dist=%.1f trackID=%s",
                            t, click_cx, click_cy, det_cx, det_cy,
                            float(best_dist**0.5),
                            state.target_track_id,
                        )
                        bw_lock = bb[2] - bb[0]
                        bh_lock = bb[3] - bb[1]
                        state.last_xywh = np.array(
                            [bb[0], bb[1], bw_lock, bh_lock], dtype=float
                        )
                        state.target_hist = _compute_hist(frame, bb)
                        # Store jersey color fingerprint for tracking verification
                        state._ref_crop = _jersey_fingerprint(frame, bb)
                        anchor_lock_time = t  # start 2s display timer
                        state.lost_count = 0
                        # Initialize Kalman filter at lock-on position
                        kalman = KalmanTarget(det_cx, det_cy, bw_lock, bh_lock)
                        logger.info("Kalman filter initialized at (%.0f, %.0f)", det_cx, det_cy)
        elif state.target_track_id is None and tracked_xyxy.size:
            # ── Enhanced combined histogram + proximity re-acquisition ──
            reacq_config = {
                'enhanced_tracking_mode': enhanced_tracking_mode,
                'reacquisition_search_radius': reacquisition_search_radius,
            }
            
            best_idx, confidence = _enhanced_reacquisition(
                frame, tracked_xyxy, track_ids, hist_bank, state.target_hist,
                state.last_xywh, selection_xywh, reacq_config
            )
            
            if best_idx is not None and track_ids.size:
                if (not strict_target_lock) or (not target_locked_once):
                    state.target_track_id = int(track_ids[best_idx])
                    target_locked_once = True
                bb = tracked_xyxy[best_idx].astype(float)
                state.last_xywh = np.array(
                    [bb[0], bb[1], bb[2] - bb[0], bb[3] - bb[1]], dtype=float
                )
                state.lost_count = 0
                logger.debug("Enhanced reacquisition successful at t=%.2f with confidence=%.3f", t, confidence)

        chosen = None
        chosen_conf = 0.0

        # ═══ CONTINUOUS JERSEY-COLOR VERIFIED TRACKING ═══
        # Works for BOTH anchor mode and single-click mode.
        # The anchor_expired flag only controls whether we're in the "guaranteed
        # 2-second display" window — tracking itself NEVER stops due to anchor expiry.
        # After anchor_expired, we fall through to the standard tracking path below
        # which uses the same jersey fingerprint + Kalman gating.
        ref_crop = getattr(state, '_ref_crop', None)

        # ── Kalman predict step (every frame, even when player is visible) ──
        if kalman is not None:
            kalman.predict()

        if len(anchors) > 0 and tracked_xyxy.size and state.last_xywh is not None and ref_crop is not None:
            lx, ly, lw, lh = state.last_xywh
            # Use Kalman predicted position if available, else last known
            if kalman is not None:
                lcx = kalman.predicted_cx
                lcy = kalman.predicted_cy
            else:
                lcx = lx + lw / 2.0
                lcy = ly + lh / 2.0

            # ── Step A: Track ID + jersey color verification ──
            id_match_found = False
            if state.target_track_id is not None and track_ids.size:
                match = np.where(track_ids == state.target_track_id)[0]
                if match.size:
                    bb = tracked_xyxy[int(match[0])].astype(float)
                    bcx = float((bb[0] + bb[2]) / 2.0)
                    bcy = float((bb[1] + bb[3]) / 2.0)
                    dist = np.sqrt((bcx - lcx) ** 2 + (bcy - lcy) ** 2)

                    # Scale max movement by player size + Kalman uncertainty
                    capped_dim = min(max(lw, lh), 60.0)
                    kalman_sigma = max(1.0, float(kalman.P[0, 0]) ** 0.5) if kalman is not None else 20.0
                    max_id_move = max(capped_dim * 2.0 + 20.0, kalman_sigma * 3.0)

                    if dist <= max_id_move:
                        cand_fp = _jersey_fingerprint(frame, bb)
                        crop_sim = _crop_similarity(ref_crop, cand_fp)

                        # Adaptive threshold: lower when player has been lost longer
                        jersey_thresh = max(0.30, 0.45 - state.lost_count * 0.02)

                        if crop_sim >= jersey_thresh:
                            chosen = bb
                            chosen_conf = 1.0
                            state.lost_count = 0
                            id_match_found = True
                            state.last_xywh = np.array(
                                [bb[0], bb[1], bb[2] - bb[0], bb[3] - bb[1]], dtype=float
                            )
                            # Update Kalman with confirmed measurement
                            if kalman is not None:
                                bw = bb[2] - bb[0]
                                bh_k = bb[3] - bb[1]
                                kalman.update(bcx, bcy, bw, bh_k)
                            # Do NOT update ref_crop — keep it frozen from anchor

            # ── Step B: ID lost or jersey rejected — Kalman-gated color search ──
            if not id_match_found:
                # Search radius scales with how long player has been lost
                base_radius = min(max(lw, lh), 60.0) * 2.0 + 20.0
                lost_expansion = state.lost_count * 5.0  # expand 5px per lost frame
                max_move = min(base_radius + lost_expansion, 200.0)

                candidates = []
                for i, bb in enumerate(tracked_xyxy):
                    bcx = float((bb[0] + bb[2]) / 2.0)
                    bcy = float((bb[1] + bb[3]) / 2.0)
                    d = np.sqrt((bcx - lcx) ** 2 + (bcy - lcy) ** 2)
                    if d <= max_move:
                        cand_fp = _jersey_fingerprint(frame, bb)
                        crop_sim = _crop_similarity(ref_crop, cand_fp)
                        # Adaptive threshold: lower when player has been lost longer
                        jersey_thresh = max(0.25, 0.40 - state.lost_count * 0.02)
                        if crop_sim >= jersey_thresh:
                            norm_d = d / max(max_move, 1.0)
                            # Combined score: appearance + proximity
                            score = crop_sim * 0.5 + (1.0 - norm_d) * 0.5
                            candidates.append((i, d, crop_sim, score))

                if candidates:
                    candidates.sort(key=lambda c: c[3], reverse=True)
                    best_i, best_d, best_sim, best_score = candidates[0]
                    bb = tracked_xyxy[best_i].astype(float)
                    chosen = bb
                    chosen_conf = min(0.95, best_sim)
                    state.lost_count = 0
                    if track_ids.size:
                        state.target_track_id = int(track_ids[best_i])
                    bcx_new = float((bb[0] + bb[2]) / 2.0)
                    bcy_new = float((bb[1] + bb[3]) / 2.0)
                    state.last_xywh = np.array(
                        [bb[0], bb[1], bb[2] - bb[0], bb[3] - bb[1]], dtype=float
                    )
                    # Update Kalman with re-acquired measurement
                    if kalman is not None:
                        bw = bb[2] - bb[0]
                        bh_k = bb[3] - bb[1]
                        kalman.update(bcx_new, bcy_new, bw, bh_k)
                    # Do NOT update ref_crop — keep frozen from anchor
                else:
                    state.lost_count += 1

        elif state.target_track_id is not None and tracked_xyxy.size:
            match = (
                np.where(track_ids == state.target_track_id)[0]
                if track_ids.size
                else np.array([], dtype=int)
            )
            if match.size:
                bb = tracked_xyxy[int(match[0])].astype(float)
                # Guard against tracker-ID reuse: the same numeric track ID can
                # occasionally jump to another player after occlusion/cuts.
                same_identity = True
                cand_hist = _compute_hist(frame, bb)
                sim = _enhanced_hist_bank_best_sim(hist_bank, cand_hist, state.target_hist, use_enhanced_similarity=enhanced_tracking_mode)

                # Even when the ID matches, require minimum appearance similarity.
                if state.target_hist is None:
                    same_identity = False
                elif sim < same_id_min_hist_sim:
                    same_identity = False

                if state.last_xywh is not None:
                    lx, ly, lw, lh = state.last_xywh
                    lcx = lx + lw / 2.0
                    lcy = ly + lh / 2.0
                    bcx = float((bb[0] + bb[2]) / 2.0)
                    bcy = float((bb[1] + bb[3]) / 2.0)
                    dist = np.sqrt((bcx - lcx) ** 2 + (bcy - lcy) ** 2)

                    # Max plausible per-frame movement:
                    # At 3fps, a player moves ~5m/s max → ~1.7m per frame.
                    # On a 424px-wide frame showing ~50m of pitch, that's
                    # ~14px per frame. Allow 3x margin = ~45px max per frame.
                    # Also scale by player box for larger resolutions.
                    max_per_frame_move = max(lw, lh) * 1.5 + 20.0  # ~45px for tiny players
                    
                    # Overall search distance for same-ID (covers missed frames)
                    max_dist = max(lw, lh) * same_id_max_dist_factor

                    if dist > max_per_frame_move and state.lost_count == 0:
                        # Detection jumped too far in one frame — ID swap!
                        same_identity = False
                        logger.info(
                            "REJECTED ID swap at t=%.2f: dist=%.1f > max_per_frame=%.1f (trackID=%s)",
                            t, dist, max_per_frame_move, state.target_track_id,
                        )
                    elif dist > max_dist:
                        same_identity = False

                if same_identity:
                    chosen = bb
                    chosen_conf = 1.0
                    identity_break_count = 0
                elif strict_target_lock and target_locked_once and strict_no_reacquire:
                    identity_break_count += 1
                    # Use enhanced tracking termination logic
                    if _should_terminate_tracking(enhanced_tracking_mode, identity_break_count, max_identity_break_frames, strict_no_reacquire):
                        tracking_terminated = True
                        logger.info("Tracking terminated at t=%.2f due to identity breaks (legacy mode)", t)
                    frame_idx += 1
                    continue
            else:
                # In strict mode, once target identity is locked, never jump to a
                # different detection. If the locked ID is missing, stay hidden.
                if strict_target_lock and target_locked_once:
                    # Optional safe re-acquire: accept only very strong same-player
                    # candidates by appearance + proximity.
                    if safe_reacquire and state.last_xywh is not None and track_ids.size:
                        lx, ly, lw, lh = state.last_xywh
                        lcx, lcy = lx + lw / 2.0, ly + lh / 2.0
                        max_dist = max(lw, lh) * safe_reacquire_dist_factor + 10.0
                        best_idx = None
                        best_score = -1e9
                        for i, cand_bb in enumerate(tracked_xyxy):
                            c_hist = _compute_hist(frame, cand_bb)
                            c_sim = _enhanced_hist_bank_best_sim(hist_bank, c_hist, state.target_hist, use_enhanced_similarity=enhanced_tracking_mode)
                            if c_sim < safe_reacquire_min_hist:
                                continue

                            ccx = float((cand_bb[0] + cand_bb[2]) / 2.0)
                            ccy = float((cand_bb[1] + cand_bb[3]) / 2.0)
                            c_dist = np.sqrt((ccx - lcx) ** 2 + (ccy - lcy) ** 2)
                            if c_dist > max_dist:
                                continue

                            score = c_sim - (c_dist / max_dist) * 0.15
                            if score > best_score:
                                best_score = score
                                best_idx = i

                        if best_idx is not None:
                            state.target_track_id = int(track_ids[best_idx])
                            bb = tracked_xyxy[best_idx].astype(float)
                            chosen = bb
                            chosen_conf = 0.95
                            identity_break_count = 0
                            state.last_xywh = np.array(
                                [bb[0], bb[1], bb[2] - bb[0], bb[3] - bb[1]], dtype=float
                            )
                        else:
                            if strict_no_reacquire:
                                identity_break_count += 1
                                # Use enhanced tracking termination logic
                                if _should_terminate_tracking(enhanced_tracking_mode, identity_break_count, max_identity_break_frames, strict_no_reacquire):
                                    tracking_terminated = True
                                    logger.info("Tracking terminated at t=%.2f due to identity breaks (legacy mode)", t)
                            frame_idx += 1
                            continue
                    else:
                        if strict_no_reacquire:
                            identity_break_count += 1
                            # Use enhanced tracking termination logic
                            if _should_terminate_tracking(enhanced_tracking_mode, identity_break_count, max_identity_break_frames, strict_no_reacquire):
                                tracking_terminated = True
                                logger.info("Tracking terminated at t=%.2f due to identity breaks (legacy mode)", t)
                        frame_idx += 1
                        continue
                # IoU reattach (use lower threshold during zoom cooldown)
                # Lowered IoU thresholds for real-case partial occlusion / sandy bg
                iou_thresh = 0.05 if zoom_cooldown > 0 else 0.08
                if state.last_xywh is not None:
                    ridx = reattach_by_iou(
                        tracked_xyxy.astype(float), state.last_xywh, min_iou=iou_thresh
                    )
                    if ridx is not None and track_ids.size:
                        if (
                            (not strict_target_lock)
                            or (not target_locked_once)
                        ):
                            state.target_track_id = int(track_ids[ridx])
                            target_locked_once = True
                        bb = tracked_xyxy[ridx].astype(float)
                        chosen = bb
                        chosen_conf = 1.0
                # Histogram + proximity fallback
                if chosen is None and (state.target_hist is not None or hist_bank):
                    best_sim = -1.0
                    best_idx = None
                    for i, bb in enumerate(tracked_xyxy):
                        cand_hist = _compute_hist(frame, bb)
                        sim = _enhanced_hist_bank_best_sim(
                            hist_bank, cand_hist, state.target_hist, use_enhanced_similarity=enhanced_tracking_mode
                        )
                        if sim > best_sim:
                            best_sim = sim
                            best_idx = i
                    if (
                        best_idx is not None
                        and best_sim >= hist_min_sim
                        and track_ids.size
                    ):
                        if (
                            (not strict_target_lock)
                            or (not target_locked_once)
                        ):
                            state.target_track_id = int(track_ids[best_idx])
                            target_locked_once = True
                        bb = tracked_xyxy[best_idx].astype(float)
                        chosen = bb
                        chosen_conf = 1.0
                # Distance fallback: nearest detection to last known position
                # ONLY used when we have NO appearance reference (hist_bank empty AND no ref_crop)
                # This prevents jumping to wrong players when appearance data is available.
                if chosen is None and state.last_xywh is not None:
                    lx, ly, lw, lh = state.last_xywh
                    lcx, lcy = lx + lw / 2.0, ly + lh / 2.0
                    has_appearance_ref = bool(hist_bank) or state.target_hist is not None or ref_crop is not None
                    if not has_appearance_ref:
                        # No appearance data — distance-only is the only option
                        best_dist = float("inf")
                        best_didx = None
                        for i, bb in enumerate(tracked_xyxy):
                            bcx = float((bb[0] + bb[2]) / 2.0)
                            bcy = float((bb[1] + bb[3]) / 2.0)
                            d = np.sqrt((bcx - lcx) ** 2 + (bcy - lcy) ** 2)
                            if d < best_dist:
                                best_dist = d
                                best_didx = i
                        max_search_dist = max(lw, lh) * 2.0 + 10.0
                        if (
                            best_didx is not None
                            and best_dist <= max_search_dist
                            and track_ids.size
                        ):
                            if (
                                (not strict_target_lock)
                                or (not target_locked_once)
                            ):
                                state.target_track_id = int(track_ids[best_didx])
                                target_locked_once = True
                            bb = tracked_xyxy[best_didx].astype(float)
                            chosen = bb
                            chosen_conf = 0.5  # low confidence for distance-only match
                    # If we DO have appearance data but still no match, stay hidden
                    # rather than jumping to the wrong player.

        elif tracked_xyxy.size:
            if state.last_xywh is not None:
                ridx = reattach_by_iou(
                    tracked_xyxy.astype(float), state.last_xywh, min_iou=0.05
                )
                if ridx is not None:
                    bb = tracked_xyxy[int(ridx)].astype(float)
                    chosen = bb
                    chosen_conf = (
                        float(tracked_conf[ridx]) if tracked_conf.size else 0.5
                    )
                    if track_ids.size:
                        if (
                            (not strict_target_lock)
                            or (not target_locked_once)
                        ):
                            state.target_track_id = int(track_ids[ridx])
                            target_locked_once = True

            if (
                chosen is None
                and selection_xywh is not None
                and selection_t0 is not None
            ):
                if abs(t - selection_t0) <= selection_window_s:
                    # Find nearest detection to click center (same logic as primary matching)
                    sx, sy, sw, sh = selection_xywh
                    click_cx = sx + sw / 2.0
                    click_cy = sy + sh / 2.0
                    
                    best_dist = float("inf")
                    best_idx = None
                    for i, bb in enumerate(tracked_xyxy):
                        cx = float((bb[0] + bb[2]) / 2.0)
                        cy = float((bb[1] + bb[3]) / 2.0)
                        dist = (cx - click_cx) ** 2 + (cy - click_cy) ** 2
                        if dist < best_dist:
                            best_dist = dist
                            best_idx = i
                    
                    max_accept_dist = max(sw, sh, 60.0) * 1.5
                    if (
                        best_idx is not None
                        and best_dist <= max_accept_dist * max_accept_dist
                    ):
                        bb = tracked_xyxy[best_idx].astype(float)
                        chosen = bb
                        chosen_conf = (
                            float(tracked_conf[best_idx]) if tracked_conf.size else 0.5
                        )
                        if track_ids.size:
                            if (
                                (not strict_target_lock)
                                or (not target_locked_once)
                            ):
                                state.target_track_id = int(track_ids[best_idx])
                                target_locked_once = True

        if chosen is None:
            if state.target_track_id is not None:
                state.lost_count += 1
                # ── Velocity prediction for short gaps (enhanced configuration) ──
                # Use last known velocity to predict position instead of losing data.
                # Enhanced mode: use configurable prediction frames and gap duration
                if allow_predicted_points and len(anchors) == 0 and state.lost_count <= velocity_prediction_frames and len(positions) >= 2:
                    p_prev = positions[-1]
                    p_prev2 = positions[-2]
                    dt_pred = p_prev["t"] - p_prev2["t"]
                    if dt_pred > 1e-6:
                        vx = (p_prev["cx"] - p_prev2["cx"]) / dt_pred
                        vy = (p_prev["cy"] - p_prev2["cy"]) / dt_pred
                        dt_now = t - p_prev["t"]
                        if 0 < dt_now < 10.0:  # max 10 s gap (was 3 s)
                            pred_cx = p_prev["cx"] + vx * dt_now
                            pred_cy = p_prev["cy"] + vy * dt_now
                            pred_ncx = pred_cx / max(1.0, frame_w)
                            pred_ncy = pred_cy / max(1.0, frame_h)
                            if (
                                canonical_output_track_id is None
                                and state.target_track_id is not None
                            ):
                                canonical_output_track_id = int(state.target_track_id)
                            positions.append(
                                {
                                    "t": float(t),
                                    "cx": pred_cx,
                                    "cy": pred_cy,
                                    "ncx": pred_ncx,
                                    "ncy": pred_ncy,
                                    "conf": 0.3,  # low confidence for predicted
                                    "bbox": None,
                                    "trackId": int(canonical_output_track_id)
                                    if canonical_output_track_id is not None
                                    else None,
                                }
                            )
                if state.lost_count >= lost_limit:
                    if not (strict_target_lock and target_locked_once):
                        state.target_track_id = None
                    state.last_xywh = None
                    state.lost_count = 0
            frame_idx += 1
            continue

        # Reject physically implausible jumps even when tracker ID is present.
        if positions:
            prev = positions[-1]
            dt_prev = t - float(prev.get("t", t))
            if dt_prev > 1e-6 and frame_w > 0 and frame_h > 0:
                x1j, y1j, x2j, y2j = chosen
                cur_ncx = float((x1j + x2j) / 2.0) / max(1.0, frame_w)
                cur_ncy = float((y1j + y2j) / 2.0) / max(1.0, frame_h)
                prev_ncx = float(prev.get("ncx", float(prev.get("cx", 0.0)) / max(1.0, frame_w)))
                prev_ncy = float(prev.get("ncy", float(prev.get("cy", 0.0)) / max(1.0, frame_h)))
                jump_speed = np.sqrt((cur_ncx - prev_ncx) ** 2 + (cur_ncy - prev_ncy) ** 2) / dt_prev
                if jump_speed > max_locked_norm_speed:
                    state.lost_count += 1
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
                state.target_hist = (0.9 * state.target_hist + 0.1 * hist).astype(
                    np.float32
                )
            # ── Enhanced histogram bank management for robust re-acquisition ──
            if len(hist_bank) < HIST_BANK_MAX:
                # Enhanced diversity check: only add if sufficiently different from existing bank entries
                is_novel = True
                min_diversity_threshold = HIST_BANK_MIN_DIFF
                
                for bh in hist_bank:
                    similarity = _enhanced_hist_similarity(hist, bh)
                    if similarity > (1.0 - min_diversity_threshold):
                        is_novel = False
                        break
                
                if is_novel:
                    hist_bank.append(hist.copy())
                    logger.debug("Added histogram to bank (size: %d/%d)", len(hist_bank), HIST_BANK_MAX)
            elif len(hist_bank) == HIST_BANK_MAX:
                # Bank is full - replace least similar histogram if current one is more diverse
                worst_idx = None
                worst_avg_sim = float('inf')
                
                for i, bh in enumerate(hist_bank):
                    # Calculate average similarity to all other histograms in bank
                    avg_sim = sum(_enhanced_hist_similarity(bh, other) for j, other in enumerate(hist_bank) if i != j)
                    avg_sim /= max(1, len(hist_bank) - 1)
                    
                    if avg_sim < worst_avg_sim:
                        worst_avg_sim = avg_sim
                        worst_idx = i
                
                # Replace if current histogram is more diverse
                if worst_idx is not None:
                    current_avg_sim = sum(_enhanced_hist_similarity(hist, bh) for bh in hist_bank)
                    current_avg_sim /= len(hist_bank)
                    
                    if current_avg_sim < worst_avg_sim:
                        hist_bank[worst_idx] = hist.copy()
                        logger.debug("Replaced histogram in bank at index %d", worst_idx)

        # Store both pixel and normalized (frame-relative) coordinates.
        # Normalized coords eliminate zoom-induced false motion.
        ncx = cx / max(1.0, frame_w) if frame_w > 0 else cx
        ncy = cy / max(1.0, frame_h) if frame_h > 0 else cy
        if canonical_output_track_id is None and state.target_track_id is not None:
            canonical_output_track_id = int(state.target_track_id)

        positions.append(
            {
                "t": float(t),
                "cx": cx,
                "cy": cy,
                "ncx": ncx,
                "ncy": ncy,
                "conf": float(chosen_conf),
                "bbox": [float(x1), float(y1), float(x2), float(y2)],
                "trackId": int(canonical_output_track_id)
                if canonical_output_track_id is not None
                else None,
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

    # ── Post-loop gap interpolation (optional) ──
    # Disabled by default in strict mode to avoid fake cursor motion when
    # the selected player is not visible.
    if allow_gap_interpolation:
        max_gap_s = 5.0
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
                        interp_ncx = (
                            p0.get("ncx", interp_cx)
                            + (p1.get("ncx", p1["cx"]) - p0.get("ncx", p0["cx"])) * frac
                        )
                        interp_ncy = (
                            p0.get("ncy", interp_cy)
                            + (p1.get("ncy", p1["cy"]) - p0.get("ncy", p0["cy"])) * frac
                        )
                        interpolated.append(
                            {
                                "t": float(interp_t),
                                "cx": float(interp_cx),
                                "cy": float(interp_cy),
                                "ncx": float(interp_ncx),
                                "ncy": float(interp_ncy),
                                "conf": 0.25,  # low confidence for interpolated
                                "bbox": None,
                                "trackId": None,
                            }
                        )
            interpolated.append(positions[-1])
            positions = interpolated
            logger.info(
                "process: interpolation added %d points (total now %d)",
                len(positions) - len([p for p in positions if p["conf"] > 0.25]),
                len(positions),
            )

    # ── Final strict output cleanup ──
    # Keep only physically consistent points and stop after long target loss.
    output_max_gap_s = float(os.getenv("SCOUTAI_OUTPUT_MAX_GAP_S", "6.0"))
    output_max_norm_speed = float(
        os.getenv("SCOUTAI_OUTPUT_MAX_NORM_SPEED", str(max_locked_norm_speed))
    )
    if len(positions) >= 2:
        cleaned: list[dict[str, Any]] = [positions[0]]
        for cur in positions[1:]:
            prev = cleaned[-1]
            dt = float(cur.get("t", 0.0)) - float(prev.get("t", 0.0))
            if dt <= 1e-6:
                continue
            if dt > output_max_gap_s:
                # Skip inconsistent point but keep remaining output.
                continue

            prev_ncx = float(prev.get("ncx", float(prev.get("cx", 0.0)) / max(1.0, frame_w)))
            prev_ncy = float(prev.get("ncy", float(prev.get("cy", 0.0)) / max(1.0, frame_h)))
            cur_ncx = float(cur.get("ncx", float(cur.get("cx", 0.0)) / max(1.0, frame_w)))
            cur_ncy = float(cur.get("ncy", float(cur.get("cy", 0.0)) / max(1.0, frame_h)))
            v = np.sqrt((cur_ncx - prev_ncx) ** 2 + (cur_ncy - prev_ncy) ** 2) / dt
            if v > output_max_norm_speed:
                continue

            cleaned.append(cur)

        if len(cleaned) >= 2:
            positions = cleaned

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

    metrics = compute_metrics(
        ts, cxs, cys, calibration_model, norm_xs=ncxs, norm_ys=ncys
    )

    debug: dict[str, Any] = {
        "elapsedSeconds": float(elapsed_total),
        "origFps": float(orig_fps),
        "samplingFps": float(req.samplingFps),
        "step": int(step),
        "effectiveSamplingFps": float(effective_sampling),
        "windowMode": len(anchors) > 0,
        "anchorCount": len(anchors),
        "windowStart": float(window_start_s),
        "windowEnd": float(window_end_s) if window_end_s != float("inf") else None,
        "trackerBackend": tracker_backend,
        "calibrated": bool(calibration_model is not None),
        "calibrationKind": calibration_model.kind
        if calibration_model is not None
        else None,
        "meterPerPx": float(calibration_model.meter_per_px)
        if calibration_model is not None and calibration_model.meter_per_px is not None
        else None,
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


@app.post("/profile-player", response_model=ProfilePlayerResponse)
def profile_player(req: ProfilePlayerRequest) -> Any:
    """Extract crops from video at each selection point and build a Claude
    player fingerprint.  Called by the backend before /process-upload when
    multi-selection (5-point cursor) mode is active."""
    selections = [
        {"t0": s.t0, "x": s.x, "y": s.y, "w": s.w, "h": s.h}
        for s in req.selections
    ]
    logger.info(
        "profile-player: profiling with %d selections from %s",
        len(selections),
        req.video_path,
    )
    profile = profile_player_from_video(req.video_path, selections)
    return {
        "profile": profile,
        "crops_used": len(selections),
        "model": os.getenv("CLAUDE_MODEL", "claude-sonnet-4-20250514"),
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
    samplingFps: float = Form(1.0),
    tracker: str | None = Form(None),
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
            "tracker": tracker,
            "selection": None,
            "calibration": None,
            "player_profile": None,
            "multi_selections": None,
        }
        if selection:
            sel_data = json.loads(selection)
            # Extract player_profile if embedded in the selection by the backend
            if isinstance(sel_data, dict) and "player_profile" in sel_data:
                payload["player_profile"] = sel_data.pop("player_profile")
            # Extract multi_selections (anchor points for re-acquisition)
            if isinstance(sel_data, dict) and "multi_selections" in sel_data:
                payload["multi_selections"] = sel_data.pop("multi_selections")
            payload["selection"] = sel_data
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
