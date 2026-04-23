FROM python:3.11-slim

WORKDIR /app

# System libs needed by ffmpeg + OpenCV
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
       ffmpeg \
       libglib2.0-0 \
       libgl1 \
       libsm6 \
       libxext6 \
       libgomp1 \
  && rm -rf /var/lib/apt/lists/*

# ── Install PyTorch CPU-only FIRST ────────────────────────────────────────────
# Without this, ultralytics pulls the CUDA build (~2.5 GB) which causes
# Docker to run out of disk space and fail with EOF during image export.
RUN pip install --no-cache-dir --timeout 180 --retries 10 \
    torch torchvision \
    --index-url https://download.pytorch.org/whl/cpu

# ── Install remaining Python dependencies ─────────────────────────────────────
COPY requirements.txt ./
RUN pip install --no-cache-dir --timeout 180 --retries 10 -r requirements.txt

# ── Copy application code ──────────────────────────────────────────────────────
COPY app ./app

# NOTE: YOLO weights (yolov8n.pt) are downloaded at first request, not at build
# time. Pre-downloading inside Docker frequently fails due to network restrictions
# in CI/build environments and adds ~6 MB to every image layer unnecessarily.

ENV PYTHONUNBUFFERED=1
EXPOSE 8002

CMD ["python", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8002"]
