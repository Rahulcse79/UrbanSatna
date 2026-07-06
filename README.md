# UrbanSatna · Servexa

Hyperlocal service marketplace for India — "Uber for home services".
Customers book verified nearby professionals (electrician, plumber, AC
technician, cleaning, …) with upfront prices, live status, and an arrival-OTP
trust handshake. Launch city: **Satna, Madhya Pradesh**. Service categories
are data managed by admins at runtime, never code.

The mobile app ships under the brand name **Servexa** (app ID
`com.servexa`, Dart package `servexa`).

| Part       | Stack                                        | Path       |
|------------|----------------------------------------------|------------|
| API        | Rust · Axum · SQLx · PostgreSQL 16 · Redis   | `backend/` |
| Mobile     | Flutter · Riverpod · GoRouter · Dio          | `mobile/`  |
| Contract   | OpenAPI 3.1 (source of truth)                | `api/`     |
| Dev infra  | Docker Compose (PG, Redis, MinIO)            | `infra/`   |
| Deploy     | Render blueprint (auto-deploy on push)       | `render.yaml` |

Read first: [CLAUDE.md](CLAUDE.md) (architecture rules) ·
[docs/PRODUCT.md](docs/PRODUCT.md) (vision, features, roadmap) ·
[docs/PLAN.md](docs/PLAN.md) (engineering phases).

## What works today

**Customer** — OTP login · category grid → fixed-price booking · live status
timeline (accepted → on the way → arrived → working → done) · arrival OTP to
share at the door · call the assigned worker · rate 1–5★ · profile photo ·
light/dark/system theme · English + Hindi.

**Worker** — apply with skills + KYC photos (ID + selfie) · admin-verified
before the first job · online job feed, first-accept-wins · call customer +
one-tap Google Maps navigation after accept · OTP-gated job start · earnings.

**Admin (in-app panel)** — worker verification queue with KYC viewer ·
catalog manager (add/toggle categories & services live) · promo banner
editor · maintenance mode · min-build force update · server-URL kill switch.
Admins cannot be workers (separation of duties), and prices are admin-only —
workers will get a request-queue, never direct edits.

**Platform** — permission-based RBAC · every mutation audited · rotating
refresh tokens · atomic first-accept · contact privacy until accept ·
customer-only OTP redaction · Render auto-deploy.

## Quickstart

```bash
# Backend + dependencies in one step (creates backend/.env on first run,
# reuses running Postgres/Redis, falls back to docker compose / local redis):
./start.sh              # dev build
./start.sh --release    # optimized build
# → http://localhost:8080/health, /metrics

# Mobile
cd mobile
flutter pub get && flutter gen-l10n
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080   # Android emulator
```

Manual alternative to `start.sh`:

```bash
docker compose -f infra/docker-compose.yml up -d --wait   # PG 55432, Redis, MinIO
cd backend && cp .env.example .env && cargo run           # migrations run on startup
```

### No Docker? (native fallback)

Any local PostgreSQL ≥ 13 and Redis work. Create a database and point
`backend/.env` at it:

```bash
createdb urbansatna
# DATABASE_URL=postgres://<you>@localhost:5432/urbansatna
redis-server --daemonize yes
```

## Deployment

Pushing to `main` auto-deploys the API to Render (`render.yaml` wires the
web service + Postgres + Redis). Production: `https://urbansatna.onrender.com`
(`/health` shows DB/Redis status).

APK/IPA builds: GitHub Actions → **Mobile Release Builds** → *Run workflow*
with `api_base_url` (defaults are baked toward the Render URL). Each build
gets `APP_BUILD` = the CI run number — shown in the app's Settings footer and
compared against the admin `min_build` flag for force updates.

**Free-tier reality (before real users):** Render free services sleep
(~50 s cold start) and free Postgres expires after ~90 days with no backups;
`DEV_RETURN_OTP=true` returns the login OTP in the API response because no
SMS gateway is wired yet. Both are launch gates — see
[docs/PRODUCT.md §12](docs/PRODUCT.md).

## Break glass: flip flags without the app

Admins bypass maintenance mode in the app, and the login screen is never
blocked — but if you're ever locked out anyway, every flag is one API
call away:

```bash
# One-liner tool (asks the server for the OTP while DEV_RETURN_OTP=true):
./scripts/admin_config.py https://urbansatna.onrender.com +91XXXXXXXXXX \
    set maintenance_mode false
```

Or raw curl, three steps:

```bash
BASE=https://urbansatna.onrender.com
# 1. request OTP (dev mode echoes it back as data.dev_otp)
curl -s -X POST $BASE/api/v1/auth/otp/request \
  -H 'content-type: application/json' -d '{"phone":"+91XXXXXXXXXX"}'
# 2. verify -> copy data.access_token
curl -s -X POST $BASE/api/v1/auth/otp/verify \
  -H 'content-type: application/json' \
  -d '{"phone":"+91XXXXXXXXXX","otp":"<OTP>","device":"cli"}'
# 3. turn maintenance off (admin token required)
curl -s -X PATCH $BASE/api/v1/app-config \
  -H "authorization: Bearer <ACCESS_TOKEN>" \
  -H 'content-type: application/json' -d '{"maintenance_mode":false}'
```

The same PATCH accepts `allow_server_url_change`, `promo_enabled`,
`promo_title`, `promo_subtitle`, and `min_build`.

## Versioning

Every CI build stamps three matching numbers from the Actions run number:
Android `versionCode`, `versionName` (`0.1.<run>`), and the in-app
`APP_BUILD` (Settings footer shows `Servexa v0.1.<run>`). Builds are signed
with the committed **test** keystore (`mobile/ci/debug.keystore`) so a new
APK installs over the old one without uninstalling — replace it with a real
keystore before any Play Store upload.

## Verifying

```bash
cd backend
cargo fmt --all --check && cargo clippy --all-targets -- -D warnings && cargo test
cd ../mobile
flutter analyze && flutter test
```

CI (GitHub Actions) runs the same on every push/PR.

## Layout

```
backend/src/
  api/          Axum routers + DTOs (envelope: success/data/error/meta)
  domain/       entities, state machine, errors — pure, no I/O
  infra/        Postgres repos, Redis, OTP, JWT (vendors behind traits)
  middleware/   auth extractor, RBAC helpers
backend/migrations/   forward-only SQL, embedded & applied at startup
mobile/lib/
  core/         config, theme, router, network, shared utils
  features/<f>/ presentation · data · domain (auth, home, catalog,
                bookings, jobs, worker, profile, admin, settings, shell)
```
