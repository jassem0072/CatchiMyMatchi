from __future__ import annotations

import cv2
import numpy as np


def frame_histogram(frame_bgr: np.ndarray) -> np.ndarray:
    hsv = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2HSV)
    hist = cv2.calcHist([hsv], [0, 1], None, [30, 32], [0, 180, 0, 256])
    cv2.normalize(hist, hist)
    return hist.flatten()


def is_cut(prev_hist: np.ndarray | None, curr_hist: np.ndarray, threshold: float = 0.65) -> bool:
    if prev_hist is None:
        return False
    dist = cv2.compareHist(prev_hist.astype(np.float32), curr_hist.astype(np.float32), cv2.HISTCMP_BHATTACHARYYA)
    return dist > threshold
