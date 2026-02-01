from __future__ import annotations

from dataclasses import dataclass

import cv2
import numpy as np

from .schemas import Calibration, HomographyCalibration, TwoPointsCalibration


@dataclass(frozen=True)
class CalibrationModel:
    kind: str
    meter_per_px: float | None = None
    H: np.ndarray | None = None

    def image_to_pitch(self, x: float, y: float) -> tuple[float, float] | None:
        if self.H is None:
            return None
        pt = np.array([[[x, y]]], dtype=np.float32)
        out = cv2.perspectiveTransform(pt, self.H)
        return float(out[0, 0, 0]), float(out[0, 0, 1])


def build_calibration(calibration: Calibration | None) -> CalibrationModel | None:
    if calibration is None:
        return None

    if isinstance(calibration, TwoPointsCalibration):
        dx = float(calibration.x2 - calibration.x1)
        dy = float(calibration.y2 - calibration.y1)
        dpx = (dx * dx + dy * dy) ** 0.5
        if dpx <= 1e-6:
            return None
        return CalibrationModel(kind="two_points", meter_per_px=float(calibration.distance_m) / dpx)

    if isinstance(calibration, HomographyCalibration):
        src = np.array(calibration.src_points, dtype=np.float32)
        dst = np.array(calibration.dst_points, dtype=np.float32)
        H = cv2.getPerspectiveTransform(src, dst)
        return CalibrationModel(kind="homography", H=H)

    return None
