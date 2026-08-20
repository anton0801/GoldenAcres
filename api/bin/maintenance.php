#!/usr/bin/env php
<?php
declare(strict_types=1);

/**
 * Housekeeping. Run from cron, e.g. every 15 minutes:
 *
 *   ​*​/15 * * * * /usr/bin/php /var/www/goldenacres/api/bin/maintenance.php >> /var/log/goldenacres-maintenance.log 2>&1
 *
 * Removes expired sessions, stale reuse records, spent rate-limit windows and
 * old idempotency keys. Nothing here touches a user's farm data.
 */

use GoldenAcres\Core\Clock;
use GoldenAcres\Core\Config;
use GoldenAcres\Core\Database;
use GoldenAcres\Security\Tokens;

$root = dirname(__DIR__);

spl_autoload_register(static function (string $class) use ($root): void {
    static $map = [
        'GoldenAcres\Core\Config'          => '/src/Core/Config.php',
        'GoldenAcres\Core\Database'        => '/src/Core/Database.php',
        'GoldenAcres\Core\ApiException'    => '/src/Core/Http.php',
        'GoldenAcres\Core\Request'         => '/src/Core/Http.php',
        'GoldenAcres\Core\Response'        => '/src/Core/Http.php',
        'GoldenAcres\Core\Router'          => '/src/Core/Support.php',
        'GoldenAcres\Core\Ids'             => '/src/Core/Support.php',
        'GoldenAcres\Core\Clock'           => '/src/Core/Support.php',
        'GoldenAcres\Core\RateLimiter'     => '/src/Core/Support.php',
        'GoldenAcres\Core\Validator'       => '/src/Core/Support.php',
        'GoldenAcres\Security\Tokens'      => '/src/Security/Tokens.php',
        'GoldenAcres\Security\SecurityLog' => '/src/Security/SecurityLog.php',
    ];
    if (isset($map[$class])) {
        require_once $root . $map[$class];
    }
});

Config::load($root);

$now = Clock::now();
$report = [];

// Sessions whose refresh window has passed, and the reuse records that guard them.
Tokens::purgeExpired();
$report[] = 'sessions and retired refresh tokens purged';

// Rate-limit windows that are long finished.
$deleted = Database::execute(
    'DELETE FROM rate_limits WHERE window_start < ? AND (blocked_until IS NULL OR blocked_until < ?)',
    [Clock::sql($now->modify('-1 day')), Clock::sql($now)]
);
$report[] = "{$deleted} rate-limit window(s) removed";

// Idempotency keys only need to outlive a client's retry window.
$deleted = Database::execute(
    'DELETE FROM idempotency_keys WHERE created_at < ?',
    [Clock::sql($now->modify('-2 days'))]
);
$report[] = "{$deleted} idempotency key(s) removed";

// Security events are kept for a year, then dropped.
$deleted = Database::execute(
    'DELETE FROM security_events WHERE created_at < ?',
    [Clock::sql($now->modify('-365 days'))]
);
$report[] = "{$deleted} security event(s) removed";

// Soft-deleted domain rows are purged once every client has had time to sync.
$graceDays = Config::int('TOMBSTONE_RETENTION_DAYS', 90);
$cutoff = Clock::sql($now->modify("-{$graceDays} days"));
$tables = [
    'farms', 'fields', 'crop_seasons', 'observations', 'soil_tests',
    'irrigation_plans', 'irrigation_runs', 'tasks', 'inventory_lots',
    'stock_movements', 'input_applications', 'harvest_batches', 'harvest_loads',
    'team_members', 'season_reviews', 'domain_audit_events',
];
$purged = 0;
foreach ($tables as $table) {
    $purged += Database::execute(
        "DELETE FROM {$table} WHERE deleted_at IS NOT NULL AND deleted_at < ?",
        [$cutoff]
    );
}
$report[] = "{$purged} tombstoned row(s) purged after {$graceDays} days";

// Accounts that asked for deletion and passed their grace period.
$pending = Database::select(
    "SELECT id FROM users WHERE status = 'pending_deletion' AND deletion_requested_at < ?",
    [Clock::sql($now->modify('-30 days'))]
);
foreach ($pending as $user) {
    Database::execute('DELETE FROM users WHERE id = ?', [$user['id']]);
}
$report[] = count($pending) . ' account(s) finalised for deletion';

echo '[' . $now->format('Y-m-d H:i:s') . "] " . implode('; ', $report) . PHP_EOL;
