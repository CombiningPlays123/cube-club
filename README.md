# Cube Club

Cube Club is the public club website (Repository #2) for members to sign in with an Account Hub token, view server-verified stats and goals, compete on leaderboards, and request rewards. It is a static, GitHub Pages-friendly frontend. The backend remains the source of truth for identity, sessions, solves, goals, points, rewards, and permissions.

## Two repositories, one account system

1. A member creates/manages their account in **Cube Club Account Hub** (Repository #1).
2. Repository #1's backend generates a long random token, stores only a secure token hash and metadata, and associates the token with the member account.
3. The member enters that credential here. This site sends it to `POST /auth/token` over HTTPS.
4. The backend validates status and expiration using server time, resolves the account, invalidates/limits the one-time token exchange as appropriate, and creates a secure session.
5. This site requests safe account data from the API. Tokens do not encode usernames, points, solves, rewards, or expiration.

The Account Hub URL and API URL are public configuration values in `config.js`. No private keys or secrets belong in this GitHub Pages repository. `CUBE_CLUB_API_URL` is intentionally blank until you have a real API. `ACCOUNT_HUB_URL` is also intentionally blank until Repository #1 has a deployed URL. Update both in one place before deployment.

## Requirements

- Node.js 20+ (only for the optional local static server; no frontend build step is required).
- A deployed HTTPS API implementing the contract below.
- A database controlled only by that backend.

The frontend uses plain HTML, CSS, and JavaScript. There is no framework install step and no package manifest to maintain.

## Install and local development

Clone this repository, edit `config.js`, then serve the repository root with any static server. For example:

```sh
cd cube-club
npx serve .
```

Open the local URL printed by `serve`. Opening `index.html` directly can cause browser API restrictions; use a local HTTP server. The app runs without a build command.

### Development demo mode

Demo data is available only on `localhost` or `127.0.0.1` and only when `DEMO_MODE: true` is explicitly set in `config.js`. Demo login accepts any non-empty token; the demo token is never sent to an API. Demo reward requests alter only in-memory sample data, and the admin API remains unavailable. Keep `DEMO_MODE: false` in all production deployments. Never point the demo at production data.

## Configure the URLs

Edit `config.js`:

```js
window.CUBE_CLUB_CONFIG = {
  CUBE_CLUB_API_URL: "https://api.example.org/cube-club",
  ACCOUNT_HUB_URL: "https://account.example.org",
  DEMO_MODE: false
};
```

`CUBE_CLUB_API_URL` is the base URL for the backend API. `ACCOUNT_HUB_URL` powers the **Create an Account**, **Get a Token**, and account-management links. The values are visible to every visitor and must only be public URLs. `.env.example` is documentation: GitHub Pages does not read `.env` files or securely inject secrets into browser code.

## GitHub Pages deployment

1. Commit the contents of this project, including `.nojekyll`, to your Cube Club repository.
2. Set production URL values in `config.js`; leave `DEMO_MODE: false`.
3. In GitHub, open **Settings → Pages**, choose **Deploy from a branch**, then select the default branch and `/ (root)`.
4. Wait for the Pages deployment and open its HTTPS URL.
5. Configure the API's CORS allowlist for the exact Pages origin (including any custom domain), and test token exchange and session restoration.

GitHub Pages is static hosting. It cannot run API routes, protect secrets, validate solves, administer rewards, or enforce authorization. Deploy the API separately (for example, serverless functions or a managed backend) and use a custom domain/HTTPS in production.

## Backend API contract

Base URL: `CUBE_CLUB_API_URL`. All endpoints below require HTTPS. Requests and responses use JSON unless stated otherwise. The frontend sends credentials using `credentials: "include"` so a backend may use a `Secure; HttpOnly; SameSite` session cookie. The backend can also return a short-lived opaque session token; if so, protect it from XSS and prefer HttpOnly cookies. Configure strict CORS, origin checks, CSRF protection for cookie-authenticated mutations, rate limits, and security headers.

### Authentication and member data

| Method | Endpoint | Purpose |
|---|---|---|
| `POST` | `/auth/token` | Exchange `{ "token": "CC-…" }` for a secure session and safe member summary. |
| `POST` | `/auth/logout` | Revoke the current session. |
| `GET` | `/me` | Restore session; return current safe member summary. |
| `GET` | `/me/stats` | Return trusted points, rank, solve statistics, goals count, achievements, and token/session expiry status. |
| `GET` | `/me/goals` | Return goals, backend-computed state and progress. |
| `GET` | `/me/transactions` | Return immutable points transaction history. |
| `GET` | `/me/profile` | Return member's safe profile and visibility-filtered public stats. |
| `GET` | `/profiles/{public_id}` | Return only fields the member has made public. |
| `GET` | `/leaderboard?category=cube_points&period=all_time` | Return public display names and ranked values. Categories: `cube_points`, `best_single`, `best_average`, `total_solves`, `weekly_points`, `monthly_points`; periods: `all_time`, `this_month`, `this_week`. |
| `GET` | `/shop` | Return enabled shop items and prices. |
| `POST` | `/redemptions` | Request `{ "shop_item_id": "…" }`; atomically verify balance, debit points, and create `PENDING` redemption. |
| `GET` | `/redemptions` | Return current member's reward history. |

Token exchange failures may return `401` and a stable `code`: `INVALID_TOKEN`, `TOKEN_EXPIRED`, or `TOKEN_REVOKED`. Avoid revealing whether a credential belongs to an account. Never trust client-supplied balances, rank, user ID, goal completion, reward cost, or admin flags. The app maps token errors to the requested user-facing messages.

Suggested response for `POST /auth/token`:

```json
{
  "user": {
    "id": "opaque-public-id",
    "display_name": "CubeNinja",
    "points": 4250,
    "is_admin": false
  },
  "session_token": "opaque-short-lived-session-or-omit-when-using-cookie"
}
```

For cookie-based sessions, omit `session_token` and set the cookie in the response. The site requests `/me` after exchange and on page load to refresh trusted state.

### Goals, solves, points, and imports

Repository #1 owns CSTimer solve import. Support exported solve files where available; do not claim direct CSTimer account access unless a real, supported integration exists. The Account Hub backend must validate imports, deduplicate solves, calculate statistics, check goal eligibility, and create points transactions. Useful backend endpoints include `POST /imports/cstimer` for a validated export and `GET /me/solves`; they are outside this public site's direct API surface. Never award points merely because a browser reports a goal complete. Flag impossible times, repeated payloads, duplicate solves, and unusual point movement for administrator review rather than automatically banning based on one event.

### Admin API

Admin routes are server-authorized using the authenticated account's database-backed role, never a browser flag. Recommended endpoints include:

- `GET /admin/overview`, `/admin/members`, `/admin/solves`, `/admin/redemptions`, `/admin/audit-logs`
- `POST`/`PATCH` `/admin/goals`, `/admin/shop-items`
- `POST /admin/redemptions/{id}/approve`, `/reject`, `/fulfill`
- `POST /admin/members/{id}/revoke-tokens`, `/disable`
- `POST /admin/points-adjustments` with amount and required reason

Record actor ID, timestamp, action, target, reason, and relevant before/after values for each privileged mutation. Reject unauthorized requests with `403`; do not rely on hiding the Admin link.

## Database structure

`schema.sql` provides a PostgreSQL/Supabase-oriented starting point for core tables and integrity constraints. Treat it as a schema proposal: apply it only after adapting it to Repository #1's existing account IDs, retention rules, and migration process. The backend's database role owns all writes. Enable row-level security if clients can reach Supabase directly; never ship a service-role key. Prefer routing privileged mutations through trusted server code.

Important data rules:

- `tokens`: store token hash, account relation, created/expiry/revoked/last-used timestamps; never store the raw token after issuance.
- `points_transactions`: append-only source of truth. Balance is the sum of trusted transactions (or a transactionally maintained cache reconciled to that ledger).
- `solves`: unique import identity per account; validate server-side and retain provenance.
- `user_goals`: unique account/goal pair prevents repeat claims.
- `redemptions`: atomically debit points and create a pending request in one database transaction. A cancellation/refund must create a compensating transaction.
- `audit_logs`: append-only record for manual adjustments and admin actions.
- Public profile / leaderboard queries must apply privacy filters and return display names only.

## Security checklist

- [ ] Use HTTPS for Pages and API; allow only expected website origins through CORS.
- [ ] Keep signing keys, database credentials, service-role keys, admin secrets, and gift card codes on the backend only.
- [ ] Generate random high-entropy tokens; store hashes; enforce server-clock expiry, revocation, rate limits, and safe error handling.
- [ ] Exchange credentials for a short-lived secure session; do not use the account token as a permanent session.
- [ ] Authorize every read and write on the backend; validate ownership and admin role from trusted session state.
- [ ] Calculate points and stats from validated server-side records; make ledger and audit trails append-only.
- [ ] Deduplicate imports and claims; flag suspicious activity for review.
- [ ] Atomically debit reward cost and create redemption; refund via a logged compensating transaction on cancellation.
- [ ] Keep private profile fields out of public profile and leaderboard responses.
- [ ] Keep demo mode off in production and never connect demo data to a production database.

## Connecting Repository #1 and Repository #2

1. In Repository #1's backend, implement the token table and issue random credentials (for example, `CC-` plus grouped random characters). Store only a cryptographic hash and metadata. Show the raw token to the member once.
2. Implement `POST /auth/token`: rate-limit, hash the submitted token, check expiration/revocation using server time, resolve the account, and create a fresh secure session.
3. Implement `/me`, stats, goals, transactions, leaderboard, shop, and redemption endpoints described above. Use account IDs and database joins internally, not client-supplied values.
4. Deploy the backend and database. Configure CORS, session cookies/CSRF protections, and admin roles.
5. Set `CUBE_CLUB_API_URL` and `ACCOUNT_HUB_URL` in `config.js` in this repository. Keep `DEMO_MODE: false`.
6. Deploy this static site to GitHub Pages and add its origin to the API's allowed origins. The separate Account Hub repository must also set its own API URL and this site's URL.
7. Test an expired, revoked, invalid, and valid token; check server-returned profile data; submit a redemption and verify atomic debit plus `PENDING` state; check public privacy filtering and unauthorized admin calls.

## Limitations before backend configuration

This repository supplies the working UI and API client structure, but it cannot create or deploy Repository #1's backend/database. Until a real API URL is configured, the production site intentionally shows an API configuration error at sign-in. The built-in development demo is local-only, clearly marked, and not a production account system. Profile privacy editing, actual data imports, and admin mutation forms need their corresponding authenticated backend endpoints before those operations can be live.
