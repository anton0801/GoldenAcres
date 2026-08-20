<?php
declare(strict_types=1);

namespace GoldenAcres\Core;

final class Router
{
    /** @var array<int, array{method:string, regex:string, params:string[], handler:callable, auth:bool}> */
    private array $routes = [];

    public function add(string $method, string $pattern, callable $handler, bool $auth = true): void
    {
        $params = [];
        $regex = preg_replace_callback(
            '/\{([a-zA-Z_][a-zA-Z0-9_]*)\}/',
            static function (array $m) use (&$params): string {
                $params[] = $m[1];
                return '([^/]+)';
            },
            $pattern
        );
        $this->routes[] = [
            'method'  => strtoupper($method),
            'regex'   => '#^' . $regex . '$#',
            'params'  => $params,
            'handler' => $handler,
            'auth'    => $auth,
        ];
    }

    public function get(string $p, callable $h, bool $auth = true): void { $this->add('GET', $p, $h, $auth); }
    public function post(string $p, callable $h, bool $auth = true): void { $this->add('POST', $p, $h, $auth); }
    public function patch(string $p, callable $h, bool $auth = true): void { $this->add('PATCH', $p, $h, $auth); }
    public function put(string $p, callable $h, bool $auth = true): void { $this->add('PUT', $p, $h, $auth); }
    public function delete(string $p, callable $h, bool $auth = true): void { $this->add('DELETE', $p, $h, $auth); }

    /**
     * @return array{handler:callable, params:array<string,string>, auth:bool}
     */
    public function match(string $method, string $path): array
    {
        $pathMatched = false;
        foreach ($this->routes as $route) {
            if (preg_match($route['regex'], $path, $matches) !== 1) {
                continue;
            }
            $pathMatched = true;
            if ($route['method'] !== $method) {
                continue;
            }
            array_shift($matches);
            $params = [];
            foreach ($route['params'] as $index => $name) {
                $params[$name] = $matches[$index] ?? '';
            }
            return ['handler' => $route['handler'], 'params' => $params, 'auth' => $route['auth']];
        }

        if ($pathMatched) {
            throw new ApiException(405, 'method_not_allowed', 'That method is not allowed on this endpoint.');
        }
        throw ApiException::notFound('No endpoint matches this path.');
    }
}

final class Ids
{
    public static function uuid4(): string
    {
        $bytes = random_bytes(16);
        $bytes[6] = chr((ord($bytes[6]) & 0x0f) | 0x40);
        $bytes[8] = chr((ord($bytes[8]) & 0x3f) | 0x80);
        $hex = bin2hex($bytes);
        return sprintf(
            '%s-%s-%s-%s-%s',
            substr($hex, 0, 8),
            substr($hex, 8, 4),
            substr($hex, 12, 4),
            substr($hex, 16, 4),
            substr($hex, 20, 12)
        );
    }

    public static function isUuid(string $value): bool
    {
        return preg_match(
            '/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i',
            $value
        ) === 1;
    }
}

final class Clock
{
    public static function now(): \DateTimeImmutable
    {
        return new \DateTimeImmutable('now', new \DateTimeZone('UTC'));
    }

    public static function sql(?\DateTimeImmutable $moment = null): string
    {
        return ($moment ?? self::now())->format('Y-m-d H:i:s.v');
    }

    /** Parses an ISO-8601 timestamp from a client into a UTC SQL string. */
    public static function parse(string $value): ?string
    {
        $value = trim($value);
        if ($value === '') {
            return null;
        }
        foreach ([\DateTimeInterface::RFC3339_EXTENDED, \DateTimeInterface::RFC3339, 'Y-m-d\TH:i:s.uP', 'Y-m-d H:i:s.v', 'Y-m-d H:i:s', 'Y-m-d'] as $format) {
            $parsed = \DateTimeImmutable::createFromFormat($format, $value, new \DateTimeZone('UTC'));
            if ($parsed instanceof \DateTimeImmutable) {
                return $parsed->setTimezone(new \DateTimeZone('UTC'))->format('Y-m-d H:i:s.v');
            }
        }
        try {
            return (new \DateTimeImmutable($value))
                ->setTimezone(new \DateTimeZone('UTC'))
                ->format('Y-m-d H:i:s.v');
        } catch (\Exception) {
            return null;
        }
    }

    /** Renders a stored timestamp back to the client as ISO-8601 UTC. */
    public static function iso(?string $sqlValue): ?string
    {
        if ($sqlValue === null || $sqlValue === '') {
            return null;
        }
        try {
            return (new \DateTimeImmutable($sqlValue, new \DateTimeZone('UTC')))
                ->format('Y-m-d\TH:i:s.v\Z');
        } catch (\Exception) {
            return null;
        }
    }
}

/**
 * Sliding-window limiter backed by the database, so limits hold across
 * processes and restarts rather than living in one worker's memory.
 */
final class RateLimiter
{
    public static function hit(string $bucket, int $limit, int $windowSeconds, int $blockSeconds = 0): void
    {
        $bucket = substr(hash('sha256', $bucket), 0, 60) . ':' . substr(preg_replace('/[^a-z0-9:._-]/i', '', $bucket) ?? '', 0, 100);
        $bucket = substr($bucket, 0, 190);
        $now = Clock::now();
        $nowSql = Clock::sql($now);

        Database::transaction(static function () use ($bucket, $limit, $windowSeconds, $blockSeconds, $now, $nowSql): void {
            $row = Database::selectOne(
                'SELECT hits, window_start, blocked_until FROM rate_limits WHERE bucket = ? FOR UPDATE',
                [$bucket]
            );

            if ($row === null) {
                Database::execute(
                    'INSERT INTO rate_limits (bucket, hits, window_start) VALUES (?, 1, ?)',
                    [$bucket, $nowSql]
                );
                return;
            }

            if ($row['blocked_until'] !== null) {
                $blockedUntil = new \DateTimeImmutable($row['blocked_until'], new \DateTimeZone('UTC'));
                if ($blockedUntil > $now) {
                    throw ApiException::tooManyRequests(
                        'Too many attempts. Try again shortly.',
                        max(1, $blockedUntil->getTimestamp() - $now->getTimestamp())
                    );
                }
            }

            $windowStart = new \DateTimeImmutable($row['window_start'], new \DateTimeZone('UTC'));
            $elapsed = $now->getTimestamp() - $windowStart->getTimestamp();

            if ($elapsed >= $windowSeconds) {
                Database::execute(
                    'UPDATE rate_limits SET hits = 1, window_start = ?, blocked_until = NULL WHERE bucket = ?',
                    [$nowSql, $bucket]
                );
                return;
            }

            $hits = (int) $row['hits'] + 1;
            if ($hits > $limit) {
                $retry = $blockSeconds > 0 ? $blockSeconds : ($windowSeconds - $elapsed);
                $blockedUntil = $now->modify('+' . max(1, $retry) . ' seconds');
                Database::execute(
                    'UPDATE rate_limits SET hits = ?, blocked_until = ? WHERE bucket = ?',
                    [$hits, Clock::sql($blockedUntil), $bucket]
                );
                throw ApiException::tooManyRequests('Too many attempts. Try again shortly.', max(1, $retry));
            }

            Database::execute('UPDATE rate_limits SET hits = ? WHERE bucket = ?', [$hits, $bucket]);
        });
    }

    public static function clear(string $bucket): void
    {
        $bucket = substr(hash('sha256', $bucket), 0, 60) . ':' . substr(preg_replace('/[^a-z0-9:._-]/i', '', $bucket) ?? '', 0, 100);
        Database::execute('DELETE FROM rate_limits WHERE bucket = ?', [substr($bucket, 0, 190)]);
    }
}

/**
 * Input validation. Every field a client can send passes through here, so a
 * controller never sees an unchecked value.
 */
final class Validator
{
    private array $errors = [];

    public function __construct(private readonly array $input)
    {
    }

    public function errors(): array
    {
        return $this->errors;
    }

    public function assertValid(): void
    {
        if ($this->errors !== []) {
            throw ApiException::unprocessable('Some fields need attention.', $this->errors);
        }
    }

    public function has(string $key): bool
    {
        return array_key_exists($key, $this->input);
    }

    public function string(string $key, bool $required = false, int $min = 0, int $max = 255): ?string
    {
        $value = $this->input[$key] ?? null;
        if ($value === null || (is_string($value) && trim($value) === '')) {
            if ($required) {
                $this->errors[$key] = 'This field is required.';
            }
            return null;
        }
        if (!is_string($value)) {
            $this->errors[$key] = 'Must be text.';
            return null;
        }
        $value = trim($value);
        // Reject control characters that have no place in a text field.
        if (preg_match('/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/', $value) === 1) {
            $this->errors[$key] = 'Contains characters that are not allowed.';
            return null;
        }
        $length = mb_strlen($value);
        if ($length < $min) {
            $this->errors[$key] = "Must be at least {$min} characters.";
            return null;
        }
        if ($length > $max) {
            $this->errors[$key] = "Must be at most {$max} characters.";
            return null;
        }
        return $value;
    }

    public function text(string $key, int $max = 20000): ?string
    {
        $value = $this->input[$key] ?? null;
        if ($value === null || $value === '') {
            return null;
        }
        if (!is_string($value)) {
            $this->errors[$key] = 'Must be text.';
            return null;
        }
        if (mb_strlen($value) > $max) {
            $this->errors[$key] = "Must be at most {$max} characters.";
            return null;
        }
        return $value;
    }

    public function email(string $key, bool $required = true): ?string
    {
        $value = $this->string($key, $required, 3, 320);
        if ($value === null) {
            return null;
        }
        if (filter_var($value, FILTER_VALIDATE_EMAIL) === false) {
            $this->errors[$key] = 'Enter a valid email address.';
            return null;
        }
        return $value;
    }

    public function number(string $key, bool $required = false, ?float $min = null, ?float $max = null): ?float
    {
        $value = $this->input[$key] ?? null;
        if ($value === null || $value === '') {
            if ($required) {
                $this->errors[$key] = 'This field is required.';
            }
            return null;
        }
        if (is_bool($value) || (!is_int($value) && !is_float($value) && !is_numeric($value))) {
            $this->errors[$key] = 'Must be a number.';
            return null;
        }
        $number = (float) $value;
        if (!is_finite($number)) {
            $this->errors[$key] = 'Must be a finite number.';
            return null;
        }
        if ($min !== null && $number < $min) {
            $this->errors[$key] = "Must be at least {$min}.";
            return null;
        }
        if ($max !== null && $number > $max) {
            $this->errors[$key] = "Must be at most {$max}.";
            return null;
        }
        return $number;
    }

    public function bool(string $key, ?bool $default = null): ?bool
    {
        $value = $this->input[$key] ?? null;
        if ($value === null) {
            return $default;
        }
        if (is_bool($value)) {
            return $value;
        }
        if (in_array($value, [0, 1, '0', '1', 'true', 'false'], true)) {
            return in_array($value, [1, '1', 'true'], true);
        }
        $this->errors[$key] = 'Must be true or false.';
        return $default;
    }

    public function timestamp(string $key, bool $required = false): ?string
    {
        $value = $this->input[$key] ?? null;
        if ($value === null || $value === '') {
            if ($required) {
                $this->errors[$key] = 'This field is required.';
            }
            return null;
        }
        if (!is_string($value)) {
            $this->errors[$key] = 'Must be an ISO-8601 timestamp.';
            return null;
        }
        $parsed = Clock::parse($value);
        if ($parsed === null) {
            $this->errors[$key] = 'Must be an ISO-8601 timestamp.';
            return null;
        }
        return $parsed;
    }

    public function uuid(string $key, bool $required = false): ?string
    {
        $value = $this->input[$key] ?? null;
        if ($value === null || $value === '') {
            if ($required) {
                $this->errors[$key] = 'This field is required.';
            }
            return null;
        }
        if (!is_string($value) || !Ids::isUuid($value)) {
            $this->errors[$key] = 'Must be a UUID.';
            return null;
        }
        return strtolower($value);
    }

    public function enum(string $key, array $allowed, bool $required = false, ?string $default = null): ?string
    {
        $value = $this->input[$key] ?? null;
        if ($value === null || $value === '') {
            if ($required) {
                $this->errors[$key] = 'This field is required.';
            }
            return $default;
        }
        if (!is_string($value) || !in_array($value, $allowed, true)) {
            $this->errors[$key] = 'Must be one of: ' . implode(', ', $allowed) . '.';
            return $default;
        }
        return $value;
    }

    /** JSON-typed columns: accept an array/object and re-encode it safely. */
    public function json(string $key, int $maxBytes = 65536): ?string
    {
        $value = $this->input[$key] ?? null;
        if ($value === null) {
            return null;
        }
        if (!is_array($value)) {
            $this->errors[$key] = 'Must be a JSON array or object.';
            return null;
        }
        $encoded = json_encode($value, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        if ($encoded === false) {
            $this->errors[$key] = 'Could not be encoded as JSON.';
            return null;
        }
        if (strlen($encoded) > $maxBytes) {
            $this->errors[$key] = 'JSON payload is too large.';
            return null;
        }
        return $encoded;
    }

    public function fail(string $key, string $message): void
    {
        $this->errors[$key] = $message;
    }
}
