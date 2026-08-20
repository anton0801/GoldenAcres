<?php
declare(strict_types=1);

namespace GoldenAcres\Core;

/**
 * Configuration loaded from a .env file or the real environment.
 *
 * Secrets never have a usable default: if APP_PEPPER is missing in production
 * the application refuses to boot rather than silently running with a weak one.
 */
final class Config
{
    private static array $values = [];
    private static bool $loaded = false;

    public static function load(string $rootDir): void
    {
        if (self::$loaded) {
            return;
        }

        // Prefer a .env kept one level above the document root: on shared
        // hosting that puts the secrets physically outside anything the web
        // server can serve, even if a rewrite rule is later broken.
        $envFile = null;
        foreach ([dirname($rootDir) . '/.env', $rootDir . '/.env'] as $candidate) {
            if (is_readable($candidate)) {
                $envFile = $candidate;
                break;
            }
        }

        if ($envFile !== null) {
            foreach (file($envFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
                $line = trim($line);
                if ($line === '' || str_starts_with($line, '#')) {
                    continue;
                }
                $parts = explode('=', $line, 2);
                if (count($parts) !== 2) {
                    continue;
                }
                $key = trim($parts[0]);
                $value = trim($parts[1]);
                // Strip surrounding quotes if present.
                if (strlen($value) >= 2
                    && ($value[0] === '"' || $value[0] === "'")
                    && $value[strlen($value) - 1] === $value[0]) {
                    $value = substr($value, 1, -1);
                }
                self::$values[$key] = $value;
            }
        }

        // Real environment wins over the file.
        foreach ($_ENV as $key => $value) {
            if (is_string($value)) {
                self::$values[$key] = $value;
            }
        }
        foreach ($_SERVER as $key => $value) {
            if (is_string($value) && str_starts_with($key, 'GA_')) {
                self::$values[substr($key, 3)] = $value;
            }
        }

        self::$loaded = true;
    }

    public static function get(string $key, ?string $default = null): ?string
    {
        return self::$values[$key] ?? $default;
    }

    public static function require(string $key): string
    {
        $value = self::$values[$key] ?? null;
        if ($value === null || $value === '') {
            throw new \RuntimeException("Missing required configuration: {$key}");
        }
        return $value;
    }

    public static function int(string $key, int $default): int
    {
        $value = self::$values[$key] ?? null;
        return $value === null || $value === '' ? $default : (int) $value;
    }

    public static function bool(string $key, bool $default): bool
    {
        $value = self::$values[$key] ?? null;
        if ($value === null || $value === '') {
            return $default;
        }
        return in_array(strtolower($value), ['1', 'true', 'yes', 'on'], true);
    }

    public static function isProduction(): bool
    {
        return strtolower(self::get('APP_ENV', 'production') ?? 'production') === 'production';
    }

    /**
     * Extra secret mixed into passwords before hashing. Kept outside the
     * database so a database-only leak cannot be cracked offline.
     */
    public static function pepper(): string
    {
        $pepper = self::get('APP_PEPPER', '');
        if (($pepper === null || $pepper === '') && self::isProduction()) {
            throw new \RuntimeException('APP_PEPPER must be set in production.');
        }
        return $pepper ?? '';
    }
}
