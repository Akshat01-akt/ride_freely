# Phase 5a: Admin Website

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (inline). Steps use checkbox syntax.

**Goal:** Admins manage drivers, their documents and all users from a website.

**Architecture:** Static HTML, CSS and JavaScript (no build step, no framework), served by the existing nginx at `/admin/`, same origin as the API so there is no CORS. It talks to `/api/v1/admin/*` with the admin's bearer token. New admin endpoints add listings, driver detail, stats and an activate/deactivate switch.

**Rulings (decided here, not by the product owner):**
- Pages: Dashboard (counts), Drivers (search, filter, detail with documents, approve/reject documents and drivers, suspend/reinstate), Users (search, filter by role, activate/deactivate).
- Admin accounts are still created only with the CLI. The site never creates admins.
- Deactivating a user is refused for admins, for the caller themselves, and for anyone with an accepted or running booking that has not ended. Deactivating a driver also takes them offline and clears their location. A deactivated account cannot log in, refresh or use a token (already enforced).
- Documents are fetched with the bearer token and shown from an in-memory blob, never from a public URL.
- The site renders all server text with `textContent` (no HTML injection) and nginx sends a strict Content-Security-Policy for `/admin/`.
- The token is kept in `sessionStorage` (cleared when the tab closes).
- Not in this phase: booking management, audit log, admin roles/permissions, login rate limiting beyond nginx's existing limit.

## Review Focus
- A non-admin token gets 403 on every new endpoint; no token 401.
- Search text containing `%`, `_`, quotes or very long strings is safe; limit and offset are bounded.
- Deactivating self, another admin, or a driver with a live booking is refused.
- Page text from users (names, notes) can never run as HTML.

### Task 1: Admin API additions (stats, driver list and detail, user list, activate/deactivate)
### Task 2: nginx serving and CSP, compose volume
### Task 3: The website (login, dashboard, drivers, driver detail, users), checked in a real browser
### Task 4: Whole-phase review and fixes
