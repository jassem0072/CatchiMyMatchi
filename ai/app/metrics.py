from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from .calibration import CalibrationModel


@dataclass
class MetricsConfig:
    sprint_speed_kmh: float = 25.0
    sprint_min_duration_s: float = 1.0
    heatmap_w: int = 24
    heatmap_h: int = 16
    smooth_window: int = 5


def _moving_average(x: np.ndarray, window: int) -> np.ndarray:
    if window <= 1 or x.size == 0:
        return x
    window = min(window, x.size)
    kernel = np.ones(window, dtype=np.float32) / float(window)
    return np.convolve(x, kernel, mode="same")


def compute_heatmap(
    xs: np.ndarray,
    ys: np.ndarray,
    grid_w: int,
    grid_h: int,
    bounds: tuple[float, float, float, float],
) -> list[list[int]]:
    xmin, ymin, xmax, ymax = bounds
    if xs.size == 0:
        return [[0 for _ in range(grid_w)] for _ in range(grid_h)]

    xs_n = (xs - xmin) / max(1e-6, (xmax - xmin))
    ys_n = (ys - ymin) / max(1e-6, (ymax - ymin))

    xi = np.clip((xs_n * grid_w).astype(int), 0, grid_w - 1)
    yi = np.clip((ys_n * grid_h).astype(int), 0, grid_h - 1)

    counts = np.zeros((grid_h, grid_w), dtype=np.int32)
    for xj, yj in zip(xi, yi):
        counts[yj, xj] += 1

    return counts.tolist()


def compute_metrics(
    ts: np.ndarray,
    cxs: np.ndarray,
    cys: np.ndarray,
    calibration: CalibrationModel | None,
    cfg: MetricsConfig | None = None,
) -> dict:
    cfg = cfg or MetricsConfig()

    if ts.size == 0:
        return {
            "distanceMeters": None,
            "avgSpeedKmh": None,
            "maxSpeedKmh": None,
            "sprintCount": 0,
            "accelPeaks": [],
            "heatmap": {
                "grid_w": cfg.heatmap_w,
                "grid_h": cfg.heatmap_h,
                "counts": compute_heatmap(np.array([]), np.array([]), cfg.heatmap_w, cfg.heatmap_h, (0, 0, 1, 1)),
                "coord_space": "image",
                "bounds": {"xmin": 0.0, "ymin": 0.0, "xmax": 1.0, "ymax": 1.0},
            },
        }

    # coordinate space for metrics
    coord_space = "image"
    xs = cxs.copy()
    ys = cys.copy()

    if calibration is not None and calibration.H is not None:
        coord_space = "pitch"
        pts = np.stack([xs, ys], axis=1).astype(np.float32)
        pts = pts.reshape((-1, 1, 2))
        import cv2

        out = cv2.perspectiveTransform(pts, calibration.H).reshape((-1, 2))
        xs = out[:, 0]
        ys = out[:, 1]

    # distance & speed only if calibrated
    if calibration is None:
        distance_m = None
        avg_kmh = None
        max_kmh = None
        accel_peaks: list[float] = []
        sprint_count = 0
    else:
        dt = np.diff(ts)
        dt = np.where(dt <= 1e-6, 1e-6, dt)

        dx = np.diff(xs)
        dy = np.diff(ys)

        if calibration.meter_per_px is not None:
            step_m = np.sqrt(dx * dx + dy * dy) * float(calibration.meter_per_px)
        else:
            # homography outputs meters already
            step_m = np.sqrt(dx * dx + dy * dy)

        distance_m = float(step_m.sum())

        v_mps = step_m / dt
        v_mps = _moving_average(v_mps, cfg.smooth_window)
        v_kmh = v_mps * 3.6

        max_kmh = float(np.max(v_kmh)) if v_kmh.size else 0.0
        avg_kmh = float(distance_m / max(1e-6, (ts[-1] - ts[0])) * 3.6) if ts.size >= 2 else 0.0

        accel = np.diff(v_mps) / dt[1:] if v_mps.size >= 2 else np.array([])
        accel_peaks = [float(np.max(accel))] if accel.size else []

        # sprint count
        if v_kmh.size:
            above = v_kmh > cfg.sprint_speed_kmh
            # each speed sample corresponds to segment between frames
            sprint_min_segments = int(np.ceil(cfg.sprint_min_duration_s / float(np.median(dt))))
            sprint_min_segments = max(1, sprint_min_segments)

            sprint_count = 0
            run = 0
            for val in above:
                if val:
                    run += 1
                else:
                    if run >= sprint_min_segments:
                        sprint_count += 1
                    run = 0
            if run >= sprint_min_segments:
                sprint_count += 1
        else:
            sprint_count = 0

    # heatmap bounds
    if coord_space == "pitch":
        bounds = (0.0, 0.0, 105.0, 68.0)
    else:
        bounds = (float(np.min(xs)), float(np.min(ys)), float(np.max(xs)), float(np.max(ys)))
        # expand if degenerate
        if abs(bounds[2] - bounds[0]) < 1e-6:
            bounds = (bounds[0], bounds[1], bounds[0] + 1.0, bounds[3])
        if abs(bounds[3] - bounds[1]) < 1e-6:
            bounds = (bounds[0], bounds[1], bounds[2], bounds[1] + 1.0)

    heat_counts = compute_heatmap(xs, ys, cfg.heatmap_w, cfg.heatmap_h, bounds)

    return {
        "distanceMeters": distance_m,
        "avgSpeedKmh": avg_kmh,
        "maxSpeedKmh": max_kmh,
        "sprintCount": int(sprint_count),
        "accelPeaks": accel_peaks,
        "heatmap": {
            "grid_w": cfg.heatmap_w,
            "grid_h": cfg.heatmap_h,
            "counts": heat_counts,
            "coord_space": coord_space,
            "bounds": {"xmin": float(bounds[0]), "ymin": float(bounds[1]), "xmax": float(bounds[2]), "ymax": float(bounds[3])},
        },
    }
