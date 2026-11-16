# Phase 5b: Simple Sign-up, Dynamic Driver Application, Full Admin Panel

## Intent

Today a driver must type licence number, experience and rate just to create an account, and the admin site is basic. The owner wants:

1. **Easy sign-up.** Email + password, or mobile number + password. Nothing else.
2. **A driver application after sign-up.** A new driver is shown a form (details + documents). Submitting it makes them a pending driver. Only after an admin verifies the documents does the driver become visible and bookable by customers.
3. **Form fields come from the server**, so the admin changes what is asked (add/remove/require a field or a document) without an app release.
4. **A complete admin panel** with an attractive, animated look, where every driver and user can be managed through their whole life, including seeing where drivers are (tracking).

## Goals

- Sign-up needs only a name, one of email or mobile, and a password, for both drivers and customers.
- Login accepts the email or the mobile number plus password.
- Driver application form is rendered by the app from a server-defined field list.
- Admin can edit the driver form (and optional customer profile form) from the panel.
- Driver lifecycle is explicit and visible: Signed up → Application submitted → Under review → Approved / Needs changes (rejected with reason, can resubmit) → Suspended / Reinstated. Deactivation of the account stays as built.
- Unverified drivers are never shown in nearby search and cannot go online (already true; must stay true).
- Admin panel: dashboard, review queue, drivers, users, bookings list, form builder, live map of drivers, animated attractive UI.

## Non-goals

- OTP / email verification / forgot password (PRD P2).
- Push notifications, Razorpay, pricing configuration, customer-side live tracking (later Phase 5 work).
- Admin roles/permissions, audit log (still excluded).
- Admin creating admins from the site (CLI only, unchanged).

## Anti-goals (failure even if it technically works)

- A driver becoming bookable before an admin approved the documents.
- Changing the form in the admin breaking existing drivers' stored answers or the app crashing on an unknown field type.
- Any user-supplied text rendered as HTML in the admin site.
- Existing accounts or bookings lost by the sign-up migration.

## Constraints

- Build on what exists: FastAPI + Postgres/PostGIS + Redis backend, Flutter apps, static HTML/CSS/JS admin site served by nginx at `/admin` with strict CSP (no framework, no build step; no inline scripts; external libraries only if self-hosted or allowed by the CSP, builder's call).
- Alembic migrations; existing data preserved.
- CLAUDE.md rules: minimal changes, tests for backend behaviour, verify in a real browser for the website.

## Decisions (the owner decided)

- Sign-up is email-or-mobile + password, both roles.
- Drivers fill an application form after first login, including document uploads.
- Admin verifies documents; only then the driver is shown to customers.
- Form fields are served by the backend.

## Calls made by the author (not yet agreed by the owner)

- Identifier: `users.phone` becomes optional; `users.email` becomes unique when present; at least one of the two is required. Login takes either in one field.
- No verification of the email/mobile in this phase (no OTP).
- Form definition: a table of fields per role (`driver`, `customer`) with key, label, type (text, number, date, choice, document), required flag, help text, choices, order, active flag. Driver answers are stored as JSON on the profile; documents stay in the documents table keyed by the field key (the fixed LICENCE / ID_PROOF / PHOTO enum becomes a string key). The three current document types plus licence number, experience and hourly rate are the seeded default form.
- Customer profile form exists in the builder but is optional and non-blocking; only the driver form gates bookability.
- A driver who edits answers after approval goes back to review (consistent with the existing re-review-on-document-change rule).
- Removing a field hides it (soft delete); old answers are kept.
- Live tracking in the admin = a map of online drivers' last known positions, refreshed by polling every few seconds, using the data already stored (Redis freshness + PostGIS). A trip-by-trip history is out of scope.
- Admin bookings page is read-only (list, filter, detail); no admin editing of bookings.
- Visual direction: dark, modern, gradient/glass look with animated background and smooth transitions, respecting `prefers-reduced-motion`.

## Further calls from the builder check (author's calls, owner to check)

- **Existing drivers:** every driver already Approved stays Approved and bookable after the migration. Their licence number, experience and rate are copied into the new answers JSON, and the three document types map to string keys 1:1. Nobody is sent back to review by the migration.
- **States:** "Suspended" is the existing suspension (driver stays logged in, sees the status, cannot go online, is hidden from search; reinstating returns them to Approved without re-review). "Deactivated" is the existing account switch (cannot log in at all). They stay two separate things. "Needs changes" means one or more documents or fields were rejected.
- **Review is per item:** admin approves or rejects each document, with a reason, and the driver is Approved only when all required documents are approved. On resubmit the driver sees only the flagged items and re-uploads/edits just those. Editing an approved driver's answers or documents sends them back to review (existing rule).
- **Sign-up migration:** existing users keep their phone. Email is lower-cased; if existing emails collide, the migration keeps the email on the oldest account and clears it on the rest, and reports which. Phone keeps the current +91 normalisation. Login treats input containing "@" as email, otherwise as a mobile number.
- **Customer form:** in scope as a small optional "complete your profile" screen in the customer app, rendered from the server form; answers are stored and shown on the admin user detail page. It never blocks booking.
- **Unknown field types in the app:** a non-required unknown field is skipped; a required unknown field makes the app show "update the app to continue" and blocks submit (the server also reports a form version so this is detectable).
- **Live map:** shows drivers whose last location update is within the existing 30 s freshness window and who are AVAILABLE, RESERVED, BOOKED or ON_TRIP; offline or stale drivers are not shown. The driver detail page shows "last seen" if known.
- **Clients:** one Flutter app with role selection (existing). Changed screens: sign-up, login, driver application and status, customer optional profile.

## Owner decision (2026-11-16)

- When the admin adds a required field or document after drivers are approved, approved drivers **stay bookable** and see a "please update your details" notice (the admin sees them flagged as needing an update). Approved by the owner, along with all calls above.

## Left to the builder

- Exact table and column names, API shapes, migration strategy.
- Map library and tile source for the admin map (must work under the CSP and without a paid key if possible).
- Field validation rules per type, file type/size limits (reuse existing).
- Breaking up work into tasks, test design, animation details.

## Review focus

- Unapproved, rejected, pending and suspended drivers never appear in customer search or can accept bookings.
- Sign-up with only email, only mobile, both, or neither; duplicates; case-insensitive email; login by either.
- Form changes: required field added after drivers applied; field removed; type unknown to an old app.
- Admin endpoints: 403 non-admin, 401 no token; form edits validated.
