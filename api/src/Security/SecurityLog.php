<?php
declare(strict_types=1);

namespace GoldenAcres\Security;

use GoldenAcres\Core\Clock;
use GoldenAcres\Core\Database;
use GoldenAcres\Core\Ids;

/**
 * Append-only record of security-relevant events (sign-in, failures, token
 * reuse, password changes, deletions). Never contains passwords or tokens.
 */
final class SecurityLog
{
    public static function record(
        string $event,
        string $outcome,
        ?string $userId,
        string $ip,
        string $userAgent,
        ?string $detail = null
    ): void {
        try {
            Database::execute(
                'INSERT INTO security_events (id, user_id, event, outcome, ip_address, user_agent, detail, created_at)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
                [
                    Ids::uuid4(),
                    $userId,
                    mb_substr($event, 0, 64),
                    $outcome === 'success' ? 'success' : 'failure',
                    @inet_pton($ip) ?: null,
                    $userAgent !== '' ? mb_substr($userAgent, 0, 255) : null,
                    $detail !== null ? mb_substr($detail, 0, 500) : null,
                    Clock::sql(),
                ]
            );
        } catch (\Throwable) {
            // Logging must never break the request it is describing.
        }
    }

    /** @return array<int, array<string, mixed>> */
    public static function recentForUser(string $userId, int $limit = 25): array
    {
        $limit = max(1, min($limit, 100));
        $rows = Database::select(
            'SELECT event, outcome, ip_address, user_agent, detail, created_at
             FROM security_events WHERE user_id = ?
             ORDER BY created_at DESC LIMIT ' . $limit,
            [$userId]
        );
        return array_map(static fn (array $row): array => [
            'event'      => $row['event'],
            'outcome'    => $row['outcome'],
            'ip_address' => Tokens::unpackIp($row['ip_address']),
            'user_agent' => $row['user_agent'],
            'detail'     => $row['detail'],
            'created_at' => Clock::iso($row['created_at']),
        ], $rows);
    }
}
