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

Next: phase 2 payments (SSLCommerz / bKash, teacher ledger and payouts), phase 3 session booking, phase 4 jobs.
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

## Deploy (one VPS)

```bash
POSTGRES_PASSWORD=... docker compose up -d --build
docker compose exec api npx ts-node prisma/seed.ts   # first admin (needs ADMIN_EMAIL / ADMIN_PASSWORD in backend/.env)
```

Put Nginx with Let's Encrypt in front: `api.tech.dropout.it` → `127.0.0.1:3000`.

Release app builds point at production with
`flutter build appbundle --dart-define=API_URL=https://api.tech.dropout.it/api/v1`.
