# Ride Freely: Project Status

Last updated: 2026-11-16. Branch with the latest work: `phase5b-onboarding-admin` (cut from `phase1-foundation`, not merged yet).

Companion documents: `prd.md` (what we are building), `architecture.md` (original design, Draft v1), `superpowers/specs` and `superpowers/plans` (per-phase designs and task lists).

## 1. What the product is

A driver-on-demand app. A **customer** books a verified **driver** by the hour or day. A **driver** signs up, submits details and documents, and is shown to customers only after an **admin** verifies them. One Flutter app has a customer interface and a driver interface; admins use a website.

## 2. Phases

| Phase | Scope | Status |
|-------|-------|--------|
| 1 Foundation | Backend skeleton, separate customer and driver login (JWT access and refresh), Flutter app skeletons, role selection, onboarding | Done |
| 2 Drivers | Driver documents (upload with file-type checks), admin approval, online/offline, GPS location updates, nearby driver search (PostGIS + Redis freshness), suspension | Done |
| 3 Bookings | Booking engine: request, accept, reject, start, complete, cancel; server-side pricing; 20 s request expiry; no double-booking enforced by the database; busy drivers hidden from search | Done |
| 4 App flows | Booking form, customer bookings, driver requests, rate a trip, driver earnings tab, self-refreshing lists | Done |
| 5a Admin website | Static admin site served by nginx at `/admin`: dashboard, drivers with documents, users, activate/deactivate | Done |
| 5b Onboarding + full admin | Simple sign-up, server-defined application forms, per-item review, full admin panel, live driver map, animated redesign | Done (on branch, reviewed, fixes applied) |
| 5c Remaining | See section 6 | Not started |

### What Phase 5b added (the latest work)

- **Sign-up** needs only a name, an email *or* mobile number, and a password (drivers and customers alike). Login accepts either identifier.
- **Server-defined forms.** Admins edit the driver application and the customer profile questions from the panel (add, reword, reorder, hide, require). Apps draw the form from `GET /forms/{role}`; an app that meets a field type it does not know skips it, or asks for an update if the field is required.
- **Driver application.** After first login a driver sees the form (details plus documents). Lifecycle: Signed up, Application submitted, Under review, Approved, or "Needs changes" (the admin sent items back with a note; the driver fixes only those and resubmits). Suspend, reinstate and account deactivation stay separate.
- **Rules kept:** an unapproved, pending, rejected or suspended driver is never shown to customers or bookable. When an admin adds a required question later, approved drivers stay bookable and are asked to answer it. Admin actions that would revoke a driver are refused while they have an accepted or running booking.
- **Admin panel:** dashboard, review queue, drivers (filters, detail, per-item approve or send back, lifecycle timeline), users, bookings (read-only), forms builder, live map of online drivers.
- **Optional customer profile** form (never blocks booking).

## 3. Tech stack: what is used for what, and where

| Layer | Technology | Used for | Where |
|-------|------------|----------|-------|
| Mobile app | Flutter (Dart) | One app, customer and driver interfaces | `lib/` |
| App state and routing | GetX (`get`) | Controllers, dependency injection, routes | `lib/core`, `lib/features/*`, `lib/routes.dart`, `lib/app.dart` |
| App networking | Dio | HTTP client with token refresh | `lib/core/api/` |
| App storage | flutter_secure_storage | Tokens, saved role, server address | `lib/core/storage/`, `lib/core/role/` |
| Location | geolocator | Driver GPS sharing, customer search point | `lib/core/location/`, `lib/features/driver/availability_controller.dart` |
| Photos | image_picker | Picking document photos | `lib/features/driver/documents_controller.dart` |
| API | FastAPI, Pydantic v2 | REST endpoints under `/api/v1`, validation | `backend/app/api/v1/`, `backend/app/schemas/` |
| Business logic | Plain Python service modules | Auth, bookings, review, forms, applications, locations | `backend/app/services/` |
| Database access | SQLAlchemy 2 async, asyncpg | Models and queries | `backend/app/models/` |
| Migrations | Alembic | Schema changes (currently up to `0008`) | `backend/migrations/versions/` |
| Database | PostgreSQL 17 + PostGIS 3.5 | All permanent data, spatial search, the no-double-booking exclusion constraint | Docker service `db` |
| Cache | Redis 7 | Live driver location freshness (30 s), upload locks | Docker service `redis`; `backend/app/core/redis.py` |
| Auth | PyJWT, pwdlib (Argon2) | Access and refresh tokens, password hashing | `backend/app/core/security.py`, `backend/app/services/auth_service.py` |
| File storage | Local disk (volume) | Driver documents, served only to admins | `backend/app/services/storage.py` |
| Web server | nginx | Reverse proxy, rate limit, serves the admin site, strict Content-Security-Policy | `docker/nginx.conf` |
| Admin website | Plain HTML, CSS, ES modules, canvas (no framework, no build step) | Admin panel UI, animated background, live map | `docker/admin/` (`app.js`, `js/*.js`, `styles.css`) |
| Packaging | Docker Compose | Runs db, redis, api, nginx together | `docker-compose.yml`, `backend/Dockerfile` |
| Backend tests | pytest, pytest-asyncio, httpx | API and service tests against a real test database | `backend/tests/` |
| App tests | flutter_test | Widget, controller and API tests | `test/` |
| Admin site tests | `node --test` | Pure helper tests | `docker/admin/js/*.test.mjs` |

## 4. Repository map

```
ride_freely/
  backend/app/
    api/v1/        routes: auth, drivers, customers, bookings, locations, forms, admin
    services/      business rules (booking, review, application, form, customer_profile, document, location, earnings, auth)
    models/        tables (user, driver, customer, document, answer, customer_answer, form, booking, location)
    schemas/       request and response shapes
    core/          config, database, redis, security
  backend/migrations/   Alembic versions 0001 to 0008
  backend/tests/        pytest suites
  lib/core/        API client, auth, forms models, theme, shared UI
  lib/features/    auth, customer, driver, bookings, forms (dynamic form), onboarding, role_select
  docker/          nginx.conf and the admin website
  docs/            this file, prd.md, architecture.md, superpowers/ (specs and plans)
```

## 5. How to run and check

```
docker compose up -d --build          # db, redis, api, nginx (admin site at http://localhost/admin/)
docker compose exec api alembic upgrade head
docker compose exec api python -m app.cli create-admin --phone +91XXXXXXXXXX --name "Ops"

cd backend && source .venv/bin/activate && python -m pytest -q    # 350 tests
flutter analyze && flutter test                                    # 276 tests
node --test docker/admin/js                                        # 11 tests
```

Admin accounts are created only with the command above; the website never creates admins. Migrations are not run automatically when the api container starts.

## 6. Not done yet

- Live driver tracking for the **customer** during a trip (the admin map exists).
- Push notifications (Firebase Cloud Messaging).
- Payments (Razorpay), commission and refunds. Prices are calculated on the server but nothing is charged.
- OTP and email verification, forgot password.
- Admin: pricing and commission settings, reports, complaints and support tickets, audit log, admin roles.
- Scheduled bookings and automatic driver matching or reassignment.
- Celery background jobs, WebSockets, and a map in the app (flutter_map). These appear in `architecture.md` as the plan but are **not** in the code yet.

## 7. Known gaps from the Phase 5b review (deferred, none critical)

- Replacing a driver's document keeps the same document id, so an admin with the page already open could approve the new file without seeing it. "Approve driver" also approves any pending answers in bulk.
- The admin's note on "Needs changes" for a whole driver is not stored (per-item notes are).
- The review queue shows the newest 50 pending applications only.
- Bookings page "Customer" link does not filter by name; stats use UTC midnight for "bookings today".
- Optional answers cannot be cleared once saved; form field keys may be upper case.
- Migration downgrades for `0005` and `0007` fail or leave data once email-only users or custom document keys exist.
- Email-only users cannot see each other's contact on a booking (only phone is shared).
- The Flutter app was tested with widget tests only; it has not been run on a device or emulator in this phase.
