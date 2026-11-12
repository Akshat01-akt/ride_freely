# Ride Freely: Architecture

Status: Draft v1 (2026-11-12). Companion to `prd.md`.

## 1. Overview

One Flutter app with two interfaces (Customer and Driver) talks to one FastAPI backend over REST and WebSockets. PostgreSQL with PostGIS holds permanent data and answers geographic queries. Redis holds short-lived state: live locations, reservation locks, request timeouts and job queues. Nginx fronts everything.

```
 Flutter app (customer + driver interfaces)   (Admin dashboard, later)
                  |                                  |
                  +-------- HTTPS / WSS -------------+
                      |
                    Nginx  (TLS, rate limit, WS upgrade)
                      |
                   FastAPI  --------- Celery worker / beat
                  /   |    \               |
        PostgreSQL  Redis   External:      Redis (broker)
        + PostGIS          FCM, Razorpay,
                           Maps, object storage
```

## 2. Repository layout

```
ride_freely/
  backend/            FastAPI service, Alembic migrations, tests
  lib/                Flutter app (one app, two interfaces)
    core/             API client, auth, role store, theme, shared widgets
    features/         customer/, driver/, auth/, role_select/
  android/ ios/ test/ Flutter platform folders and tests
  docker/             Nginx config
  docker-compose.yml
  docs/               prd.md, architecture.md, plans
```

## 3. Technology choices

| Concern | Choice | Reason |
|---------|--------|--------|
| Mobile | Flutter, GetX, Dio | One codebase per app; GetX for state and routing |
| Maps (dev) | OpenStreetMap via flutter_map | No billing during development; swap to Google Maps if needed |
| API | FastAPI, Pydantic v2 | Async, typed, auto docs |
| ORM / migrations | SQLAlchemy 2.0 async, Alembic | Standard, supports PostGIS via GeoAlchemy2 |
| Database | PostgreSQL 17 + PostGIS 3.5 | Spatial index, exclusion constraints |
| Cache / locks | Redis 7 | Atomic locks, TTL keys, pub/sub |
| Jobs | Celery + Redis | Request timeouts, notifications, scheduled tasks |
| Realtime | FastAPI WebSockets | Location and booking updates |
| Push | Firebase Cloud Messaging | Background notifications |
| Payments | Razorpay (test mode first) | Indian market |
| Proxy | Nginx | TLS, routing, rate limits |
| Packaging | Docker Compose | Same stack locally and on a VPS |

## 4. Backend structure

Feature modules with service and repository layers, not logic in route handlers.

```
backend/app/
  main.py
  core/          config, security (hashing, JWT), database, redis, exceptions
  models/        SQLAlchemy models
  schemas/       Pydantic request/response models
  api/v1/        routers: auth, customers, drivers, locations, bookings, payments, admin
  api/deps.py    get_current_user, require_role
  services/      auth, driver, location, matching, booking, payment, notification
  repositories/  driver, booking, location (data access)
  workers/       Celery tasks and schedule
  websockets/    connection manager and handlers
```

The four engines are separate service modules:

- **Location engine:** ingests driver GPS, keeps the latest position in Redis, writes history to PostgreSQL, answers nearby queries.
- **Matching engine:** filters eligible drivers, ranks them, and offers the booking in order.
- **Booking engine:** state machine, reservations, overlap protection, cancellations.
- **Payment engine:** pricing, Razorpay orders, verification, commission, earnings, refunds.

## 5. Authentication and authorization

- One `users` table with a `role` (`customer`, `driver`, `admin`). Phone is the unique login identifier.
- Role-specific endpoints (`/auth/customer/*`, `/auth/driver/*`) create the matching profile row and only authenticate users of that role.
- JWT claims: `sub`, `role`, `type` (`access` 30 min, `refresh` 7 days). The `type` claim stops a refresh token being used as an access token.
- `require_role(...)` dependency guards routes; inactive users are rejected on every request.
- WebSocket connections authenticate with the access token and check ownership of the booking being subscribed to.

## 6. Data model

Core tables (UUID keys, `TIMESTAMPTZ`, `NUMERIC(10,2)` for money):

| Table | Purpose |
|-------|---------|
| users | Credentials, role, active flag |
| customer_profiles | Customer details |
| driver_profiles | Licence, experience, hourly rate, verification_status, availability_status, rating |
| driver_documents | Document type, object-storage URL, review status |
| driver_locations | Latest position as `geography(Point,4326)` with GiST index |
| driver_availability | Scheduled working windows |
| bookings | Customer, driver, start/end, pickup, status, total amount |
| booking_status_history | Audit of every transition |
| payments, refunds | Gateway references and status |
| location_history | Trip track points |
| reviews | Rating and comment per booking |
| notifications, support_tickets | Messaging and complaints |

Driver enums: availability = OFFLINE, AVAILABLE, RESERVED, BOOKED, ON_TRIP, SUSPENDED; verification = PENDING, APPROVED, REJECTED (kept separate from availability).

Documents are stored in S3-compatible object storage, never in PostgreSQL. Completed bookings and payments are retained and anonymised rather than deleted.

## 7. Nearby driver search

PostGIS does the distance work, not Python.

1. Driver app sends position (lat, lng, heading, speed, accuracy, timestamp). Latest value is written to Redis (`driver:location:{id}`, short TTL) and persisted to `driver_locations`.
2. Search uses `ST_DWithin(location, point, radius)` on the GiST index, ordered by `ST_Distance`. Note `ST_MakePoint(lng, lat)`: longitude first.
3. Filters: verified, availability AVAILABLE, location fresher than 30 s, service area covers pickup, no overlapping booking, within the customer's budget if set.
4. Straight-line distance shortlists; a routing API gives realistic ETA for the shortlist once added (after the MVP).

Update cadence (tunable): available every 10-15 s, accepted booking every 5-10 s, on trip every 3-5 s, offline none. Mobile background location must use platform background services, not a Dart timer.

## 8. Matching and booking flow

```
Customer requests booking
  -> backend creates booking SEARCHING
  -> PostGIS shortlist of eligible drivers, ranked
  -> for the next driver:
       acquire Redis lock driver:lock:{id} (unique token, TTL ~30 s)
       booking REQUESTED, push + WebSocket to driver, 20 s timeout (Celery)
       accept  -> PostgreSQL transaction validates and sets CONFIRMED, lock released
       reject / timeout -> release lock, try next driver
  -> none left -> EXPIRED, customer notified
```

Booking state machine: SEARCHING, REQUESTED, ACCEPTED, CONFIRMED, DRIVER_ARRIVING, ARRIVED, IN_PROGRESS, COMPLETED, plus terminal CANCELLED, EXPIRED, REJECTED. Transitions are validated in one place and written to `booking_status_history`.

### Double-booking protection (layered)
1. Redis lock with a unique token and Lua compare-and-delete release (short-lived reservation only).
2. PostgreSQL transaction for the final confirmation (source of truth).
3. Exclusion constraint on `bookings`: `EXCLUDE USING GIST (driver_id WITH =, tstzrange(start_time, end_time, '[)') WITH &&) WHERE status IN ('CONFIRMED','DRIVER_ARRIVING','ARRIVED','IN_PROGRESS')`. Requires the `btree_gist` extension.
4. Idempotency keys on create-booking requests.

## 9. Redis usage

| Key / feature | Use |
|---------------|-----|
| driver:location:{id} | Latest position, TTL for freshness |
| driver:lock:{id} | Reservation lock |
| booking:request:{id} | Request timeout state |
| booking:active:{id} | Active booking cache |
| pub/sub channels | Fan-out of WebSocket events across API workers |
| Celery broker | Background jobs |

Redis is never the source of truth for bookings or payments.

## 10. Real-time

| WebSocket | Purpose |
|-----------|---------|
| /ws/driver/location | Driver GPS uploads |
| /ws/driver/requests | Incoming booking requests |
| /ws/bookings/{id} | Booking status updates (customer and driver) |
| /ws/customer/tracking/{id} | Assigned driver's live position |

FCM push covers the background case. On reconnect, apps fetch current booking state over REST before resubscribing.

## 11. Payments

Server calculates price; the client never sends an amount. Flow: create booking, backend prices it, backend creates a Razorpay order, Flutter opens checkout, backend verifies the signature, webhook updates status idempotently, commission and driver earnings are recorded. Payment timing (upfront, on acceptance, or at completion) is an open product decision (see PRD).

## 12. Flutter architecture

A single app serves both roles. On first launch the user picks "I need a driver" or "I'm a driver"; the choice is stored (`RoleStore`) and the app then shows that interface's own login, registration and home screens. "Switch account type" on the login screen clears it.

- Each interface has its own session: a separate `ApiClient` and token storage namespace per role, and an `AuthController` registered in GetX under the role's name (`authFor(role)`). A customer login and a driver login never share tokens.
- Each interface has its own look from the shared palette: customer is cream-led (light theme), driver is dark-grey-led (dark theme), applied per route by `RoleTheme`.
- `lib/core`: `ApiClient` (Dio; attaches the bearer token, one refresh on 401, clears tokens if refresh fails), `TokenStorage` (`flutter_secure_storage`), `AuthRepository` and `AuthController` parameterised by `UserRole`, `AppTheme`, shared widgets.
- `lib/features/<role>`: pages and controllers per interface. Controllers handle presentation and API calls only; all matching and availability rules live in the backend.
- The backend, not the app, enforces role separation: a customer token cannot call driver endpoints.

## 13. Deployment

Local and initial hosting both use Docker Compose: `db`, `redis`, `api`, `worker`, `beat`, `nginx`. PostgreSQL and Redis are not exposed publicly (db is bound to 127.0.0.1 for local tooling only). Production adds TLS, secrets management, volume backups, health checks, resource limits, controlled migrations (`alembic upgrade head` as a deploy step), CI via GitHub Actions, and Sentry for error tracking.

## 14. Testing strategy

- Backend: pytest with httpx against a real PostGIS test database; concurrency tests for double booking; webhook idempotency tests.
- Flutter: unit tests for `ride_core`, widget tests for each app's auth flow, `integration_test` for end-to-end journeys later.
- Load: Locust or k6 on nearby search and booking creation.

## 15. Security and privacy summary

Argon2id hashing, short-lived access tokens, role checks on every route and WebSocket, rate limiting at Nginx, server-side payment verification, least-privilege database user, no public DB or Redis ports, consent for location collection, coarse location during discovery and exact location only within an active booking, and a GPS history retention policy.

## 16. Decisions recorded

- One backend, one Flutter app with two role-based interfaces (decided by the product owner; earlier drafts had two apps).
- PostGIS for spatial queries; Redis only for ephemeral state.
- OpenStreetMap for development; Google Maps/Routes considered once ETA accuracy matters.
- GetX chosen for familiarity; revisit if the apps grow complex.
- Admin dashboard is deferred; drivers are approved through the API first.
