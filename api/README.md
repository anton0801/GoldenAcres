# GoldenAcres API

PHP 8.2+ / MySQL 8+. No Composer dependencies — the whole thing is standard
library plus PDO.

Every endpoint except `health`, `register`, `login` and `refresh` requires a
bearer token, and every domain row is scoped to the account that owns it.

## Layout

```
api/
├── public/          document root — nothing above this is web-reachable
│   ├── index.php    front controller: routing, auth, idempotency
│   └── .htaccess    HTTPS redirect, front-controller rewrite, headers
├── src/
│   ├── Core/        config, PDO, request/response, router, validator, rate limiter
│   ├── Security/    Argon2id passwords, opaque tokens, security log
│   ├── Domain/      declarative resource registry
│   └── Controllers/ auth, account, resources, sync
├── migrations/001_init.sql
├── bin/maintenance.php   cron housekeeping
└── .env.example
```

## Install

```bash
mysql -u root -e "CREATE DATABASE goldenacres CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;"
mysql -u root -e "CREATE USER 'goldenacres'@'localhost' IDENTIFIED BY 'a-strong-password';"
mysql -u root -e "GRANT SELECT, INSERT, UPDATE, DELETE ON goldenacres.* TO 'goldenacres'@'localhost';"
mysql -u goldenacres -p goldenacres < migrations/001_init.sql

cp .env.example .env
php -r "echo 'APP_PEPPER=', bin2hex(random_bytes(32)), PHP_EOL;"   # paste into .env
```

Point the web server's document root at `public/`. Nothing else may be served.

`APP_PEPPER` must be set before the first account is created and must never
change afterwards — every stored password hash depends on it.

## Endpoints

All paths are prefixed `/v1`. Success is `{"data": …}`, failure is
`{"error": {"code", "message", "details"}}`.

| Method | Path | Auth | Purpose |
|---|---|---|---|
| GET | `/health` | – | Liveness |
| POST | `/auth/register` | – | Create an account, returns tokens |
| POST | `/auth/login` | – | Sign in, returns tokens |
| POST | `/auth/refresh` | – | Rotate tokens using the refresh token |
| POST | `/auth/logout` | ✓ | End this session |
| POST | `/auth/logout-all` | ✓ | End every session |
| GET | `/me` | ✓ | Profile |
| PATCH | `/me` | ✓ | Update profile fields |
| DELETE | `/me` | ✓ | Delete the account and all its records |
| POST | `/me/password` | ✓ | Change password, revokes other sessions |
| GET | `/me/sessions` | ✓ | Signed-in devices |
| DELETE | `/me/sessions/{id}` | ✓ | Sign a device out |
| GET | `/me/security-events` | ✓ | Recent auth activity |
| GET | `/resources` | ✓ | Names of the domain resources |
| GET/POST | `/{resource}` | ✓ | List / create |
| GET/PATCH/DELETE | `/{resource}/{id}` | ✓ | Read / update / delete |
| GET | `/sync` | ✓ | Pull everything changed since a cursor |
| POST | `/sync` | ✓ | Push a batch of local changes |

Resources: `farms`, `fields`, `crop-seasons`, `observations`, `soil-tests`,
`irrigation-plans`, `irrigation-runs`, `tasks`, `inventory-lots`,
`stock-movements`, `input-applications`, `harvest-batches`, `harvest-loads`,
`team-members`, `season-reviews`, `audit-events`.

### Example

```bash
curl -sX POST https://api.example.com/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"you@farm.example","password":"…","device_name":"iPhone"}'

curl -s https://api.example.com/v1/fields \
  -H 'Authorization: Bearer gaa_…'
```

## How the security works

**Passwords.** Argon2id (64 MiB, 3 passes) over an HMAC-SHA256 of the password
and a server-side pepper. The pepper lives in `.env`, never in the database, so
a database-only leak cannot be cracked offline. Hashes are upgraded on sign-in
when the cost parameters change.

**Tokens.** Opaque 32-byte random values, `gaa_` for access and `gar_` for
refresh. Only SHA-256 hashes are stored, so the token table is worthless to an
attacker. Access tokens last an hour; refresh tokens last 30 days and **rotate
on every use**. A rotated refresh token is recorded, and presenting it a second
time revokes the whole session — that is how a stolen token gets caught.

**Session invalidation.** Each session records the password version it was
issued under. Changing the password bumps that version and every older token
stops working immediately.

**Ownership.** `user_id = ?` is in the WHERE clause of every domain query.
Foreign keys are checked against the same account, so a record cannot be
attached to someone else's field. A row belonging to another account returns
404, never 403, so the API does not confirm that an id exists.

**Abuse limits.** Database-backed sliding windows per IP and per account:
20 logins / 15 min per IP, 10 per email, 5 registrations / hour, 300 API calls
/ minute per account. Eight failed logins lock an account for 15 minutes.
Unknown emails still run a full Argon2 verification so response timing does not
reveal whether an address is registered.

**Input.** Everything is validated against the resource registry before it
reaches SQL: types, lengths, ranges, enums, UUID format, ISO-8601 dates.
Columns come from the registry, never from the request body, so an unknown key
is ignored rather than written. All statements are prepared with emulation off.

**Integrity in the database, not only in code.** `CHECK` constraints enforce
non-negative stock and that a harvest load's marketable + waste never exceeds
gross. A unique index makes a duplicate load impossible inside one batch.

**Responses.** `display_errors` is off; SQL errors are logged and answered with
a generic 500. Security headers (`nosniff`, `DENY`, CSP `default-src 'none'`,
HSTS in production) are on every response, including errors.

**Deletion.** `DELETE /me` needs the password *and* the literal string
`DELETE`, then removes the account and cascades to every owned row, reporting
exactly what was removed.

## Verified behaviour

`api_test.py` in the project scratchpad exercises 98 cases end to end —
registration, login, token enforcement, rotation, theft detection, ownership
isolation between two accounts, optimistic concurrency, harvest constraints,
immutability, idempotency, sync conflicts, password change and deletion. All
98 pass against a live server.

One real bug was found and fixed by that suite: theft detection originally
revoked the session inside a transaction that the subsequent 401 rolled back,
so a replayed refresh token left the session alive. The revocation now happens
outside the transaction.

## Housekeeping

```bash
*/15 * * * * /usr/bin/php /path/to/api/bin/maintenance.php >> /var/log/goldenacres.log 2>&1
```

## Before going live

- `APP_ENV=production` (enforces HTTPS, requires `APP_PEPPER`).
- Give the database user only `SELECT, INSERT, UPDATE, DELETE`.
- Terminate TLS in front of PHP and set `TRUST_PROXY=true` only if a proxy you
  control sets `X-Forwarded-For`; otherwise the header is spoofable and the
  per-IP limits become useless.
- Keep `.env` out of version control (`.gitignore` already covers it).
- Take database backups; the pepper is *not* in them, so store it separately —
  losing it makes every password unverifiable.
