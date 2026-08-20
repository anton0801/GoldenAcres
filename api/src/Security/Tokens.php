<?php
declare(strict_types=1);

namespace GoldenAcres\Security;

use GoldenAcres\Core\ApiException;
use GoldenAcres\Core\Clock;
use GoldenAcres\Core\Config;
use GoldenAcres\Core\Database;
use GoldenAcres\Core\Ids;

/**
 * Opaque bearer tokens.
 *
 * Only SHA-256 hashes are stored, so a database leak yields nothing that can
 * be replayed. Access tokens are short-lived; refresh tokens rotate on every
 * use and a replayed refresh token revokes the whole session (theft detection).
 */
final class Tokens
{
    public const ACCESS_PREFIX  = 'gaa_';
    public const REFRESH_PREFIX = 'gar_';

    public static function accessTtl(): int
    {
        return Config::int('ACCESS_TOKEN_TTL', 3600);
    }

    public static function refreshTtl(): int
    {
        return Config::int('REFRESH_TOKEN_TTL', 2592000); // 30 days
    }

    private static function generate(string $prefix): string
    {
        return $prefix . rtrim(strtr(base64_encode(random_bytes(32)), '+/', '-_'), '=');
    }

    public static function fingerprint(string $token): string
    {
        return hash('sha256', $token);
    }

    /**
     * Issues a brand-new session for a user (sign-in).
     *
     * @return array{session_id:string, access_token:string, refresh_token:string, access_expires_at:string, refresh_expires_at:string}
     */
    public static function createSession(
        string $userId,
        int $passwordVersion,
        ?string $deviceName,
        string $ip,
        string $userAgent
    ): array {
        $now = Clock::now();
        $sessionId = Ids::uuid4();
        $access = self::generate(self::ACCESS_PREFIX);
        $refresh = self::generate(self::REFRESH_PREFIX);
        $accessExpires = $now->modify('+' . self::accessTtl() . ' seconds');
        $refreshExpires = $now->modify('+' . self::refreshTtl() . ' seconds');

        Database::execute(
            'INSERT INTO sessions
                (id, user_id, access_token_hash, refresh_token_hash, access_expires_at,
                 refresh_expires_at, password_version, device_name, ip_address, user_agent,
                 created_at, last_used_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [
                $sessionId,
                $userId,
                self::fingerprint($access),
                self::fingerprint($refresh),
                Clock::sql($accessExpires),
                Clock::sql($refreshExpires),
                $passwordVersion,
                $deviceName !== null ? mb_substr($deviceName, 0, 120) : null,
                self::packIp($ip),
                $userAgent !== '' ? $userAgent : null,
                Clock::sql($now),
                Clock::sql($now),
            ]
        );

        return [
            'session_id'         => $sessionId,
            'access_token'       => $access,
            'refresh_token'      => $refresh,
            'access_expires_at'  => Clock::iso(Clock::sql($accessExpires)) ?? '',
            'refresh_expires_at' => Clock::iso(Clock::sql($refreshExpires)) ?? '',
        ];
    }

    /**
     * Resolves an access token to its user, or throws 401.
     *
     * @return array{user:array, session:array}
     */
    public static function authenticate(string $token): array
    {
        if (!str_starts_with($token, self::ACCESS_PREFIX)) {
            throw ApiException::unauthorized('Invalid access token.');
        }

        $row = Database::selectOne(
            'SELECT s.id AS session_id, s.user_id, s.access_expires_at, s.revoked_at,
                    s.password_version AS session_password_version,
                    u.id AS uid, u.email, u.display_name, u.farm_name, u.country,
                    u.unit_system, u.currency_code, u.time_zone, u.status,
                    u.password_version, u.created_at AS user_created_at,
                    u.last_login_at, u.deletion_requested_at
             FROM sessions s
             INNER JOIN users u ON u.id = s.user_id
             WHERE s.access_token_hash = ?
             LIMIT 1',
            [self::fingerprint($token)]
        );

        if ($row === null) {
            throw ApiException::unauthorized('Invalid or expired access token.');
        }
        if ($row['revoked_at'] !== null) {
            throw ApiException::unauthorized('This session has been signed out.');
        }
        if ($row['access_expires_at'] === null
            || new \DateTimeImmutable($row['access_expires_at'], new \DateTimeZone('UTC')) <= Clock::now()) {
            throw ApiException::unauthorized('Access token has expired.');
        }
        // A password change invalidates every token issued before it.
        if ((int) $row['session_password_version'] !== (int) $row['password_version']) {
            throw ApiException::unauthorized('Credentials changed. Sign in again.');
        }
        if ($row['status'] === 'locked') {
            throw ApiException::forbidden('This account is locked.');
        }
        if ($row['status'] === 'pending_deletion') {
            throw ApiException::forbidden('This account is scheduled for deletion.');
        }

        Database::execute(
            'UPDATE sessions SET last_used_at = ? WHERE id = ?',
            [Clock::sql(), $row['session_id']]
        );

        return [
            'user' => [
                'id'            => $row['uid'],
                'email'         => $row['email'],
                'display_name'  => $row['display_name'],
                'farm_name'     => $row['farm_name'],
                'country'       => $row['country'],
                'unit_system'   => $row['unit_system'],
                'currency_code' => $row['currency_code'],
                'time_zone'     => $row['time_zone'],
                'status'        => $row['status'],
                'created_at'    => $row['user_created_at'],
                'last_login_at' => $row['last_login_at'],
            ],
            'session' => [
                'id' => $row['session_id'],
            ],
        ];
    }

    /**
     * Rotates a refresh token. Replaying an already-rotated token is treated
     * as theft: the session is revoked immediately.
     *
     * @return array{session_id:string, user_id:string, access_token:string, refresh_token:string, access_expires_at:string, refresh_expires_at:string}
     */
    public static function rotate(string $refreshToken, string $ip, string $userAgent): array
    {
        if (!str_starts_with($refreshToken, self::REFRESH_PREFIX)) {
            throw ApiException::unauthorized('Invalid refresh token.');
        }
        $hash = self::fingerprint($refreshToken);

        // Reuse detection runs *outside* a transaction on purpose: it ends in a
        // thrown 401, and a rollback would undo the very revocation that makes
        // the detection worth having.
        $retired = Database::selectOne(
            'SELECT session_id, user_id FROM retired_refresh_tokens WHERE token_hash = ?',
            [$hash]
        );
        if ($retired !== null) {
            Database::execute(
                "UPDATE sessions
                    SET revoked_at = ?, revoked_reason = 'refresh_reuse',
                        access_token_hash = NULL, refresh_token_hash = NULL
                  WHERE id = ? AND revoked_at IS NULL",
                [Clock::sql(), $retired['session_id']]
            );
            SecurityLog::record(
                'auth.refresh_reuse',
                'failure',
                $retired['user_id'],
                $ip,
                $userAgent,
                'Rotated refresh token replayed; session revoked.'
            );
            throw ApiException::unauthorized('This session is no longer valid. Sign in again.');
        }

        return Database::transaction(static function () use ($hash, $ip, $userAgent): array {
            $session = Database::selectOne(
                'SELECT s.id, s.user_id, s.refresh_expires_at, s.revoked_at, s.password_version,
                        u.password_version AS current_password_version, u.status
                 FROM sessions s
                 INNER JOIN users u ON u.id = s.user_id
                 WHERE s.refresh_token_hash = ?
                 FOR UPDATE',
                [$hash]
            );

            if ($session === null) {
                throw ApiException::unauthorized('Invalid refresh token.');
            }
            if ($session['revoked_at'] !== null) {
                throw ApiException::unauthorized('This session has been signed out.');
            }
            if (new \DateTimeImmutable($session['refresh_expires_at'], new \DateTimeZone('UTC')) <= Clock::now()) {
                throw ApiException::unauthorized('Session expired. Sign in again.');
            }
            if ((int) $session['password_version'] !== (int) $session['current_password_version']) {
                throw ApiException::unauthorized('Credentials changed. Sign in again.');
            }
            if ($session['status'] !== 'active') {
                throw ApiException::forbidden('This account is not active.');
            }

            $now = Clock::now();
            $newAccess = self::generate(self::ACCESS_PREFIX);
            $newRefresh = self::generate(self::REFRESH_PREFIX);
            $accessExpires = $now->modify('+' . self::accessTtl() . ' seconds');
            $refreshExpires = $now->modify('+' . self::refreshTtl() . ' seconds');

            Database::execute(
                'INSERT INTO retired_refresh_tokens (token_hash, session_id, user_id, retired_at)
                 VALUES (?, ?, ?, ?)',
                [$hash, $session['id'], $session['user_id'], Clock::sql($now)]
            );

            Database::execute(
                'UPDATE sessions
                    SET access_token_hash = ?, refresh_token_hash = ?,
                        access_expires_at = ?, refresh_expires_at = ?,
                        last_used_at = ?, ip_address = ?, user_agent = ?
                  WHERE id = ?',
                [
                    self::fingerprint($newAccess),
                    self::fingerprint($newRefresh),
                    Clock::sql($accessExpires),
                    Clock::sql($refreshExpires),
                    Clock::sql($now),
                    self::packIp($ip),
                    $userAgent !== '' ? $userAgent : null,
                    $session['id'],
                ]
            );

            return [
                'session_id'         => $session['id'],
                'user_id'            => $session['user_id'],
                'access_token'       => $newAccess,
                'refresh_token'      => $newRefresh,
                'access_expires_at'  => Clock::iso(Clock::sql($accessExpires)) ?? '',
                'refresh_expires_at' => Clock::iso(Clock::sql($refreshExpires)) ?? '',
            ];
        });
    }

    public static function revokeSession(string $sessionId, string $userId, string $reason): void
    {
        Database::execute(
            'UPDATE sessions SET revoked_at = ?, revoked_reason = ?, access_token_hash = NULL,
                    refresh_token_hash = NULL
             WHERE id = ? AND user_id = ? AND revoked_at IS NULL',
            [Clock::sql(), $reason, $sessionId, $userId]
        );
    }

    public static function revokeAllSessions(string $userId, string $reason, ?string $exceptSessionId = null): int
    {
        $sql = 'UPDATE sessions SET revoked_at = ?, revoked_reason = ?, access_token_hash = NULL,
                       refresh_token_hash = NULL
                WHERE user_id = ? AND revoked_at IS NULL';
        $params = [Clock::sql(), $reason, $userId];
        if ($exceptSessionId !== null) {
            $sql .= ' AND id <> ?';
            $params[] = $exceptSessionId;
        }
        return Database::execute($sql, $params);
    }

    /** Housekeeping: drop expired sessions and stale reuse records. */
    public static function purgeExpired(): void
    {
        Database::execute('DELETE FROM sessions WHERE refresh_expires_at < ?', [Clock::sql()]);
        Database::execute(
            'DELETE FROM retired_refresh_tokens WHERE retired_at < ?',
            [Clock::sql(Clock::now()->modify('-60 days'))]
        );
    }

    private static function packIp(string $ip): ?string
    {
        $packed = @inet_pton($ip);
        return $packed === false ? null : $packed;
    }

    public static function unpackIp(?string $packed): ?string
    {
        if ($packed === null || $packed === '') {
            return null;
        }
        $ip = @inet_ntop($packed);
        return $ip === false ? null : $ip;
    }
}
