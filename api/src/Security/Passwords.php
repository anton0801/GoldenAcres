<?php
declare(strict_types=1);

namespace GoldenAcres\Security;

use GoldenAcres\Core\ApiException;
use GoldenAcres\Core\Config;

/**
 * Argon2id password hashing with a server-side pepper.
 *
 * The pepper is HMAC'd into the password before hashing, so a stolen database
 * alone is not enough to mount an offline cracking attack — the attacker also
 * needs the application secret, which never lives in the database.
 */
final class Passwords
{
    private const MIN_LENGTH = 10;
    private const MAX_LENGTH = 200;

    /** A short list of the passwords attackers try first. */
    private const FORBIDDEN = [
        'password', 'password1', 'password123', '12345678', '123456789', '1234567890',
        'qwertyuiop', 'letmein123', 'welcome123', 'admin12345', 'iloveyou1',
        'goldenacres', 'changeme123', 'passw0rd!', 'qwerty12345',
    ];

    public static function hash(string $plain): string
    {
        $hash = password_hash(self::prepare($plain), PASSWORD_ARGON2ID, self::options());
        if (!is_string($hash) || $hash === '') {
            throw new \RuntimeException('Password hashing failed.');
        }
        return $hash;
    }

    public static function verify(string $plain, string $hash): bool
    {
        return password_verify(self::prepare($plain), $hash);
    }

    public static function needsRehash(string $hash): bool
    {
        return password_needs_rehash($hash, PASSWORD_ARGON2ID, self::options());
    }

    /**
     * Burns roughly the same CPU as a real verification. Used on the
     * login path when the account does not exist, so response timing does not
     * reveal whether an email is registered.
     */
    public static function burnEquivalentTime(): void
    {
        static $dummy = null;
        if ($dummy === null) {
            $dummy = password_hash('timing-equalisation-placeholder', PASSWORD_ARGON2ID, self::options());
        }
        password_verify('timing-equalisation-placeholder-x', $dummy);
    }

    /**
     * @throws ApiException when the password does not meet the policy.
     */
    public static function assertStrong(string $plain, array $context = []): void
    {
        $length = mb_strlen($plain);
        if ($length < self::MIN_LENGTH) {
            throw ApiException::unprocessable('Some fields need attention.', [
                'password' => 'Use at least ' . self::MIN_LENGTH . ' characters.',
            ]);
        }
        if ($length > self::MAX_LENGTH) {
            throw ApiException::unprocessable('Some fields need attention.', [
                'password' => 'Use at most ' . self::MAX_LENGTH . ' characters.',
            ]);
        }

        $normalized = strtolower($plain);
        foreach (self::FORBIDDEN as $forbidden) {
            if ($normalized === $forbidden) {
                throw ApiException::unprocessable('Some fields need attention.', [
                    'password' => 'That password is too common. Choose something else.',
                ]);
            }
        }

        // Must not contain the email local part or the display name.
        foreach ($context as $value) {
            if (!is_string($value) || mb_strlen($value) < 4) {
                continue;
            }
            if (str_contains($normalized, strtolower($value))) {
                throw ApiException::unprocessable('Some fields need attention.', [
                    'password' => 'Do not include your name or email in the password.',
                ]);
            }
        }

        // A single repeated character is long but worthless.
        if (preg_match('/^(.)\1+$/u', $plain) === 1) {
            throw ApiException::unprocessable('Some fields need attention.', [
                'password' => 'Use a mix of characters.',
            ]);
        }

        // Shorter passwords must mix character classes; long passphrases need not.
        if ($length < 16) {
            $classes = 0;
            $classes += preg_match('/[a-z]/u', $plain) === 1 ? 1 : 0;
            $classes += preg_match('/[A-Z]/u', $plain) === 1 ? 1 : 0;
            $classes += preg_match('/[0-9]/u', $plain) === 1 ? 1 : 0;
            $classes += preg_match('/[^a-zA-Z0-9]/u', $plain) === 1 ? 1 : 0;
            if ($classes < 3) {
                throw ApiException::unprocessable('Some fields need attention.', [
                    'password' => 'Use at least three of: lowercase, uppercase, digits, symbols — or a passphrase of 16+ characters.',
                ]);
            }
        }
    }

    private static function prepare(string $plain): string
    {
        $pepper = Config::pepper();
        // HMAC first so the Argon2 input is a fixed length and the pepper is
        // mixed in cryptographically rather than concatenated.
        return $pepper === ''
            ? $plain
            : hash_hmac('sha256', $plain, $pepper);
    }

    private static function options(): array
    {
        return [
            'memory_cost' => Config::int('ARGON_MEMORY_KIB', 65536), // 64 MiB
            'time_cost'   => Config::int('ARGON_TIME_COST', 3),
            'threads'     => Config::int('ARGON_THREADS', 2),
        ];
    }
}
