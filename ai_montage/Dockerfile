FROM python:3.11-slim

WORKDIR /app

# Install ffmpeg (includes ffprobe)
RUN apt-get update \
  && apt-get install -y --no-install-recommends ffmpeg \
  && rm -rf /var/lib/apt/lists/*

COPY requirements.txt ./
RUN pip install --no-cache-dir --timeout 120 --retries 10 -r requirements.txt

COPY app ./app

ENV PYTHONUNBUFFERED=1
EXPOSE 8002

CMD ["python", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8002"]
