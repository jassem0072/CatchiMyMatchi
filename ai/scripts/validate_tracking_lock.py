#!/usr/bin/env python3
"""Validate single-player tracking quality from ScoutAI /process-upload output.

This script sends one video + selection to the AI service and checks whether
tracking behaves like a strict single-target lock:
- one consistent trackId (no identity switching),
- starts around selected time,
- no implausible position jumps,
- reasonable temporal continuity.

Exit code:
- 0: PASS
- 1: FAIL
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys
from dataclasses import dataclass
from typing import Any

try:
    import requests
except ModuleNotFoundError:
    print("Missing dependency: requests")
    print("Install with: py -m pip install requests")
    sys.exit(2)


@dataclass
class CheckResult:
    name: str
    ok: bool
    message: str


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate strict single-player tracking via /process-upload"
    )
    parser.add_argument("--video", required=True, help="Path to input video file")
    parser.add_argument(
        "--base-url",
        default="http://127.0.0.1:8001",
        help="AI service base URL (default: http://127.0.0.1:8001)",
    )
    parser.add_argument("--t0", type=float, required=True, help="Selection time (seconds)")
    parser.add_argument("--x", type=float, required=True, help="Selection x (pixels)")
    parser.add_argument("--y", type=float, required=True, help="Selection y (pixels)")
    parser.add_argument("--w", type=float, required=True, help="Selection width (pixels)")
    parser.add_argument("--h", type=float, required=True, help="Selection height (pixels)")
    parser.add_argument(
        "--sampling-fps",
        type=float,
        default=4.0,
        help="Sampling FPS sent to AI (default: 4)",
    )
    parser.add_argument(
        "--tracker",
        choices=["bytetrack", "deepsort"],
        default="bytetrack",
        help="Tracking backend request hint (default: bytetrack)",
    )
    parser.add_argument(
        "--start-tolerance",
        type=float,
        default=1.0,
        help="Allowed seconds before t0 for first point (default: 1.0)",
    )
    parser.add_argument(
        "--max-gap",
        type=float,
        default=1.8,
        help="Max allowed gap (seconds) between consecutive points (default: 1.8)",
    )
    parser.add_argument(
        "--max-norm-speed",
        type=float,
        default=0.55,
        help="Max normalized speed (units/s) allowed between points (default: 0.55)",
    )
    parser.add_argument(
        "--min-points",
        type=int,
        default=6,
        help="Minimum number of positions required to pass (default: 6)",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=1800,
        help="Request timeout in seconds (default: 1800)",
    )
    parser.add_argument(
        "--save-json",
        default="",
        help="Optional output file path to save raw AI JSON response",
    )
    return parser.parse_args()


def _post_process_upload(args: argparse.Namespace) -> dict[str, Any]:
    endpoint = args.base_url.rstrip("/") + "/process-upload"

    if not os.path.isfile(args.video):
        raise FileNotFoundError(f"Video not found: {args.video}")

    selection = {
        "t0": args.t0,
        "x": args.x,
        "y": args.y,
        "w": args.w,
        "h": args.h,
    }

    with open(args.video, "rb") as fh:
        files = {"file": (os.path.basename(args.video), fh, "video/mp4")}
        data = {
            "chunkIndex": "0",
            "samplingFps": str(args.sampling_fps),
            "tracker": args.tracker,
            "selection": json.dumps(selection),
        }
        resp = requests.post(endpoint, files=files, data=data, timeout=args.timeout)

    if resp.status_code >= 400:
        raise RuntimeError(
            f"AI request failed: HTTP {resp.status_code}\n{resp.text[:800]}"
        )

    payload = resp.json()
    if args.save_json:
        with open(args.save_json, "w", encoding="utf-8") as out:
            json.dump(payload, out, ensure_ascii=True, indent=2)
    return payload


def _as_float(v: Any, default: float = 0.0) -> float:
    try:
        if v is None:
            return default
        return float(v)
    except Exception:
        return default


def _ncx(p: dict[str, Any]) -> float:
    if isinstance(p.get("ncx"), (int, float)):
        return float(p["ncx"])
    if isinstance(p.get("cx"), (int, float)):
        return float(p["cx"]) / 1920.0
    return 0.5


def _ncy(p: dict[str, Any]) -> float:
    if isinstance(p.get("ncy"), (int, float)):
        return float(p["ncy"])
    if isinstance(p.get("cy"), (int, float)):
        return float(p["cy"]) / 1080.0
    return 0.5


def _tid(p: dict[str, Any]) -> int | None:
    v = p.get("trackId")
    if isinstance(v, bool):
        return None
    if isinstance(v, int):
        return v
    if isinstance(v, float):
        return int(v)
    try:
        return int(v)
    except Exception:
        return None


def _validate(payload: dict[str, Any], args: argparse.Namespace) -> tuple[list[CheckResult], list[dict[str, Any]]]:
    positions_raw = payload.get("positions")
    if not isinstance(positions_raw, list):
        return [CheckResult("positions_field", False, "Response has no positions list")], []

    positions: list[dict[str, Any]] = [
        p for p in positions_raw if isinstance(p, dict) and isinstance(p.get("t"), (int, float))
    ]
    positions.sort(key=lambda p: float(p["t"]))

    checks: list[CheckResult] = []

    checks.append(
        CheckResult(
            "min_points",
            len(positions) >= args.min_points,
            f"points={len(positions)} min_required={args.min_points}",
        )
    )

    if positions:
        first_t = _as_float(positions[0].get("t"))
        ok = first_t >= (args.t0 - args.start_tolerance)
        checks.append(
            CheckResult(
                "start_time",
                ok,
                f"first_t={first_t:.3f} selection_t0={args.t0:.3f} tolerance={args.start_tolerance:.3f}",
            )
        )
    else:
        checks.append(CheckResult("start_time", False, "No points to evaluate start time"))

    tids = [_tid(p) for p in positions]
    tids_non_null = [t for t in tids if t is not None]
    unique_tids = sorted(set(tids_non_null))
    checks.append(
        CheckResult(
            "single_track_id",
            len(unique_tids) <= 1,
            f"unique_track_ids={unique_tids if unique_tids else 'none'}",
        )
    )

    max_gap = 0.0
    jump_count = 0
    max_speed_seen = 0.0

    for i in range(1, len(positions)):
        a = positions[i - 1]
        b = positions[i]
        dt = _as_float(b.get("t")) - _as_float(a.get("t"))
        if dt <= 1e-6:
            continue

        if dt > max_gap:
            max_gap = dt

        dx = _ncx(b) - _ncx(a)
        dy = _ncy(b) - _ncy(a)
        speed = math.sqrt(dx * dx + dy * dy) / dt
        if speed > max_speed_seen:
            max_speed_seen = speed
        if speed > args.max_norm_speed:
            jump_count += 1

    checks.append(
        CheckResult(
            "max_gap",
            max_gap <= args.max_gap,
            f"max_gap={max_gap:.3f}s allowed={args.max_gap:.3f}s",
        )
    )
    checks.append(
        CheckResult(
            "jump_speed",
            jump_count == 0,
            f"jump_violations={jump_count} max_speed_seen={max_speed_seen:.3f} allowed={args.max_norm_speed:.3f}",
        )
    )

    return checks, positions


def main() -> int:
    args = _parse_args()

    try:
        payload = _post_process_upload(args)
    except Exception as exc:
        print(f"FAIL: request error: {exc}")
        return 1

    checks, positions = _validate(payload, args)

    print("=== AI Tracking Validation Report ===")
    debug = payload.get("debug")
    if isinstance(debug, dict):
        backend = debug.get("trackerBackend")
        if backend is not None:
            print(f"trackerBackend: {backend}")
    print(f"positions_count: {len(positions)}")

    failed = [c for c in checks if not c.ok]
    for c in checks:
        status = "PASS" if c.ok else "FAIL"
        print(f"[{status}] {c.name}: {c.message}")

    if failed:
        print("\nRESULT: FAIL")
        return 1

    print("\nRESULT: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
