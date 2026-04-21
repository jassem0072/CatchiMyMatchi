# DevOps & CI/CD Setup

## Stack

| Component | Tool | Cost |
|---|---|---|
| CI/CD Runner | GitHub Actions | Free (2,000 min/month) |
| Android Deploy | Fastlane | Free & open source |
| Container Registry | Docker Hub | Free (1 private repo, unlimited public) |
| Cloud Deploy (Option A) | Render.com | Free (spins down after 15min inactivity) |
| Cloud Deploy (Option B) | Fly.io | Free (3 shared-CPU VMs, 160GB bw) |
| Self-hosted Deploy (Option C) | VPS via SSH | Oracle Cloud Free Tier / any VPS |

---

## Workflows

### 1. CI (`ci.yml`) — runs on every push/PR to main/develop
- **Backend**: npm install → build → lint
- **Flutter**: pub get → analyze → test → build debug APK
- **Docker**: compose up → health check backend is responding

### 2. CD Android (`cd-android.yml`) — runs on tag push `v*`
- Build release AAB → Fastlane deploy to Google Play Internal track

### 3. CD Docker (`cd-docker.yml`) — runs on push to main (when backend/ai/admin change)
- Build & push all Docker images to Docker Hub with `latest` + commit SHA tags

### 4. Deploy VPS (`deploy-vps.yml`) — runs on push to main
- SSH into your VPS → git pull → docker compose up --build

---

## Deployment Options

### Option A: Render.com (Easiest — Free)

**What deploys**: Backend API + Admin dashboard + MongoDB
**Limitation**: Free services spin down after 15min inactivity (cold start ~30s). AI services need paid plan.

1. Go to [render.com](https://render.com) → Sign up with GitHub
2. Click **New** → **Blueprint** → Select your `CatchiMyMatchi` repo
3. Render auto-detects `render.yaml` and creates all services
4. Fill in the `sync: false` env vars in Render dashboard (MONGODB_URI, GOOGLE_CLIENT_ID, etc.)
5. For MongoDB: Use [Render MongoDB](https://render.com/docs/mongodb) or [MongoDB Atlas free tier](https://www.mongodb.com/atlas)
6. Every push to `main` auto-deploys

**MongoDB Atlas free tier** (recommended with Render):
1. Go to [mongodb.com/atlas](https://www.mongodb.com/atlas) → Create free cluster
2. Create database user → Get connection string
3. Set `MONGODB_URI` in Render env vars

---

### Option B: Fly.io (Best free for all services including AI)

**What deploys**: Backend + AI tracker + AI montage (all Docker containers)
**Limitation**: Free tier = 3 VMs total. AI service needs more memory.

1. Install Fly CLI:
   ```bash
   # Windows (PowerShell)
   iwr https://fly.io/install.ps1 -useb | iex
   ```

2. Login:
   ```bash
   fly auth login
   ```

3. Launch each app (first time only):
   ```bash
   # Backend
   fly launch --config fly.toml --no-deploy
   fly secrets set MONGODB_URI=mongodb+srv://... JWT_SECRET=your_secret GOOGLE_CLIENT_ID=... GOOGLE_CLIENT_SECRET=...

   # AI tracker
   fly launch --config fly.ai.toml --no-deploy

   # AI montage
   fly launch --config fly.montage.toml --no-deploy
   ```

4. Deploy:
   ```bash
   fly deploy --config fly.toml          # backend
   fly deploy --config fly.ai.toml       # AI tracker
   fly deploy --config fly.montage.toml  # montage
   ```

5. Set secrets for each app via `fly secrets set KEY=VALUE`

6. For MongoDB: Use MongoDB Atlas free tier (see above)

---

### Option C: VPS via SSH (Full control — Oracle Cloud Free Tier)

**What deploys**: Everything (full Docker Compose — backend, AI, montage, admin, MongoDB)
**Best for**: Running all services together, no cold starts, full Docker Compose support.

1. Get a free VPS:
   - [Oracle Cloud Free Tier](https://cloud.oracle.com/free) — Always-free ARM VMs (4 cores, 24GB RAM)
   - Or any VPS (Hetzner €4/mo, DigitalOcean $6/mo)

2. Setup VPS (one-time):
   ```bash
   # SSH into your VPS
   ssh root@YOUR_VPS_IP

   # Install Docker
   curl -fsSL https://get.docker.com | sh
   sudo usermod -aG docker ubuntu

   # Clone repo
   git clone https://github.com/jassem0072/CatchiMyMatchi.git /opt/scoutai
   cd /opt/scoutai

   # Create .env with production values
   nano .env
   # Add all your secrets here

   # Start everything
   docker compose up -d --build
   ```

3. Add GitHub Secrets for auto-deploy:
   | Secret | Value |
   |---|---|
   | `VPS_HOST` | Your VPS IP address |
   | `VPS_USER` | `root` or `ubuntu` |
   | `VPS_SSH_KEY` | Your SSH private key |
   | `VPS_PORT` | `22` (or custom port) |
   | `VPS_PROJECT_PATH` | `/opt/scoutai` |

4. Every push to `main` now auto-deploys via SSH

---

## All GitHub Secrets (complete list)

Go to **Settings → Secrets and variables → Actions**

### Android Release
| Secret | Description |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | Base64-encoded `.jks` keystore file |
| `KEYSTORE_PASSWORD` | Keystore password |
| `KEY_ALIAS` | Key alias name |
| `KEY_PASSWORD` | Key password |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | Google Play service account JSON key |
| `API_BASE_URL` | Production API base URL |

### Docker Hub
| Secret | Description |
|---|---|
| `DOCKERHUB_USERNAME` | Docker Hub username |
| `DOCKERHUB_TOKEN` | Docker Hub access token |

### VPS Deploy
| Secret | Description |
|---|---|
| `VPS_HOST` | VPS IP or hostname |
| `VPS_USER` | SSH username |
| `VPS_SSH_KEY` | SSH private key |
| `VPS_PORT` | SSH port (default 22) |
| `VPS_PROJECT_PATH` | Project path on VPS |

---

## How to Trigger a Release

```bash
# Tag a release → triggers CD Android workflow
git tag v1.0.0
git push origin v1.0.0
```

## Fastlane Setup (one-time)

1. Create a Google Play Service Account:
   - Go to [Google Play Console](https://play.google.com/console) → Setup → API access → Create service account
   - Download JSON key file
   - Paste full JSON content into `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` secret

2. Generate a release keystore:
   ```bash
   keytool -genkey -v -keystore keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias scoutai
   # On PowerShell:
   [Convert]::ToBase64String([IO.File]::ReadAllBytes("keystore.jks")) | Set-Clipboard
   # Paste clipboard into ANDROID_KEYSTORE_BASE64 secret
   ```

3. Update `android/app/build.gradle.kts` signing config for release builds (replace debug signing with your keystore).

---

## Quick Decision Guide

| Need | Best Option |
|---|---|
| Easiest setup, backend only | **Render.com** |
| All services including AI, free | **Fly.io** |
| Full control, no cold starts | **VPS (Oracle Free Tier)** |
| Production-ready, zero cost | **VPS + Docker Compose** |

## No iOS (yet)

No `ios/` folder exists. When you add iOS support, add a `Fastlane` lane for `deliver_to_testflight` and an iOS CD workflow.
