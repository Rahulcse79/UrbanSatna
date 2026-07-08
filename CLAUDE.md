# CLAUDE.md — UrbanSatna

> Guidance for AI agents and engineers working in this repository.
> Claude Code reads this file automatically. Follow it exactly.

---

## 1. What this project is

**UrbanSatna** is an AI-ready, hyperlocal **service marketplace platform for India**
(Urban Company model): customers instantly find and book verified nearby
professionals — electricians, plumbers, AC technicians, cleaners, tutors,
repair technicians, and **any category the admin adds at runtime**.

Three clients, one backend:

| App               | Who uses it        | Platform                  |
|-------------------|--------------------|---------------------------|
| Customer app      | End customers      | Flutter (Android/iOS)     |
| Worker app        | Service providers  | Flutter (Android/iOS)     |
| Admin panel       | Operations team    | Web (Flutter Web, later)  |

**Non-negotiable design constraints — do not violate these:**

1. **Modular monolith first.** One Rust backend binary. No microservices,
   no Kafka, no service mesh in v1. Clean module boundaries so services can
   be split later *if* metrics ever demand it.
2. **Categories/services are data, not code.** Adding a service category must
   never require a code change, migration, or redeploy.
3. **Money paths are transactional and audited.** Every booking, payment,
   wallet, and refund mutation runs in a DB transaction and writes an
   `audit_logs` row. No exceptions.
4. **RBAC from day one.** Roles and permissions live in the database.
   Adding a role must not require code changes.
5. **Abstraction over vendors.** Payments (Razorpay/Stripe/UPI/cash),
   SMS/WhatsApp, storage (S3/R2/MinIO), and maps sit behind traits/interfaces.
   Never call a vendor SDK directly from a handler or use case.
6. **AI features are additive.** Recommendations, dynamic pricing, chatbot,
   fraud detection plug in behind interfaces later — never block core booking
   flow on an AI dependency.

**Targets:** booking flow works end-to-end on day one for Satna; architecture
scales 100 → 1M+ users without redesign (scale hardware and read replicas,
not architecture).

---

## 2. Architecture

Clean Architecture + feature-first modules, on both sides.

```
Flutter apps (customer / worker / admin)
        │  HTTPS (REST /api/v1) + FCM push
        ▼
┌──────────────────── urbansatna-api (one Rust binary) ────────────────────┐
│ api/          Axum routers + extractors + DTOs (per feature)             │
│ application/  use cases, orchestration, transactions                     │
│ domain/       entities, value objects, domain errors (pure, no I/O)      │
│ infra/        SQLx repos · Redis · S3 · FCM · SMS · payments · maps      │
└───────────────────────────────────────────────────────────────────────────┘
        │                     │                    │
        ▼                     ▼                    ▼
  PostgreSQL 16         Redis (OTP, sessions,   S3-compatible storage
  (single source        rate limits, cache,     (KYC docs, images,
   of truth, UUID PKs)   geo lookups)            invoices)
```

**Dependency rule (both Rust and Flutter):**
`api/presentation → application → domain ← infra`.
Domain imports nothing from other layers. Handlers never touch SQL.
Repositories are traits defined in `application`/`domain`, implemented in `infra`.

---

## 3. Tech stack

| Concern        | Choice                                                     |
|----------------|------------------------------------------------------------|
| Mobile         | Flutter (stable), Material 3, Riverpod, GoRouter, Dio,     |
|                | Freezed + json_serializable, flutter_secure_storage, Hive  |
| Backend        | Rust (stable), Axum, Tokio, Tower, Serde                   |
| DB access      | SQLx (compile-time checked queries), PostgreSQL 16         |
| Migrations     | `sqlx migrate` — SQL files, forward-only, checked in       |
| Cache/queue    | Redis (OTP, sessions, rate limit, cache); PG `SKIP LOCKED` |
|                | for background jobs — **no Kafka/RabbitMQ in v1**          |
| Auth           | JWT access (15 min) + rotating refresh tokens; Argon2id    |
| Push           | Firebase Cloud Messaging                                   |
| Maps           | Google Maps SDK + Distance Matrix; PostGIS or Redis GEO    |
|                | for nearby-worker search                                   |
| Storage        | S3 API (works with AWS S3 / Cloudflare R2 / MinIO)         |
| Observability  | `tracing` JSON logs, request_id on every request,          |
|                | Prometheus `/metrics`, OpenTelemetry behind a flag         |
| API docs       | OpenAPI (`utoipa`) served at `/docs` — contract-first      |
| Local dev      | Docker Compose (PG + Redis + MinIO), Nginx in front        |
| CI             | GitHub Actions: fmt, clippy `-D warnings`, tests, build    |

---

## 4. Repository layout

```
UrbanSatna/
  backend/
    src/
      main.rs               # wiring + graceful shutdown only, keep thin
      config/               # env config, feature flags
      api/                  # one module per feature: routes + DTOs
        auth/  users/  workers/  catalog/  bookings/  payments/
        wallet/  reviews/  notifications/  chat/  admin/  support/
      application/          # use cases (one file per use case)
      domain/               # entities, value objects, errors — pure
      infra/
        db/                 # SQLx repositories, one file per aggregate
        redis/  storage/  fcm/  sms/  payments/  maps/
      middleware/           # auth, RBAC, rate-limit, request_id, tracing
      jobs/                 # background workers (PG SKIP LOCKED queue)
    migrations/             # sqlx NNNN_name.{up,down}.sql pairs — docs/MIGRATIONS.md
    scripts/                # db.sh (dev DB helper), check_migrations.sh (CI guard)
    tests/                  # integration tests (testcontainers)
  mobile/
    lib/
      core/                 # config, theme, router, network, errors, utils
      shared/               # shared widgets, extensions
      features/<feature>/
        presentation/       # screens, widgets, Riverpod controllers
        application/        # state + use-case orchestration
        domain/             # entities, repository contracts
        data/               # DTOs, datasources, repository impls
  api/openapi.yaml          # REST contract — source of truth
  infra/
    docker-compose.yml  nginx/  .github/workflows/
  docs/
    PLAN.md  ARCHITECTURE.md  DATABASE.md  DECISIONS.md (ADRs)
```

---

## 5. Common commands

```bash
# Backend (run from backend/)
cargo run                          # start API against local compose stack
cargo test                         # unit + integration tests
cargo fmt --all && cargo clippy --all-targets -- -D warnings
scripts/db.sh new <name>           # new up+down migration pair
scripts/db.sh status               # applied vs pending migrations
scripts/db.sh check                # detect migration drift
scripts/db.sh reset                # drop + recreate + re-migrate dev DB
sqlx migrate run                   # apply migrations (sqlx-cli)
cargo sqlx prepare                 # refresh offline query metadata (commit it)

# Mobile (run from mobile/)
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze && flutter test
flutter run --dart-define-from-file=env/dev.json

# Local stack (repo root)
docker compose -f infra/docker-compose.yml up -d   # PG + Redis + MinIO
```

---

## 6. Database conventions

- **UUID v7 primary keys** everywhere. Never expose serial IDs.
- **Audit columns** on every table: `created_at`, `updated_at`; **soft delete**
  via `deleted_at` (never hard-delete user-facing data).
- **Money is `BIGINT` paise.** Never floats, never `NUMERIC` in app math.
- Status fields are **PG enums or CHECK-constrained text**, mirrored by Rust
  enums — never free strings.
- Booking state machine is enforced in `domain`, not scattered in handlers:
  `created → searching → assigned → accepted → en_route → arrived →
  otp_verified → in_progress → completed → paid | cancelled | disputed`.
- Migrations are reversible pairs (`NNNN_name.up.sql` + `.down.sql`) with
  sequential versions; the down exactly reverses the up. Once a migration is
  on `main`, never edit, rename, or delete it (CI enforces this) — write a new
  migration instead. Downs are dev-only tools (branch switching); production
  is forward-only and never runs `revert`. Full workflow: `docs/MIGRATIONS.md`.
- Index every FK and every column used in WHERE/ORDER BY on hot paths.
  Nearby-worker search uses a geo index (PostGIS `GIST` or Redis GEO).

---

## 7. API conventions

- All routes under `/api/v1`. Version in the path, never break v1.
- **Uniform envelope** (GUI/app depend on this shape):
  ```json
  { "success": true,  "data": { }, "error": null, "meta": { "page": 1 } }
  { "success": false, "data": null,
    "error": { "code": "BOOKING_NOT_FOUND", "message": "…" } }
  ```
- Error codes are stable SCREAMING_SNAKE strings from one central registry —
  clients switch on `code`, never on `message`.
- Pagination (`page`, `per_page`, `meta.total`), filtering, and sorting on
  every list endpoint. Validate all input at the DTO boundary.
- Rate limits (Redis) on OTP, login, and search endpoints.
- `/health` (liveness + DB/Redis checks) and `/metrics` are unauthenticated
  but network-restricted.

---

## 8. Security rules (do not regress)

- Argon2id for passwords; OTPs hashed in Redis with TTL ≤ 5 min and
  max 3 verify attempts; lockout with exponential backoff.
- JWT: short-lived access token; refresh tokens rotated on use, revocable
  per device (`sessions` table). "Logout all devices" must work.
- RBAC middleware checks **permissions, not role names** —
  e.g. `bookings:read:any` vs `bookings:read:own`.
- Every handler resolves ownership: a customer can only read *their*
  bookings; a worker only *their* jobs. Never trust IDs from the client.
- Secrets only via env/secret manager. Never in code, logs, or git.
- Never log OTPs, tokens, passwords, or full phone numbers (mask: `+91••••1234`).
- KYC documents in private buckets, served via short-lived signed URLs only.
- Webhooks (payments) verify signatures and are idempotent
  (dedupe on provider event ID).

---

## 9. Testing strategy

1. **Unit** — domain logic (booking state machine, pricing, commission math)
   table-driven, no I/O.
2. **Integration** — repositories + handlers against testcontainers PG/Redis.
3. **Contract** — responses validated against `api/openapi.yaml`.
4. **Flutter** — widget tests per feature; golden tests for key screens.
5. **Money invariants** — property tests: wallet balance never negative,
   commission + payout == amount, refund never exceeds payment.
6. **Load (pre-launch)** — booking flow at target concurrency; nearby-search p95.

Do not merge with failing tests, clippy warnings, or unformatted code.

---

## 10. Coding conventions

- Rust: no `unwrap`/`expect` in request paths; `thiserror` domain errors mapped
  centrally to HTTP; `#[tracing::instrument]` on use cases; no global mutable
  state — inject dependencies through `AppState`.
- Flutter: feature-first; no business logic in widgets; all networking through
  the Dio client in `core/network` (auth + refresh interceptors); Freezed for
  models and state; no hard-coded strings/colors — theme + l10n from day one
  (English + Hindi).
- Comments only for non-obvious constraints, not narration.
- Conventional Commits (`feat:`, `fix:`, `refactor:` …).

---

## 11. Quick agent checklist (read before you code)

- [ ] Is new behavior in the right layer (domain logic not in handlers/widgets)?
- [ ] Are categories/services still **pure data** (no hard-coded service types)?
- [ ] Does every money/state mutation run in a **transaction + audit log row**?
- [ ] Are permissions checked via **RBAC middleware**, ownership via query scope?
- [ ] Money in **paise (BIGINT)**? IDs **UUID**? Soft delete respected?
- [ ] Vendor calls behind a **trait/interface** with a mock for tests?
- [ ] `api/openapi.yaml` updated for any endpoint change?
- [ ] Envelope shape (`success/data/error/meta`) intact?
- [ ] `cargo fmt` + `clippy -D warnings` + tests green? `flutter analyze` clean?
