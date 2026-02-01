# ScoutAI – Python AI Service

## Run locally

1) Create venv (Windows PowerShell)

```
python -m venv .venv
.\.venv\Scripts\Activate.ps1
```

2) Install deps

```
pip install -r requirements.txt
```

3) Start API

```
uvicorn app.main:app --host 0.0.0.0 --port 8001 --reload
```

## Example requests

### POST /process-chunk

```
curl -X POST http://127.0.0.1:8001/process-chunk \
  -H "Content-Type: application/json" \
  -d "{\"chunkPathOrUrl\":\"C:/path/to/chunk.mp4\",\"chunkIndex\":0,\"samplingFps\":3,\"selection\":{\"t0\":0.0,\"x\":100,\"y\":120,\"w\":80,\"h\":180},\"calibration\":null}"
```

### POST /merge

```
curl -X POST http://127.0.0.1:8001/merge \
  -H "Content-Type: application/json" \
  -d "{\"chunks\":[ /* put process-chunk responses here */ ]}"
```

### POST /process-upload (multipart)

`selection` and `calibration` must be JSON strings.

```powershell
curl.exe -X POST http://127.0.0.1:8001/process-upload `
  -F "file=@C:\path\to\chunk.mp4" `
  -F "chunkIndex=0" `
  -F "samplingFps=3" `
  -F "selection={\"t0\":0.0,\"x\":100,\"y\":120,\"w\":80,\"h\":180}" 
```

## Endpoints

- POST `/process-chunk`
- POST `/process-upload`
- POST `/merge`
