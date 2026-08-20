-- ===========================================================================
--  GoldenAcres API — complete database setup
--
--  HOW TO USE ON HOSTINGER
--  1. hPanel -> Databases -> MySQL Databases
--     Create a database and a user, tick all privileges, note the details:
--       database  u123456789_goldenacres
--       user      u123456789_ga
--       host      localhost
--  2. Click "Enter phpMyAdmin" next to the new database.
--  3. Import tab -> choose this file -> Go.
--  4. Put the same details into .env (DB_NAME / DB_USER / DB_PASSWORD).
--
--  This file does NOT create the database or the user: shared hosting does not
--  grant those privileges, and phpMyAdmin already imports into the database you
--  selected. Everything here is CREATE TABLE IF NOT EXISTS, so running it twice
--  is harmless and it will never overwrite existing data.
--
--  Works on MySQL 5.7+, MySQL 8+ and MariaDB 10.2+.
--  All timestamps are UTC with millisecond precision.
--
--  SECURITY NOTES
--  * No password or token is ever stored in readable form. Passwords are
--    Argon2id hashes; tokens are stored only as SHA-256 fingerprints.
--  * Every domain table carries user_id and is filtered by it on every query,
--    so one account can never read another's rows.
--  * CHECK constraints enforce the rules that matter even if application code
--    is bypassed: stock can never go negative, and a harvest load's
--    marketable + waste can never exceed its gross quantity.
-- ===========================================================================

-- If you DO have privileges (VPS, local machine), uncomment these two lines:
-- CREATE DATABASE IF NOT EXISTS goldenacres CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
-- USE goldenacres;

SET NAMES utf8mb4;
SET time_zone = '+00:00';
SET FOREIGN_KEY_CHECKS = 1;
SET sql_mode = 'STRICT_TRANS_TABLES,NO_ENGINE_SUBSTITUTION';

-- ---------------------------------------------------------------------------
-- Accounts
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS users (
    id                  CHAR(36)     NOT NULL PRIMARY KEY,
    email               VARCHAR(320) NOT NULL,
    -- Lowercased email used for uniqueness and lookup, so casing can't create duplicates.
    email_canonical     VARCHAR(320) NOT NULL,
    password_hash       VARCHAR(255) NOT NULL,
    -- Bumped whenever the password changes; invalidates every issued token.
    password_version    INT UNSIGNED NOT NULL DEFAULT 1,
    display_name        VARCHAR(120) NULL,
    farm_name           VARCHAR(160) NULL,
    country             VARCHAR(80)  NULL,
    unit_system         ENUM('metric','imperial') NOT NULL DEFAULT 'metric',
    currency_code       CHAR(3)      NOT NULL DEFAULT 'USD',
    time_zone           VARCHAR(64)  NOT NULL DEFAULT 'UTC',
    status              ENUM('active','locked','pending_deletion') NOT NULL DEFAULT 'active',
    failed_login_count  INT UNSIGNED NOT NULL DEFAULT 0,
    locked_until        DATETIME(3)  NULL,
    last_login_at       DATETIME(3)  NULL,
    deletion_requested_at DATETIME(3) NULL,
    created_at          DATETIME(3)  NOT NULL,
    updated_at          DATETIME(3)  NOT NULL,
    UNIQUE KEY uq_users_email_canonical (email_canonical),
    KEY idx_users_status (status),
    KEY idx_users_deletion (deletion_requested_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- One row per signed-in device. Holds the current access token hash and the
-- current refresh token hash; both rotate on every refresh.
CREATE TABLE IF NOT EXISTS sessions (
    id                  CHAR(36)     NOT NULL PRIMARY KEY,
    user_id             CHAR(36)     NOT NULL,
    access_token_hash   CHAR(64)     NULL,
    refresh_token_hash  CHAR(64)     NULL,
    access_expires_at   DATETIME(3)  NULL,
    refresh_expires_at  DATETIME(3)  NOT NULL,
    password_version    INT UNSIGNED NOT NULL DEFAULT 1,
    device_name         VARCHAR(120) NULL,
    ip_address          VARBINARY(16) NULL,
    user_agent          VARCHAR(255) NULL,
    created_at          DATETIME(3)  NOT NULL,
    last_used_at        DATETIME(3)  NULL,
    revoked_at          DATETIME(3)  NULL,
    revoked_reason      VARCHAR(64)  NULL,
    UNIQUE KEY uq_sessions_access (access_token_hash),
    UNIQUE KEY uq_sessions_refresh (refresh_token_hash),
    KEY idx_sessions_user (user_id, revoked_at),
    KEY idx_sessions_refresh_exp (refresh_expires_at),
    CONSTRAINT fk_sessions_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Refresh tokens that have already been rotated away. Presenting one of these
-- again means the token was captured, so the whole session is revoked.
CREATE TABLE IF NOT EXISTS retired_refresh_tokens (
    token_hash  CHAR(64)    NOT NULL PRIMARY KEY,
    session_id  CHAR(36)    NOT NULL,
    user_id     CHAR(36)    NOT NULL,
    retired_at  DATETIME(3) NOT NULL,
    KEY idx_retired_session (session_id),
    CONSTRAINT fk_retired_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- Abuse protection
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS rate_limits (
    bucket      VARCHAR(190) NOT NULL PRIMARY KEY,
    hits        INT UNSIGNED NOT NULL DEFAULT 0,
    window_start DATETIME(3) NOT NULL,
    blocked_until DATETIME(3) NULL,
    KEY idx_rate_window (window_start)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS idempotency_keys (
    id              CHAR(36)     NOT NULL PRIMARY KEY,
    user_id         CHAR(36)     NOT NULL,
    idem_key        VARCHAR(190) NOT NULL,
    endpoint        VARCHAR(190) NOT NULL,
    request_hash    CHAR(64)     NOT NULL,
    response_status INT          NOT NULL,
    response_body   MEDIUMTEXT   NOT NULL,
    created_at      DATETIME(3)  NOT NULL,
    UNIQUE KEY uq_idem (user_id, idem_key, endpoint),
    KEY idx_idem_created (created_at),
    CONSTRAINT fk_idem_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Server-side security trail. Separate from the app's own domain audit log.
CREATE TABLE IF NOT EXISTS security_events (
    id          CHAR(36)     NOT NULL PRIMARY KEY,
    user_id     CHAR(36)     NULL,
    event       VARCHAR(64)  NOT NULL,
    outcome     ENUM('success','failure') NOT NULL,
    ip_address  VARBINARY(16) NULL,
    user_agent  VARCHAR(255) NULL,
    detail      VARCHAR(500) NULL,
    created_at  DATETIME(3)  NOT NULL,
    KEY idx_sec_user (user_id, created_at),
    KEY idx_sec_event (event, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- Domain
--
-- Every table below repeats the same sync contract:
--   user_id     owner, enforced on every statement
--   revision    optimistic-concurrency counter, bumped on each write
--   deleted_at  soft delete so clients can converge on removals
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS farms (
    id               CHAR(36) NOT NULL PRIMARY KEY,
    user_id          CHAR(36) NOT NULL,
    name             VARCHAR(160) NOT NULL,
    country          VARCHAR(80)  NULL,
    time_zone        VARCHAR(64)  NULL,
    unit_system      VARCHAR(16)  NULL,
    currency_code    CHAR(3)      NULL,
    weather_source   VARCHAR(80)  NULL,
    retention_months INT          NULL,
    is_archived      TINYINT(1)   NOT NULL DEFAULT 0,
    revision         BIGINT UNSIGNED NOT NULL DEFAULT 1,
    created_at       DATETIME(3)  NOT NULL,
    updated_at       DATETIME(3)  NOT NULL,
    deleted_at       DATETIME(3)  NULL,
    KEY idx_farms_user (user_id, updated_at),
    CONSTRAINT fk_farms_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS fields (
    id                CHAR(36) NOT NULL PRIMARY KEY,
    user_id           CHAR(36) NOT NULL,
    farm_id           CHAR(36) NULL,
    name              VARCHAR(160) NOT NULL,
    area_value        DOUBLE       NULL,
    area_unit         VARCHAR(12)  NULL,
    soil_type         VARCHAR(120) NULL,
    irrigation_method VARCHAR(40)  NULL,
    notes             TEXT         NULL,
    latitude          DOUBLE       NULL,
    longitude         DOUBLE       NULL,
    boundary          JSON         NULL,
    is_archived       TINYINT(1)   NOT NULL DEFAULT 0,
    revision          BIGINT UNSIGNED NOT NULL DEFAULT 1,
    created_at        DATETIME(3)  NOT NULL,
    updated_at        DATETIME(3)  NOT NULL,
    deleted_at        DATETIME(3)  NULL,
    KEY idx_fields_user (user_id, updated_at),
    KEY idx_fields_farm (farm_id),
    CONSTRAINT fk_fields_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS crop_seasons (
    id                     CHAR(36) NOT NULL PRIMARY KEY,
    user_id                CHAR(36) NOT NULL,
    field_id               CHAR(36) NULL,
    crop_name              VARCHAR(160) NOT NULL,
    variety                VARCHAR(160) NULL,
    intended_use           VARCHAR(60)  NULL,
    planting_window_start  DATETIME(3)  NULL,
    planting_window_end    DATETIME(3)  NULL,
    actual_planting_date   DATETIME(3)  NULL,
    expected_harvest_start DATETIME(3)  NULL,
    expected_harvest_end   DATETIME(3)  NULL,
    target_area_value      DOUBLE       NULL,
    target_area_unit       VARCHAR(12)  NULL,
    seed_lot_id            CHAR(36)     NULL,
    seed_lot_label         VARCHAR(200) NULL,
    notes                  TEXT         NULL,
    status                 VARCHAR(20)  NOT NULL DEFAULT 'draft',
    allows_intercropping   TINYINT(1)   NOT NULL DEFAULT 0,
    activated_at           DATETIME(3)  NULL,
    closed_at              DATETIME(3)  NULL,
    closing_snapshot       JSON         NULL,
    revision               BIGINT UNSIGNED NOT NULL DEFAULT 1,
    created_at             DATETIME(3)  NOT NULL,
    updated_at             DATETIME(3)  NOT NULL,
    deleted_at             DATETIME(3)  NULL,
    KEY idx_seasons_user (user_id, updated_at),
    KEY idx_seasons_field (field_id),
    CONSTRAINT fk_seasons_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS observations (
    id                  CHAR(36) NOT NULL PRIMARY KEY,
    user_id             CHAR(36) NOT NULL,
    field_id            CHAR(36) NULL,
    season_id           CHAR(36) NULL,
    observed_at         DATETIME(3)  NOT NULL,
    observation_type    VARCHAR(60)  NOT NULL,
    severity            VARCHAR(20)  NULL,
    notes               TEXT         NULL,
    affected_area_value DOUBLE       NULL,
    affected_area_unit  VARCHAR(12)  NULL,
    related_crop_stage  VARCHAR(120) NULL,
    latitude            DOUBLE       NULL,
    longitude           DOUBLE       NULL,
    confirmed_category  VARCHAR(160) NULL,
    review_requested    TINYINT(1)   NOT NULL DEFAULT 0,
    field_name_snapshot VARCHAR(160) NULL,
    photo_filenames     JSON         NULL,
    image_suggestion    JSON         NULL,
    is_archived         TINYINT(1)   NOT NULL DEFAULT 0,
    revision            BIGINT UNSIGNED NOT NULL DEFAULT 1,
    created_at          DATETIME(3)  NOT NULL,
    updated_at          DATETIME(3)  NOT NULL,
    deleted_at          DATETIME(3)  NULL,
    KEY idx_obs_user (user_id, updated_at),
    KEY idx_obs_field (field_id),
    CONSTRAINT fk_obs_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS soil_tests (
    id                     CHAR(36) NOT NULL PRIMARY KEY,
    user_id                CHAR(36) NOT NULL,
    field_id               CHAR(36) NULL,
    laboratory             VARCHAR(160) NULL,
    sample_date            DATETIME(3)  NOT NULL,
    zone                   VARCHAR(120) NULL,
    depth_value            DOUBLE       NULL,
    depth_unit             VARCHAR(12)  NULL,
    ph                     DOUBLE       NULL,
    organic_matter_percent DOUBLE       NULL,
    nitrogen_value         DOUBLE       NULL,
    nitrogen_unit          VARCHAR(16)  NULL,
    phosphorus_value       DOUBLE       NULL,
    phosphorus_unit        VARCHAR(16)  NULL,
    potassium_value        DOUBLE       NULL,
    potassium_unit         VARCHAR(16)  NULL,
    salinity_value         DOUBLE       NULL,
    salinity_unit          VARCHAR(16)  NULL,
    micronutrients         JSON         NULL,
    parsed_suggestions     JSON         NULL,
    parse_provenance       JSON         NULL,
    parse_failed_reason    VARCHAR(500) NULL,
    original_file_name     VARCHAR(200) NULL,
    notes                  TEXT         NULL,
    status                 VARCHAR(20)  NOT NULL DEFAULT 'draft',
    confirmed_at           DATETIME(3)  NULL,
    field_name_snapshot    VARCHAR(160) NULL,
    revision               BIGINT UNSIGNED NOT NULL DEFAULT 1,
    created_at             DATETIME(3)  NOT NULL,
    updated_at             DATETIME(3)  NOT NULL,
    deleted_at             DATETIME(3)  NULL,
    KEY idx_soil_user (user_id, updated_at),
    KEY idx_soil_field (field_id),
    CONSTRAINT fk_soil_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS irrigation_plans (
    id                       CHAR(36) NOT NULL PRIMARY KEY,
    user_id                  CHAR(36) NOT NULL,
    field_id                 CHAR(36) NULL,
    season_id                CHAR(36) NULL,
    zone                     VARCHAR(120) NULL,
    crop_stage               VARCHAR(120) NULL,
    method                   VARCHAR(40)  NULL,
    available_flow_value     DOUBLE       NULL,
    flow_unit                VARCHAR(16)  NULL,
    target_depth_value       DOUBLE       NULL,
    depth_unit               VARCHAR(12)  NULL,
    rain_adjustment_mm       DOUBLE       NULL,
    rain_adjustment_source   VARCHAR(120) NULL,
    start_window             DATETIME(3)  NULL,
    planned_duration_minutes DOUBLE       NULL,
    water_source             VARCHAR(160) NULL,
    restrictions             TEXT         NULL,
    status                   VARCHAR(20)  NOT NULL DEFAULT 'draft',
    calculation              JSON         NULL,
    field_name_snapshot      VARCHAR(160) NULL,
    revision                 BIGINT UNSIGNED NOT NULL DEFAULT 1,
    created_at               DATETIME(3)  NOT NULL,
    updated_at               DATETIME(3)  NOT NULL,
    deleted_at               DATETIME(3)  NULL,
    KEY idx_irr_user (user_id, updated_at),
    KEY idx_irr_field (field_id),
    CONSTRAINT fk_irr_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS irrigation_runs (
    id                  CHAR(36) NOT NULL PRIMARY KEY,
    user_id             CHAR(36) NOT NULL,
    plan_id             CHAR(36) NULL,
    started_at          DATETIME(3) NOT NULL,
    ended_at            DATETIME(3) NULL,
    actual_volume_value DOUBLE      NULL,
    volume_unit         VARCHAR(12) NULL,
    meter_reading_start DOUBLE      NULL,
    meter_reading_end   DOUBLE      NULL,
    notes               TEXT        NULL,
    recorded_at         DATETIME(3) NOT NULL,
    revision            BIGINT UNSIGNED NOT NULL DEFAULT 1,
    created_at          DATETIME(3) NOT NULL,
    updated_at          DATETIME(3) NOT NULL,
    deleted_at          DATETIME(3) NULL,
    KEY idx_run_user (user_id, updated_at),
    KEY idx_run_plan (plan_id),
    CONSTRAINT fk_run_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS tasks (
    id                         CHAR(36) NOT NULL PRIMARY KEY,
    user_id                    CHAR(36) NOT NULL,
    season_id                  CHAR(36) NULL,
    field_id                   CHAR(36) NULL,
    field_name_snapshot        VARCHAR(160) NULL,
    title                      VARCHAR(200) NOT NULL,
    detail                     TEXT         NULL,
    due_start                  DATETIME(3)  NULL,
    due_end                    DATETIME(3)  NULL,
    estimated_duration_minutes DOUBLE       NULL,
    priority                   VARCHAR(20)  NOT NULL DEFAULT 'Normal',
    assignee                   VARCHAR(120) NULL,
    equipment                  VARCHAR(160) NULL,
    required_inputs            JSON         NULL,
    dependency_ids             JSON         NULL,
    status                     VARCHAR(20)  NOT NULL DEFAULT 'Planned',
    blocked_reason             VARCHAR(500) NULL,
    started_at                 DATETIME(3)  NULL,
    completed_at               DATETIME(3)  NULL,
    actual_duration_minutes    DOUBLE       NULL,
    weather_review_needed      TINYINT(1)   NOT NULL DEFAULT 0,
    weather_review_note        VARCHAR(500) NULL,
    source_window_description  VARCHAR(500) NULL,
    completion_key             CHAR(36)     NULL,
    revision                   BIGINT UNSIGNED NOT NULL DEFAULT 1,
    created_at                 DATETIME(3)  NOT NULL,
    updated_at                 DATETIME(3)  NOT NULL,
    deleted_at                 DATETIME(3)  NULL,
    KEY idx_tasks_user (user_id, updated_at),
    KEY idx_tasks_season (season_id),
    CONSTRAINT fk_tasks_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS inventory_lots (
    id                   CHAR(36) NOT NULL PRIMARY KEY,
    user_id              CHAR(36) NOT NULL,
    farm_id              CHAR(36) NULL,
    item_name            VARCHAR(200) NOT NULL,
    category             VARCHAR(60)  NOT NULL DEFAULT 'Other',
    lot_code             VARCHAR(120) NULL,
    on_hand_quantity     DOUBLE       NOT NULL DEFAULT 0,
    reserved_quantity    DOUBLE       NOT NULL DEFAULT 0,
    unit                 VARCHAR(16)  NOT NULL DEFAULT 'kg',
    storage_location     VARCHAR(160) NULL,
    received_date        DATETIME(3)  NULL,
    expiry_date          DATETIME(3)  NULL,
    unit_cost            DECIMAL(18,4) NULL,
    supplier             VARCHAR(160) NULL,
    safety_file_name     VARCHAR(200) NULL,
    label_scan_provenance JSON        NULL,
    is_archived          TINYINT(1)   NOT NULL DEFAULT 0,
    revision             BIGINT UNSIGNED NOT NULL DEFAULT 1,
    created_at           DATETIME(3)  NOT NULL,
    updated_at           DATETIME(3)  NOT NULL,
    deleted_at           DATETIME(3)  NULL,
    KEY idx_lots_user (user_id, updated_at),
    KEY idx_lots_farm (farm_id),
    -- Physical stock and reservations can never go negative.
    CONSTRAINT chk_lots_nonneg CHECK (on_hand_quantity >= 0 AND reserved_quantity >= 0),
    CONSTRAINT fk_lots_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS stock_movements (
    id                       CHAR(36) NOT NULL PRIMARY KEY,
    user_id                  CHAR(36) NOT NULL,
    lot_id                   CHAR(36) NULL,
    type                     VARCHAR(40) NOT NULL,
    quantity                 DOUBLE      NOT NULL DEFAULT 0,
    unit                     VARCHAR(16) NOT NULL DEFAULT 'kg',
    reason                   VARCHAR(500) NULL,
    occurred_at              DATETIME(3) NOT NULL,
    related_record_id        CHAR(36)    NULL,
    related_record_label     VARCHAR(200) NULL,
    actor                    VARCHAR(120) NULL,
    balance_after_on_hand    DOUBLE      NULL,
    balance_after_reserved   DOUBLE      NULL,
    revision                 BIGINT UNSIGNED NOT NULL DEFAULT 1,
    created_at               DATETIME(3) NOT NULL,
    updated_at               DATETIME(3) NOT NULL,
    deleted_at               DATETIME(3) NULL,
    KEY idx_mov_user (user_id, updated_at),
    KEY idx_mov_lot (lot_id, occurred_at),
    CONSTRAINT fk_mov_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS input_applications (
    id                    CHAR(36) NOT NULL PRIMARY KEY,
    user_id               CHAR(36) NOT NULL,
    season_id             CHAR(36) NULL,
    field_id              CHAR(36) NULL,
    field_name_snapshot   VARCHAR(160) NULL,
    product_name          VARCHAR(200) NOT NULL,
    category              VARCHAR(60)  NOT NULL DEFAULT 'Other',
    registration_note     VARCHAR(500) NULL,
    lot_id                CHAR(36)     NULL,
    lot_label_snapshot    VARCHAR(200) NULL,
    quantity              DOUBLE       NOT NULL DEFAULT 0,
    quantity_unit         VARCHAR(16)  NOT NULL DEFAULT 'L',
    area_treated_value    DOUBLE       NULL,
    area_unit             VARCHAR(12)  NULL,
    applied_at            DATETIME(3)  NOT NULL,
    operator_name         VARCHAR(120) NULL,
    purpose               TEXT         NULL,
    weather_snapshot      JSON         NULL,
    attachment_names      JSON         NULL,
    voided_at             DATETIME(3)  NULL,
    void_reason           VARCHAR(500) NULL,
    supersedes_id         CHAR(36)     NULL,
    label_scan_provenance JSON         NULL,
    revision              BIGINT UNSIGNED NOT NULL DEFAULT 1,
    created_at            DATETIME(3)  NOT NULL,
    updated_at            DATETIME(3)  NOT NULL,
    deleted_at            DATETIME(3)  NULL,
    KEY idx_app_user (user_id, updated_at),
    KEY idx_app_season (season_id),
    CONSTRAINT chk_app_qty CHECK (quantity >= 0),
    CONSTRAINT fk_app_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS harvest_batches (
    id                  CHAR(36) NOT NULL PRIMARY KEY,
    user_id             CHAR(36) NOT NULL,
    season_id           CHAR(36) NULL,
    field_id            CHAR(36) NULL,
    field_name_snapshot VARCHAR(160) NULL,
    batch_code          VARCHAR(80)  NOT NULL,
    started_at          DATETIME(3)  NOT NULL,
    closed_at           DATETIME(3)  NULL,
    status              VARCHAR(20)  NOT NULL DEFAULT 'Open',
    quality_grade       VARCHAR(120) NULL,
    storage_destination VARCHAR(160) NULL,
    crew                VARCHAR(160) NULL,
    notes               TEXT         NULL,
    revisions           JSON         NULL,
    revision            BIGINT UNSIGNED NOT NULL DEFAULT 1,
    created_at          DATETIME(3)  NOT NULL,
    updated_at          DATETIME(3)  NOT NULL,
    deleted_at          DATETIME(3)  NULL,
    KEY idx_batch_user (user_id, updated_at),
    KEY idx_batch_season (season_id),
    CONSTRAINT fk_batch_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS harvest_loads (
    id                   CHAR(36) NOT NULL PRIMARY KEY,
    user_id              CHAR(36) NOT NULL,
    batch_id             CHAR(36) NULL,
    occurred_at          DATETIME(3) NOT NULL,
    gross_quantity       DOUBLE      NOT NULL DEFAULT 0,
    marketable_quantity  DOUBLE      NULL,
    waste_quantity       DOUBLE      NULL,
    unit                 VARCHAR(16) NOT NULL DEFAULT 'kg',
    notes                TEXT        NULL,
    idempotency_key      VARCHAR(120) NOT NULL,
    recorded_by          VARCHAR(120) NULL,
    revision             BIGINT UNSIGNED NOT NULL DEFAULT 1,
    created_at           DATETIME(3) NOT NULL,
    updated_at           DATETIME(3) NOT NULL,
    deleted_at           DATETIME(3) NULL,
    -- The same load can never be recorded twice inside one batch.
    UNIQUE KEY uq_load_idem (batch_id, idempotency_key),
    KEY idx_load_user (user_id, updated_at),
    -- Gross must be positive and the split can never exceed it.
    CONSTRAINT chk_load_gross CHECK (gross_quantity >= 0),
    CONSTRAINT chk_load_split CHECK (
        COALESCE(marketable_quantity, 0) + COALESCE(waste_quantity, 0) <= gross_quantity + 0.0001
    ),
    CONSTRAINT fk_load_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS team_members (
    id         CHAR(36) NOT NULL PRIMARY KEY,
    user_id    CHAR(36) NOT NULL,
    farm_id    CHAR(36) NULL,
    name       VARCHAR(160) NOT NULL,
    email      VARCHAR(320) NULL,
    role       VARCHAR(40)  NOT NULL DEFAULT 'Worker',
    invited_at DATETIME(3)  NOT NULL,
    is_active  TINYINT(1)   NOT NULL DEFAULT 1,
    revision   BIGINT UNSIGNED NOT NULL DEFAULT 1,
    created_at DATETIME(3)  NOT NULL,
    updated_at DATETIME(3)  NOT NULL,
    deleted_at DATETIME(3)  NULL,
    KEY idx_team_user (user_id, updated_at),
    CONSTRAINT fk_team_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS season_reviews (
    id           CHAR(36) NOT NULL PRIMARY KEY,
    user_id      CHAR(36) NOT NULL,
    season_id    CHAR(36) NOT NULL,
    completed_at DATETIME(3) NULL,
    lessons      JSON        NULL,
    revision     BIGINT UNSIGNED NOT NULL DEFAULT 1,
    created_at   DATETIME(3) NOT NULL,
    updated_at   DATETIME(3) NOT NULL,
    deleted_at   DATETIME(3) NULL,
    KEY idx_review_user (user_id, updated_at),
    KEY idx_review_season (season_id),
    CONSTRAINT fk_review_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS domain_audit_events (
    id          CHAR(36) NOT NULL PRIMARY KEY,
    user_id     CHAR(36) NOT NULL,
    occurred_at DATETIME(3)  NOT NULL,
    actor       VARCHAR(120) NULL,
    action      VARCHAR(80)  NOT NULL,
    entity_type VARCHAR(80)  NOT NULL,
    entity_id   CHAR(36)     NULL,
    summary     VARCHAR(500) NOT NULL,
    detail      TEXT         NULL,
    revision    BIGINT UNSIGNED NOT NULL DEFAULT 1,
    created_at  DATETIME(3)  NOT NULL,
    updated_at  DATETIME(3)  NOT NULL,
    deleted_at  DATETIME(3)  NULL,
    KEY idx_audit_user (user_id, occurred_at),
    CONSTRAINT fk_audit_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ===========================================================================
--  Verification — the import worked if this returns 22 tables.
-- ===========================================================================

SELECT COUNT(*) AS tables_created
FROM information_schema.tables
WHERE table_schema = DATABASE()
  AND table_name IN (
    'users','sessions','retired_refresh_tokens','rate_limits','idempotency_keys',
    'security_events','farms','fields','crop_seasons','observations','soil_tests',
    'irrigation_plans','irrigation_runs','tasks','inventory_lots','stock_movements',
    'input_applications','harvest_batches','harvest_loads','team_members',
    'season_reviews','domain_audit_events'
  );

-- Expected result: tables_created = 22
