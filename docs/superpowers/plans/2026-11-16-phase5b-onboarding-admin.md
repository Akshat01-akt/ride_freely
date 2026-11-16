# Phase 5b: Simple Sign-up, Dynamic Driver Application, Full Admin Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Anyone signs up with email-or-mobile + password; drivers then fill a server-defined application (details + documents) that an admin reviews before the driver is bookable; the admin panel manages the whole driver/user lifecycle, edits the forms, shows live driver positions, and looks polished and animated.

**Architecture:** Backend gains a `form_fields` table (per role), a `driver_answers` table (one row per field, with per-item review status, mirroring `driver_documents`), and a `NOT_SUBMITTED` verification state. Flutter apps render forms from `GET /forms/{role}`. The admin site stays static HTML/CSS/ES modules behind nginx at `/admin` and grows new pages.

**Tech Stack:** FastAPI, SQLAlchemy async, Alembic, Postgres/PostGIS, Redis, pytest; Flutter + GetX; vanilla JS admin site; nginx.

**Spec:** `docs/superpowers/specs/2026-11-16-phase5b-onboarding-admin-design.md`

## Global Constraints

- Build on the existing stack; no admin-site framework or build step; no inline scripts; admin CSP stays strict (any new external host, e.g. map tiles, is added to the nginx CSP explicitly and minimally).
- All admin endpoints under `/api/v1/admin/*`: 401 without a token, 403 for non-admin.
- Server text is rendered in the admin site with `textContent` only.
- Existing data preserved: already-APPROVED drivers stay APPROVED and bookable after migration; migrations have working downgrades.
- Unapproved, rejected, pending, not-submitted and suspended drivers never appear in `/drivers/nearby` and cannot go online or accept bookings.
- Registration needs only `full_name`, one of `email`/`phone`, and `password` for both roles; no OTP.
- Core driver fields `licence_number`, `experience_years`, `hourly_rate` map onto `driver_profiles` columns (pricing and search need them): they cannot be deleted, deactivated, retyped or made optional from the builder; only their label, help text and position can change. *(Author's call.)*
- Admin map shows drivers fresh within the existing 30 s window with status AVAILABLE, RESERVED, BOOKED or ON_TRIP.
- Animations respect `prefers-reduced-motion`.
- Commits follow the repo's `feat:/fix:` style; backend tests run with `cd backend && pytest -q`; Flutter with `flutter analyze && flutter test`.

## Review Focus

- Sign-up with email only, phone only, both, neither (422); duplicate email differing only in case → 409; login by email with different casing works. (Task 1)
- Admin adds a required field after drivers are approved: approved drivers stay bookable, `GET /drivers/me` lists them in `needs_update`. (Task 3)
- Admin deletes (deactivates) a field that has stored answers: answers kept, driver detail still shows them. (Task 2)
- Driver submits with a missing required field, an unknown key, a wrong type, or a document key not in the form: 422 naming the field. (Task 3)
- Old Flutter app meets an unknown required field type: shows "update the app", never crashes. (Task 6)

---

### Task 1: Sign-up and login by email or mobile (backend)

**Files:**
- Create: `backend/migrations/versions/0005_signup_identifiers.py`
- Modify: `backend/app/models/user.py`, `backend/app/schemas/auth.py`, `backend/app/services/auth_service.py`, `backend/app/api/v1/auth.py`, `backend/tests/helpers.py`, existing tests that register drivers (`tests/test_*.py` via helpers)
- Test: `backend/tests/test_signup_identifiers.py`

**Interfaces:**
- Produces: `SignUp` schema `{full_name, phone: Phone|None, email: EmailStr|None, password}` with validator requiring phone or email; `CustomerRegister`/`DriverRegister` both become `SignUp` (driver no longer carries licence/rate). `LoginRequest{identifier: str, password}` (accepts legacy `phone` key too). `auth_service.authenticate(session, identifier: str, password: str, role) -> User`. Exception `PhoneAlreadyRegistered` renamed `IdentifierTaken`; API returns 409 "Email or mobile number is already registered".
- Produces (DB): `users.phone` nullable (unique), `users.email_normalized` lower-cased, unique where not null. Driver profile columns `licence_number`, `experience_years`, `hourly_rate` become nullable (used by Task 3).

- [ ] **Step 1: Write failing tests** in `test_signup_identifiers.py`: `test_register_with_email_only`, `test_register_with_phone_only`, `test_register_with_neither_is_422`, `test_duplicate_email_case_insensitive_is_409`, `test_login_by_email_any_case`, `test_login_by_phone`, `test_driver_register_needs_no_licence`, `test_admin_login_still_works_with_phone`.
- [ ] **Step 2: Run** `pytest tests/test_signup_identifiers.py -v` → FAIL.
- [ ] **Step 3: Migration `0005`** — make `users.phone` nullable; add `email_normalized` (backfill `lower(email)`; for collisions keep the oldest user's email and set the rest to NULL, printing the affected user ids); unique index on `email_normalized`; make the three `driver_profiles` columns nullable. Downgrade reverses (restore NOT NULL only if no NULLs).
- [ ] **Step 4: Implement** schema, service and endpoints as in Interfaces. Login treats an identifier containing `@` as email (lower-cased lookup), otherwise normalises with `normalize_phone`. Keep the dummy-hash timing protection.
- [ ] **Step 5: Update `tests/helpers.py`**: `register_driver` posts the simple body only and returns tokens; add `apply_driver(client, headers, ...)` stub that Task 3 completes; `DRIVER` dict keeps licence/rate for the application step. Run `pytest -q`; fix tests broken by the removed registration fields (they should use `apply_driver` once Task 3 exists — until then mark them to be switched in Task 3 and keep this task green by having `register_driver` also set the three columns directly through the DB session when `legacy=True`).
- [ ] **Step 6: Run** `pytest -q` → PASS. **Commit** `feat: sign up and log in with email or mobile`.

---

### Task 2: Server-defined forms (model, seed, public read, admin builder API)

**Files:**
- Create: `backend/migrations/versions/0006_forms.py`, `backend/app/models/form.py`, `backend/app/services/form_service.py`, `backend/app/api/v1/forms.py`
- Modify: `backend/app/api/v1/admin.py` (builder endpoints), `backend/app/main.py` (router), `backend/app/models/__init__.py`
- Test: `backend/tests/test_forms.py`

**Interfaces:**
- Produces: `FormField` model: `id, role ('driver'|'customer'), key (slug, unique per role), label, field_type ('text'|'number'|'date'|'choice'|'document'), required: bool, help_text, choices: list[str]|None, position: int, is_active: bool, is_core: bool, created_at`.
- Produces: `form_service.get_form(session, role: Role) -> dict` → `{"version": int, "fields": [...]}`, where `version` is a counter bumped on every builder change (stored in a one-row `form_versions(role, version)` table).
- Produces: `GET /api/v1/forms/{role}` (any authenticated user; active fields only, ordered by position). Admin: `GET /admin/forms/{role}` (all fields including inactive), `POST /admin/forms/{role}/fields`, `PATCH /admin/forms/{role}/fields/{field_id}`, `DELETE /admin/forms/{role}/fields/{field_id}` (soft: `is_active=false`; 409 for core fields), `PUT /admin/forms/{role}/order` body `{ids: [uuid]}`.
- Seed (migration): driver form = `licence_number` text*, `experience_years` number*, `hourly_rate` number*, documents `LICENCE`*, `ID_PROOF`*, `PHOTO` (not required); customer form = `default_address` text (optional). Core: the three driver fields and the three document keys.

- [ ] **Step 1: Write failing tests**: `test_seeded_driver_form_has_core_fields_and_documents`, `test_non_admin_cannot_edit_forms` (403) and unauthenticated (401), `test_add_field_bumps_version`, `test_duplicate_key_is_409`, `test_key_must_be_slug` (rejects `"Bad Key!"`), `test_choice_field_requires_choices`, `test_cannot_delete_or_retype_core_field`, `test_delete_is_soft_and_hides_from_public_form`, `test_reorder`.
- [ ] **Step 2: Run** `pytest tests/test_forms.py -v` → FAIL.
- [ ] **Step 3: Implement** model, migration with seed, service, and routes; validate key `^[a-z][a-z0-9_]{1,40}$`, label ≤ 120, ≤ 30 active fields per role, choices 2–20 strings.
- [ ] **Step 4: Run** `pytest -q` → PASS. **Commit** `feat: server-defined registration forms with admin builder API`.

---

### Task 3: Driver application and lifecycle

**Files:**
- Create: `backend/migrations/versions/0007_driver_application.py`, `backend/app/models/answer.py`, `backend/app/services/application_service.py`
- Modify: `backend/app/models/driver.py` (add `NOT_SUBMITTED`, `form_version`), `backend/app/models/document.py` (`doc_type` becomes `String(40)`; keep `DocType` constants as default keys), `backend/app/services/document_service.py`, `backend/app/services/review_service.py`, `backend/app/api/v1/drivers.py`, `backend/app/schemas/auth.py`, `backend/tests/helpers.py`
- Test: `backend/tests/test_driver_application.py`

**Interfaces:**
- Consumes: Task 1 nullable profile columns; Task 2 `form_service.get_form`, `FormField`.
- Produces: `DriverAnswer(driver_id, field_key, value: str, status: DocStatus, review_note, updated_at)` unique on `(driver_id, field_key)`. `VerificationStatus.NOT_SUBMITTED` (new drivers start here; migration leaves existing rows unchanged and backfills their three core answers as `APPROVED`/`PENDING` to match the profile status).
- Produces: `application_service.submit(session, redis, profile, answers: dict[str, str]) -> DriverProfile`: validates against active form fields (required present, type-correct, choice in choices, no unknown keys, all required documents uploaded), writes answers and the three core columns, sets status `PENDING` (from `NOT_SUBMITTED` or `REJECTED`), and if the profile was `APPROVED` goes back to `PENDING` via `send_back_for_review`. On resubmit only changed or previously rejected answers reset to `PENDING`.
- Produces: `application_service.needs_update(session, profile) -> list[str]`: active required field keys with no answer (and required documents missing) — informational only, never changes status.
- Produces: `POST /drivers/application` body `{answers: {key: str}}` → `DriverOut`; `GET /drivers/me` now includes `application: {status, answers: [{key,value,status,review_note}], documents: [...], needs_update: [...], form_version}`. `POST /drivers/documents` takes `doc_type: str` validated against active document fields (422 otherwise).
- Change: admin "approve driver" requires all active *required* document fields approved (replaces the fixed `REQUIRED_DOCS` check) and all answers `APPROVED` or never-rejected. Rejecting any item sets the driver `REJECTED` ("Needs changes").

- [ ] **Step 1: Write failing tests**: `test_new_driver_starts_not_submitted_and_cannot_go_online`, `test_submit_application_moves_to_pending`, `test_submit_missing_required_field_422_names_field`, `test_submit_unknown_key_422`, `test_submit_wrong_type_422`, `test_submit_without_required_documents_422`, `test_pending_driver_not_in_nearby`, `test_admin_rejects_one_document_driver_needs_changes`, `test_resubmit_only_resets_flagged_items`, `test_approved_driver_edit_goes_back_to_review_and_offline`, `test_admin_adds_required_field_approved_driver_stays_bookable_and_flagged`, `test_existing_approved_driver_survives_migration` (seed an approved profile with old columns, run backfill function, still APPROVED with three APPROVED answers).
- [ ] **Step 2: Run** `pytest tests/test_driver_application.py -v` → FAIL.
- [ ] **Step 3: Implement** migration (string doc_type, `driver_answers`, `form_version`, backfill), models, `application_service`, the new endpoint and `/drivers/me` payload; adapt `review_service.set_verification`/`review_document`.
- [ ] **Step 4: Complete `tests/helpers.py::apply_driver`** (upload the three documents, post the application) and switch the legacy-flagged tests from Task 1 to it; remove the `legacy=True` shortcut. Run `pytest -q` → PASS.
- [ ] **Step 5: Commit** `feat: driver application with per-item review and Needs-changes loop`.

---

### Task 4: Admin API for the full panel

**Files:**
- Modify: `backend/app/api/v1/admin.py`, `backend/app/services/location_service.py`
- Create: `backend/app/services/admin_queries.py`
- Test: `backend/tests/test_admin_panel_v2.py`

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces:
  - `PATCH /admin/drivers/{id}/answers/{key}` body `{status: "APPROVED"|"REJECTED", note?: str}`.
  - `GET /admin/drivers?verification=NOT_SUBMITTED|PENDING|APPROVED|REJECTED&availability=...&needs_update=true` and `driver_detail` now returns `answers`, `needs_update`, `last_seen` (from `driver_locations.recorded_at`), completed trips, rating.
  - `GET /admin/drivers/live` → `{"drivers": [{id, name, status, latitude, longitude, heading, speed, recorded_at}]}` for fresh drivers (30 s window, statuses above). Function `live_drivers(session, redis) -> list[dict]` in `location_service.py`.
  - `GET /admin/bookings?status=&driver_id=&customer_id=&limit&offset` and `GET /admin/bookings/{id}` (read-only).
  - `GET /admin/users/{id}` including customer form answers (`customer_answers`) and, for drivers, a link field `driver_id`.
  - `GET /admin/stats` adds `not_submitted`, `rejected`, `needs_update`, `online_now`, `bookings_today`.

- [ ] **Step 1: Write failing tests**: `test_every_new_endpoint_401_403`, `test_answer_rejection_sets_driver_rejected`, `test_live_drivers_only_fresh_and_active_statuses`, `test_live_drivers_excludes_offline_and_stale`, `test_bookings_list_filters_and_bounds` (limit>100 → 422, filter by status), `test_user_detail_shows_customer_answers`, `test_stats_counts`, `test_search_with_percent_and_underscore_is_literal`.
- [ ] **Step 2: Run** `pytest tests/test_admin_panel_v2.py -v` → FAIL.
- [ ] **Step 3: Implement** the endpoints above, reusing the existing `_search` helper and bounded `limit`/`offset`.
- [ ] **Step 4: Run** `pytest -q` → PASS. **Commit** `feat: admin API for review queue, live drivers, bookings and richer detail`.

---

### Task 5: Customer optional profile (backend)

**Files:**
- Modify: `backend/app/api/v1/customers.py`
- Create: `backend/migrations/versions/0008_customer_answers.py`, `backend/app/models/customer_answer.py`
- Test: `backend/tests/test_customer_profile.py`

**Interfaces:**
- Consumes: Task 2 form service (role `customer`).
- Produces: `CustomerAnswer(customer_id, field_key, value)` unique pair; `PUT /customers/profile` body `{answers: {key: str}}` (validated like the driver submit; documents not allowed on the customer form → 422); `GET /customers/me` includes `profile: {answers, needs_update, form_version}`. `default_address` answer also updates `CustomerProfile.default_address`. Never blocks booking.

- [ ] **Step 1: Write failing tests**: `test_customer_can_save_profile_answers`, `test_unknown_key_422`, `test_document_field_not_allowed_for_customer`, `test_booking_works_without_profile`, `test_default_address_synced`.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** `pytest -q` → PASS.
- [ ] **Step 5: Commit** `feat: optional customer profile from the server form`.

---

### Task 6: Flutter sign-up, dynamic application and status screens

**Files:**
- Create: `lib/core/forms/form_models.dart`, `lib/core/forms/dynamic_form.dart` (renders `FormFieldSpec` list), `lib/features/driver/application_page.dart`, `lib/features/driver/application_controller.dart`, `lib/features/customer/profile_form_page.dart`
- Modify: `lib/core/auth/auth_repository.dart` (login by `identifier`), `lib/features/auth/login_page.dart`, `lib/features/auth/validators.dart`, `lib/features/driver/driver_register_page.dart`, `lib/features/customer/customer_register_page.dart`, `lib/features/driver/driver_home_shell.dart`, `lib/features/driver/documents_page.dart`, `lib/routes.dart`, `lib/app.dart`, `lib/main_preview.dart`, `lib/core/preview.dart`
- Test: `test/forms/dynamic_form_test.dart`, `test/auth/validators_test.dart`

**Interfaces:**
- Produces: `class FormFieldSpec {key, label, type: FieldType, required, helpText, choices, position}` with `FieldType {text, number, date, choice, document, unknown}` (unrecognised server types parse to `unknown`); `Future<FormSpec> fetchForm(UserRole)`; `DynamicForm` widget `({FormSpec spec, Map<String,String> initial, Set<String> flagged, onSubmit(Map<String,String>), uploadDocument(String key, PickedFile)})`.
- Behaviour: register pages take name, one identifier (email or mobile, one field that is validated as either) and password only. After a driver's first login `driver_home_shell` shows by status: `NOT_SUBMITTED` → application page; `PENDING` → "Under review" screen; `REJECTED` → "Needs changes" with admin notes and only flagged items editable; `APPROVED` → existing home, plus a dismissible "Please update your details" card when `needs_update` is non-empty. Unknown optional field types are skipped; an unknown required type shows "Update the app to continue" and disables submit. The customer profile form is reachable from the Profile tab and never blocks anything.

- [ ] **Step 1: Write failing tests**: `dynamic_form_test.dart` — `renders_each_supported_type`, `required_field_blocks_submit`, `unknown_optional_type_is_skipped`, `unknown_required_type_shows_update_message`, `flagged_items_only_editable_on_resubmit`; `validators_test.dart` — `identifier_accepts_email_and_indian_mobile`, `identifier_rejects_garbage`.
- [ ] **Step 2: Run** `flutter test` → FAIL.
- [ ] **Step 3: Implement** models, `DynamicForm`, controller (fetch form, submit via `POST /drivers/application`, upload via `POST /drivers/documents`), pages and routing per Behaviour.
- [ ] **Step 4: Run** `flutter analyze && flutter test` → PASS. Run the app in preview/emulator against the local backend and walk: sign up as driver → application → submit → see "Under review"; screenshot each state.
- [ ] **Step 5: Commit** `feat: simple sign-up, server-driven application form and status screens`.

---

### Task 7: Admin website redesign and new pages

**Files:**
- Modify: `docker/admin/index.html`, `docker/admin/styles.css`, `docker/admin/app.js` (split into ES modules), `docker/nginx.conf` (CSP only if the map needs a tile host), `docker-compose.yml` (no change expected)
- Create: `docker/admin/js/{api,router,ui,dashboard,review,drivers,driver-detail,users,bookings,forms,map}.js`, `docker/admin/js/background.js`
- Test: browser walk with Playwright (screenshots in `.playwright-mcp/`), plus `docker/admin/js/*.test.mjs` for pure helpers (`node --test`)

**Interfaces:**
- Consumes: Task 2–5 admin endpoints.
- Pages: Dashboard (stat tiles with count-up, recent applications), Review queue (pending applications: each answer and document with approve/reject + note, then "Approve driver"), Drivers (search, status/availability filters, "needs update" filter, detail with lifecycle timeline NOT_SUBMITTED→PENDING→APPROVED/REJECTED→SUSPENDED, suspend/reinstate, deactivate), Users (search, role filter, detail incl. customer answers), Bookings (read-only list and detail), Forms (builder for driver and customer: add/edit/reorder/disable fields, shows version), Live map (polls `/admin/drivers/live` every 5 s; pauses when the tab is hidden; marker colour by status; click for driver card).
- Look: dark theme with animated gradient/aurora background drawn on a `<canvas>` or CSS, glass cards, staggered page-enter and list animations, smooth route transitions, skeleton loaders, count-up numbers, animated status badges; all disabled under `prefers-reduced-motion`.
- Map: builder's choice (Leaflet self-hosted under `docker/admin/vendor/` with OSM tiles needs `img-src https://tile.openstreetmap.org`; a tile-free canvas plot of lat/lng is acceptable if tiles are not allowed). Either way the CSP change is explicit and tested.

- [ ] **Step 1: Write failing tests** for pure helpers in `js/ui.test.mjs`: `formatStatus`, `timeAgo`, `escape-free text building` (assert helper never produces markup from `<img onerror>` input), `buildQuery` (drops empty params, encodes `%` and `_`).
- [ ] **Step 2: Run** `node --test docker/admin/js` → FAIL.
- [ ] **Step 3: Implement** modules and pages per above; keep `textContent` rendering; keep token in `sessionStorage`; keep stale-reply discarding and refresh guard from Phase 5a.
- [ ] **Step 4: Run** `node --test docker/admin/js` → PASS; `docker compose up -d --build` then in a real browser: log in as admin, review a submitted application end to end, edit a form field and see it appear in the API, open Live map with a fake-located driver, and check the console shows no CSP violations. Save screenshots.
- [ ] **Step 5: Commit** `feat: animated admin website with review queue, form builder, bookings and live map`.

---

### Task 8: Whole-phase review and fixes

**Files:** whatever the review finds; docs: `docs/architecture.md` ("As built in Phase 5b").

- [ ] **Step 1: Dispatch a fresh reviewer** over the branch diff against the spec's anti-goals and the Review Focus above, in particular: an unapproved driver reaching search or bookings by any path, a stale form version breaking submit, admin text rendered as HTML, migration data loss.
- [ ] **Step 2: Fix every confirmed finding**, each with a failing test first. Run `cd backend && pytest -q`, `flutter analyze && flutter test`, `node --test docker/admin/js`.
- [ ] **Step 3: Update `docs/architecture.md`** with the lifecycle states, form tables and live-map endpoint. **Commit** `fix: phase 5b review findings` and `docs: phase 5b as built`.
