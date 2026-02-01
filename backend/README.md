# ScoutAI Backend (NestJS + MongoDB)

This backend is responsible for **uploading/storing** match videos (persistent), **listing** them, and **streaming** them to the app.

## Run locally (Windows PowerShell)

1) Install deps

```
npm install
```

2) Configure env

Create `.env` (see `.env.example`).

3) Start dev server

```
npm run start:dev
```

## Notes

- Video files are stored on disk (MVP) and metadata is stored in MongoDB.
- The AI service remains in `/ai` as a separate FastAPI microservice.
