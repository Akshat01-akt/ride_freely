# Ride Freely

On-demand driver rental: car owners book a verified driver, by the hour or for a full day, to drive their own car.

| Path | What |
|------|------|
| `backend/` | FastAPI + PostgreSQL/PostGIS + Redis |
| `lib/` | The Flutter app: one app, two interfaces (customer and driver) |
| `lib/core/` | API client, auth, role store, theme, shared widgets |
| `lib/features/customer/`, `lib/features/driver/` | The two interfaces |
| `docs/` | [PRD](docs/prd.md), [architecture](docs/architecture.md), plans |

## Run the backend

```bash
cp .env.example .env          # then set DB_PASSWORD and SECRET_KEY, and keep DATABASE_URL's password in sync
docker compose up -d --build
# apply migrations (db is published on 127.0.0.1:5433)
cd backend && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
set -a; . ../.env; set +a
DATABASE_URL="postgresql+asyncpg://app_user:$DB_PASSWORD@127.0.0.1:5433/driver_booking" .venv/bin/alembic upgrade head
curl localhost/api/v1/health
```

API docs: http://localhost/docs

## Admin: approving drivers

There is no admin screen yet; admins use the API. Create an admin once, then log in and review:

```bash
docker compose exec api python -m app.cli create-admin --phone +919000000001 --name "Ops"   # prompts for a password
curl -X POST localhost/api/v1/auth/admin/login -H 'content-type: application/json' -d '{"phone":"+919000000001","password":"..."}'
# with the returned access_token as `Authorization: Bearer ...`:
#   GET   /api/v1/admin/drivers/pending
#   GET   /api/v1/admin/documents/{id}/file
#   PATCH /api/v1/admin/documents/{id}            {"status": "APPROVED", "note": "..."}
#   PATCH /api/v1/admin/drivers/{driver_id}/verification  {"status": "APPROVED"}   # needs approved LICENCE + ID_PROOF
#   PATCH /api/v1/admin/drivers/{driver_id}/suspension    {"suspended": true}
```

Driver flow: register, upload documents, admin approves, driver goes online (location is shared every 10 s while the app is open), customers see the driver in nearby search (5 km by default).

## Backend tests

Needs the compose `db` and `redis` services running (Redis is published on `127.0.0.1:6390`, the database on `127.0.0.1:5433`). Tests create and migrate a separate `ride_freely_test` database.

```bash
cd backend && .venv/bin/python -m pytest
```

## Run the apps

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2/api/v1     # Android emulator (default)
flutter run --dart-define=API_BASE_URL=http://localhost/api/v1    # iOS simulator
flutter run --dart-define=API_BASE_URL=http://<your-lan-ip>/api/v1  # physical phone on the same Wi-Fi
```

Android blocks plain-HTTP traffic on release builds; use HTTPS for anything beyond local development.

On first launch the app asks "I need a driver" or "I'm a driver", remembers the choice, and shows that interface's own login, registration and home screens. Use "Switch account type" on the login screen to change it.

### Design review without a backend

```bash
flutter run -t lib/main_preview.dart --dart-define=UI_PREVIEW=true
```

Shows every screen with clearly labelled sample content (drivers, wallet, booking). Normal builds never show sample data: until the backend has drivers, bookings and a wallet, those screens show empty states. Do not use `UI_PREVIEW` in release builds.

## Flutter tests

```bash
flutter test
flutter analyze
```

## Brand palette

Fuchsia `#D8125B`, dark grey `#2C2E39`, cream `#FFFDF2`, black `#000000`, beige `#DDD0C8`, dark grey `#323232` (see `lib/core/theme/`).
