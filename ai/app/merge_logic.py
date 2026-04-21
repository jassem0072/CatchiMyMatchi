from __future__ import annotations

import numpy as np

from .metrics import compute_metrics


def merge_chunks(chunks: list[dict]) -> dict:
    if not chunks:
        m = compute_metrics(np.array([], dtype=float), np.array([], dtype=float), np.array([], dtype=float), None)
        return {"frameSamplingFps": 0.0, "positions": [], "cuts": [], "metrics": m}

    sampling = float(chunks[0]["frameSamplingFps"])
    # build global timeline by concatenating with offsets
    positions = []
    cuts = []
    t_offset = 0.0

    for ch in sorted(chunks, key=lambda x: x["chunkIndex"]):
        ch_pos = ch.get("positions", [])
        if ch_pos:
            max_t = max(p["t"] for p in ch_pos)
        else:
            max_t = 0.0

        for p in ch_pos:
            positions.append({**p, "t": float(p["t"]) + t_offset})

        for ct in ch.get("cuts", []):
            cuts.append(float(ct) + t_offset)

        # offset by chunk duration (best effort)
        t_offset += max_t + (1.0 / max(1e-6, sampling))

    # Metrics are computed on the merged positions.
    ts = np.array([p["t"] for p in positions], dtype=float)
    cxs = np.array([p["cx"] for p in positions], dtype=float)
    cys = np.array([p["cy"] for p in positions], dtype=float)
    ncxs = np.array([p.get("ncx", p["cx"]) for p in positions], dtype=float)
    ncys = np.array([p.get("ncy", p["cy"]) for p in positions], dtype=float)

    # Merge recomputes metrics without calibration info (stateless contract).
    m = compute_metrics(ts, cxs, cys, None, norm_xs=ncxs, norm_ys=ncys)

    return {
        "frameSamplingFps": sampling,
        "positions": positions,
        "cuts": cuts,
        "metrics": m,
    }
