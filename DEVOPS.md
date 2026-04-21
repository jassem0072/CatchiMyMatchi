# DevOps & CI/CD Setup

## Stack

| Component | Tool | Cost |
|---|---|---|
| CI/CD Runner | GitHub Actions | Free (2,000 min/month) |
| Android Deploy | Fastlane | Free & open source |
| Container Registry | Docker Hub | Free (1 private repo, unlimited public) |

## Workflows

### 1. CI (`ci.yml`) — runs on every push/PR to main/develop
- **Backend**: npm install → build → lint
- **Flutter**: pub get → analyze → test → build debug APK
- **Docker**: compose up → health check backend is responding

### 2. CD Android (`cd-android.yml`) — runs on tag push `v*`
- Build release AAB → Fastlane deploy to Google Play Internal track

### 3. CD Docker (`cd-docker.yml`) — runs on push to main (when backend/ai/admin change)
- Build & push all Docker images to Docker Hub with `latest` + commit SHA tags

## Required GitHub Secrets

Go to **Settings → Secrets and variables → Actions** and add:

### Android Release
| Secret | Description |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | Base64-encoded `.jks` keystore file (`base64 -w0 keystore.jks`) |
| `KEYSTORE_PASSWORD` | Keystore password |
| `KEY_ALIAS` | Key alias name |
| `KEY_PASSWORD` | Key password |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | Google Play service account JSON key file content |
| `API_BASE_URL` | Production API base URL |

### Docker Hub
| Secret | Description |
|---|---|
| `DOCKERHUB_USERNAME` | Docker Hub username |
| `DOCKERHUB_TOKEN` | Docker Hub access token (create at Account Settings → Security) |

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
   base64 -w0 keystore.jks  # copy output to ANDROID_KEYSTORE_BASE64 secret
   ```

3. Update `android/app/build.gradle.kts` signing config for release builds (replace debug signing with your keystore).

## No iOS (yet)

No `ios/` folder exists. When you add iOS support, add a `Fastlane` lane for `deliver_to_testflight` and an iOS CD workflow.
