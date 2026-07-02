# PLAN.md — UrbanSatna Development Roadmap

> Phased, vertical-slice roadmap. Each phase ships something testable
> end-to-end. Do not start a phase before the previous phase's exit
> criteria are met. Architecture rules live in [CLAUDE.md](../CLAUDE.md).

---

## Guiding principles

- **Vertical slices, not horizontal layers.** "OTP login works on the phone
  against the real API" beats "all 40 tables migrated."
- **Monolith first.** One Rust binary, one PostgreSQL, one Redis. Scale by
  optimizing queries, caching, and read replicas — not by splitting services.
- **Launch city: Satna.** Multi-city is modeled in the schema from day one
  (`cities` table, city-scoped queries) but operationally we launch one city.
- **De-scope ruthlessly.** v1 has no chat, no wallet, no AI, no admin web
  panel beyond essentials. They are designed-for, not built.

---

## Phase 0 — Foundations (Week 1–2)

Skeleton that everything else hangs on.

- [ ] Repo layout per CLAUDE.md §4; `backend/`, `mobile/`, `infra/`, `docs/`
- [ ] Docker Compose: PostgreSQL 16, Redis, MinIO
- [ ] Axum app: config loading, `/health`, `/metrics`, request_id middleware,
      tracing JSON logs, central error → HTTP mapping, response envelope
- [ ] SQLx migrations wired; first migration: `users`, `roles`, `permissions`,
      `role_permissions`, `sessions`, `cities`, `audit_logs`
- [ ] Flutter app scaffold: core/ (theme, router, Dio client, env config),
      Riverpod setup, l10n (en + hi) skeleton
- [ ] CI: fmt + clippy + cargo test; flutter analyze + test
- [ ] `api/openapi.yaml` seeded with health + auth contract

**Exit criteria:** `docker compose up` + `cargo run` gives a healthy API;
Flutter app boots and reads `/health`; CI is green.

## Phase 1 — Identity & RBAC (Week 2–4)

- [ ] OTP login (phone) with Redis-backed OTP (hashed, TTL, attempt limit)
- [ ] JWT access + rotating refresh tokens; device sessions; logout-all
- [ ] RBAC middleware (permission-based); seed roles: customer, worker,
      admin, super_admin
- [ ] User profile CRUD + addresses (with lat/lng)
- [ ] Mobile: onboarding, OTP screens, secure token storage, auth-aware router

**Exit criteria:** a real phone can register, log in, kill other sessions;
RBAC blocks a customer from an admin route (integration-tested).

## Phase 2 — Catalog & Worker Onboarding (Week 4–6)

- [ ] `categories` / `subcategories` / `services` — fully data-driven,
      admin CRUD endpoints, image upload to S3/MinIO
- [ ] Worker registration: profile, skills (service links), service radius,
      availability schedule
- [ ] KYC document upload (private bucket, signed URLs), admin verify queue
- [ ] Nearby-worker search: geo index + `service_id` + availability filter
- [ ] Mobile (customer): home with category grid, service listing, search
- [ ] Mobile (worker): registration, KYC upload, availability toggle

**Exit criteria:** admin adds a brand-new category via API and it appears in
the app with zero code changes; nearby search returns correct workers p95 < 300 ms.

## Phase 3 — Booking Engine (Week 6–9) — the core

- [ ] Booking state machine in `domain` (see CLAUDE.md §6), transactional
      transitions, every transition audited
- [ ] Job offer fan-out to nearby workers via FCM; first-accept wins
      (row-lock protected); timeout → re-dispatch → manual fallback
- [ ] Live tracking: worker location ping → customer map (polling v1;
      WebSocket later)
- [ ] Arrival OTP verification; job start/complete
- [ ] Cancellation rules + reasons on both sides
- [ ] Background job worker (PG `SKIP LOCKED`) for dispatch timeouts,
      notifications, cleanup
- [ ] Mobile: full booking flow on customer + worker apps

**Exit criteria:** two phones (one customer, one worker) complete a real
booking end-to-end: book → accept → track → OTP → complete. Double-accept
race is integration-tested.

## Phase 4 — Payments, Pricing & Reviews (Week 9–12)

- [ ] `PaymentProvider` trait; implementations: cash (v1 default) +
      Razorpay (flagged); webhook signature verification, idempotent handlers
- [ ] Pricing: service base price per city, visiting charge, admin-set
      commission %; invoice generation (PDF to S3)
- [ ] Worker earnings ledger + settlement report (payout execution manual in v1)
- [ ] Refund flow (admin-initiated)
- [ ] Ratings & reviews both directions; aggregates on worker profile
- [ ] Coupons: flat/percent, min order, expiry, usage limits

**Exit criteria:** paid booking produces consistent invoice, commission,
and earnings rows (property-tested invariants); Razorpay sandbox flow passes
including webhook replay.

## Phase 5 — Admin Panel & Ops (Week 12–15)

- [ ] Admin API: dashboards (bookings/revenue/workers), user & worker
      management, KYC queue, category/pricing/coupon management,
      dispute + support tickets, audit log viewer, CSV export
- [ ] Admin UI: Flutter Web (thin — the API does the work)
- [ ] Notification templates (push/SMS) managed as data
- [ ] Feature flags table + runtime toggling

**Exit criteria:** operations team can run a day in Satna — verify workers,
resolve a dispute, refund a booking — without touching the database.

## Phase 6 — Hardening & Launch (Week 15–18)

- [ ] Load test booking flow + nearby search at 10k concurrent users;
      fix top offenders (indexes, caching, pool sizing)
- [ ] Security pass: OWASP checklist, rate limits, secrets audit, dependency
      audit (`cargo audit`)
- [ ] Observability: Grafana dashboards, alerting on error rate / queue depth /
      p95 latency
- [ ] Backups + restore drill; deployment runbook; staging environment
- [ ] Play Store / App Store release pipeline; crash reporting

**Exit criteria:** staging survives load test at target; restore drill passes;
apps approved in stores. **Launch Satna.**

## Phase 7+ — Post-launch (data-driven, in rough order)

Wallet & escrow · in-app chat · WebSocket live tracking · Elasticsearch/
OpenSearch (only if PG search measurably fails) · AI: recommendations,
dynamic pricing, fraud scoring, support chatbot (behind existing interfaces) ·
multi-city rollout · regional/city-manager roles · subscription plans for workers.

---

## Explicit v1 non-goals

No microservices · no Kafka/RabbitMQ · no chat · no wallet money-in ·
no AI features · no iOS-first polish (Android is the Satna market) ·
no multi-language beyond en/hi · no Elasticsearch.

Every one of these has a designed seam (trait, table, or module boundary) so
adding it later is additive, not a rewrite.

---

## Risk register

| Risk                              | Mitigation                                        |
|-----------------------------------|---------------------------------------------------|
| Double-accept on job offers       | Row-level lock + unique constraint; race test     |
| Payment webhook replay/dup        | Idempotency key on provider event ID              |
| Worker supply cold-start in Satna | Cash-first payments, manual dispatch fallback     |
| SQLx compile-time queries in CI   | Commit `sqlx prepare` offline metadata            |
| FCM delivery unreliability        | Dispatch timeout + re-offer loop, SMS fallback    |
| Scope creep (the enemy)           | This file. New scope goes to Phase 7+, not v1.    |
