<?php
declare(strict_types=1);

namespace GoldenAcres\Controllers;

use GoldenAcres\Core\ApiException;
use GoldenAcres\Core\Clock;
use GoldenAcres\Core\Config;
use GoldenAcres\Core\Database;
use GoldenAcres\Core\Ids;
use GoldenAcres\Core\RateLimiter;
use GoldenAcres\Core\Request;
use GoldenAcres\Core\Response;
use GoldenAcres\Core\Validator;
use GoldenAcres\Security\Passwords;
use GoldenAcres\Security\SecurityLog;
use GoldenAcres\Security\Tokens;

final class AuthController
{
    private const MAX_FAILED_LOGINS = 8;
    private const LOCK_MINUTES = 15;

    /** POST /v1/auth/register */
    public function register(Request $request): void
    {
        $ip = $request->clientIp();
        RateLimiter::hit("register:ip:{$ip}", Config::int('RL_REGISTER_PER_HOUR', 5), 3600, 3600);

        $body = $request->body();
        $validator = new Validator($body);
        $email = $validator->email('email');
        $displayName = $validator->string('display_name', false, 1, 120);
        $farmName = $validator->string('farm_name', false, 1, 160);
        $country = $validator->string('country', false, 1, 80);
        $unitSystem = $validator->enum('unit_system', ['metric', 'imperial'], false, 'metric');
        $currency = $validator->string('currency_code', false, 3, 3);
        $timeZone = $validator->string('time_zone', false, 1, 64);
        $password = is_string($body['password'] ?? null) ? $body['password'] : null;
        if ($password === null || $password === '') {
            $validator->fail('password', 'This field is required.');
        }
        $validator->assertValid();

        /** @var string $email */
        /** @var string $password */
        $localPart = explode('@', $email)[0];
        Passwords::assertStrong($password, array_filter([$localPart, $displayName]));

        if ($currency !== null && preg_match('/^[A-Za-z]{3}$/', $currency) !== 1) {
            throw ApiException::unprocessable('Some fields need attention.', [
                'currency_code' => 'Use a three-letter currency code.',
            ]);
        }
        if ($timeZone !== null && !in_array($timeZone, \DateTimeZone::listIdentifiers(), true)) {
            throw ApiException::unprocessable('Some fields need attention.', [
                'time_zone' => 'Unknown time zone identifier.',
            ]);
        }

        $canonical = mb_strtolower($email);
        $now = Clock::sql();
        $userId = Ids::uuid4();
        $hash = Passwords::hash($password);

        try {
            Database::execute(
                'INSERT INTO users
                    (id, email, email_canonical, password_hash, password_version, display_name,
                     farm_name, country, unit_system, currency_code, time_zone, status,
                     created_at, updated_at)
                 VALUES (?, ?, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
                [
                    $userId,
                    $email,
                    $canonical,
                    $hash,
                    $displayName,
                    $farmName,
                    $country,
                    $unitSystem ?? 'metric',
                    $currency !== null ? strtoupper($currency) : 'USD',
                    $timeZone ?? 'UTC',
                    'active',
                    $now,
                    $now,
                ]
            );
        } catch (\PDOException $e) {
            // 23000 = integrity constraint, i.e. the unique email index.
            if ($e->getCode() === '23000') {
                SecurityLog::record('auth.register', 'failure', null, $ip, $request->userAgent(), 'Email already registered.');
                throw ApiException::conflict('That email address cannot be used for a new account.');
            }
            throw $e;
        }

        $tokens = Tokens::createSession(
            $userId,
            1,
            $this->deviceName($request),
            $ip,
            $request->userAgent()
        );
        SecurityLog::record('auth.register', 'success', $userId, $ip, $request->userAgent());

        Response::ok([
            'user'   => $this->loadUser($userId),
            'tokens' => $this->tokenPayload($tokens),
        ], [], 201);
    }

    /** POST /v1/auth/login */
    public function login(Request $request): void
    {
        $ip = $request->clientIp();
        $body = $request->body();
        $validator = new Validator($body);
        $email = $validator->email('email');
        $password = is_string($body['password'] ?? null) ? $body['password'] : null;
        if ($password === null || $password === '') {
            $validator->fail('password', 'This field is required.');
        }
        $validator->assertValid();

        RateLimiter::hit("login:ip:{$ip}", Config::int('RL_LOGIN_PER_IP', 20), 900, 900);
        RateLimiter::hit('login:email:' . mb_strtolower((string) $email), Config::int('RL_LOGIN_PER_EMAIL', 10), 900, 900);

        $user = Database::selectOne(
            'SELECT id, email, password_hash, password_version, status, failed_login_count, locked_until
             FROM users WHERE email_canonical = ? LIMIT 1',
            [mb_strtolower((string) $email)]
        );

        // Same work and the same message whether or not the account exists.
        if ($user === null) {
            Passwords::burnEquivalentTime();
            SecurityLog::record('auth.login', 'failure', null, $ip, $request->userAgent(), 'Unknown email.');
            throw ApiException::unauthorized('Email or password is incorrect.');
        }

        if ($user['locked_until'] !== null
            && new \DateTimeImmutable($user['locked_until'], new \DateTimeZone('UTC')) > Clock::now()) {
            SecurityLog::record('auth.login', 'failure', $user['id'], $ip, $request->userAgent(), 'Account temporarily locked.');
            throw ApiException::tooManyRequests(
                'Too many failed attempts. Try again later.',
                max(1, (new \DateTimeImmutable($user['locked_until'], new \DateTimeZone('UTC')))->getTimestamp() - time())
            );
        }

        if (!Passwords::verify((string) $password, $user['password_hash'])) {
            $this->registerFailedLogin($user, $ip, $request->userAgent());
            throw ApiException::unauthorized('Email or password is incorrect.');
        }

        if ($user['status'] === 'locked') {
            throw ApiException::forbidden('This account is locked.');
        }
        if ($user['status'] === 'pending_deletion') {
            throw ApiException::forbidden('This account is scheduled for deletion.');
        }

        // Upgrade the stored hash if the cost parameters have moved on.
        if (Passwords::needsRehash($user['password_hash'])) {
            Database::execute(
                'UPDATE users SET password_hash = ?, updated_at = ? WHERE id = ?',
                [Passwords::hash((string) $password), Clock::sql(), $user['id']]
            );
        }

        Database::execute(
            'UPDATE users SET failed_login_count = 0, locked_until = NULL, last_login_at = ?, updated_at = ?
             WHERE id = ?',
            [Clock::sql(), Clock::sql(), $user['id']]
        );
        RateLimiter::clear('login:email:' . mb_strtolower((string) $email));

        $tokens = Tokens::createSession(
            $user['id'],
            (int) $user['password_version'],
            $this->deviceName($request),
            $ip,
            $request->userAgent()
        );
        SecurityLog::record('auth.login', 'success', $user['id'], $ip, $request->userAgent());

        Response::ok([
            'user'   => $this->loadUser($user['id']),
            'tokens' => $this->tokenPayload($tokens),
        ]);
    }

    /** POST /v1/auth/refresh */
    public function refresh(Request $request): void
    {
        $ip = $request->clientIp();
        RateLimiter::hit("refresh:ip:{$ip}", Config::int('RL_REFRESH_PER_HOUR', 120), 3600, 600);

        $body = $request->body();
        $refresh = is_string($body['refresh_token'] ?? null) ? trim($body['refresh_token']) : '';
        if ($refresh === '') {
            throw ApiException::unprocessable('Some fields need attention.', [
                'refresh_token' => 'This field is required.',
            ]);
        }

        $rotated = Tokens::rotate($refresh, $ip, $request->userAgent());
        SecurityLog::record('auth.refresh', 'success', $rotated['user_id'], $ip, $request->userAgent());

        Response::ok([
            'user'   => $this->loadUser($rotated['user_id']),
            'tokens' => $this->tokenPayload($rotated),
        ]);
    }

    /** POST /v1/auth/logout — ends the current session only. */
    public function logout(Request $request, array $context): void
    {
        Tokens::revokeSession($context['session']['id'], $context['user']['id'], 'logout');
        SecurityLog::record('auth.logout', 'success', $context['user']['id'], $request->clientIp(), $request->userAgent());
        Response::ok(['signed_out' => true]);
    }

    /** POST /v1/auth/logout-all — ends every session on every device. */
    public function logoutAll(Request $request, array $context): void
    {
        $count = Tokens::revokeAllSessions($context['user']['id'], 'logout_all');
        SecurityLog::record('auth.logout_all', 'success', $context['user']['id'], $request->clientIp(), $request->userAgent(), "Revoked {$count} session(s).");
        Response::ok(['signed_out' => true, 'sessions_revoked' => $count]);
    }

    // -----------------------------------------------------------------

    private function registerFailedLogin(array $user, string $ip, string $userAgent): void
    {
        $failures = (int) $user['failed_login_count'] + 1;
        $lockUntil = null;
        if ($failures >= self::MAX_FAILED_LOGINS) {
            $lockUntil = Clock::sql(Clock::now()->modify('+' . self::LOCK_MINUTES . ' minutes'));
            $failures = 0;
        }
        Database::execute(
            'UPDATE users SET failed_login_count = ?, locked_until = ?, updated_at = ? WHERE id = ?',
            [$failures, $lockUntil, Clock::sql(), $user['id']]
        );
        SecurityLog::record(
            'auth.login',
            'failure',
            $user['id'],
            $ip,
            $userAgent,
            $lockUntil !== null ? 'Wrong password; account locked temporarily.' : 'Wrong password.'
        );
    }

    private function deviceName(Request $request): ?string
    {
        $body = $request->body();
        $name = is_string($body['device_name'] ?? null) ? trim($body['device_name']) : '';
        if ($name !== '') {
            return mb_substr($name, 0, 120);
        }
        $header = $request->header('x-device-name');
        return $header !== null && trim($header) !== '' ? mb_substr(trim($header), 0, 120) : null;
    }

    private function tokenPayload(array $tokens): array
    {
        return [
            'access_token'       => $tokens['access_token'],
            'refresh_token'      => $tokens['refresh_token'],
            'token_type'         => 'Bearer',
            'expires_in'         => Tokens::accessTtl(),
            'access_expires_at'  => $tokens['access_expires_at'],
            'refresh_expires_at' => $tokens['refresh_expires_at'],
        ];
    }

    public static function presentUser(array $row): array
    {
        return [
            'id'            => $row['id'],
            'email'         => $row['email'],
            'display_name'  => $row['display_name'],
            'farm_name'     => $row['farm_name'],
            'country'       => $row['country'],
            'unit_system'   => $row['unit_system'],
            'currency_code' => $row['currency_code'],
            'time_zone'     => $row['time_zone'],
            'status'        => $row['status'],
            'created_at'    => Clock::iso($row['created_at']),
            'last_login_at' => Clock::iso($row['last_login_at'] ?? null),
        ];
    }

    private function loadUser(string $userId): array
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
        return self::presentUser($row);
    }
}
