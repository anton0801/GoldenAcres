<?php
declare(strict_types=1);

namespace GoldenAcres\Controllers;

use GoldenAcres\Core\ApiException;
use GoldenAcres\Core\Clock;
use GoldenAcres\Core\Config;
use GoldenAcres\Core\Database;
use GoldenAcres\Core\RateLimiter;
use GoldenAcres\Core\Request;
use GoldenAcres\Core\Response;
use GoldenAcres\Core\Validator;
use GoldenAcres\Domain\ResourceRegistry;
use GoldenAcres\Security\Passwords;
use GoldenAcres\Security\SecurityLog;
use GoldenAcres\Security\Tokens;

final class AccountController
{
    /** GET /v1/me */
    public function show(Request $request, array $context): void
    {
        Response::ok(['user' => $this->load($context['user']['id'])]);
    }

    /** PATCH /v1/me — profile fields only; email and password have their own endpoints. */
    public function update(Request $request, array $context): void
    {
        $userId = $context['user']['id'];
        $body = $request->body();
        $validator = new Validator($body);

        $updates = [];
        if ($validator->has('display_name')) {
            $updates['display_name'] = $validator->string('display_name', false, 1, 120);
        }
        if ($validator->has('farm_name')) {
            $updates['farm_name'] = $validator->string('farm_name', false, 1, 160);
        }
        if ($validator->has('country')) {
            $updates['country'] = $validator->string('country', false, 1, 80);
        }
        if ($validator->has('unit_system')) {
            $updates['unit_system'] = $validator->enum('unit_system', ['metric', 'imperial'], true);
        }
        if ($validator->has('currency_code')) {
            $code = $validator->string('currency_code', true, 3, 3);
            if ($code !== null && preg_match('/^[A-Za-z]{3}$/', $code) !== 1) {
                $validator->fail('currency_code', 'Use a three-letter currency code.');
            }
            $updates['currency_code'] = $code !== null ? strtoupper($code) : null;
        }
        if ($validator->has('time_zone')) {
            $zone = $validator->string('time_zone', true, 1, 64);
            if ($zone !== null && !in_array($zone, \DateTimeZone::listIdentifiers(), true)) {
                $validator->fail('time_zone', 'Unknown time zone identifier.');
            }
            $updates['time_zone'] = $zone;
        }
        $validator->assertValid();

        if ($updates === []) {
            throw ApiException::badRequest('No supported fields were supplied.');
        }

        $assignments = [];
        $params = [];
        foreach ($updates as $column => $value) {
            $assignments[] = "{$column} = ?";
            $params[] = $value;
        }
        $assignments[] = 'updated_at = ?';
        $params[] = Clock::sql();
        $params[] = $userId;

        Database::execute(
            'UPDATE users SET ' . implode(', ', $assignments) . ' WHERE id = ?',
            $params
        );
        SecurityLog::record('account.update', 'success', $userId, $request->clientIp(), $request->userAgent(),
            'Fields: ' . implode(', ', array_keys($updates)));

        Response::ok(['user' => $this->load($userId)]);
    }

    /** POST /v1/me/password — requires the current password; revokes other sessions. */
    public function changePassword(Request $request, array $context): void
    {
        $userId = $context['user']['id'];
        $ip = $request->clientIp();
        RateLimiter::hit("password:user:{$userId}", 5, 3600, 900);

        $body = $request->body();
        $current = is_string($body['current_password'] ?? null) ? $body['current_password'] : '';
        $next = is_string($body['new_password'] ?? null) ? $body['new_password'] : '';

        $errors = [];
        if ($current === '') {
            $errors['current_password'] = 'This field is required.';
        }
        if ($next === '') {
            $errors['new_password'] = 'This field is required.';
        }
        if ($errors !== []) {
            throw ApiException::unprocessable('Some fields need attention.', $errors);
        }

        $row = Database::selectOne(
            'SELECT password_hash, password_version, email, display_name FROM users WHERE id = ?',
            [$userId]
        );
        if ($row === null) {
            throw ApiException::notFound('Account not found.');
        }
        if (!Passwords::verify($current, $row['password_hash'])) {
            SecurityLog::record('account.password_change', 'failure', $userId, $ip, $request->userAgent(), 'Current password incorrect.');
            throw ApiException::unprocessable('Some fields need attention.', [
                'current_password' => 'That is not your current password.',
            ]);
        }
        if (hash_equals($current, $next)) {
            throw ApiException::unprocessable('Some fields need attention.', [
                'new_password' => 'Choose a password you have not used here before.',
            ]);
        }

        Passwords::assertStrong($next, array_filter([
            explode('@', (string) $row['email'])[0],
            $row['display_name'],
        ]));

        $newVersion = (int) $row['password_version'] + 1;
        Database::transaction(static function () use ($userId, $next, $newVersion, $context): void {
            Database::execute(
                'UPDATE users SET password_hash = ?, password_version = ?, updated_at = ? WHERE id = ?',
                [Passwords::hash($next), $newVersion, Clock::sql(), $userId]
            );
            // Every other device is signed out; this one keeps working.
            Tokens::revokeAllSessions($userId, 'password_changed', $context['session']['id']);
            Database::execute(
                'UPDATE sessions SET password_version = ? WHERE id = ?',
                [$newVersion, $context['session']['id']]
            );
        });

        SecurityLog::record('account.password_change', 'success', $userId, $ip, $request->userAgent(), 'Other sessions revoked.');
        Response::ok(['password_changed' => true, 'other_sessions_revoked' => true]);
    }

    /** GET /v1/me/sessions — every signed-in device. */
    public function sessions(Request $request, array $context): void
    {
        $rows = Database::select(
            'SELECT id, device_name, ip_address, user_agent, created_at, last_used_at,
                    access_expires_at, refresh_expires_at
             FROM sessions
             WHERE user_id = ? AND revoked_at IS NULL AND refresh_expires_at > ?
             ORDER BY last_used_at DESC',
            [$context['user']['id'], Clock::sql()]
        );

        $currentId = $context['session']['id'];
        Response::ok([
            'sessions' => array_map(static fn (array $row): array => [
                'id'                 => $row['id'],
                'device_name'        => $row['device_name'],
                'ip_address'         => Tokens::unpackIp($row['ip_address']),
                'user_agent'         => $row['user_agent'],
                'created_at'         => Clock::iso($row['created_at']),
                'last_used_at'       => Clock::iso($row['last_used_at']),
                'refresh_expires_at' => Clock::iso($row['refresh_expires_at']),
                'is_current'         => $row['id'] === $currentId,
            ], $rows),
        ]);
    }

    /** DELETE /v1/me/sessions/{id} — sign a single device out. */
    public function revokeSession(Request $request, array $context, array $params): void
    {
        $sessionId = $params['id'] ?? '';
        $exists = Database::selectOne(
            'SELECT id FROM sessions WHERE id = ? AND user_id = ? AND revoked_at IS NULL',
            [$sessionId, $context['user']['id']]
        );
        if ($exists === null) {
            throw ApiException::notFound('Session not found.');
        }
        Tokens::revokeSession($sessionId, $context['user']['id'], 'revoked_by_user');
        SecurityLog::record('account.session_revoked', 'success', $context['user']['id'],
            $request->clientIp(), $request->userAgent());
        Response::noContent();
    }

    /** GET /v1/me/security-events */
    public function securityEvents(Request $request, array $context): void
    {
        Response::ok(['events' => SecurityLog::recentForUser($context['user']['id'], $request->queryInt('limit', 25))]);
    }

    /**
     * DELETE /v1/me — deletes the account and every record it owns.
     *
     * Requires the password and an explicit confirmation string, so a stolen
     * access token alone cannot destroy someone's data.
     */
    public function destroy(Request $request, array $context): void
    {
        $userId = $context['user']['id'];
        $ip = $request->clientIp();
        RateLimiter::hit("delete:user:{$userId}", 5, 3600, 3600);

        $body = $request->body();
        $password = is_string($body['password'] ?? null) ? $body['password'] : '';
        $confirm = is_string($body['confirm'] ?? null) ? trim($body['confirm']) : '';

        $errors = [];
        if ($password === '') {
            $errors['password'] = 'Enter your password to confirm.';
        }
        if (strtoupper($confirm) !== 'DELETE') {
            $errors['confirm'] = 'Type DELETE to confirm.';
        }
        if ($errors !== []) {
            throw ApiException::unprocessable('Some fields need attention.', $errors);
        }

        $row = Database::selectOne('SELECT password_hash, email FROM users WHERE id = ?', [$userId]);
        if ($row === null) {
            throw ApiException::notFound('Account not found.');
        }
        if (!Passwords::verify($password, $row['password_hash'])) {
            SecurityLog::record('account.delete', 'failure', $userId, $ip, $request->userAgent(), 'Wrong password.');
            throw ApiException::unprocessable('Some fields need attention.', [
                'password' => 'That is not your password.',
            ]);
        }

        // Count what will go, so the response can state it plainly.
        $counts = [];
        foreach (ResourceRegistry::tables() as $table) {
            $result = Database::selectOne("SELECT COUNT(*) AS c FROM {$table} WHERE user_id = ?", [$userId]);
            $count = (int) ($result['c'] ?? 0);
            if ($count > 0) {
                $counts[$table] = $count;
            }
        }

        Database::transaction(static function () use ($userId): void {
            Tokens::revokeAllSessions($userId, 'account_deleted');
            // Domain rows and sessions are removed by ON DELETE CASCADE.
            Database::execute('DELETE FROM users WHERE id = ?', [$userId]);
        });

        // Logged without a user id, since the row is gone.
        SecurityLog::record('account.delete', 'success', null, $ip, $request->userAgent(),
            'Account deleted. Removed: ' . (json_encode($counts) ?: '{}'));

        Response::ok([
            'deleted'         => true,
            'records_removed' => $counts,
            'message'         => 'The account and all of its records have been permanently removed.',
        ]);
    }

    private function load(string $userId): array
    {
        $row = Database::selectOne(
            'SELECT id, email, display_name, farm_name, country, unit_system, currency_code,
                    time_zone, status, created_at, last_login_at
             FROM users WHERE id = ? LIMIT 1',
            [$userId]
        );
        if ($row === null) {
            throw ApiException::notFound('Account not found.');
        }
        return AuthController::presentUser($row);
    }
}
