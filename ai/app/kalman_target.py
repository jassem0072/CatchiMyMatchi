"""
Per-target Kalman filter for smooth motion prediction during occlusions.

State vector: [cx, cy, w, h, vx, vy]
Measurement:  [cx, cy, w, h]
"""
from __future__ import annotations

import numpy as np


class KalmanTarget:
    """Constant-velocity Kalman filter for a single tracked player."""

    def __init__(self, cx: float, cy: float, w: float, h: float) -> None:
        # State: [cx, cy, w, h, vx, vy]
        self.x = np.array([cx, cy, w, h, 0.0, 0.0], dtype=np.float64)

        # State transition matrix (constant velocity)
        self.F = np.eye(6, dtype=np.float64)
        self.F[0, 4] = 1.0  # cx += vx
        self.F[1, 5] = 1.0  # cy += vy

        # Measurement matrix (we observe cx, cy, w, h)
        self.H = np.zeros((4, 6), dtype=np.float64)
        self.H[0, 0] = 1.0
        self.H[1, 1] = 1.0
        self.H[2, 2] = 1.0
        self.H[3, 3] = 1.0

        # Process noise
        self.Q = np.diag([4.0, 4.0, 2.0, 2.0, 16.0, 16.0])

        # Measurement noise
        self.R = np.diag([4.0, 4.0, 8.0, 8.0])

        # Initial covariance — high uncertainty on velocity
        self.P = np.diag([10.0, 10.0, 10.0, 10.0, 100.0, 100.0])

        self.lost_frames: int = 0

    # ------------------------------------------------------------------
    def predict(self) -> np.ndarray:
        """Advance state by one step. Returns predicted [cx, cy, w, h]."""
        self.x = self.F @ self.x
        self.P = self.F @ self.P @ self.F.T + self.Q
        self.lost_frames += 1
        return self.x[:4].copy()

    def update(self, cx: float, cy: float, w: float, h: float) -> None:
        """Correct state with a new measurement."""
        z = np.array([cx, cy, w, h], dtype=np.float64)
        y = z - self.H @ self.x
        S = self.H @ self.P @ self.H.T + self.R
        K = self.P @ self.H.T @ np.linalg.inv(S)
        self.x = self.x + K @ y
        self.P = (np.eye(6) - K @ self.H) @ self.P
        self.lost_frames = 0

    # ------------------------------------------------------------------
    @property
    def predicted_cx(self) -> float:
        return float(self.x[0])

    @property
    def predicted_cy(self) -> float:
        return float(self.x[1])

    @property
    def predicted_w(self) -> float:
        return max(5.0, float(self.x[2]))

    @property
    def predicted_h(self) -> float:
        return max(5.0, float(self.x[3]))

    def gate_distance(self, cx: float, cy: float) -> float:
        """Mahalanobis-like gating distance for a candidate centroid."""
        dx = cx - self.x[0]
        dy = cy - self.x[1]
        # Use position covariance for gating
        sx = max(1.0, float(self.P[0, 0]) ** 0.5)
        sy = max(1.0, float(self.P[1, 1]) ** 0.5)
        return float(((dx / sx) ** 2 + (dy / sy) ** 2) ** 0.5)

    def pixel_distance(self, cx: float, cy: float) -> float:
        """Euclidean pixel distance from predicted position."""
        return float(((cx - self.x[0]) ** 2 + (cy - self.x[1]) ** 2) ** 0.5)
