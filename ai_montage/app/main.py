from __future__ import annotations

import logging
import math
import os
import re
import subprocess
import tempfile
from typing import Any, Optional

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ─── COCO class IDs used for detection ────────────────────────────────────────
PERSON_CLASS_ID = 0
BALL_CLASS_ID = 32  # "sports ball" in COCO-80

# ─── Lazy YOLO model cache (loaded on first use) ──────────────────────────────
_yolo_model: Any = None

# ─── App setup ────────────────────────────────────────────────────────────────
app = FastAPI(
    title="ScoutAI Montage Service",
    version="2.0.0",
    description=(
        "Football player montage service — automatically detects every moment "
        "a selected player has the ball and creates a highlight montage."
    ),
)

origins_env = os.getenv("MONTAGE_ALLOWED_ORIGINS", "*").strip()
allow_origins = (
    ["*"]
    if origins_env == "*"
    else [o.strip() for o in origins_env.split(",") if o.strip()]
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=allow_origins,
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ══════════════════════════════════════════════════════════════════════════════
#  PYDANTIC MODELS
# ══════════════════════════════════════════════════════════════════════════════

# ─── Existing models (kept unchanged) ─────────────────────────────────────────


class Clip(BaseModel):
    start: float
    end: float
    label: str = ""


class GenerateMontageRequest(BaseModel):
    videoPath: str
    clips: list[Clip]
    outputDir: str
    videoId: str


class GenerateMontageResponse(BaseModel):
    outputPath: str
    outputFilename: str
    duration: float
    clipCount: int


class DetectMontageRequest(BaseModel):
    videoPath: str


class DetectMontageResponse(BaseModel):
    isMontage: bool
    confidence: float
    reason: str
    cutCount: int
    duration: float
    cutsPerMinute: float


# ─── New models for player-based montage ──────────────────────────────────────


class RelativePosition(BaseModel):
    """
    Player position inside the video frame, expressed as fractions 0.0–1.0.
    (0,0) = top-left corner, (1,1) = bottom-right corner.
    """

    x: float = Field(
        ..., ge=0.0, le=1.0, description="Horizontal position (0=left, 1=right)"
    )
    y: float = Field(
        ..., ge=0.0, le=1.0, description="Vertical position   (0=top,  1=bottom)"
    )


class PlayerSelection(BaseModel):
    """
    Tells the system which player to follow.
    Pause the video at any moment where the player is clearly visible,
    note the time (seconds) and their approximate screen position.
    """

    frameTime: float = Field(
        ...,
        ge=0.0,
        description="Seconds into the video where the player is clearly visible.",
    )
    position: RelativePosition = Field(
        ...,
        description="Approximate position of the player in that frame (relative 0-1).",
    )


class CreatePlayerMontageRequest(BaseModel):
    videoPath: str = Field(..., description="Absolute path to source match video.")
    outputDir: str = Field(
        ..., description="Directory to write the output montage file."
    )
    videoId: str = Field(..., description="Used as the output filename prefix.")
    playerSelection: PlayerSelection

    # clip padding
    clipPaddingBefore: float = Field(
        3.0, ge=0.0, description="Seconds to include before each ball-touch moment."
    )
    clipPaddingAfter: float = Field(
        5.0, ge=0.0, description="Seconds to include after  each ball-touch moment."
    )

    # grouping
    minEventGap: float = Field(
        4.0,
        ge=0.0,
        description="Two touches closer than this (seconds) are merged into one clip.",
    )
    maxClips: int = Field(
        25, ge=1, description="Maximum number of clips in the final montage."
    )

    # analysis performance
    analysisStride: int = Field(
        6,
        ge=1,
        description=(
            "Process every Nth frame. "
            "1 = every frame (most accurate, very slow), "
            "6 = every 6th frame (~5 fps for 30 fps video, recommended), "
            "15 = fast scan (~2 fps). Increase for long matches."
        ),
    )
    ballProximityFactor: float = Field(
        2.0,
        ge=1.0,
        description=(
            "How much to expand the player's bounding-box when checking "
            "ball proximity. 2.0 = double the player box size."
        ),
    )
    detectionConfidence: float = Field(
        0.25,
        ge=0.05,
        le=1.0,
        description="Minimum YOLO detection confidence (lower = more detections, more false positives).",
    )
    yoloModel: str = Field(
        "yolov8n.pt",
        description="YOLO model weights to use. yolov8n=fastest, yolov8s/m/l/x=more accurate.",
    )


class CreatePlayerMontageResponse(BaseModel):
    outputPath: str
    outputFilename: str
    duration: float
    clipCount: int
    playerTrackId: int
    ballTouchCount: int
    touchTimestamps: list[float]


class AnalyzePlayerRequest(BaseModel):
    videoPath: str
    playerSelection: PlayerSelection
    analysisStride: int = 6
    ballProximityFactor: float = 2.0
    detectionConfidence: float = 0.25
    yoloModel: str = "yolov8n.pt"


class AnalyzePlayerResponse(BaseModel):
    playerTrackId: int
    ballTouchCount: int
    touchTimestamps: list[float]
    suggestedClips: list[dict[str, Any]]
    videoDuration: float


# ══════════════════════════════════════════════════════════════════════════════
#  FFMPEG / FFPROBE HELPERS  (kept from v1)
# ══════════════════════════════════════════════════════════════════════════════


def _ffmpeg_path() -> str:
    return os.getenv("FFMPEG_BIN", "ffmpeg")


def _get_video_duration(ffmpeg: str, path: str) -> float:
    ffprobe = ffmpeg.replace("ffmpeg", "ffprobe")
    cmd = [
        ffprobe,
        "-v",
        "error",
        "-show_entries",
        "format=duration",
        "-of",
        "default=noprint_wrappers=1:nokey=1",
        path,
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if result.returncode == 0 and result.stdout.strip():
            return float(result.stdout.strip())
    except Exception:
        pass
    return 0.0


def _extract_clip(ffmpeg: str, src: str, start: float, end: float, dest: str) -> None:
    duration = end - start
    if duration <= 0:
        raise ValueError(f"Invalid clip: start={start} end={end}")
    cmd = [
        ffmpeg,
        "-y",
        "-ss",
        str(start),
        "-i",
        src,
        "-t",
        str(duration),
        "-c",
        "copy",
        "-avoid_negative_ts",
        "make_zero",
        dest,
    ]
    logger.info("Extracting clip: %s → %s  (%.2fs – %.2fs)", src, dest, start, end)
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        logger.error("ffmpeg clip error: %s", result.stderr[-2000:])
        raise RuntimeError(
            f"ffmpeg failed extracting clip [{start}-{end}]: {result.stderr[-500:]}"
        )


def _concat_clips(ffmpeg: str, clip_paths: list[str], output_path: str) -> None:
    with tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False) as f:
        concat_list = f.name
        for p in clip_paths:
            escaped = p.replace("\\", "/").replace("'", "\\'")
            f.write(f"file '{escaped}'\n")
    try:
        cmd = [
            ffmpeg,
            "-y",
            "-f",
            "concat",
            "-safe",
            "0",
            "-i",
            concat_list,
            "-c",
            "copy",
            output_path,
        ]
        logger.info("Concatenating %d clips → %s", len(clip_paths), output_path)
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            logger.error("ffmpeg concat error: %s", result.stderr[-2000:])
            raise RuntimeError(f"ffmpeg concat failed: {result.stderr[-500:]}")
    finally:
        try:
            os.unlink(concat_list)
        except OSError:
            pass


# ══════════════════════════════════════════════════════════════════════════════
#  YOLO / TRACKING HELPERS
# ══════════════════════════════════════════════════════════════════════════════


def _load_yolo_model(model_name: str) -> Any:
    """Load (or return cached) YOLO model by name."""
    global _yolo_model
    # If a different model is requested, reload
    cached_name = getattr(_yolo_model, "_model_name", None)
    if _yolo_model is None or cached_name != model_name:
        try:
            from ultralytics import YOLO  # type: ignore
        except ImportError:
            raise RuntimeError(
                "ultralytics is not installed. "
                "Add `ultralytics>=8.2` to requirements.txt and rebuild the container."
            )
        logger.info("Loading YOLO model: %s", model_name)
        _yolo_model = YOLO(model_name)
        _yolo_model._model_name = model_name  # type: ignore[attr-defined]
    return _yolo_model


def _bbox_center(bbox: list[float]) -> tuple[float, float]:
    return ((bbox[0] + bbox[2]) / 2.0, (bbox[1] + bbox[3]) / 2.0)


def _is_ball_near_player(
    ball_bbox: list[float],
    player_bbox: list[float],
    expansion: float = 2.0,
) -> bool:
    """
    Check whether the ball is inside an expanded version of the player's bounding box.

    The player bbox is expanded symmetrically by `expansion` factor.
    expansion=2.0  →  each side extended by 50% of the box's half-width/height.
    """
    ball_cx, ball_cy = _bbox_center(ball_bbox)
    px1, py1, px2, py2 = player_bbox
    pw = (px2 - px1) * (expansion / 2.0)
    ph = (py2 - py1) * (expansion / 2.0)
    cx = (px1 + px2) / 2.0
    cy = (py1 + py2) / 2.0
    return abs(ball_cx - cx) <= pw and abs(ball_cy - cy) <= ph


def _analyze_video_for_player(
    video_path: str,
    player_selection: PlayerSelection,
    analysis_stride: int = 6,
    ball_proximity_factor: float = 2.0,
    detection_confidence: float = 0.25,
    yolo_model_name: str = "yolov8n.pt",
) -> tuple[int, list[float], float]:
    """
    Core analysis function.

    Processes the video using YOLOv8 + ByteTrack, identifies the target player
    by their position in the selection frame, then records every timestamp at
    which that player has the ball nearby.

    Returns
    -------
    (target_track_id, list_of_ball_touch_timestamps_seconds, video_fps)
    target_track_id == -1  if the player could not be identified.
    """
    try:
        import cv2  # type: ignore
    except ImportError:
        raise RuntimeError(
            "opencv-python-headless is not installed. "
            "Add `opencv-python-headless>=4.9` to requirements.txt."
        )

    model = _load_yolo_model(yolo_model_name)

    # ── Video metadata ────────────────────────────────────────────────────────
    cap = cv2.VideoCapture(video_path)
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)) or 1920
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT)) or 1080
    cap.release()

    logger.info(
        "Video metadata: %.2f fps | %d frames | %dx%d — stride=%d",
        fps,
        total,
        width,
        height,
        analysis_stride,
    )
    logger.info(
        "Estimated analysis time: depends on hardware (video = %.1f min)",
        total / fps / 60,
    )

    # ── Absolute pixel position of the player in the selection frame ──────────
    target_frame_idx = int(player_selection.frameTime * fps)
    sel_x_px = player_selection.position.x * width
    sel_y_px = player_selection.position.y * height
    # Accept identification within a ±3-stride window around the selection frame
    id_window_half = max(analysis_stride * 3, int(fps * 1.5))

    target_track_id: Optional[int] = None
    ball_touch_timestamps: list[float] = []
    processed = 0

    logger.info(
        "Looking for player near pixel (%.0f, %.0f) around t=%.1fs (frame ~%d)",
        sel_x_px,
        sel_y_px,
        player_selection.frameTime,
        target_frame_idx,
    )

    # ── Run YOLOv8 tracking over the full video ───────────────────────────────
    results_gen = model.track(
        source=video_path,
        persist=True,
        tracker="bytetrack.yaml",
        classes=[PERSON_CLASS_ID, BALL_CLASS_ID],
        vid_stride=analysis_stride,
        conf=detection_confidence,
        stream=True,
        verbose=False,
    )

    for frame_result in results_gen:
        actual_frame = processed * analysis_stride
        timestamp = actual_frame / fps
        processed += 1

        if frame_result.boxes is None or frame_result.boxes.id is None:
            continue

        boxes = frame_result.boxes
        track_ids = boxes.id.int().tolist()
        class_ids = boxes.cls.int().tolist()
        bboxes = boxes.xyxy.tolist()

        persons: dict[int, list[float]] = {}
        balls: list[list[float]] = []

        for tid, cid, bbox in zip(track_ids, class_ids, bboxes):
            if cid == PERSON_CLASS_ID:
                persons[tid] = bbox
            elif cid == BALL_CLASS_ID:
                balls.append(bbox)

        # ── Step 1: identify target player near the selection frame ───────────
        if (
            target_track_id is None
            and abs(actual_frame - target_frame_idx) <= id_window_half
        ):
            best_tid: Optional[int] = None
            best_dist: float = float("inf")
            for tid, bbox in persons.items():
                cx, cy = _bbox_center(bbox)
                dist = math.hypot(cx - sel_x_px, cy - sel_y_px)
                if dist < best_dist:
                    best_dist = dist
                    best_tid = tid
            if best_tid is not None:
                target_track_id = best_tid
                logger.info(
                    "✔ Player identified — track_id=%d  distance=%.1f px  frame=%d  t=%.2fs",
                    target_track_id,
                    best_dist,
                    actual_frame,
                    timestamp,
                )

        # ── Step 2: record frames where the target player has the ball ────────
        if target_track_id is not None and target_track_id in persons and balls:
            player_bbox = persons[target_track_id]
            for ball_bbox in balls:
                if _is_ball_near_player(ball_bbox, player_bbox, ball_proximity_factor):
                    ball_touch_timestamps.append(round(timestamp, 3))
                    break  # one ball is enough

    if target_track_id is None:
        logger.warning(
            "Player NOT found near (%.0f, %.0f) in frame window [%d ± %d]",
            sel_x_px,
            sel_y_px,
            target_frame_idx,
            id_window_half,
        )
        return -1, [], fps

    logger.info(
        "Analysis complete — track_id=%d | %d ball-touch frames detected",
        target_track_id,
        len(ball_touch_timestamps),
    )
    return target_track_id, ball_touch_timestamps, fps


def _group_timestamps_to_clips(
    timestamps: list[float],
    padding_before: float,
    padding_after: float,
    min_event_gap: float,
    video_duration: float,
    max_clips: int,
) -> list[tuple[float, float]]:
    """
    Convert a list of ball-touch timestamps into a list of (start, end) clip intervals.

    Algorithm
    ---------
    1. Group timestamps that are closer than `min_event_gap` seconds together.
    2. For each group, the clip starts `padding_before` seconds before the first
       touch and ends `padding_after` seconds after the last touch.
    3. Merge any clips that still overlap after padding.
    4. Clamp to [0, video_duration] and cap at `max_clips`.
    """
    if not timestamps:
        return []

    # Group
    groups: list[list[float]] = [[timestamps[0]]]
    for t in timestamps[1:]:
        if t - groups[-1][-1] <= min_event_gap:
            groups[-1].append(t)
        else:
            groups.append([t])

    # Build clips
    raw_clips: list[tuple[float, float]] = []
    for group in groups:
        s = max(0.0, min(group) - padding_before)
        e = min(video_duration, max(group) + padding_after)
        if e > s:
            raw_clips.append((s, e))

    if not raw_clips:
        return []

    # Merge overlapping
    merged: list[tuple[float, float]] = [raw_clips[0]]
    for s, e in raw_clips[1:]:
        ms, me = merged[-1]
        if s <= me:
            merged[-1] = (ms, max(me, e))
        else:
            merged.append((s, e))

    # Sort by start, limit count
    merged.sort(key=lambda x: x[0])
    if len(merged) > max_clips:
        logger.info(
            "Capping clips from %d to %d (maxClips limit)", len(merged), max_clips
        )
        merged = merged[:max_clips]

    return merged


# ══════════════════════════════════════════════════════════════════════════════
#  EXISTING ENDPOINT LOGIC  (generate-montage internals, reused by new endpoints)
# ══════════════════════════════════════════════════════════════════════════════


def _run_generate_montage(req: GenerateMontageRequest) -> GenerateMontageResponse:
    """
    Core montage-generation logic extracted from the endpoint so it can be
    called internally by the player-montage pipeline.
    """
    ffmpeg = _ffmpeg_path()

    if not os.path.isfile(req.videoPath):
        raise HTTPException(
            status_code=400, detail=f"Video file not found: {req.videoPath}"
        )
    if not req.clips:
        raise HTTPException(status_code=400, detail="No clips provided")

    valid_clips = [c for c in req.clips if c.end > c.start]
    if not valid_clips:
        raise HTTPException(
            status_code=400, detail="All clips have invalid start/end times"
        )
    valid_clips = valid_clips[:30]

    os.makedirs(req.outputDir, exist_ok=True)
    output_filename = f"{req.videoId}_montage.mp4"
    output_path = os.path.join(req.outputDir, output_filename)

    if len(valid_clips) == 1:
        c = valid_clips[0]
        _extract_clip(ffmpeg, req.videoPath, c.start, c.end, output_path)
    else:
        tmp_clips: list[str] = []
        with tempfile.TemporaryDirectory() as tmpdir:
            for i, c in enumerate(valid_clips):
                tmp_path = os.path.join(tmpdir, f"clip_{i:03d}.mp4")
                try:
                    _extract_clip(ffmpeg, req.videoPath, c.start, c.end, tmp_path)
                    if os.path.isfile(tmp_path) and os.path.getsize(tmp_path) > 0:
                        tmp_clips.append(tmp_path)
                except Exception as exc:
                    logger.warning(
                        "Skipping clip %d (%.2f–%.2f): %s", i, c.start, c.end, exc
                    )

            if not tmp_clips:
                raise HTTPException(
                    status_code=500, detail="Failed to extract any clips"
                )

            if len(tmp_clips) == 1:
                import shutil

                shutil.copy2(tmp_clips[0], output_path)
            else:
                _concat_clips(ffmpeg, tmp_clips, output_path)

    if not os.path.isfile(output_path):
        raise HTTPException(status_code=500, detail="Output file was not created")

    duration = _get_video_duration(ffmpeg, output_path)
    logger.info(
        "Montage ready: %s  (%.2fs, %d clips)", output_path, duration, len(valid_clips)
    )

    return GenerateMontageResponse(
        outputPath=output_path,
        outputFilename=output_filename,
        duration=duration,
        clipCount=len(valid_clips),
    )


def _detect_montage(ffmpeg: str, path: str) -> DetectMontageResponse:
    duration = _get_video_duration(ffmpeg, path)
    if duration <= 0:
        return DetectMontageResponse(
            isMontage=False,
            confidence=0.0,
            reason="Could not read video duration",
            cutCount=0,
            duration=0.0,
            cutsPerMinute=0.0,
        )

    cmd = [
        ffmpeg,
        "-hide_banner",
        "-i",
        path,
        "-vf",
        "select='gt(scene,0.40)',showinfo",
        "-an",
        "-f",
        "null",
        "-",
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        log_text = (result.stderr or "") + "\n" + (result.stdout or "")
        cut_count = len(re.findall(r"pts_time:\s*\d+(?:\.\d+)?", log_text))
    except Exception as exc:
        logger.warning("Montage detection failed: %s", exc)
        return DetectMontageResponse(
            isMontage=False,
            confidence=0.0,
            reason=f"Scene detection failed: {exc}",
            cutCount=0,
            duration=duration,
            cutsPerMinute=0.0,
        )

    cuts_per_min = cut_count / max(duration / 60.0, 1e-6)
    is_montage = (duration <= 300 and cut_count >= 12 and cuts_per_min >= 3.0) or (
        cut_count >= 25 and cuts_per_min >= 4.0
    )
    confidence = min(1.0, max(0.0, (cuts_per_min / 8.0) + min(cut_count / 60.0, 0.35)))
    reason = (
        "High scene-cut density typical of edited montage"
        if is_montage
        else "Scene-cut density closer to continuous/raw footage"
    )
    return DetectMontageResponse(
        isMontage=is_montage,
        confidence=confidence,
        reason=reason,
        cutCount=cut_count,
        duration=duration,
        cutsPerMinute=cuts_per_min,
    )


# ══════════════════════════════════════════════════════════════════════════════
#  ENDPOINTS
# ══════════════════════════════════════════════════════════════════════════════


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "service": "montage", "version": "2.0.0"}


# ── v1 endpoints (unchanged behaviour) ────────────────────────────────────────


@app.post("/generate-montage", response_model=GenerateMontageResponse)
def generate_montage(req: GenerateMontageRequest) -> Any:
    """
    Generate a montage from a list of manually-specified (start, end) clips.
    This is the original endpoint — clips must be provided by the caller.
    """
    try:
        return _run_generate_montage(req)
    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("generate_montage failed")
        raise HTTPException(status_code=500, detail=str(exc))


@app.post("/detect-montage", response_model=DetectMontageResponse)
def detect_montage(req: DetectMontageRequest) -> Any:
    """Detect whether a video is likely an already-edited montage."""
    ffmpeg = _ffmpeg_path()
    if not os.path.isfile(req.videoPath):
        raise HTTPException(
            status_code=400, detail=f"Video file not found: {req.videoPath}"
        )
    try:
        return _detect_montage(ffmpeg, req.videoPath)
    except Exception as exc:
        logger.exception("detect_montage failed")
        raise HTTPException(status_code=500, detail=str(exc))


# ── v2 endpoints: AI player tracking ──────────────────────────────────────────


@app.post(
    "/analyze-player",
    response_model=AnalyzePlayerResponse,
    summary="Analyze a match video and find every moment a chosen player has the ball",
)
def analyze_player(req: AnalyzePlayerRequest) -> Any:
    """
    **Step 1 / debug tool** — Run the AI analysis and return all ball-touch
    timestamps for the selected player WITHOUT generating any video output.

    Use this to verify the player was identified correctly and to inspect
    what clips would be created, before committing to the full montage render.

    ### How to select the player
    - Scrub to any moment in the match where the chosen player is **clearly visible**
      and **not overlapping** another player.
    - Note the time in seconds → `frameTime`
    - Note the player's approximate position on screen as fractions:
      `x=0.5` means centre horizontally, `y=0.3` means upper third.
    """
    ffmpeg = _ffmpeg_path()

    if not os.path.isfile(req.videoPath):
        raise HTTPException(
            status_code=400, detail=f"Video file not found: {req.videoPath}"
        )

    video_duration = _get_video_duration(ffmpeg, req.videoPath)

    if req.playerSelection.frameTime >= max(video_duration, 1.0):
        raise HTTPException(
            status_code=400,
            detail=f"playerSelection.frameTime ({req.playerSelection.frameTime}s) exceeds video duration ({video_duration:.1f}s)",
        )

    try:
        track_id, timestamps, _fps = _analyze_video_for_player(
            video_path=req.videoPath,
            player_selection=req.playerSelection,
            analysis_stride=req.analysisStride,
            ball_proximity_factor=req.ballProximityFactor,
            detection_confidence=req.detectionConfidence,
            yolo_model_name=req.yoloModel,
        )
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc))

    # Build suggested clips preview (without generating video)
    suggested_clips: list[dict[str, Any]] = []
    if timestamps and video_duration > 0:
        raw_clips = _group_timestamps_to_clips(
            timestamps=timestamps,
            padding_before=3.0,
            padding_after=5.0,
            min_event_gap=4.0,
            video_duration=video_duration,
            max_clips=25,
        )
        suggested_clips = [
            {
                "index": i,
                "start": round(s, 3),
                "end": round(e, 3),
                "duration": round(e - s, 3),
            }
            for i, (s, e) in enumerate(raw_clips)
        ]

    return AnalyzePlayerResponse(
        playerTrackId=track_id,
        ballTouchCount=len(timestamps),
        touchTimestamps=timestamps,
        suggestedClips=suggested_clips,
        videoDuration=video_duration,
    )


@app.post(
    "/create-player-montage",
    response_model=CreatePlayerMontageResponse,
    summary="Automatically create a football player highlight montage from a full match video",
)
def create_player_montage(req: CreatePlayerMontageRequest) -> Any:
    """
    **Full pipeline** — Given a raw match video and a player selection, this endpoint:

    1. Runs YOLOv8 + ByteTrack to detect and track every person and the ball
       across the entire video.
    2. Identifies the chosen player by their position at `playerSelection.frameTime`.
    3. Records every frame where the ball enters that player's proximity zone.
    4. Groups those frames into clips (with configurable before/after padding).
    5. Extracts and concatenates the clips into a single montage `.mp4` file.

    ### Tips for best results
    - Use `analysisStride=6` (default) for a good speed/accuracy trade-off.
    - For a full 90-minute match on CPU, analysis can take **20–60 minutes** —
      consider running in a background job.
    - If the ball is rarely detected, lower `detectionConfidence` to `0.15–0.20`.
    - If too many false positives (wrong player), increase `ballProximityFactor` closer to `1.5`.
    - For better accuracy at the cost of speed, use `yoloModel=yolov8s.pt` or `yolov8m.pt`.

    ### How to choose the player
    - Pause the video at a moment where your player is **clearly visible and isolated**.
    - Set `frameTime` to that timestamp (seconds).
    - Set `position.x` / `position.y` to their approximate screen position (0.0–1.0).
    """
    ffmpeg = _ffmpeg_path()

    # ── Validate video path ───────────────────────────────────────────────────
    if not os.path.isfile(req.videoPath):
        raise HTTPException(
            status_code=400, detail=f"Video file not found: {req.videoPath}"
        )

    video_duration = _get_video_duration(ffmpeg, req.videoPath)
    if video_duration <= 0:
        raise HTTPException(status_code=400, detail="Could not read video duration.")

    if req.playerSelection.frameTime >= video_duration:
        raise HTTPException(
            status_code=400,
            detail=(
                f"playerSelection.frameTime ({req.playerSelection.frameTime}s) "
                f"exceeds video duration ({video_duration:.1f}s)."
            ),
        )

    # ── Step 1: AI analysis ───────────────────────────────────────────────────
    logger.info(
        "=== create_player_montage START  video=%s  selection=t=%.1fs pos=(%.2f,%.2f) ===",
        req.videoPath,
        req.playerSelection.frameTime,
        req.playerSelection.position.x,
        req.playerSelection.position.y,
    )

    try:
        track_id, touch_timestamps, _fps = _analyze_video_for_player(
            video_path=req.videoPath,
            player_selection=req.playerSelection,
            analysis_stride=req.analysisStride,
            ball_proximity_factor=req.ballProximityFactor,
            detection_confidence=req.detectionConfidence,
            yolo_model_name=req.yoloModel,
        )
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc))

    # ── Step 2: Validate analysis result ─────────────────────────────────────
    if track_id == -1:
        raise HTTPException(
            status_code=422,
            detail=(
                "Could not identify the player at the specified position/time. "
                "Try a slightly different frameTime where the player is clearly "
                "separated from other players, or adjust the position values."
            ),
        )

    logger.info(
        "Player track_id=%d identified — %d ball-touch moments found",
        track_id,
        len(touch_timestamps),
    )

    if not touch_timestamps:
        raise HTTPException(
            status_code=422,
            detail=(
                f"Player (track_id={track_id}) was tracked but no ball-touch moments were detected. "
                "Possible fixes: lower detectionConfidence, increase ballProximityFactor, "
                "or verify the ball is visible (sports ball class) in the video."
            ),
        )

    # ── Step 3: Group touches into clips ─────────────────────────────────────
    clips = _group_timestamps_to_clips(
        timestamps=touch_timestamps,
        padding_before=req.clipPaddingBefore,
        padding_after=req.clipPaddingAfter,
        min_event_gap=req.minEventGap,
        video_duration=video_duration,
        max_clips=req.maxClips,
    )

    if not clips:
        raise HTTPException(
            status_code=422,
            detail="Ball-touch moments were detected but no valid clips could be formed.",
        )

    logger.info(
        "Grouped %d touch frames into %d clips (%.1f–%.1f padding, gap=%.1f)",
        len(touch_timestamps),
        len(clips),
        req.clipPaddingBefore,
        req.clipPaddingAfter,
        req.minEventGap,
    )
    for i, (s, e) in enumerate(clips):
        logger.info("  clip[%02d]  %.2fs → %.2fs  (%.1fs)", i, s, e, e - s)

    # ── Step 4: Generate montage video ────────────────────────────────────────
    clip_models = [
        Clip(start=s, end=e, label=f"player_{track_id}_touch_{i}")
        for i, (s, e) in enumerate(clips)
    ]
    montage_req = GenerateMontageRequest(
        videoPath=req.videoPath,
        clips=clip_models,
        outputDir=req.outputDir,
        videoId=req.videoId,
    )

    try:
        result = _run_generate_montage(montage_req)
    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("Montage video generation failed")
        raise HTTPException(status_code=500, detail=str(exc))

    logger.info(
        "=== create_player_montage DONE  output=%s  duration=%.2fs  clips=%d ===",
        result.outputPath,
        result.duration,
        result.clipCount,
    )

    return CreatePlayerMontageResponse(
        outputPath=result.outputPath,
        outputFilename=result.outputFilename,
        duration=result.duration,
        clipCount=result.clipCount,
        playerTrackId=track_id,
        ballTouchCount=len(touch_timestamps),
        touchTimestamps=touch_timestamps,
    )
