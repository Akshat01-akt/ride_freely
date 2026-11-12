# Ride Freely Phase 1: Backend Foundation and Flutter Skeletons Implementation Plan

> **Amended during execution (2026-11-12):** the product owner asked for ONE Flutter app with two interfaces instead of two apps. Tasks 5-7 were implemented as a single app at the repo root (`lib/core` replaces `packages/ride_core`; `lib/features/customer` and `lib/features/driver` replace the two apps; a role-choice screen was added). Brand palette: fuchsia #D8125B, #2C2E39, cream #FFFDF2, black, beige #DDD0C8, #323232. Backend tasks 1-4 are unchanged.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A running Dockerised FastAPI backend with separate customer and driver registration/login (JWT, role-enforced), plus two Flutter app skeletons (Customer, Driver) with their own login, register and home-shell screens wired to it.

**Architecture:** One FastAPI service with a `role` column (`customer` | `driver` | `admin`) on `users`. Role-specific auth endpoints (`/auth/customer/*`, `/auth/driver/*`) create the matching profile row; a `require_role` dependency guards role-only routes. Flutter is a monorepo: two apps share a `ride_core` package (Dio client, secure token storage, auth repository, theme).

**Tech Stack:** FastAPI, SQLAlchemy 2.0 async + asyncpg, Alembic, Pydantic v2, PyJWT, pwdlib[argon2], PostgreSQL 17 + PostGIS 3.5, Redis 7, Nginx, pytest + httpx; Flutter 3.44 / Dart 3.12, GetX, Dio, flutter_secure_storage.

**Spec:** No separate design doc. Source is the user's pasted project brief (sections 3-12, 20) plus the chat playback approved on 2026-11-12: separate customer/driver logins and UIs, two Flutter apps, one backend, OpenStreetMap maps later, admin panel later.

## Global Constraints

- Monorepo layout: `backend/`, `apps/customer_app/`, `apps/driver_app/`, `packages/ride_core/`, `docker-compose.yml` at repo root.
- API prefix `/api/v1`. Primary keys are UUID. Money is `NUMERIC(10,2)`. Timestamps are `TIMESTAMPTZ`.
- Passwords hashed with Argon2id. Never log or return `password_hash`.
- Phone is the login identifier (unique, E.164 style `+91XXXXXXXXXX`); email optional.
- JWT: access 30 min, refresh 7 days, carries `sub` (user id), `role`, `type` (`access`|`refresh`).
- Driver `verification_status` starts `PENDING`; `availability_status` starts `OFFLINE` (enum: OFFLINE, AVAILABLE, RESERVED, BOOKED, ON_TRIP, SUSPENDED).
- Postgres and Redis are not published to the host in the compose file's `api`-facing network except `db` on `5432` bound to `127.0.0.1` for local tooling. Only Nginx exposes 80.
- Secrets come from `.env` (never committed); commit `.env.example`.
- GetX for Flutter state and routing. Base URL configurable via `--dart-define=API_BASE_URL`, default `http://10.0.2.2/api/v1` (Android emulator).

## Review Focus

- Registering a phone that already exists (either role) returns 409, not 500; no second profile row is created.
- A customer access token calling a driver-only route gets 403; a driver token on a customer route gets 403.
- A refresh token presented as an access token (and the reverse) is rejected with 401.
- Malformed, expired or tampered JWT returns 401 with a JSON body, not a stack trace.
- A deactivated user (`is_active=false`) cannot log in or use an existing token.
- Logging in through the wrong role's endpoint (driver phone at `/auth/customer/login`) fails with 401 and does not reveal that the phone exists.
- Phone input with spaces or missing `+` is normalised or rejected with 422, never stored raw.
- Flutter: network offline or 401 on startup sends the user to the correct role's login rather than crashing.

---

### Task 1: Repo layout and Docker Compose stack

**Files:**
- Create: `docker-compose.yml`, `.env.example`, `.gitignore` (append backend/env entries), `docker/nginx.conf`, `backend/Dockerfile`, `backend/requirements.txt`, `backend/app/__init__.py`, `backend/app/main.py`
- Test: `backend/tests/test_health.py`

**Interfaces:**
- Produces: `app.main.app` (FastAPI instance); `GET /api/v1/health` returns `{"status": "ok"}`; compose services `db` (postgis/postgis:17-3.5), `redis` (redis:7-alpine, appendonly), `api` (uvicorn on 8000, `expose` only), `nginx` (80 -> api), all with healthchecks.

- [ ] **Step 1: Write the failing test** `test_health_returns_ok`: httpx `AsyncClient(transport=ASGITransport(app=app))` GET `/api/v1/health` asserts 200 and `{"status": "ok"}`.
- [ ] **Step 2: Run** `cd backend && python -m pytest tests/test_health.py -v`. Expected: FAIL (module missing).
- [ ] **Step 3: Implement** `main.py` with `app = FastAPI(title="Ride Freely")` and the health route; write `requirements.txt` with pinned versions (resolve current stable via `pip index versions`), `Dockerfile` (python:3.13-slim, non-root user), compose file, nginx proxy to `api:8000` with WebSocket upgrade headers, `.env.example` (DB_PASSWORD, SECRET_KEY, DATABASE_URL, REDIS_URL).
- [ ] **Step 4: Run** the test, expect PASS. Then `cp .env.example .env && docker compose up -d --build` and `curl localhost/api/v1/health` returns `{"status":"ok"}`; `docker compose ps` shows all services healthy.
- [ ] **Step 5: Commit** (`git init` first if needed): `feat: docker stack and health endpoint`.

### Task 2: Config, async DB session, Alembic, core models

**Files:**
- Create: `backend/app/core/config.py`, `backend/app/core/database.py`, `backend/app/models/{base,user,customer,driver}.py`, `backend/alembic.ini`, `backend/migrations/env.py`, first migration under `backend/migrations/versions/`
- Test: `backend/tests/conftest.py`, `backend/tests/test_models.py`

**Interfaces:**
- Produces: `Settings` (pydantic-settings; fields `database_url`, `redis_url`, `secret_key`, `access_token_minutes=30`, `refresh_token_days=7`); `get_session() -> AsyncIterator[AsyncSession]`; models `User(id, full_name, phone unique, email nullable, password_hash, role, is_active, created_at)`, `CustomerProfile(id, user_id unique FK, default_address nullable)`, `DriverProfile(id, user_id unique FK, licence_number, experience_years, hourly_rate Numeric(10,2), verification_status, availability_status, rating)`. Migration also runs `CREATE EXTENSION postgis` and `btree_gist`.
- `conftest.py` provides fixtures `client` (httpx AsyncClient) and a per-test clean DB (separate `ride_freely_test` database on the compose `db`, tables created via Alembic upgrade, truncated between tests).

- [ ] **Step 1: Write failing tests** in `test_models.py`: `test_user_phone_is_unique` (inserting two users with the same phone raises IntegrityError), `test_driver_profile_defaults` (new DriverProfile has `verification_status == "PENDING"` and `availability_status == "OFFLINE"`).
- [ ] **Step 2: Run** `pytest tests/test_models.py -v` (db must be up). Expected: FAIL.
- [ ] **Step 3: Implement** settings, engine/session factory, models with SQLAlchemy 2.0 `Mapped[]` style, `Enum` values as strings. Configure Alembic async `env.py` reading `Settings.database_url`; autogenerate the migration and hand-add the extensions.
- [ ] **Step 4: Run** `alembic upgrade head` then the tests. Expected: PASS. Verify `docker compose exec db psql -U app_user -d driver_booking -c "\dx"` lists postgis.
- [ ] **Step 5: Commit** `feat: settings, database session, alembic and user/profile models`.

### Task 3: Security primitives and role guard

**Files:**
- Create: `backend/app/core/security.py`, `backend/app/api/deps.py`
- Test: `backend/tests/test_security.py`

**Interfaces:**
- Produces: `hash_password(plain: str) -> str`, `verify_password(plain: str, hashed: str) -> bool`, `create_token(user_id: UUID, role: str, token_type: Literal["access","refresh"]) -> str`, `decode_token(token: str, expected_type: str) -> TokenPayload` (raises `InvalidTokenError`), FastAPI deps `get_current_user` (loads active user from access token) and `require_role(*roles: str)` returning a dependency yielding the `User` (403 on wrong role, 401 on bad token or inactive user).

- [ ] **Step 1: Write failing tests**: `test_password_roundtrip`, `test_hash_is_argon2` (starts with `$argon2id$`), `test_refresh_token_rejected_as_access`, `test_expired_token_rejected` (token created with past expiry), `test_tampered_token_rejected`.
- [ ] **Step 2: Run** and confirm FAIL.
- [ ] **Step 3: Implement** with pwdlib Argon2 hasher and PyJWT HS256; map decode errors to HTTP 401 `{"detail": "Invalid or expired token"}` in deps.
- [ ] **Step 4: Run** and confirm PASS.
- [ ] **Step 5: Commit** `feat: password hashing, jwt tokens and role dependency`.

### Task 4: Customer and driver auth endpoints

**Files:**
- Create: `backend/app/schemas/auth.py`, `backend/app/services/auth_service.py`, `backend/app/api/v1/auth.py`, `backend/app/api/v1/customers.py`, `backend/app/api/v1/drivers.py`; modify `backend/app/main.py` to include routers.
- Test: `backend/tests/test_auth.py`

**Interfaces:**
- Consumes: Task 2 models, Task 3 security.
- Produces endpoints:
  - `POST /api/v1/auth/customer/register` body `{full_name, phone, password, email?}` -> 201 `TokenPair`
  - `POST /api/v1/auth/driver/register` body adds `licence_number`, `experience_years`, `hourly_rate` -> 201 `TokenPair`
  - `POST /api/v1/auth/customer/login` and `/auth/driver/login` body `{phone, password}` -> `TokenPair`; wrong role or bad password -> identical 401
  - `POST /api/v1/auth/refresh` body `{refresh_token}` -> `TokenPair`
  - `GET /api/v1/customers/me` (role customer) and `GET /api/v1/drivers/me` (role driver, includes verification and availability status)
  - `TokenPair = {access_token, refresh_token, token_type: "bearer"}`
  - Phone validator normalises to `+91` E.164 style, strips spaces, rejects non-digit input (422). Password min 8 chars.

- [ ] **Step 1: Write failing tests**: `test_customer_register_login_me`, `test_driver_register_creates_pending_offline_profile`, `test_duplicate_phone_returns_409_across_roles`, `test_customer_token_forbidden_on_drivers_me` (403) and the reverse, `test_driver_phone_on_customer_login_returns_401`, `test_refresh_issues_new_pair`, `test_access_token_rejected_by_refresh_endpoint`, `test_inactive_user_cannot_login`, `test_phone_with_spaces_is_normalised`, `test_invalid_phone_returns_422`.
- [ ] **Step 2: Run** `pytest tests/test_auth.py -v`. Expected: FAIL.
- [ ] **Step 3: Implement** service functions `register_customer`, `register_driver`, `authenticate(phone, password, role)` (always runs a password verify to avoid timing leaks), routers under `/api/v1`. Registration creates user and profile in one transaction; catch unique violation -> 409.
- [ ] **Step 4: Run** the whole suite `pytest -v`. Expected: all PASS. Then via compose, `curl` a driver register and `/drivers/me` through Nginx to confirm the full stack.
- [ ] **Step 5: Commit** `feat: separate customer and driver auth endpoints`.

### Task 5: `ride_core` shared Flutter package

**Files:**
- Create: `packages/ride_core/pubspec.yaml`, `lib/ride_core.dart`, `lib/src/api/api_client.dart`, `lib/src/storage/token_storage.dart`, `lib/src/auth/{auth_repository,auth_controller}.dart`, `lib/src/models/token_pair.dart`, `lib/src/theme/app_theme.dart`, `lib/src/widgets/{app_text_field,primary_button}.dart`
- Test: `packages/ride_core/test/auth_repository_test.dart`

**Interfaces:**
- Produces: `ApiClient(baseUrl, TokenStorage)` wrapping Dio with an interceptor that attaches the bearer token and, on 401, tries one refresh then clears tokens; `TokenStorage {Future<void> save(TokenPair), Future<TokenPair?> read(), Future<void> clear()}` (flutter_secure_storage, with an in-memory implementation for tests); `AuthRepository(ApiClient, UserRole role)` with `register(...)`, `login(phone, password)`, `me()`, `logout()`; `UserRole {customer, driver}`; `AuthController` (GetX) exposing `status` (`unknown|authenticated|unauthenticated`), `isLoading`, `error`; `AppTheme.light(Color seed)`.

- [ ] **Step 1: Write failing tests** with a mocked Dio adapter: `login_saves_tokens_and_hits_role_endpoint` (customer role calls `/auth/customer/login`, driver calls `/auth/driver/login`), `login_failure_surfaces_server_detail`, `expired_access_token_triggers_single_refresh_then_retries`, `refresh_failure_clears_tokens`.
- [ ] **Step 2: Run** `cd packages/ride_core && flutter test`. Expected: FAIL.
- [ ] **Step 3: Implement** the above. Keep widgets generic (no role-specific copy) so both apps reuse them.
- [ ] **Step 4: Run** `flutter test` (PASS) and `flutter analyze` (no issues).
- [ ] **Step 5: Commit** `feat: ride_core shared package`.

### Task 6: Customer app skeleton

**Files:**
- Create via `flutter create --org com.ridefreely --project-name customer_app apps/customer_app` (platforms android, ios); modify `pubspec.yaml` (path dependency on `ride_core`, `get`); create `lib/main.dart`, `lib/routes.dart`, `lib/features/auth/{splash,login,register}_page.dart`, `lib/features/home/home_shell.dart` (bottom nav: Home, Bookings, Profile with placeholder bodies)
- Test: `apps/customer_app/test/auth_flow_test.dart`

**Interfaces:**
- Consumes: Task 5 `AuthRepository(role: UserRole.customer)`, `AuthController`, `AppTheme`.
- Produces: routes `/splash`, `/login`, `/register`, `/home`. Splash reads stored tokens, calls `me()`, routes to `/home` or `/login`. Visual identity: seed colour deep teal, copy aimed at "book a driver for your own car" (hourly / full day). Register form: name, phone, email (optional), password.

- [ ] **Step 1: Write failing widget tests**: `login_page_shows_validation_errors_on_empty_submit`, `successful_login_navigates_to_home_shell` (fake repository), `splash_without_token_goes_to_login`, `register_page_rejects_short_password`.
- [ ] **Step 2: Run** `flutter test`. Expected: FAIL.
- [ ] **Step 3: Implement** pages and routing; use `Get.put` bindings in `main.dart`; build UI to the theme, not default Material blue.
- [ ] **Step 4: Run** `flutter test` and `flutter analyze` (clean); run on a simulator/emulator against the local stack and register + log in as a customer.
- [ ] **Step 5: Commit** `feat: customer app skeleton with auth and home shell`.

### Task 7: Driver app skeleton

**Files:**
- Create via `flutter create --org com.ridefreely --project-name driver_app apps/driver_app`; same structure as Task 6 with `lib/features/home/home_shell.dart` (tabs: Dashboard, Requests, Earnings, Profile) and a Dashboard with an online/offline switch (UI only, local state, labelled as not yet connected) and a verification-status banner reading from `/drivers/me`.
- Test: `apps/driver_app/test/auth_flow_test.dart`

**Interfaces:**
- Consumes: Task 5 package with `UserRole.driver`. Register form adds licence number, years of experience, hourly rate (decimal, > 0). Distinct visual identity from the customer app (seed colour deep amber/orange) so the two are unmistakable.

- [ ] **Step 1: Write failing widget tests**: `driver_register_requires_licence_and_rate`, `successful_login_shows_dashboard`, `pending_driver_sees_verification_banner`, `splash_without_token_goes_to_login`.
- [ ] **Step 2: Run** `flutter test`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test`, `flutter analyze`; run on emulator, register a driver, see the "pending verification" banner; confirm a customer account cannot log in here (shows invalid credentials).
- [ ] **Step 5: Commit** `feat: driver app skeleton with auth and dashboard shell`.

### Task 8: Root cleanup and README

**Files:**
- Modify: `README.md` (setup, `docker compose up`, run each app, run tests); remove the untouched default Flutter template at the repo root (`lib/`, `test/`, `pubspec.yaml`, `pubspec.lock`, platform folders) only after the user confirms.

- [ ] **Step 1: Confirm with the user** that the root template can be removed (it is the unmodified `flutter create` counter app).
- [ ] **Step 2: Remove it, write the README, verify** that `docker compose up -d --build`, backend `pytest`, and both apps' `flutter test` all pass from a clean checkout.
- [ ] **Step 3: Commit** `docs: readme and remove default template`.

---

**Self-review notes:** Every Phase 1 item from the approved playback maps to a task (Docker: T1; schema/migrations: T2; JWT + role separation: T3-T4; Flutter skeletons with separate logins: T5-T7). Out of scope until Phase 2+: document upload, GPS, matching, bookings, admin dashboard, maps. Names are consistent across tasks (`require_role`, `TokenPair`, `UserRole`, `AuthRepository`).
