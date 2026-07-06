# Servexa — Product Vision & Feature Spec (v2)

> What we are building, why it wins, and every feature A→Z.
> Engineering roadmap lives in [PLAN.md](PLAN.md); architecture rules in [CLAUDE.md](../CLAUDE.md).

---

## 1. The pitch

**"Uber for home services."** Open the app, tap a service, and a verified
professional is at your door — you watch them come to you live on the map,
exactly like tracking an Uber or Rapido ride. Pay cash or UPI after the work
is done. Book in under 60 seconds.

Urban Company made home services organized but slot-based and metro-only.
Servexa makes them **instant and hyperlocal**, starting where the big players
don't go: Tier-2/3 India (launch city: Satna, MP).

---

## 2. Why this can be #1

| Edge | What it means |
|------|---------------|
| **Instant, not slots** | Uber-style dispatch: request → nearby workers get the job → first accept wins → live tracking. Urban Company makes you pick a 2-hour slot tomorrow. |
| **Tier-2/3 first** | Zero competition in Satna-class cities. Urban Company covers ~60 metros; India has 4000+ towns that need an electrician *now*. |
| **Cash + UPI first** | Match how these markets actually pay. Cards optional, never required. |
| **Hindi-first, bilingual** | Full hi + en from day one. Workers onboard in Hindi. |
| **Worker-friendly economics** | Low commission, transparent earnings screen, instant job visibility, no inventory "purchase" schemes. Happy supply side = reliable service = happy customers. Rapido beat Ola on driver economics; we do the same. |
| **Trust as a feature** | KYC-verified workers, arrival OTP handshake, both-way ratings, SOS button, price shown *before* booking — no "estimate shock". |
| **Categories are data** | Admin adds "Mehndi Artist" or "Tractor Repair" from the panel and it's live in every app instantly. The platform molds to each city's demand. |

**North-star metric:** completed bookings per week.
**The one promise:** *the worker actually shows up* — everything (dispatch
timeouts, re-offers, ops fallback, worker ratings) exists to defend that promise.

---

## 3. How it works — the three experiences

### 3.1 Customer (like booking an Uber)

1. **Open app** → GPS auto-detects location; address confirmed via map-pin drag.
2. **Browse** → category grid → services with **fixed upfront price** (₹, visiting charge shown separately).
3. **Book** → describe the problem (text + optional photos), confirm address, book.
4. **Matching** → animated "Finding a professional near you…" (like Uber's car-search). Nearby online workers get the offer; first accept wins.
5. **Track** → full-screen Google Map: worker's photo/rating card, live moving marker, route polyline, ETA countdown. Call button.
6. **Arrival handshake** → worker arrives → customer shares the 4-digit **arrival OTP** (like Uber ride-start PIN) → job starts.
7. **Done** → worker marks complete → customer pays (cash / UPI QR) → rates the worker 1–5 ★.
8. **History** → all bookings, re-book in one tap, invoices.

### 3.2 Worker (like driving for Rapido)

1. **Register** → phone OTP → pick skills (services) → upload KYC (Aadhaar/PAN + selfie) → admin verifies → approved.
2. **Go online** → availability toggle, exactly like a driver app.
3. **Job offer** → push notification + in-app card: service, distance, pay, customer area. 60-sec accept window. First accept wins (enforced atomically in DB).
4. **Navigate** → one tap opens Google Maps turn-by-turn to the customer. App pings location every 10–15 s so the customer sees them coming.
5. **Arrive** → enter customer's OTP → work → mark complete → collect payment.
6. **Earnings** → today/week/lifetime totals, per-job breakdown, average rating, completed count. Settlement report.

### 3.3 Admin (ops team)

- **Live ops map**: all active bookings + online workers on one map (god view).
- KYC verify queue · category/service/price management (pure data) ·
  booking monitor with manual re-dispatch · refunds · coupons ·
  user/worker management · audit log · dashboards (bookings, revenue, supply).

---

## 4. Google Maps — everywhere

| Feature | API | Screen |
|---------|-----|--------|
| Address picker: draggable pin + search autocomplete | Places API + Geocoding | Booking flow, saved addresses |
| Auto-detect current location | Fused Location (geolocator) | Home, booking |
| Live tracking: worker marker animates toward customer | Maps SDK + our location pings | Tracking screen |
| Route line worker → customer | Directions API (polyline) | Tracking screen |
| ETA + distance ("Ramesh is 1.2 km · 6 min away") | Distance Matrix | Tracking + offer cards |
| Worker navigation | Deep link to Google Maps app | Worker job screen |
| Nearby-worker matching (radius search) | Redis GEO / PostGIS (server-side) | Dispatch engine |
| Admin god view | Maps SDK (web) | Admin panel |

**Backend:** `POST /api/v1/location/ping` (worker, en-route only) → Redis GEO +
last-known in PG. Customer polls `GET /bookings/:id/track` v1 (WebSocket later).
Maps vendor sits behind a `MapsProvider` trait (CLAUDE.md rule 5).

**Cost control (the $200/month credit dies fast if used naively):**
- Directions API **once per job** at accept (+ re-route only on big deviation) — never per ping.
- Distance Matrix ETA at accept, then refresh at most every 60 s; between refreshes the client interpolates the marker along the cached polyline.
- Geocode results cached; saved addresses never re-geocoded.
- Server-side matching uses Redis GEO (free) — Google is never called for dispatch.
- Autocomplete uses session tokens (billed per session, not per keystroke).

**Platform reality:** worker location pings require an Android **foreground
service** with a persistent notification (OS kills silent background loops)
plus battery-optimization exemption UX. This is its own work item, not a
bullet inside "tracking". iOS background location adds App Store review
friction — Android-first, iOS parity later.

---

## 5. Full feature catalog

✅ built · 🔜 next milestone · 📋 planned

### Customer app
- ✅ OTP login, JWT + refresh, profile, roles
- ✅ Category grid → service list → book (data-driven catalog)
- ✅ Bookings: active/past, status chips, cancel, rate 1–5★
- ✅ Server URL setting (admin-lockable)
- 🔜 UI v2 (design system below), promo banner, popular services, active-booking pinned card
- 🔜 Address book with map-pin picker + GPS autodetect
- 🔜 Live tracking screen (map, route, ETA, call)
- 🔜 Arrival OTP display
- 🔜 Problem photos on booking
- 🔜 Push notifications (FCM): offer accepted, en-route, arrived, completed
- 📋 UPI/Razorpay payment, invoices (PDF), coupons/referral codes
- 📋 In-app chat with worker · scheduled ("book for tomorrow 10am") bookings
- 📋 Wallet · subscriptions (AMC plans: 2 AC services/year) · service packages
- 📋 AI: "describe your problem" → suggested service, price estimate from photo

### Worker app (same binary, worker mode)
- ✅ Become-a-worker, online toggle, job feed, accept (first-wins), status advance, earnings card
- 🔜 KYC upload + verification states (pending/approved/rejected) — **accept
  gate: only admin-verified workers receive offers or can accept.** Today
  `become_worker` is a self-service toggle (test phase); it must not survive M2.
- 🔜 Job offer full-screen card with 60-s countdown + sound (like Rapido)
- 🔜 Navigate button + background location pings while en-route
- 🔜 Skill & radius selection, weekly availability schedule
- 🔜 **Price-change request**: propose a new price for a service with reason;
  track its status (pending/approved/rejected) — admin decides, never the worker
- 📋 Settlement/payout view · leaderboards & incentives ("complete 20 jobs → bonus") · training content

### Admin — runtime control plane (see §6.5)
- ✅ RBAC (permission-based), `ADMIN_PHONES` bootstrap, app-config flags (server-URL lock)
- ✅ Audit log on every mutation
- 🔜 Category/service CRUD from app (currently DB-seeded)
- 🔜 **Pricing control**: service prices, visiting charge, commission % — live edits, audited
- 🔜 **Offers & coupons**: promo banners with schedule, coupon engine
- 🔜 **Remote branding**: app name, logo, colors, support contacts via app-config
- 🔜 **Feature flags**: maintenance mode, min app version, dispatch tuning knobs
- 🔜 KYC verify queue · booking monitor + manual re-dispatch
- 📋 Maker-checker approval queue for money-sensitive changes
- 📋 White-label build pipeline (rebranded APK from one GitHub Actions click)
- 📋 Web panel (Flutter Web): dashboards, live ops map, refunds, disputes, CSV export

### Customer service (see §6.6)
- 🔜 `support` role + permissions (data-only change — RBAC is ready for it)
- 🔜 Support console: user/booking lookup, full audit timeline, internal notes
- 🔜 Ticket system: in-app "Report a problem" → threaded conversation with support
- 🔜 Refund *request* → admin approval queue (maker-checker)
- 📋 SLA timers + auto-escalation · CSAT on ticket close · canned replies

### Platform
- ✅ Rust modular monolith, PG + Redis, migrations, envelope API, health, metrics, CI, Render auto-deploy
- 🔜 FCM push · dispatch engine (fan-out, timeout, re-offer) · geo search
- 🔜 **SMS gateway (MSG91/Twilio) behind `SmsProvider` trait — hard launch gate;
  kills `DEV_RETURN_OTP` (see §12.2)**
- 📋 Payments behind `PaymentProvider` trait · WebSockets · multi-city

---

## 6. UI design system v2 ("give good UI look")

Current UI is functional but generic Material. v2 makes it feel like a
polished consumer app (Zomato/Rapido/CRED quality bar).

### Brand
- **Primary:** deep indigo `#4F46E5` (trust, tech)
- **Accent:** warm amber `#F59E0B` (energy, CTAs like "Book now")
- **Success** green / **danger** red for status; each category tile gets its own soft tint (blue, teal, orange, purple, green, pink) so the grid feels alive.
- **Typography:** Google Fonts — `Poppins` for headings, `Inter` for body (both look great in Devanagari fallback via Noto Sans).
- **Shape:** 16–20 px rounded cards, soft elevation, pill buttons.
- Light **and** dark theme from one `ColorScheme.fromSeed`.

### Signature screens
- **Home:** greeting + location chip ("📍 Satna") → search bar → auto-scrolling promo carousel → colorful category grid → "Popular services" horizontal cards with price → **active booking pinned card** at bottom (live status, like Zomato's order bar).
- **Service detail sheet:** photo, price breakdown (service + visiting charge), rating, "Book now" pill.
- **Finding-worker screen:** radar/ripple animation over map (the Uber moment).
- **Tracking screen:** 65% map + bottom sheet: worker avatar, name, ★ rating, jobs done, call button, status timeline (Accepted → On the way → Arrived → Working → Done), big OTP display.
- **Worker offer card:** full-screen, service + payout + distance, circular 60-s countdown, Accept (big, green) / Decline.
- **Micro-polish:** skeleton shimmer loaders, hero animations on category tap, empty states with illustrations, haptic on booking confirm.

---

## 6.5 Runtime control plane — admin changes everything, live

> The rule "categories are data, not code" extends to the **whole product**.
> Anything an operator might want to tune ships as data in `app_settings` /
> dedicated tables, editable from the admin panel, effective instantly,
> audited. No code change, no redeploy, no app update.

### 6.5.1 Pricing & offers (admin-editable, per city)

| What | How it works |
|------|--------------|
| Service price | Base price + visiting charge per service per city; edit takes effect on the *next* booking (in-flight bookings keep their locked price) |
| Commission % | Global default + per-category override; every change audited with old→new values |
| Offers / promo banners | Title, image, discount, deeplink, start/end datetime, target city — carousel on home screen renders whatever is active |
| Coupons | Flat/percent, min order, max discount, usage limit (global + per user), expiry, first-booking-only flag |
| Referral amounts | Credit for referrer and referee, admin-tunable |
| Surge caps | Max multiplier + on/off switch (phase M6) |
| **Price-change requests (worker → admin)** | Workers never edit prices. A worker submits a request (service, proposed price, reason) from the app → lands in the admin **pricing queue** → admin approves (price updates + worker notified) or rejects with a note. Statuses: `pending → approved / rejected`. Every decision audited. |

**Price authority is one-way:** admin sets, everyone else consumes. The
customer sees the admin price at booking; the worker sees their payout
(price − commission) on the offer card. No negotiation inside a booking —
extra work goes through the add-on quote flow (§7), which the customer
approves and which uses admin-set add-on prices.

**Maker-checker on money:** price/commission changes above a threshold need a
second admin's approval (pending → approved), like real fintech back offices.
*Deferred to M4 — maker-checker is theater while there is exactly one admin;
until then the audit log is the control.*

### 6.5.2 Branding & white-label ("master level customization")

Two layers — important real-world distinction:

1. **Remote branding (instant, no new APK):** app display name (in-app
   headers/splash), logo image (S3 URL), primary + accent colors, tagline,
   support phone/email, terms & privacy URLs. Served in `GET /api/v1/app-config`
   (extends the existing endpoint); the Flutter theme is built *from this
   payload* at startup and cached for offline. Change the logo in admin →
   every user sees it on next app open.
2. **Launcher branding (needs a build):** the icon and name on the phone's
   home screen are baked into the APK by Android/iOS. Handled by the existing
   `workflow_dispatch` build pipeline gaining inputs: `app_name`, `icon_url`,
   `primary_color` → one click in GitHub Actions produces a fully rebranded
   APK. Together these make the platform white-label-ready (franchise/
   multi-city brands later).

### 6.5.3 Feature flags & app control

`allow_server_url_change` (✅ built) · `maintenance_mode` (app shows a
friendly "back soon" screen) · `min_app_version` (force-update dialog) ·
`enable_wallet`, `enable_chat`, `enable_online_payment` (ship dark, flip on) ·
`booking_offer_timeout_secs`, `dispatch_radius_km` — dispatch engine reads
these live. All flags in `app_settings`, all changes audited.

### 6.5.4 Content as data

Notification/SMS templates (with `{{name}}` placeholders) · FAQ entries ·
cancellation reasons list · onboarding copy — editable, localized (en/hi),
versioned.

---

## 6.6 Customer service — the support role & console

A dedicated **`support` role** (RBAC — permissions, not names), because real
apps never give the ops floor full admin.

### What support CAN do
- Look up any user/booking by phone or booking ID
- See the **full booking timeline** reconstructed from `audit_logs`:
  created → offered to 4 workers → accepted by Ramesh 09:32 → en-route →
  OTP verified → completed → rated. Every state change with timestamp and actor.
- See payment status, applied coupons, past tickets, device/app version
- Manage **support tickets**: reply, reassign, escalate, resolve
- Add internal notes on users/bookings (visible to staff only)
- **Request** a refund/cancellation override → goes to admin approval queue
- Trigger a re-dispatch when a booking is stuck

### What support CANNOT do (permission-enforced)
Change prices/config/branding · execute refunds (request only — maker-checker) ·
grant roles · read KYC documents · see full payment instrument details.

### Ticket system (`tickets` + `ticket_messages` tables)
- Customer app: **Help** section → "Report a problem" on any booking →
  category (worker no-show, wrong charge, quality, app issue, other) →
  chat-style thread with support, photo attachments
- Statuses: `open → in_progress → waiting_customer → resolved → closed`;
  priority + SLA timer; auto-escalate to admin if SLA breached
- Every resolution writes an audit row; CSAT ("was this helpful?") on close

### Role matrix (v2)

| Capability | customer | worker | **support** | admin | super_admin |
|---|---|---|---|---|---|
| Book / rate | ✅ | ✅ | — | — | — |
| Accept jobs | — | ✅ | — | — | — |
| Read any booking + timeline | — | — | ✅ | ✅ | ✅ |
| Tickets: manage | — | — | ✅ | ✅ | ✅ |
| Refunds | — | — | request | ✅ execute | ✅ |
| Prices / offers / coupons: set | — | — | — | ✅ | ✅ |
| Price change: request | — | ✅ submit | — | ✅ approve/reject | ✅ |
| Branding / flags | — | — | — | ✅ | ✅ |
| KYC verify | — | — | — | ✅ | ✅ |
| Grant roles / manage RBAC | — | — | — | — | ✅ |

Adding a role (e.g. `city_manager`) stays a data operation — zero code change.

---

## 7. Trust & safety

Arrival OTP handshake (no OTP = job can't start = no fraud "completed" jobs) ·
KYC + police-verification badge (phase 2) · both-way ratings; workers < 4.0★
get retrained/suspended · SOS button on tracking screen (calls emergency
contact, alerts ops) · masked calling later (exchange no real numbers) ·
price locked at booking — no doorstep inflation; extra work = in-app
"add-on quote" customer must approve.

## 8. Monetization

1. **Commission** per completed booking (admin-set %, start 10–15% — win supply
   first, raise later) — core revenue. **Cash problem solved by a dues ledger:**
   on a cash job the worker keeps the full amount and the commission posts to
   their dues balance; they settle dues via UPI in-app; offers pause
   automatically when dues exceed a cap (₹500 default). This is how
   Rapido/Porter handle cash — without it, cash bookings = zero revenue (§12.1).
2. **Visiting charge** floor so tiny jobs stay viable.
3. 📋 Worker **subscription tiers** (₹99/mo → priority dispatch, lower commission).
4. 📋 **Featured listing / sponsored category** placement.
5. 📋 **AMC subscription packs** for customers (recurring revenue).
6. 📋 Surge pricing on demand spikes (festival season) — capped, transparent.

## 9. Growth (city-by-city playbook)

Referral both sides (₹50 credit) · WhatsApp share of booking status ·
worker recruiting via local electrician/plumber associations ·
launch-city hyper-focus: 50 verified workers across 6 categories before
marketing a single rupee · Google My Business + vernacular social ads.

---

## 10. Roadmap A→Z (updated)

| Milestone | Scope | Status |
|-----------|-------|--------|
| **M1 — Core marketplace** | Auth, catalog, booking engine, worker mode, ratings, deploy | ✅ **done** |
| **M2 — Uber experience** | UI v2 redesign · addresses with map-pin picker · live tracking + ETA + arrival OTP (adds `otp_verified` state) · FCM push · dispatch fan-out with timeout/re-offer · KYC upload + **verified-only accept gate** (removes the self-service worker toggle) | 🔜 **next** |
| **M2.5 — Control plane & support** | Admin pricing/offers/coupons CRUD · **worker price-change request queue (admin approve/reject)** · remote branding (name, logo, colors) · feature flags (maintenance, min version, dispatch knobs) · `support` role + console with audit timeline · minimal booking-linked tickets | 🔜 |
| **M3 — Money & launch gate** | **Real SMS gateway, `DEV_RETURN_OTP=false` (§12.2)** · UPI/Razorpay behind trait · **cash-commission dues ledger + auto-pause over cap (§12.1)** · invoices · paid hosting + backups (§12.5) | |
| **M4 — Ops at scale** | Admin web panel (Flutter Web) · live ops map · disputes/refunds · maker-checker approvals · full ticket SLA/escalation · CSV export | |
| **M5 — Engagement** | Chat · scheduled bookings · wallet · subscriptions · referral engine | |
| **M6 — Intelligence** | Recommendations · fraud scoring · support chatbot · dynamic pricing *only if the data ever justifies it* | |
| **M7 — Expansion** | Multi-city rollout · city-manager roles · white-label build pipeline · franchise model | |

**Launch gate — all true before the first stranger uses the app:**
real SMS OTP with `DEV_RETURN_OTP=false` · only KYC-verified workers can
accept · paid database hosting with backups · OTP/login rate limits verified
under load · privacy policy + location-data retention (pings deleted after
booking completes + 30 days) · crash reporting wired.

## 11. Success metrics

Booking completion rate > 90% · median request→accept < 90 s ·
worker accept rate > 60% · p95 nearby-search < 300 ms ·
**repeat booking within 90 days > 30%** (home services are monthly/quarterly —
D30 app-retention is the wrong yardstick, see §12.7) · worker monthly churn < 10% ·
NPS > 50 · crash-free sessions > 99.5%.

---

## 12. Hard truths — deep analysis the plan must respect

1. **Cash breaks commission collection.** ~90% of Satna transactions will be
   cash, paid worker-to-hand. The platform sees none of it. Without the dues
   ledger (§8.1) the business model doesn't exist — this is the #1 failure
   mode of tier-2/3 marketplaces, which is why it moved into M3, before scale,
   not after.
2. **`DEV_RETURN_OTP` is an account-takeover hole, today.** The deployed API
   returns the OTP in the response, `ADMIN_PHONES` auto-grants admin, and the
   admin phone number is committed in `render.yaml`. Anyone who finds the URL
   can become admin in two requests. Acceptable strictly while the URL is
   private; a real SMS provider is a **launch gate**, not an M4 nicety.
   Interim rule: do not post the Render URL anywhere public.
3. **Anyone can become a worker today.** `become_worker` is a self-service
   toggle and `accept` checks only the role — the first stranger with the APK
   can take a real customer's job. The verified-only accept gate belongs in
   M2, because trust dies with one bad job.
4. **Google Maps bills per call.** Naive per-ping Directions/Distance-Matrix
   polling burns the $200 credit in days at even modest volume. Budget rules
   live in §4 and are requirements, not suggestions.
5. **Render free tier is a demo, not a launch.** Free services sleep (first
   morning booking waits ~50 s for cold start — fatal for "instant"), free
   Postgres **expires after ~90 days**, and there are no backups. Paid tier or
   a small VPS (₹400–800/mo) with nightly `pg_dump` before real users.
6. **Background location is a project, not a bullet.** Foreground service,
   persistent notification, battery-optimization exemptions, OEM quirks
   (Xiaomi/Oppo kill apps aggressively — exactly the phones Satna workers own).
   Scoped as its own M2 work item; degrade gracefully to coarse pings.
7. **Home services are not rides.** A household books monthly, not daily —
   so growth = supply quality + word of mouth, not surge mechanics or DAU.
   Metrics in §11 are transaction-based for this reason; dynamic pricing is
   parked in M6 behind a data test.
8. **One roadmap, two documents.** PRODUCT.md milestones are the product
   order; [PLAN.md](PLAN.md) keeps engineering exit criteria. Mapping:
   M2 ≈ Phases 2–3 · M2.5 ≈ Phase 5 (subset) · M3 ≈ Phase 4 · M4 ≈ Phases 5–6.
   If they disagree, PRODUCT.md wins on *what*, PLAN.md on *done-when*.
