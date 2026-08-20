# Deploying to Hostinger

Everything goes into `public_html`. The `.htaccess` in this folder routes all
traffic to `public/index.php` and blocks direct access to everything else.

## 1. Upload

Upload the **contents** of `api/` into `public_html`, so you end up with:

```
public_html/
├── .htaccess          <- routes everything to public/index.php
├── .env               <- your settings (create in step 3)
├── public/
│   ├── .htaccess
│   └── index.php      <- the only script that can be reached
├── src/               <- blocked
├── migrations/        <- blocked
├── database/          <- blocked
└── bin/               <- blocked
```

Do not skip `public_html/.htaccess` or `public_html/public/.htaccess`. The
first routes requests; the second re-allows `index.php`, which the first
deliberately denies along with every other `.php` file. Missing either one and
the API answers 403 for everything.

> Safer alternative, if hPanel lets you set the document root for the domain:
> point it at `public_html/public` and keep the rest one level above. Both
> layouts are supported; the one above is the default.

## 2. Database

1. hPanel → **Databases → MySQL Databases**. Create a database and a user, give
   the user all privileges. Note the three values Hostinger shows you, e.g.
   `u123456789_goldenacres`, `u123456789_ga`, `localhost`.
2. Click **Enter phpMyAdmin** next to the database.
3. **Import** tab → choose `database/install.sql` → **Go**.
4. The last query prints `tables_created`. It must say **22**.

`install.sql` creates tables only — it never creates the database or a user,
because shared hosting does not grant those rights. Re-running it is harmless.

## 3. `.env`

Create `public_html/.env` (File Manager → New File). Generate the pepper first,
in phpMyAdmin's SQL tab or any PHP page:

```
APP_ENV=production
APP_BASE_PATH=
APP_PEPPER=<64 random hex characters — see below>

DB_HOST=localhost
DB_PORT=3306
DB_NAME=u123456789_goldenacres
DB_USER=u123456789_ga
DB_PASSWORD=your-database-password

ACCESS_TOKEN_TTL=3600
REFRESH_TOKEN_TTL=2592000
ARGON_MEMORY_KIB=65536
ARGON_TIME_COST=3
ARGON_THREADS=2

RL_LOGIN_PER_IP=20
RL_LOGIN_PER_EMAIL=10
RL_REGISTER_PER_HOUR=5
RL_REFRESH_PER_HOUR=120
RL_API_PER_MINUTE=300

MAX_BODY_BYTES=1048576
TRUST_PROXY=false
CORS_ORIGINS=
```

To generate `APP_PEPPER`, run this SQL in phpMyAdmin and copy the result:

```sql
SELECT SHA2(CONCAT(RAND(), UUID(), NOW(6)), 256) AS app_pepper;
```

**Set `APP_PEPPER` once, before the first account is created, and never change
it.** Every password hash depends on it — changing it makes all existing
passwords unverifiable. It is not in database backups, so store it separately.

If Hostinger's PHP runs with `ARGON_MEMORY_KIB=65536` too slowly, lower it to
`32768`. Do not go below that.

> You can also put `.env` one level **above** `public_html`. The app looks there
> first. That keeps your secrets physically outside anything the web server can
> serve.

## 4. PHP version

hPanel → **Advanced → PHP Configuration** → select **PHP 8.2 or newer**, and
make sure `pdo_mysql` is enabled (it is by default).

## 5. Check it works

```bash
curl https://your-domain.com/v1/health
```

Expected:

```json
{"data":{"status":"ok","time":"2026-08-18T21:00:00.000Z"}}
```

Then confirm the protections are live — all three must return 403:

```bash
curl -i https://your-domain.com/.env
curl -i https://your-domain.com/src/Core/Config.php
curl -i https://your-domain.com/database/install.sql
```

And confirm the token header survives your host's PHP setup:

```bash
curl -sX POST https://your-domain.com/v1/auth/register \
  -H 'Content-Type: application/json' \
  -d '{"email":"you@example.com","password":"Choose-A-Strong-One-2026!"}'

# take access_token from the reply
curl -s https://your-domain.com/v1/me -H 'Authorization: Bearer gaa_...'
```

If `/v1/health` works but `/v1/me` returns 401 with a valid token, the host is
stripping the `Authorization` header. The `.htaccess` already re-injects it and
PHP reads `REDIRECT_HTTP_AUTHORIZATION` as a fallback, so this should not
happen — but if it does, contact support and ask them to enable
`CGIPassAuth`.

## 6. Point the app at it

In the app: **Farm → gear → Account → server icon**, set the base URL to
`https://your-domain.com/v1`, tap **Test connection**, then **Save endpoint**.

## 7. Cron

hPanel → **Advanced → Cron Jobs**, every 15 minutes:

```
/usr/bin/php /home/uXXXXXXXXX/public_html/bin/maintenance.php
```

This clears expired sessions, spent rate-limit windows and old idempotency
keys. Nothing in it touches your farm records.

## Troubleshooting

| Symptom | Cause |
|---|---|
| 403 on every path, including `/v1/health` | `public/.htaccess` missing — it re-allows `index.php` |
| 404 HTML page instead of JSON | `public_html/.htaccess` missing, or mod_rewrite off |
| 500 on every request | `.env` missing, wrong DB credentials, or PHP older than 8.2 |
| 401 with a valid token | `Authorization` stripped by the host — see step 5 |
| `https_required` in the reply | PHP cannot see HTTPS; set `TRUST_PROXY=true` if you use Cloudflare |
| Import fails on `utf8mb4_0900_ai_ci` | You imported `migrations/001_init.sql`; use `database/install.sql` |
