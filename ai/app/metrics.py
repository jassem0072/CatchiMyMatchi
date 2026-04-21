from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from .calibration import CalibrationModel


# Maximum realistic speed for a football player (km/h).
# Usain Bolt peaks ~44 km/h; fastest footballers ~37 km/h.
# We use 45 as a generous cap to reject tracking noise.
MAX_HUMAN_SPEED_KMH: float = 45.0


@dataclass
class MetricsConfig:
    sprint_speed_kmh: float = 25.0
    sprint_min_duration_s: float = 1.0
    heatmap_w: int = 24
    heatmap_h: int = 16
    smooth_window: int = 5
    max_speed_kmh: float = MAX_HUMAN_SPEED_KMH


def _moving_average(x: np.ndarray, window: int) -> np.ndarray:
    if window <= 1 or x.size == 0:
        return x
    window = min(window, x.size)
    kernel = np.ones(window, dtype=np.float32) / float(window)
    return np.convolve(x, kernel, mode="same")


def _median_filter(x: np.ndarray, window: int = 3) -> np.ndarray:
    """Simple 1-D median filter to reject single-frame tracking spikes."""
    if window <= 1 or x.size <= 2:
        return x
    hw = window // 2
    out = x.copy()
    for i in range(x.size):
        lo = max(0, i - hw)
        hi = min(x.size, i + hw + 1)
        out[i] = float(np.median(x[lo:hi]))
    return out


def _smooth_positions(xs: np.ndarray, ys: np.ndarray, alpha: float = 0.4) -> tuple[np.ndarray, np.ndarray]:
    """Exponential moving average on positions to reduce BB-center jitter."""
    if xs.size <= 1:
        return xs.copy(), ys.copy()
    sx = xs.copy().astype(np.float64)
    sy = ys.copy().astype(np.float64)
    for i in range(1, len(sx)):
        sx[i] = alpha * xs[i] + (1 - alpha) * sx[i - 1]
        sy[i] = alpha * ys[i] + (1 - alpha) * sy[i - 1]
    return sx, sy


def _reject_teleports(
    ts: np.ndarray, xs: np.ndarray, ys: np.ndarray,
    max_px_per_s: float = 800.0,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Remove position samples where the player 'teleports' — an impossible
    jump caused by tracker ID-switch or false detection."""
    if ts.size <= 2:
        return ts, xs, ys
    keep = [0]
    for i in range(1, ts.size):
        dt = ts[i] - ts[keep[-1]]
        if dt <= 0:
            continue
        dx = xs[i] - xs[keep[-1]]
        dy = ys[i] - ys[keep[-1]]
        speed_px = float(np.sqrt(dx * dx + dy * dy)) / dt
        if speed_px <= max_px_per_s:
            keep.append(i)
    idx = np.array(keep)
    return ts[idx], xs[idx], ys[idx]


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
    norm_xs: np.ndarray | None = None,
    norm_ys: np.ndarray | None = None,
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

    # ── Pre-processing: smooth & reject teleports on raw pixel positions ──
    # Also filter normalized coords in sync with pixel coords
    ts, cxs, cys = _reject_teleports(ts, cxs, cys)
    if norm_xs is not None and norm_ys is not None and norm_xs.size == cxs.size:
        # Re-apply teleport rejection using the same indices isn't trivial,
        # so re-run on norm coords with a matching threshold (0.5 = 50% of frame/s)
        _, norm_xs, norm_ys = _reject_teleports(ts, norm_xs, norm_ys, max_px_per_s=0.5)
    cxs, cys = _smooth_positions(cxs, cys, alpha=0.45)
    if norm_xs is not None and norm_ys is not None:
        norm_xs, norm_ys = _smooth_positions(norm_xs, norm_ys, alpha=0.45)

    if ts.size == 0:
        return {
            "distanceMeters": None, "avgSpeedKmh": None, "maxSpeedKmh": None,
            "sprintCount": 0, "accelPeaks": [], "movement": {},
            "heatmap": {"grid_w": cfg.heatmap_w, "grid_h": cfg.heatmap_h,
                        "counts": compute_heatmap(np.array([]), np.array([]),
                                                  cfg.heatmap_w, cfg.heatmap_h, (0, 0, 1, 1)),
                        "coord_space": "image",
                        "bounds": {"xmin": 0.0, "ymin": 0.0, "xmax": 1.0, "ymax": 1.0}},
        }

    # coordinate space for metrics
    coord_space = "image"
    xs = cxs.copy()
    ys = cys.copy()
    has_calibration = False
    v_kmh: np.ndarray | None = None
    accel: np.ndarray = np.array([])

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
        has_calibration = True
        dt = np.diff(ts)
        dt = np.where(dt <= 1e-6, 1e-6, dt)

        dx = np.diff(xs)
        dy = np.diff(ys)

        if calibration.meter_per_px is not None:
            step_m = np.sqrt(dx * dx + dy * dy) * float(calibration.meter_per_px)
        else:
            # homography outputs meters already
            step_m = np.sqrt(dx * dx + dy * dy)

        # Raw speed per segment
        v_mps_raw = step_m / dt

        # 1) Median filter to reject single-frame tracking spikes
        v_mps = _median_filter(v_mps_raw, window=3)
        # 2) Moving average for smoothing
        v_mps = _moving_average(v_mps, cfg.smooth_window)
        # 3) Physical speed cap
        max_cap_mps = cfg.max_speed_kmh / 3.6
        v_mps = np.clip(v_mps, 0, max_cap_mps)

        v_kmh = v_mps * 3.6  # type: np.ndarray

        # Recompute distance from cleaned speeds (excludes noise spikes)
        distance_m = float((v_mps * dt).sum())

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
        heat_xs, heat_ys = xs, ys
    else:
        # ── PCA rotation for uncalibrated data ──
        # Raw pixel coords from a camera at an angle create a diagonal pattern.
        # Rotate so the principal axis of movement aligns horizontally (pitch length).
        heat_xs, heat_ys = xs.copy(), ys.copy()
        if heat_xs.size >= 4:
            mx, my = float(np.mean(heat_xs)), float(np.mean(heat_ys))
            cx_ = heat_xs - mx
            cy_ = heat_ys - my
            cov = np.cov(cx_, cy_)
            if cov.shape == (2, 2):
                eigvals, eigvecs = np.linalg.eigh(cov)
                # Principal axis = eigenvector with largest eigenvalue
                principal = eigvecs[:, np.argmax(eigvals)]
                angle = float(np.arctan2(principal[1], principal[0]))
                # Rotate so principal axis is horizontal
                cos_a, sin_a = np.cos(-angle), np.sin(-angle)
                rx = cx_ * cos_a - cy_ * sin_a
                ry = cx_ * sin_a + cy_ * cos_a
                # If result is taller than wide, rotate 90° (pitch is landscape)
                x_range = float(np.max(rx) - np.min(rx))
                y_range = float(np.max(ry) - np.min(ry))
                if y_range > x_range * 1.2:
                    rx, ry = ry, -rx
                heat_xs = rx
                heat_ys = ry

        bounds = (float(np.min(heat_xs)), float(np.min(heat_ys)),
                  float(np.max(heat_xs)), float(np.max(heat_ys)))
        # expand if degenerate
        if abs(bounds[2] - bounds[0]) < 1e-6:
            bounds = (bounds[0], bounds[1], bounds[0] + 1.0, bounds[3])
        if abs(bounds[3] - bounds[1]) < 1e-6:
            bounds = (bounds[0], bounds[1], bounds[2], bounds[1] + 1.0)

    heat_counts = compute_heatmap(heat_xs, heat_ys, cfg.heatmap_w, cfg.heatmap_h, bounds)

    # ── Movement analytics (works for both calibrated & uncalibrated) ──
    # Use normalized coordinates for direction/turn analytics when available
    # to eliminate zoom-induced false motion.
    movement: dict = {}
    if ts.size >= 2:
        dt_all = np.diff(ts)
        dt_all = np.where(dt_all <= 1e-6, 1e-6, dt_all)
        dx_all = np.diff(xs)
        dy_all = np.diff(ys)
        total_duration = float(ts[-1] - ts[0])

        # For direction/turn analytics, prefer normalized coords (zoom-invariant)
        use_norm = (norm_xs is not None and norm_ys is not None
                    and norm_xs.size == ts.size)
        an_dx = np.diff(norm_xs) if use_norm else dx_all
        an_dy = np.diff(norm_ys) if use_norm else dy_all
        # Minimum segment length threshold (adjusted for coord scale)
        min_seg = 1e-5 if use_norm else 1e-3

        # Direction changes (>30° turn between consecutive segments)
        dir_changes = 0
        total_turn_deg = 0.0
        seg_count = 0
        for i in range(1, len(an_dx)):
            len0 = np.sqrt(an_dx[i - 1] ** 2 + an_dy[i - 1] ** 2)
            len1 = np.sqrt(an_dx[i] ** 2 + an_dy[i] ** 2)
            if len0 > min_seg and len1 > min_seg:
                dot = an_dx[i] * an_dx[i - 1] + an_dy[i] * an_dy[i - 1]
                cross = abs(an_dx[i] * an_dy[i - 1] - an_dy[i] * an_dx[i - 1])
                angle = float(np.arctan2(cross, dot))
                total_turn_deg += np.degrees(angle)
                seg_count += 1
                if angle > np.pi / 6:  # > 30 degrees
                    dir_changes += 1

        dur_min = total_duration / 60.0 if total_duration > 0 else 1.0
        movement["directionChanges"] = dir_changes
        movement["dirChangesPerMin"] = round(dir_changes / dur_min, 1)
        movement["avgTurnDegPerSec"] = round(total_turn_deg / total_duration, 2) if total_duration > 0 else 0.0
        movement["totalDurationSec"] = round(total_duration, 2)

        # Movement zones (only meaningful with calibration)
        if has_calibration and v_kmh is not None and v_kmh.size > 0:
            walking = float(np.sum((v_kmh > 0) & (v_kmh <= 7)))
            jogging = float(np.sum((v_kmh > 7) & (v_kmh <= 14)))
            running = float(np.sum((v_kmh > 14) & (v_kmh <= 21)))
            high_speed = float(np.sum((v_kmh > 21) & (v_kmh <= 25)))
            sprinting = float(np.sum(v_kmh > 25))
            total_seg = float(v_kmh.size) or 1.0
            movement["zones"] = {
                "walking_pct": round(walking / total_seg * 100, 1),
                "jogging_pct": round(jogging / total_seg * 100, 1),
                "running_pct": round(running / total_seg * 100, 1),
                "highSpeed_pct": round(high_speed / total_seg * 100, 1),
                "sprinting_pct": round(sprinting / total_seg * 100, 1),
            }
            movement["workRateMetersPerMin"] = round(float(distance_m or 0) / dur_min, 1)

            # Average acceleration (absolute)
            if accel.size > 0:
                movement["avgAccelMps2"] = round(float(np.mean(np.abs(accel))), 2)
            else:
                movement["avgAccelMps2"] = 0.0

        # Pixel-based speed analytics (works even without calibration)
        step_dist = np.sqrt(dx_all ** 2 + dy_all ** 2)
        v_px_per_s = step_dist / dt_all
        v_px_per_s = _median_filter(v_px_per_s, window=3)
        v_px_per_s = _moving_average(v_px_per_s, min(cfg.smooth_window, max(1, int(v_px_per_s.size))))
        movement["maxPxPerSec"] = round(float(np.percentile(v_px_per_s, 95)), 2) if v_px_per_s.size else 0.0
        movement["medianPxPerSec"] = round(float(np.median(v_px_per_s)), 2) if v_px_per_s.size else 0.0
        movement["totalPxDist"] = round(float(step_dist.sum()), 2)
        # Pixel-based acceleration
        if v_px_per_s.size >= 2:
            a_px = np.abs(np.diff(v_px_per_s)) / dt_all[1:]
            movement["p90AccelPxPerS2"] = round(float(np.percentile(a_px, 90)), 2)
        else:
            movement["p90AccelPxPerS2"] = 0.0

        # Normalized-coordinate speed (zoom-invariant, for more accurate analytics)
        if use_norm:
            n_step_dist = np.sqrt(an_dx ** 2 + an_dy ** 2)
            n_v = n_step_dist / dt_all
            n_v = _median_filter(n_v, window=3)
            n_v = _moving_average(n_v, min(cfg.smooth_window, max(1, int(n_v.size))))
            movement["normMaxSpeedPerSec"] = round(float(np.percentile(n_v, 95)), 5) if n_v.size else 0.0
            movement["normMedianSpeedPerSec"] = round(float(np.median(n_v)), 5) if n_v.size else 0.0
            movement["normTotalDist"] = round(float(n_step_dist.sum()), 5)
            if n_v.size >= 2:
                n_a = np.abs(np.diff(n_v)) / dt_all[1:]
                movement["normP90AccelPerS2"] = round(float(np.percentile(n_a, 90)), 5)
            else:
                movement["normP90AccelPerS2"] = 0.0

        # Moving ratio (% of time player is actually moving vs standing)
        # Use normalized coords if available for zoom robustness
        if use_norm:
            n_sd = np.sqrt(an_dx ** 2 + an_dy ** 2)
            nrx = float(np.max(norm_xs) - np.min(norm_xs)) if norm_xs.size > 1 else 1.0
            nry = float(np.max(norm_ys) - np.min(norm_ys)) if norm_ys.size > 1 else 1.0
            move_threshold = max(nrx, nry) * 0.005
            moving_count = int(np.sum(n_sd > move_threshold))
        else:
            range_x = float(np.max(xs) - np.min(xs)) if xs.size > 1 else 1.0
            range_y = float(np.max(ys) - np.min(ys)) if ys.size > 1 else 1.0
            move_threshold = max(range_x, range_y) * 0.005
            moving_count = int(np.sum(step_dist > move_threshold))
        movement["movingRatio"] = round(moving_count / max(1, len(dt_all)), 3)
        movement["numPositions"] = int(ts.size)

        # ── Quality / confidence score ──
        # Higher = more trustworthy data. Based on:
        #   - number of position samples (more = better)
        #   - tracking continuity (fewer teleport gaps)
        #   - duration of observation
        pts_score = min(1.0, ts.size / 150.0)  # 150+ positions = max
        dur_score = min(1.0, total_duration / 30.0)  # 30+ seconds = max
        # Continuity: ratio of final positions kept vs expected at sampling rate
        expected_pts = total_duration * 3.0  # ~3 FPS sampling
        continuity = min(1.0, ts.size / max(1.0, expected_pts))
        cal_bonus = 0.15 if has_calibration else 0.0
        quality = min(1.0, 0.35 * pts_score + 0.25 * dur_score + 0.25 * continuity + cal_bonus)
        movement["qualityScore"] = round(quality, 3)

    return {
        "distanceMeters": distance_m,
        "avgSpeedKmh": avg_kmh,
        "maxSpeedKmh": max_kmh,
        "sprintCount": int(sprint_count),
        "accelPeaks": accel_peaks,
        "movement": movement,
        "heatmap": {
            "grid_w": cfg.heatmap_w,
            "grid_h": cfg.heatmap_h,
            "counts": heat_counts,
            "coord_space": coord_space,
            "bounds": {"xmin": float(bounds[0]), "ymin": float(bounds[1]), "xmax": float(bounds[2]), "ymax": float(bounds[3])},
        },
    }
