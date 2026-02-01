from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, Field


class SelectionBBox(BaseModel):
    t0: float = Field(..., description="Time in seconds")
    x: float
    y: float
    w: float
    h: float


class TwoPointsCalibration(BaseModel):
    type: Literal["two_points"] = "two_points"
    x1: float
    y1: float
    x2: float
    y2: float
    distance_m: float = Field(..., gt=0)


class HomographyCalibration(BaseModel):
    type: Literal["homography"] = "homography"
    # 4 image points: [[x,y], ...] corresponding to pitch points
    src_points: list[list[float]] = Field(..., min_length=4, max_length=4)
    # 4 pitch points in meters within [0..105]x[0..68]
    dst_points: list[list[float]] = Field(..., min_length=4, max_length=4)


Calibration = TwoPointsCalibration | HomographyCalibration


class ProcessChunkRequest(BaseModel):
    chunkPathOrUrl: str
    chunkIndex: int
    samplingFps: float = Field(3.0, gt=0)
    selection: SelectionBBox | None = None
    calibration: Calibration | None = None


class Position(BaseModel):
    t: float
    cx: float
    cy: float
    conf: float
    bbox: list[float] | None = None
    trackId: int | None = None


class HeatmapPayload(BaseModel):
    grid_w: int
    grid_h: int
    counts: list[list[int]]
    coord_space: Literal["image", "pitch"]
    bounds: dict[str, float]


class MetricsPayload(BaseModel):
    distanceMeters: float | None
    avgSpeedKmh: float | None
    maxSpeedKmh: float | None
    sprintCount: int
    accelPeaks: list[float]
    heatmap: HeatmapPayload


class ProcessChunkResponse(BaseModel):
    chunkIndex: int
    frameSamplingFps: float
    positions: list[Position]
    cuts: list[float]
    metrics: MetricsPayload
    debug: dict[str, Any] | None = None


class MergeRequest(BaseModel):
    chunks: list[ProcessChunkResponse]


class MergeResponse(BaseModel):
    frameSamplingFps: float
    positions: list[Position]
    cuts: list[float]
    metrics: MetricsPayload
    debug: dict[str, Any] | None = None
 
