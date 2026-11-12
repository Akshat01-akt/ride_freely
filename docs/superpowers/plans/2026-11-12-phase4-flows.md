# Phase 4: Complete the App Flows Against the Backend

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (inline, as chosen in Phase 1). Steps use checkbox syntax.

**Goal:** Close the gaps that still make the apps feel unfinished, using real data only: customers rate a completed trip, drivers see real earnings, and the Requests and Bookings lists stay fresh without a manual refresh.

**Architecture:** Same FastAPI service and Flutter app. One migration adds `rating`, `rated_at` and `completed_at` to `bookings`. A driver's `rating` becomes the average of their rated trips. Earnings are sums over completed bookings, computed on request. The app polls the booking list while the Requests or Bookings tab is on screen.

**Spec:** `docs/prd.md` section 10 (Phase 4), `docs/superpowers/plans/2026-11-12-phase3-bookings.md` (known gaps).

**Rulings (decided here, not by the product owner):**
- Only the booking's customer can rate, only when COMPLETED, 1 to 5 stars, once. A second attempt is 409. Someone else's booking is 404.
- Driver rating = average of rated completed trips, two decimals, recalculated while the driver row is locked. Unrated drivers stay 0.00 (the apps already treat that as "no rating yet").
- Earnings count COMPLETED bookings by `completed_at` and add up `price_amount`. It is the booking total, not a payout: commission and payments are Phase 5. Periods use India time (Asia/Kolkata): today since midnight, week since Monday, month since the 1st.
- Polling: every 30 seconds, only while the tab is visible and the app is in the foreground. No server push yet.
- Not in this phase (need product decisions or heavy infrastructure): payments and wallet, live tracking, push notifications, admin dashboard, auto-completing forgotten trips.

## Global Constraints

- Endpoints under `/api/v1`. Money is a string with 2 decimals. Timestamps are timezone-aware.
- Real data only outside `UI_PREVIEW`; empty states say so honestly.

## Review Focus

- A customer cannot rate someone else's booking, a non-completed booking, or rate twice (including two simultaneous requests).
- Rating bounds 0, 6, non-integers and missing values are 422.
- The driver average is right after several ratings and never counts unrated trips.
- Earnings with no trips are zeros, not an error; a trip completed just before midnight IST lands on the right day.
- Polling stops when the tab is left or the app is closed, and never overwrites a list while an action is running.

---

### Task 1: Rating (backend)
**Files:** `backend/app/models/booking.py`, `backend/migrations/versions/0004_ratings.py`, `backend/app/services/booking_service.py`, `backend/app/api/v1/bookings.py`, `backend/app/schemas/booking.py`, `backend/tests/test_booking_rating.py`.
**Interfaces:** `POST /bookings/{id}/rating` body `{rating: 1..5}` (customer) returns the booking with `rating`; `complete` sets `completed_at`.
- [ ] Tests for every rule above, RED then GREEN.

### Task 2: Earnings (backend)
**Files:** `backend/app/services/earnings_service.py`, `backend/app/api/v1/drivers.py`, `backend/tests/test_earnings.py`.
**Interfaces:** `GET /drivers/earnings` returns `{today, week, month, total}` each `{trips: int, amount: "0.00"}`.
- [ ] Tests: zeros, sums, period boundaries in IST, other drivers excluded, customer token 403.

### Task 3: Rate a trip (Flutter)
**Files:** `lib/features/bookings/*` (model `rating`, `BookingsApi.rate`, controller `rate`), `booking_cards.dart`.
- [ ] Tests: completed unrated trip offers "Rate this trip", stars dialog sends the rating, rated trip shows its stars, errors shown.

### Task 4: Earnings (Flutter)
**Files:** `lib/features/driver/data/driver_api.dart`, `earnings_controller.dart`, `earnings_tab.dart`, `driver_home_shell.dart`.
- [ ] Tests: zeros shown honestly, real totals, load error with retry, reload on tab open.

### Task 5: Fresh lists
**Files:** `lib/features/bookings/bookings_controller.dart`, tabs.
- [ ] Tests: polling reloads on an interval while the tab is open, stops when it is left, skipped while an action runs.

### Task 6: Whole-phase review and fixes
- [ ] Fresh reviewer over the diff; fix Critical/Important with tests first.
