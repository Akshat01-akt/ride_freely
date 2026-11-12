# Phase 3: Booking Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (inline, as chosen in Phase 1). Steps use checkbox syntax.

**Goal:** A customer can request a verified driver for an hourly or full-day slot, the driver can accept or reject, the trip can be started and completed, and no driver can ever be double-booked. The Flutter apps use it with real data.

**Architecture:** One `bookings` table. Double-booking is prevented by the database: a PostgreSQL exclusion constraint on `(driver_id, tstzrange(start_time, end_time))` for the active states (REQUESTED, ACCEPTED, IN_PROGRESS). State changes lock the booking row (`SELECT ... FOR UPDATE`). Unanswered requests expire lazily (checked on every read/write touching the driver), so no scheduler is needed yet.

**Tech Stack:** as Phase 2 (FastAPI, SQLAlchemy async, Alembic, btree_gist already installed); Flutter GetX + Dio.

**Spec:** `docs/prd.md` (7.4 booking), `docs/architecture.md` (8 booking state machine, double booking).

**Decisions made here, not by the product owner (rulings):**
- States: REQUESTED → ACCEPTED → IN_PROGRESS → COMPLETED; REQUESTED → REJECTED / EXPIRED; REQUESTED or ACCEPTED → CANCELLED (customer only). No other transitions.
- Price = billed hours x driver `hourly_rate`, fixed at request time, returned as a string. FULL_DAY = 8 billed hours, window 8 hours. HOURLY = 1 to 12 hours. Payments are a later phase; nothing is charged.
- A REQUESTED booking holds the slot and expires 10 minutes after creation if the driver does not answer.
- A customer may have at most 3 active bookings (stops one customer blocking many slots).
- Start within 15 minutes of now ("book now"): driver must be AVAILABLE. Later start (up to 30 days): driver must only be APPROVED and not SUSPENDED.
- Driver status follows the trip: start sets ON_TRIP, complete sets AVAILABLE. A driver may start only from 15 minutes before `start_time`, and only while not SUSPENDED.
- The other party's phone number is shown only while a booking is ACCEPTED or IN_PROGRESS.
- Someone else's booking id returns 404, never 403.
- Nearby search hides drivers who have an active booking overlapping now.
- No Redis lock: the exclusion constraint is the single source of truth.

## Global Constraints

- All endpoints under `/api/v1`; customer endpoints need role customer, driver endpoints role driver.
- Money is a string with 2 decimals. Timestamps are timezone-aware UTC ISO strings; naive input is a 422.
- Validation errors never echo input (existing handler).

## Review Focus

- Two customers request the same driver for overlapping slots at the same time: exactly one succeeds, the other gets 409.
- Back-to-back slots (one ends at 10:00, next starts at 10:00) are both allowed.
- Driver double-accepts, or customer cancels while driver accepts: exactly one transition wins, the final state is consistent.
- An expired request cannot be accepted and its slot becomes free again.
- Another customer or driver cannot read, cancel, accept or complete a booking they are not part of.
- A suspended or unapproved driver cannot be booked; start time in the past, over 30 days ahead, naive, or hours 0 / 13 return 422.

---

### Task 1: Booking model and migration
**Files:** `backend/app/models/booking.py`, `backend/app/models/__init__.py`, `backend/migrations/versions/0003_bookings.py`, `backend/tests/conftest.py` (truncate `bookings`), `backend/tests/test_booking_model.py`.
**Produces:** `Booking(id, customer_id FK customer_profiles, driver_id FK driver_profiles, booking_type, start_time, end_time, hours, pickup_address, notes, price_amount, status, expires_at, created_at, updated_at)`; enums `BookingStatus`, `BookingType`; `ACTIVE_STATES`.
- [ ] Test: overlapping active bookings for one driver raise IntegrityError; touching slots (end == start) are allowed; an overlapping CANCELLED/REJECTED/EXPIRED/COMPLETED one does not block. RED then GREEN.

### Task 2: Booking service (create, list, get)
**Files:** `backend/app/services/booking_service.py`, `backend/tests/test_booking_create.py`.
**Interfaces:** `create_booking(session, customer_id, driver_id, booking_type, start_time, hours, pickup_address, notes) -> Booking`; `expire_stale(session, driver_id=None)`; exceptions `DriverUnavailable`, `SlotTaken`, `TooManyBookings`.
- [ ] Tests: price math, FULL_DAY 8 h, rules above, 4th active booking refused, expired request frees slot, concurrent requests: one wins.

### Task 3: API for customers
**Files:** `backend/app/api/v1/bookings.py`, `backend/app/schemas/booking.py`, `backend/app/main.py`.
**Interfaces:** `POST /bookings` (201), `GET /bookings` (caller's own, newest first, both roles), `GET /bookings/{id}`, `POST /bookings/{id}/cancel`. Body: `{driver_id, booking_type, start_time?, hours?, pickup_address, notes?}`. Response: `{id, status, booking_type, start_time, end_time, hours, price_amount, pickup_address, notes, expires_at, driver:{id,name,phone?}, customer:{name,phone?}}`.
- [ ] Tests: create/list/get/cancel, 404 for others, validation (past, >30 days, naive, hours 0/13, blank address), driver token 403 on create, phone visibility.

### Task 4: Driver actions
**Interfaces:** `POST /bookings/{id}/accept|reject|start|complete` (driver of that booking only).
- [ ] Tests: each transition and every illegal one returns 409; start before the 15-minute window 409; start sets ON_TRIP, complete sets AVAILABLE; double accept races; suspended driver cannot start; expired cannot be accepted.

### Task 5: Nearby hides busy drivers, docs
**Files:** `backend/app/services/location_service.py`, `docs/architecture.md`, `README.md`.
- [ ] Test: a driver with an ACCEPTED booking overlapping now is absent from `/drivers/nearby`; with a future booking is present.

### Task 6: Flutter data layer
**Files:** `lib/features/customer/data/{models,sources}.dart` (booking model, `BookingsApi`), `lib/features/driver/data/driver_api.dart` additions, controllers `BookingsController` (customer) and `RequestsController` (driver).
- [ ] Tests with the fake adapter: request payload, mapping, error messages for 409/422, accept/reject/start/complete calls.

### Task 7: Flutter screens
**Files:** driver details "Confirm booking" (real request, hours picker, address), customer Bookings tab (real list, cancel), driver Requests tab (list, accept/reject, start/complete), booking confirmed page fed by the real booking.
- [ ] Widget tests per screen: loading, empty, error, success; no fake data.

### Task 8: Whole-branch review and fixes
- [ ] Fresh reviewer over the diff; fix Critical/Important with tests first.
