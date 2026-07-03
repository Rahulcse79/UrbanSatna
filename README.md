# UrbanSatna

Hyperlocal service marketplace for India — customers book verified nearby
professionals (electrician, plumber, AC technician, cleaning, …). Launch
city: **Satna, Madhya Pradesh**. Service categories are data managed by
admins at runtime, never code.

| Part       | Stack                                        | Path       |
|------------|----------------------------------------------|------------|
| API        | Rust · Axum · SQLx · PostgreSQL 16 · Redis   | `backend/` |
| Mobile     | Flutter · Riverpod · GoRouter · Dio          | `mobile/`  |
| Contract   | OpenAPI 3.1 (source of truth)                | `api/`     |
| Dev infra  | Docker Compose (PG, Redis, MinIO)            | `infra/`   |

Read first: [CLAUDE.md](CLAUDE.md) (architecture rules) ·
[docs/PLAN.md](docs/PLAN.md) (roadmap) ·
[docs/MASTER_PROMPT.md](docs/MASTER_PROMPT.md) (AI session contract).

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
  application/  use cases (from Phase 1)
  domain/       entities, errors — pure, no I/O
  infra/        Postgres, Redis, storage, vendors (behind traits)
backend/migrations/   forward-only SQL, embedded & applied at startup
mobile/lib/
  core/         config, theme, router, network
  features/<f>/ presentation · application · domain · data
```
