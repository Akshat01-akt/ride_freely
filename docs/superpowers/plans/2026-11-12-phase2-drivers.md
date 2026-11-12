# Phase 2: Driver Onboarding, Availability, GPS and Nearby Search

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline, as chosen for Phase 1). Steps use checkbox syntax.

**Goal:** A driver can upload documents, an admin can approve them, an approved driver can go online and stream GPS, and a customer can fetch nearby available drivers. The Flutter apps use all of it with real data.

**Architecture:** Same FastAPI service. Documents are stored through a small `FileStorage` abstraction (local volume now, S3 later). Live location lives in Redis with a 30 s TTL (freshness) and in a PostGIS `driver_locations` row (spatial query). Nearby search = PostGIS `ST_DWithin` candidates, then drop any whose Redis key expired.

**Tech Stack:** as Phase 1, plus GeoAlchemy2 `Geography`, redis.asyncio, `geolocator` and `image_picker` in Flutter.

**Spec:** `docs/prd.md` (7.2, 7.3), `docs/architecture.md` (7, 9). Decisions made here, not by the product owner: admin accounts are created by a CLI (no admin UI yet); approval needs an approved LICENCE and ID_PROOF document; only OFFLINE and AVAILABLE can be toggled by the driver; foreground GPS only (background location is a later task).

## Global Constraints

- Location freshness: 30 seconds (Redis TTL). Search radius default 5000 m, maximum 20000 m.
- Upload limit 5 MB; types image/jpeg, image/png, application/pdf; document types LICENCE, ID_PROOF, PHOTO.
- Customers never receive a driver's exact coordinates, only `distance_meters`.
- Redis host port 127.0.0.1:6380 (6379 may be taken); uploads volume mounted at `/srv/uploads`.
- All new endpoints under `/api/v1`; admin endpoints require role `admin`.

## Review Focus

- A non-approved or suspended driver cannot go AVAILABLE or send location; an AVAILABLE driver whose Redis key expired never appears in search.
- A driver in RESERVED/BOOKED/ON_TRIP cannot be toggled OFFLINE by the availability endpoint.
- Latitude/longitude out of range, NaN, or missing fields return 422; a customer or admin token cannot post locations.
- Upload of wrong type, oversize file or a path-traversal filename is rejected and never written outside the uploads dir; one driver cannot read another's documents; only admin can download a file.
- Re-uploading a document resets it to PENDING and invalidates a previous approval.
- Rejecting a driver or suspending takes them offline and removes their location.
- Search with radius 0, negative or huge values returns 422; a driver at exactly the radius edge is included.
- Flutter: location permission denied/off shows a clear message and no crash; going online fails cleanly if the API rejects it (switch returns to off).

---

### Task 1: Redis in compose, location models and migration
**Files:** `docker-compose.yml` (publish redis 127.0.0.1:6380, uploads volume), `backend/app/core/redis.py`, `backend/app/models/location.py`, `backend/app/models/document.py`, migration `0002`, `backend/tests/conftest.py` (redis fixture, truncate new tables).
**Interfaces:** `get_redis() -> Redis`; `DriverLocation(driver_id PK/FK driver_profiles.id, location Geography(POINT,4326), heading, speed, accuracy, recorded_at)`; `DriverDocument(id, driver_id FK, doc_type, file_key, content_type, size_bytes, status, review_note, created_at, updated_at)` with unique (driver_id, doc_type).
- [ ] Test: tables exist and `driver_locations` has a GiST index; unique (driver, doc_type) enforced. RED then GREEN.

### Task 2: Admin role, CLI and admin login
**Files:** `backend/app/cli.py`, `backend/app/api/v1/auth.py` (add `/auth/admin/login`).
**Interfaces:** `python -m app.cli create-admin --phone P --name N` (password via prompt or `ADMIN_PASSWORD` env); `POST /auth/admin/login`.
- [ ] Tests: admin login ok; customer/driver credentials rejected there; admin token rejected on customer/driver routes.

### Task 3: Document upload and listing (driver)
**Files:** `backend/app/services/storage.py` (`FileStorage` protocol, `LocalFileStorage`), `backend/app/services/document_service.py`, `backend/app/api/v1/drivers.py` (`POST /drivers/documents`, `GET /drivers/documents`).
**Interfaces:** multipart fields `doc_type`, `file`; response `{id, doc_type, status, review_note}`. Storage key is a server-generated UUID path, never the client filename.
- [ ] Tests: valid upload; wrong type 415/422; >5 MB 413; traversal filename safe; re-upload replaces and resets to PENDING; driver sees only own; customer token 403.

### Task 4: Admin review
**Files:** `backend/app/api/v1/admin.py`, `backend/app/services/review_service.py`.
**Interfaces:** `GET /admin/drivers/pending`; `GET /admin/documents/{id}/file`; `PATCH /admin/documents/{id}` `{status: APPROVED|REJECTED, note?}`; `PATCH /admin/drivers/{id}/verification` `{status: APPROVED|REJECTED, note?}` (APPROVED requires LICENCE and ID_PROOF approved, else 409). REJECTED/suspension forces OFFLINE and clears location.
- [ ] Tests: pending list, approve flow, approve-without-docs 409, non-admin 403, file download admin only, reject takes an AVAILABLE driver offline.

### Task 5: Availability endpoint
**Interfaces:** `PATCH /drivers/availability` `{status: AVAILABLE|OFFLINE}` -> driver profile. 403 if not APPROVED, 409 if currently RESERVED/BOOKED/ON_TRIP/SUSPENDED. OFFLINE deletes the Redis location key.
- [ ] Tests for each rule above.

### Task 6: Location update
**Files:** `backend/app/services/location_service.py`, `backend/app/api/v1/locations.py`.
**Interfaces:** `POST /locations/update` `{latitude -90..90, longitude -180..180, heading 0..360?, speed >=0?, accuracy >=0?}` driver-only, status must be AVAILABLE; writes Redis `driver:location:{profile_id}` (TTL 30 s) and upserts `driver_locations`; 204.
- [ ] Tests: ok; OFFLINE/unapproved 409/403; range and NaN 422; customer 403; TTL set (<=30).

### Task 7: Nearby search
**Interfaces:** `GET /drivers/nearby?latitude&longitude&radius=5000` customer-only -> `{drivers: [{id, name, hourly_rate, rating, experience_years, verified, distance_meters}]}` sorted ascending. Filters: APPROVED, AVAILABLE, Redis key present, within radius (inclusive).
- [ ] Tests: ordering, radius edge, expired key excluded, offline/unapproved/suspended excluded, radius 0/-1/999999 422, driver token 403, no exact coordinates in the payload.

### Task 8: Flutter location + driver wiring
**Files:** `pubspec.yaml` (geolocator, image_picker), Android/iOS permission entries, `lib/core/location/location_service.dart` (`LocationService` interface + `GeolocatorLocationService`), `lib/features/driver/availability_controller.dart`, driver dashboard switch wired to `PATCH /drivers/availability` and a 10 s foreground location timer while online.
- [ ] Tests (fake `LocationService` and fake API): going online calls the API then starts updates; API rejection returns the switch to off with the message; permission denied shows a message and stays offline; going offline stops updates.

### Task 9: Flutter documents screen
**Files:** `lib/features/driver/documents_page.dart`, `lib/features/driver/documents_controller.dart`.
- [ ] Tests: lists the three types with status from the API; picking a file uploads and refreshes; upload error shown; dashboard banner links to it.

### Task 10: Flutter customer nearby wiring
**Files:** `lib/features/customer/data/sources.dart` (`BackendDriversSource` calls `/drivers/nearby` with the device location), home/drivers screens ask for location.
- [ ] Tests: source maps the API payload to `DriverSummary`; denied permission shows an actionable empty state; real list replaces the empty state.

### Task 11: Whole-branch review and fixes
- [ ] Fresh reviewer over the diff; fix Critical/Important with tests first.
