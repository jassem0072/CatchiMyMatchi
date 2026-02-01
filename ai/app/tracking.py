from __future__ import annotations

import logging
from dataclasses import dataclass

import numpy as np

logger = logging.getLogger(__name__)


def iou_xywh(a: np.ndarray, b: np.ndarray) -> float:
    ax1, ay1, aw, ah = a
    bx1, by1, bw, bh = b
    ax2, ay2 = ax1 + aw, ay1 + ah
    bx2, by2 = bx1 + bw, by1 + bh

    ix1 = max(ax1, bx1)
    iy1 = max(ay1, by1)
    ix2 = min(ax2, bx2)
    iy2 = min(ay2, by2)

    iw = max(0.0, ix2 - ix1)
    ih = max(0.0, iy2 - iy1)
    inter = iw * ih
    if inter <= 0:
        return 0.0

    ua = aw * ah + bw * bh - inter
    return float(inter / max(1e-6, ua))


def xyxy_to_xywh(xyxy: np.ndarray) -> np.ndarray:
    x1, y1, x2, y2 = xyxy
    return np.array([x1, y1, x2 - x1, y2 - y1], dtype=float)


@dataclass
class TargetState:
    target_track_id: int | None = None
    last_xywh: np.ndarray | None = None
    lost_count: int = 0
    target_hist: np.ndarray | None = None


def pick_initial_target(detections_xyxy: np.ndarray, selection_xywh: np.ndarray) -> int | None:
    if detections_xyxy.size == 0:
        return None

    best_idx = None
    best_iou = -1.0
    for i, bb in enumerate(detections_xyxy):
        iou = iou_xywh(xyxy_to_xywh(bb), selection_xywh)
        if iou > best_iou:
            best_iou = iou
            best_idx = i

    if best_idx is None or best_iou < 0.05:
        return None
    return int(best_idx)


def reattach_by_iou(tracks_xyxy: np.ndarray, last_xywh: np.ndarray, min_iou: float = 0.2) -> int | None:
    if tracks_xyxy.size == 0:
        return None

    best_iou = -1.0
    best_idx = None
    for i, bb in enumerate(tracks_xyxy):
        iou = iou_xywh(xyxy_to_xywh(bb), last_xywh)
        if iou > best_iou:
            best_iou = iou
            best_idx = i

    if best_idx is None or best_iou < min_iou:
        return None
    return int(best_idx)
