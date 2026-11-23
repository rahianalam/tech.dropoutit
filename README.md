# Tech.Dropout

Skill marketplace: teachers sell courses and 1:1 sessions, students learn, and a jobs board connects hirers with job seekers.

| Folder | What | Stack |
| --- | --- | --- |
| `backend/` | REST API at `api.tech.dropout.it/api/v1` | NestJS 11, Prisma 6, PostgreSQL 16 |
| `app/` | Android, iOS and admin web app | Flutter, Riverpod, go_router, Dio |

## Status

Phase 1 (foundation) — done:

- Sign up / login by email or Bangladeshi mobile, JWT access + rotating refresh tokens
- Roles: admin, teacher, student, employer, job seeker (one user can hold several)
- Teacher application with portfolio → admin approves / asks for changes / rejects
- Course builder (sections, lessons, preview lessons) → admin review → published
- Course search with ranking, categories, free/paid filter
- Free enrollment, lesson access control with signed media URLs, progress tracking
- Admin: stats, user block/unblock, commission and payout settings (all editable)

Phase 2 (payments) — done:

- Paid courses through SSLCommerz hosted checkout (bKash, Nagad, Rocket, cards); every payment is verified with SSLCommerz before access is given, and fulfilment is idempotent
- Teacher ledger: share = (price − gateway fee) × (1 − commission), held for the admin's hold period, then withdrawable
- Payouts drafted automatically on the admin's schedule (weekly on Sunday / monthly on a chosen day / manual); admin approves, sends the money and records the reference
- Refunds remove access and void or claw back the teacher's earning
- The admin's own official courses earn no teacher payout

Phase 3 (1:1 sessions) — done:

- Teachers set a weekly schedule (Bangladesh time) with slot length and a price per rule; 0 = free intro session
- Students see open slots for the next 14 days (at least 2 hours ahead) and book; one live booking per slot is enforced by the database
- Paid sessions hold the slot for 10 minutes while the student pays through SSLCommerz; if the hold ran out and someone else took the slot, the payment is refunded
- Video call link (Jitsi by default, `MEETING_BASE_URL`), reminders 24 h and 15 min before, join button opens 15 min early
- Student can cancel up to 24 h before (paid sessions are refunded); teacher can cancel any time; teacher marks completed / no-show, otherwise auto-completed
- Earnings use the session commission and the same hold and payout flow as courses
- Students rate sessions and courses; either side can report a problem to the admin

Phase 4 (jobs) — done:

- Anyone can create a company profile and post jobs; jobs from unverified companies wait for admin review (edits go back to review too), verified companies go live at once
- Job seekers make a profile with skills and a CV (PDF upload, max 5 MB, checked by file signature, or a link)
- CVs are never public: they are stored in `UPLOAD_DIR` and opened through signed links that expire after 15 minutes
- Jobs list with search and type filter; a signed-in seeker sees jobs matching their skills first
- One application per job; the employer sees CV, skills, portfolio, cover letter and courses finished on Tech.Dropout, moves applicants through stages (new → shortlisted → interview → hired / rejected) and keeps private notes; the seeker is notified at each stage
- Jobs close themselves after the deadline

Phase 5 (release readiness) — done:

- Package name `it.dropout.tech`, app icon, release signing from `android/key.properties` (CI writes it from secrets)
- GitHub Actions builds a test APK on every PR and a signed Play Store bundle on `main`
- Push notifications through Firebase Cloud Messaging; off until configured, no Firebase files needed in the repo
- Account deletion in the app (required by Google Play), privacy policy at `/privacy` and deletion instructions at `/delete-account`
- Caddy reverse proxy with automatic HTTPS in `docker-compose.yml`
The full data model for those phases is already in `backend/prisma/schema.prisma`.

## Run locally

```bash
# API
cd backend
cp .env.example .env            # set DATABASE_URL and secrets
npm ci
npx prisma migrate deploy
ADMIN_EMAIL=you@example.com ADMIN_PASSWORD=strong-pass npm run seed
npm run start:dev               # http://localhost:3000/health

# Tests (use a separate database; it is wiped)
DATABASE_URL=postgresql://.../techdropout_test npm test

# App
cd ../app
flutter pub get
flutter run --dart-define=API_URL=http://10.0.2.2:3000/api/v1   # Android emulator
```

## Payments

Set `PAYMENT_GATEWAY=sslcommerz`, `SSLCZ_STORE_ID`, `SSLCZ_STORE_PASSWORD` and `PUBLIC_API_URL` in `backend/.env`.
Use `SSLCZ_BASE_URL=https://sandbox.sslcommerz.com` with sandbox credentials, then `https://securepay.sslcommerz.com` for live.
In the SSLCommerz merchant panel set the IPN URL to `https://api.tech.dropout.it/api/v1/payments/sslcommerz/ipn`.
For local testing without SSLCommerz use `PAYMENT_GATEWAY=fake`.

## Deploy and release

Step-by-step guide (Bengali): [docs/DEPLOY.md](docs/DEPLOY.md): VPS + Docker + Caddy (automatic HTTPS), secrets, backups, Android signing, Firebase push, Play Console.

```bash
POSTGRES_PASSWORD=... docker compose up -d --build
docker compose exec api node dist/seed/seed.js   # first admin (ADMIN_EMAIL / ADMIN_PASSWORD in backend/.env)
```
