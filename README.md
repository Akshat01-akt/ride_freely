# Ride Freely

On-demand driver rental: car owners book a verified driver, by the hour or for a full day, to drive their own car.

| Path | What |
|------|------|
| `backend/` | FastAPI + PostgreSQL/PostGIS + Redis |
| `apps/customer_app/` | Flutter customer app |
| `apps/driver_app/` | Flutter driver app |
| `packages/ride_core/` | Shared Flutter code (API client, auth, theme) |
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

## Backend tests

Needs the compose `db` service running. Tests create and migrate a separate `ride_freely_test` database.

```bash
cd backend && .venv/bin/python -m pytest
```

## Run the apps

```bash
cd apps/customer_app   # or apps/driver_app
flutter run --dart-define=API_BASE_URL=http://10.0.2.2/api/v1     # Android emulator (default)
flutter run --dart-define=API_BASE_URL=http://localhost/api/v1    # iOS simulator
flutter run --dart-define=API_BASE_URL=http://<your-lan-ip>/api/v1  # physical phone on the same Wi-Fi
```

Android blocks plain-HTTP traffic on release builds; use HTTPS for anything beyond local development.

## Flutter tests

```bash
(cd packages/ride_core && flutter test)
(cd apps/customer_app && flutter test)
(cd apps/driver_app && flutter test)
```

## Brand palette

Fuchsia `#D8125B`, dark grey `#2C2E39`, cream `#FFFDF2`, black `#000000`, beige `#DDD0C8`, dark grey `#323232` (see `packages/ride_core/lib/src/theme/`).
