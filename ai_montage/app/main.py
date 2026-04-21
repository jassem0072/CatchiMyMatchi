from __future__ import annotations

import logging
import os
import subprocess
import tempfile
from typing import Any

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="ScoutAI Montage Service", version="1.0.0")

origins_env = os.getenv("MONTAGE_ALLOWED_ORIGINS", "*").strip()
allow_origins = ["*"] if origins_env == "*" else [o.strip() for o in origins_env.split(",") if o.strip()]

app.add_middleware(
    CORSMiddleware,
    allow_origins=allow_origins,
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


class Clip(BaseModel):
    start: float   # seconds
    end: float     # seconds
    label: str = ""


class GenerateMontageRequest(BaseModel):
    videoPath: str          # absolute path to source video on shared volume
    clips: list[Clip]       # list of clips to extract
    outputDir: str          # directory to write the output montage file
    videoId: str            # used as the output filename prefix


class GenerateMontageResponse(BaseModel):
    outputPath: str
    outputFilename: str
    duration: float
    clipCount: int


def _ffmpeg_path() -> str:
    return os.getenv("FFMPEG_BIN", "ffmpeg")


def _extract_clip(ffmpeg: str, src: str, start: float, end: float, dest: str) -> None:
    """Extract a single clip from src between start/end seconds into dest."""
    duration = end - start
    if duration <= 0:
        raise ValueError(f"Invalid clip: start={start} end={end}")
    cmd = [
        ffmpeg,
        "-y",
        "-ss", str(start),
        "-i", src,
        "-t", str(duration),
        "-c", "copy",         # fast: no re-encode, just copy streams
        "-avoid_negative_ts", "make_zero",
        dest,
    ]
    logger.info("Extracting clip: %s → %s (%.2fs–%.2fs)", src, dest, start, end)
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        logger.error("ffmpeg clip error: %s", result.stderr[-2000:])
        raise RuntimeError(f"ffmpeg failed extracting clip [{start}-{end}]: {result.stderr[-500:]}")


def _concat_clips(ffmpeg: str, clip_paths: list[str], output_path: str) -> None:
    """Concatenate a list of clip files into a single output file using the concat demuxer."""
    # Write concat list file
    with tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False) as f:
        concat_list = f.name
        for p in clip_paths:
            # ffmpeg concat list requires escaped paths
            escaped = p.replace("\\", "/").replace("'", "\\'")
            f.write(f"file '{escaped}'\n")

    try:
        cmd = [
            ffmpeg,
            "-y",
            "-f", "concat",
            "-safe", "0",
            "-i", concat_list,
            "-c", "copy",
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


def _get_video_duration(ffmpeg: str, path: str) -> float:
    """Use ffprobe to get the duration of a video file."""
    ffprobe = ffmpeg.replace("ffmpeg", "ffprobe")
    cmd = [
        ffprobe,
        "-v", "error",
        "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1",
        path,
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if result.returncode == 0 and result.stdout.strip():
            return float(result.stdout.strip())
    except Exception:
        pass
    return 0.0


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "service": "montage"}


@app.post("/generate-montage", response_model=GenerateMontageResponse)
def generate_montage(req: GenerateMontageRequest) -> Any:
    ffmpeg = _ffmpeg_path()

    # Validate source video exists
    if not os.path.isfile(req.videoPath):
        raise HTTPException(status_code=400, detail=f"Video file not found: {req.videoPath}")

    # Validate clips
    if not req.clips:
        raise HTTPException(status_code=400, detail="No clips provided")

    valid_clips = [c for c in req.clips if c.end > c.start]
    if not valid_clips:
        raise HTTPException(status_code=400, detail="All clips have invalid start/end times")

    # Limit: at most 30 clips to avoid abuse
    valid_clips = valid_clips[:30]

    # Ensure output directory exists
    os.makedirs(req.outputDir, exist_ok=True)
    output_filename = f"{req.videoId}_montage.mp4"
    output_path = os.path.join(req.outputDir, output_filename)

    # If there's only one clip, extract directly to output (no concat needed)
    if len(valid_clips) == 1:
        c = valid_clips[0]
        _extract_clip(ffmpeg, req.videoPath, c.start, c.end, output_path)
    else:
        # Extract each clip to a temp file, then concatenate
        tmp_clips: list[str] = []
        try:
            with tempfile.TemporaryDirectory() as tmpdir:
                for i, c in enumerate(valid_clips):
                    tmp_path = os.path.join(tmpdir, f"clip_{i:03d}.mp4")
                    try:
                        _extract_clip(ffmpeg, req.videoPath, c.start, c.end, tmp_path)
                        if os.path.isfile(tmp_path) and os.path.getsize(tmp_path) > 0:
                            tmp_clips.append(tmp_path)
                    except Exception as e:
                        logger.warning("Skipping clip %d (%.2f–%.2f): %s", i, c.start, c.end, e)

                if not tmp_clips:
                    raise HTTPException(status_code=500, detail="Failed to extract any clips")

                if len(tmp_clips) == 1:
                    import shutil
                    shutil.copy2(tmp_clips[0], output_path)
                else:
                    _concat_clips(ffmpeg, tmp_clips, output_path)
        except HTTPException:
            raise
        except Exception as e:
            logger.exception("Montage generation failed")
            raise HTTPException(status_code=500, detail=str(e))

    if not os.path.isfile(output_path):
        raise HTTPException(status_code=500, detail="Output file was not created")

    duration = _get_video_duration(ffmpeg, output_path)
    logger.info("Montage done: %s (%.2fs, %d clips)", output_path, duration, len(valid_clips))

    return GenerateMontageResponse(
        outputPath=output_path,
        outputFilename=output_filename,
        duration=duration,
        clipCount=len(valid_clips),
    )
