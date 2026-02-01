# ScoutAI Front Test

Small static website to test the NestJS backend video features.

## Run

1) Ensure backend is running:

- `npm run start:dev` in `../backend`

> If you just pulled new deps (axios/form-data), run `npm install` in `../backend` and restart.

2) Ensure AI service is running:

```
uvicorn app.main:app --host 0.0.0.0 --port 8001 --reload
```

> AI runs from `../ai`. Backend uses `AI_SERVICE_URL` (default `http://127.0.0.1:8001`).

3) Serve this folder (Windows PowerShell):

```
npx http-server -p 5173
```

4) Open:

- http://localhost:5173

## Configure backend URL

In the page, set **Backend URL** to `http://localhost:3000` (default).

## Analyze flow

1) Click **Play** on a video
2) **Drag a rectangle** on the player to select the player
3) Click **Analyze selection**
4) Metrics appear under the player
