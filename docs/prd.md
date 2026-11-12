# Ride Freely: Product Requirements Document

Status: Draft v1 (2026-11-12). Source: project brief and the scope agreed in chat.

## 1. Summary

Ride Freely is an on-demand driver rental marketplace. Customers who own a car but don't want to drive it book a verified driver, by the hour or for a full day. The driver comes to the customer and drives the customer's own vehicle.

This is not a cab service. The customer books a person, not a vehicle.

## 2. Problem and opportunity

Car owners often need someone else to drive: after a late event, for a long day of meetings, on a family trip, or when they're unwell or tired. Today they rely on personal contacts or agencies, with no price transparency, no real-time availability and no way to check a driver's background.

Drivers in the same cities lack a steady, fairly priced source of short engagements.

## 3. Goals

- G1. A customer can find and book an available, verified driver in a few minutes.
- G2. A driver can register, get verified, go online and receive booking requests.
- G3. Two customers can never hold the same driver for overlapping time.
- G4. Both parties can see booking state and, during a booking, the driver's live location.
- G5. Customers pay online and drivers' earnings are recorded.

## 4. Non-goals (initial release)

- Ride-hailing or cab fleet operations (the platform provides no vehicles).
- Multi-city expansion and dynamic/surge pricing.
- Driver subscription plans, incentives, demand forecasting.
- Automated GPS-spoofing and fraud detection.
- Insurance products.

## 5. Users and roles

| Role | Who | Primary need |
|------|-----|--------------|
| Customer | Car owner who wants to be driven | Quickly book a trustworthy driver for a set duration |
| Driver | Professional driver | Steady bookings, clear earnings, simple app |
| Admin | Platform operator | Verify drivers, resolve disputes, monitor bookings and payments |

Customers and drivers use **one app with two separate interfaces and separate logins**; the user picks their role on first launch. The backend enforces role separation: a customer credential cannot act as a driver and vice versa.

## 6. Key user journeys

**Customer:** register, log in, grant location, choose pickup, choose date, start time and duration (2h, 3h, 4h, full day), see nearby drivers, pick one or ask the system to find one, driver accepts, track arrival, trip starts, trip ends, pay, rate.

**Driver:** register with licence and ID details, upload documents, wait for admin approval, go online, receive request, accept or reject within the time limit, navigate to pickup, start and complete the booking, view earnings.

**Admin:** review pending drivers and documents, approve or reject, suspend accounts, view bookings and complaints, handle refunds.

## 7. Functional requirements

Priority: **P1** = MVP, **P2** = commercial release, **P3** = later.

### 7.1 Accounts and authentication
- P1: Separate customer and driver registration and login (phone + password).
- P1: JWT access and refresh tokens; role-based authorization.
- P2: OTP verification, forgot password.

### 7.2 Driver onboarding and verification
- P1: Driver profile: name, phone, licence number, experience, hourly rate.
- P1: Document upload (licence, ID, photo) and admin approval. Unverified drivers are never bookable.
- P1: Verification status tracked separately from availability.

### 7.3 Availability and location
- P1: Driver states: OFFLINE, AVAILABLE, RESERVED, BOOKED, ON_TRIP, SUSPENDED.
- P1: Driver GPS updates while online; stale locations (older than 30 s) excluded from search.
- P1: Nearby driver search within 5 km, expandable to 10 km.
- P2: Live driver tracking for the customer during a booking.

### 7.4 Booking
- P1: Instant booking; driver accept/reject with a 20 s response window; timeout moves to the next driver.
- P1: Booking lifecycle: SEARCHING, REQUESTED, ACCEPTED, CONFIRMED, DRIVER_ARRIVING, ARRIVED, IN_PROGRESS, COMPLETED, CANCELLED, EXPIRED, REJECTED. Every transition is audited.
- P1: No double booking: overlapping confirmed bookings for one driver are rejected.
- P2: Scheduled (future) bookings; customer-selected driver and automatic matching.
- P3: Automatic reassignment after driver cancellation.

### 7.5 Pricing and payments
- P2: Server-calculated price: base fee + hourly rate x hours + extras + taxes - discounts. Minimum duration, extra-hour, waiting, late-night and cancellation charges are configurable.
- P2: Razorpay payments with server-side signature verification and idempotent webhooks.
- P2: Platform commission and driver earnings recorded per booking; refunds tracked.

### 7.6 Reviews, support, notifications
- P2: Customer rating and comment per completed booking.
- P2: Cancellation, complaint and help tickets.
- P2: Push notifications for booking events; in-app notification list.

### 7.7 Admin
- P1: Pending-driver list, approve/reject (API first, web dashboard later).
- P2: Web dashboard: bookings, payments, complaints, pricing and commission configuration, reports.

## 8. Non-functional requirements

- **Security:** Argon2id password hashing; no secrets in the repo; rate limiting at Nginx; input validation on every endpoint.
- **Privacy:** a driver's exact location is visible only during discovery (coarse) and an active booking (exact). GPS history has a defined retention period. Explicit consent and background-location explanations in both apps.
- **Concurrency:** Redis reservation lock plus PostgreSQL transaction and exclusion constraint; PostgreSQL is the source of truth.
- **Reliability:** apps recover from network loss and resynchronise booking state on reconnect.
- **Performance targets (starting values):** nearby search p95 under 500 ms at 1,000 online drivers; booking request delivered to driver in under 2 s.
- **Compliance:** review Indian data-protection, transport and employment rules, and GST treatment, before public launch.
- **Cost:** development is free-tier only (local Docker, test-mode payments, OpenStreetMap); paid services are enabled only at pilot launch.

## 9. Success metrics

- Booking completion rate (requests that end COMPLETED).
- Median time from request to driver acceptance.
- Driver acceptance rate and request-timeout rate.
- Double-booking incidents (target: 0).
- Average rating; complaint rate per 100 bookings.
- Weekly active drivers online during peak hours.

## 10. Release phases

| Phase | Scope |
|-------|-------|
| 1 | Backend foundation, separate customer/driver auth, Flutter app skeletons |
| 2 | Driver profile, documents, admin approval, online/offline, GPS updates |
| 3 | Nearby search, matching, booking engine, accept/reject |
| 4 | Full customer and driver app flows against the backend |
| 5 | Live tracking, push notifications, pricing, Razorpay, admin dashboard |

## 11. Open questions

- Payment timing: authorise at booking, charge at acceptance, or capture at completion?
- Cancellation fee schedule and driver no-show penalties.
- Commission rate and settlement frequency for drivers.
- Does the driver need to be verified through a third-party licence check, or admin review only?
- Target launch city and operating hours.
- Safety features required at launch (SOS button, trip sharing).
