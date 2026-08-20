<?php
declare(strict_types=1);

namespace GoldenAcres\Core;

/**
 * Error carried to the client. The message is always safe to show: internal
 * details go to the log, never into the response.
 */
class ApiException extends \RuntimeException
{
    public function __construct(
        public readonly int $status,
        // Named errorCode because Exception already owns $code.
        public readonly string $errorCode,
        string $message,
        public readonly array $details = []
    ) {
        parent::__construct($message);
    }

    public static function badRequest(string $message, array $details = []): self
    {
        return new self(400, 'bad_request', $message, $details);
    }

    public static function unauthorized(string $message = 'Authentication required.'): self
    {
        return new self(401, 'unauthorized', $message);
    }

    public static function forbidden(string $message = 'You do not have access to this resource.'): self
    {
        return new self(403, 'forbidden', $message);
    }

    public static function notFound(string $message = 'Resource not found.'): self
    {
        return new self(404, 'not_found', $message);
    }

    public static function conflict(string $message, array $details = []): self
    {
        return new self(409, 'conflict', $message, $details);
    }

    public static function unprocessable(string $message, array $details = []): self
    {
        return new self(422, 'validation_failed', $message, $details);
    }

    public static function tooManyRequests(string $message, int $retryAfter): self
    {
        return new self(429, 'rate_limited', $message, ['retry_after_seconds' => $retryAfter]);
    }
}

final class Request
{
    private ?array $parsedBody = null;

    public function __construct(
        public readonly string $method,
        public readonly string $path,
        public readonly array $query,
        public readonly array $headers,
        private readonly string $rawBody
    ) {
    }

    public static function capture(): self
    {
        $method = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');
        $uri = $_SERVER['REQUEST_URI'] ?? '/';
        $path = parse_url($uri, PHP_URL_PATH) ?: '/';
        // Strip a base path when the API is mounted in a subdirectory.
        $base = Config::get('APP_BASE_PATH', '');
        if ($base !== null && $base !== '' && str_starts_with($path, $base)) {
            $path = substr($path, strlen($base));
        }
        $path = '/' . trim($path, '/');

        $headers = [];
        foreach ($_SERVER as $key => $value) {
            if (str_starts_with($key, 'HTTP_')) {
                $name = strtolower(str_replace('_', '-', substr($key, 5)));
                $headers[$name] = (string) $value;
            }
        }
        // Shared hosting (LiteSpeed, CGI, FastCGI) frequently drops the
        // Authorization header, or only exposes it as REDIRECT_HTTP_AUTHORIZATION
        // once .htaccess has re-injected it. Without this the bearer token is
        // silently lost and every authenticated request answers 401.
        if (!isset($headers['authorization'])) {
            $candidates = [
                $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? null,
                $_SERVER['HTTP_AUTHORIZATION'] ?? null,
                $_SERVER['REDIRECT_REMOTE_USER'] ?? null,
            ];
            $found = null;
            foreach ($candidates as $candidate) {
                if (is_string($candidate) && trim($candidate) !== '') {
                    $found = $candidate;
                    break;
                }
            }
            if ($found === null && function_exists('apache_request_headers')) {
                foreach (apache_request_headers() as $name => $value) {
                    if (strcasecmp($name, 'Authorization') === 0 && is_string($value)) {
                        $found = $value;
                        break;
                    }
                }
            }
            if ($found !== null) {
                $headers['authorization'] = trim($found);
            }
        }

        if (isset($_SERVER['CONTENT_TYPE'])) {
            $headers['content-type'] = (string) $_SERVER['CONTENT_TYPE'];
        }
        if (isset($_SERVER['CONTENT_LENGTH'])) {
            $headers['content-length'] = (string) $_SERVER['CONTENT_LENGTH'];
        }

        $maxBytes = Config::int('MAX_BODY_BYTES', 1_048_576);
        $declared = (int) ($headers['content-length'] ?? 0);
        if ($declared > $maxBytes) {
            throw new ApiException(413, 'payload_too_large', 'Request body is too large.');
        }

        $raw = file_get_contents('php://input') ?: '';
        if (strlen($raw) > $maxBytes) {
            throw new ApiException(413, 'payload_too_large', 'Request body is too large.');
        }

        return new self($method, $path, $_GET ?? [], $headers, $raw);
    }

    public function header(string $name): ?string
    {
        return $this->headers[strtolower($name)] ?? null;
    }

    public function bearerToken(): ?string
    {
        $header = $this->header('authorization');
        if ($header === null) {
            return null;
        }
        if (!preg_match('/^Bearer\s+(\S+)$/i', trim($header), $matches)) {
            return null;
        }
        return $matches[1];
    }

    /** Decoded JSON body. Anything that is not a JSON object is rejected. */
    public function body(): array
    {
        if ($this->parsedBody !== null) {
            return $this->parsedBody;
        }
        if (trim($this->rawBody) === '') {
            return $this->parsedBody = [];
        }

        $contentType = strtolower($this->header('content-type') ?? '');
        if ($contentType !== '' && !str_contains($contentType, 'application/json')) {
            throw ApiException::badRequest('Content-Type must be application/json.');
        }

        try {
            $decoded = json_decode($this->rawBody, true, 32, JSON_THROW_ON_ERROR);
        } catch (\JsonException $e) {
            throw ApiException::badRequest('Request body is not valid JSON.');
        }
        if (!is_array($decoded) || array_is_list($decoded)) {
            throw ApiException::badRequest('Request body must be a JSON object.');
        }
        return $this->parsedBody = $decoded;
    }

    public function rawBody(): string
    {
        return $this->rawBody;
    }

    public function queryString(string $key, ?string $default = null): ?string
    {
        $value = $this->query[$key] ?? null;
        return is_string($value) ? $value : $default;
    }

    public function queryInt(string $key, int $default): int
    {
        $value = $this->query[$key] ?? null;
        return is_string($value) && $value !== '' ? (int) $value : $default;
    }

    public function clientIp(): string
    {
        // Only trust a forwarding header when the deployment says a proxy is in front.
        if (Config::bool('TRUST_PROXY', false)) {
            $forwarded = $this->header('x-forwarded-for');
            if ($forwarded !== null && $forwarded !== '') {
                $first = trim(explode(',', $forwarded)[0]);
                if (filter_var($first, FILTER_VALIDATE_IP)) {
                    return $first;
                }
            }
        }
        $remote = $_SERVER['REMOTE_ADDR'] ?? '0.0.0.0';
        return filter_var($remote, FILTER_VALIDATE_IP) ? $remote : '0.0.0.0';
    }

    public function userAgent(): string
    {
        return substr($this->header('user-agent') ?? '', 0, 255);
    }

    public function isSecure(): bool
    {
        if (($_SERVER['HTTPS'] ?? '') !== '' && strtolower((string) $_SERVER['HTTPS']) !== 'off') {
            return true;
        }
        // Set by the web server, not the client, so these cannot be spoofed.
        if (strtolower((string) ($_SERVER['REQUEST_SCHEME'] ?? '')) === 'https') {
            return true;
        }
        if ((int) ($_SERVER['SERVER_PORT'] ?? 0) === 443) {
            return true;
        }
        // Client-supplied, therefore only trusted when a proxy is declared.
        if (Config::bool('TRUST_PROXY', false)) {
            if (strtolower($this->header('x-forwarded-proto') ?? '') === 'https') {
                return true;
            }
            if (strtolower($this->header('x-forwarded-ssl') ?? '') === 'on') {
                return true;
            }
        }
        return false;
    }
}

final class Response
{
    public static function send(int $status, array $payload, array $headers = []): void
    {
        http_response_code($status);
        header('Content-Type: application/json; charset=utf-8');
        foreach (self::securityHeaders() as $name => $value) {
            header("{$name}: {$value}");
        }
        foreach ($headers as $name => $value) {
            header("{$name}: {$value}");
        }
        echo json_encode(
            $payload,
            JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRESERVE_ZERO_FRACTION
        );
    }

    public static function ok(mixed $data, array $meta = [], int $status = 200, array $headers = []): void
    {
        $payload = ['data' => $data];
        if ($meta !== []) {
            $payload['meta'] = $meta;
        }
        self::send($status, $payload, $headers);
    }

    public static function noContent(): void
    {
        http_response_code(204);
        foreach (self::securityHeaders() as $name => $value) {
            header("{$name}: {$value}");
        }
    }

    public static function error(ApiException $e): void
    {
        $payload = [
            'error' => [
                'code'    => $e->errorCode,
                'message' => $e->getMessage(),
            ],
        ];
        if ($e->details !== []) {
            $payload['error']['details'] = $e->details;
        }
        $headers = [];
        if ($e->status === 429 && isset($e->details['retry_after_seconds'])) {
            $headers['Retry-After'] = (string) $e->details['retry_after_seconds'];
        }
        if ($e->status === 401) {
            $headers['WWW-Authenticate'] = 'Bearer realm="goldenacres"';
        }
        self::send($e->status, $payload, $headers);
    }

    /**
     * Applied to every response. The API serves only JSON to a native client,
     * so the policy is as restrictive as it can be.
     */
    private static function securityHeaders(): array
    {
        $headers = [
            'X-Content-Type-Options' => 'nosniff',
            'X-Frame-Options'        => 'DENY',
            'Referrer-Policy'        => 'no-referrer',
            'Cache-Control'          => 'no-store, private',
            'Pragma'                 => 'no-cache',
            'Content-Security-Policy' => "default-src 'none'; frame-ancestors 'none'; base-uri 'none'",
            'Permissions-Policy'     => 'geolocation=(), camera=(), microphone=()',
            'X-Permitted-Cross-Domain-Policies' => 'none',
        ];
        if (Config::isProduction()) {
            $headers['Strict-Transport-Security'] = 'max-age=31536000; includeSubDomains; preload';
        }
        return $headers;
    }
}
