<?php
declare(strict_types=1);

/**
 * GoldenAcres API — front controller.
 *
 * Every request enters here. Authentication is opt-out per route rather than
 * opt-in, so a new endpoint is protected unless it is deliberately made public.
 */

use GoldenAcres\Controllers\AccountController;
use GoldenAcres\Controllers\AuthController;
use GoldenAcres\Controllers\ResourceController;
use GoldenAcres\Controllers\SyncController;
use GoldenAcres\Core\ApiException;
use GoldenAcres\Core\Clock;
use GoldenAcres\Core\Config;
use GoldenAcres\Core\Database;
use GoldenAcres\Core\Ids;
use GoldenAcres\Core\RateLimiter;
use GoldenAcres\Core\Request;
use GoldenAcres\Core\Response;
use GoldenAcres\Core\Router;
use GoldenAcres\Domain\ResourceRegistry;
use GoldenAcres\Security\Tokens;

$root = dirname(__DIR__);

// Explicit class map. The project has no runtime dependencies, so there is no
// Composer autoloader; a map keeps loading predictable and avoids guessing.
spl_autoload_register(static function (string $class) use ($root): void {
    static $map = [
        'GoldenAcres\Core\Config'                   => '/src/Core/Config.php',
        'GoldenAcres\Core\Database'                 => '/src/Core/Database.php',
        'GoldenAcres\Core\ApiException'             => '/src/Core/Http.php',
        'GoldenAcres\Core\Request'                  => '/src/Core/Http.php',
        'GoldenAcres\Core\Response'                 => '/src/Core/Http.php',
        'GoldenAcres\Core\Router'                   => '/src/Core/Support.php',
        'GoldenAcres\Core\Ids'                      => '/src/Core/Support.php',
        'GoldenAcres\Core\Clock'                    => '/src/Core/Support.php',
        'GoldenAcres\Core\RateLimiter'              => '/src/Core/Support.php',
        'GoldenAcres\Core\Validator'                => '/src/Core/Support.php',
        'GoldenAcres\Security\Passwords'            => '/src/Security/Passwords.php',
        'GoldenAcres\Security\Tokens'               => '/src/Security/Tokens.php',
        'GoldenAcres\Security\SecurityLog'          => '/src/Security/SecurityLog.php',
        'GoldenAcres\Domain\ResourceRegistry'       => '/src/Domain/ResourceRegistry.php',
        'GoldenAcres\Controllers\AuthController'    => '/src/Controllers/AuthController.php',
        'GoldenAcres\Controllers\AccountController' => '/src/Controllers/AccountController.php',
        'GoldenAcres\Controllers\ResourceController' => '/src/Controllers/ResourceController.php',
        'GoldenAcres\Controllers\SyncController'    => '/src/Controllers/SyncController.php',
    ];
    if (isset($map[$class])) {
        require_once $root . $map[$class];
    }
});

Config::load($root);

// Errors are logged, never printed: a stack trace in a response is a leak.
ini_set('display_errors', '0');
ini_set('log_errors', '1');
error_reporting(E_ALL);

set_exception_handler(static function (\Throwable $e): void {
    error_log('[goldenacres] unhandled: ' . $e->getMessage() . ' @ ' . $e->getFile() . ':' . $e->getLine());
    Response::error(new ApiException(500, 'server_error', 'Something went wrong on our side.'));
});

try {
    $request = Request::capture();
} catch (ApiException $e) {
    Response::error($e);
    exit;
}

// Refuse plaintext in production rather than serving tokens over HTTP.
if (Config::isProduction() && !$request->isSecure()) {
    Response::error(new ApiException(403, 'https_required', 'This API is only available over HTTPS.'));
    exit;
}

// The client is a native app, so no browser origin is allowed by default.
$allowedOrigins = array_filter(array_map('trim', explode(',', Config::get('CORS_ORIGINS', '') ?? '')));
$origin = $request->header('origin');
if ($origin !== null && $origin !== '') {
    if (in_array($origin, $allowedOrigins, true)) {
        header("Access-Control-Allow-Origin: {$origin}");
        header('Vary: Origin');
        header('Access-Control-Allow-Headers: Authorization, Content-Type, Idempotency-Key, X-Device-Name');
        header('Access-Control-Allow-Methods: GET, POST, PATCH, PUT, DELETE, OPTIONS');
        header('Access-Control-Max-Age: 600');
    } else {
        Response::error(new ApiException(403, 'origin_not_allowed', 'This origin is not allowed.'));
        exit;
    }
}
if ($request->method === 'OPTIONS') {
    http_response_code(204);
    exit;
}

$router = new Router();
$auth = new AuthController();
$account = new AccountController();
$resources = new ResourceController();
$sync = new SyncController($resources);

// ---- Public --------------------------------------------------------------
$router->get('/v1/health', static function (): void {
    Response::ok(['status' => 'ok', 'time' => Clock::iso(Clock::sql())]);
}, auth: false);

$router->post('/v1/auth/register', [$auth, 'register'], auth: false);
$router->post('/v1/auth/login', [$auth, 'login'], auth: false);
$router->post('/v1/auth/refresh', [$auth, 'refresh'], auth: false);

// ---- Authenticated -------------------------------------------------------
$router->post('/v1/auth/logout', [$auth, 'logout']);
$router->post('/v1/auth/logout-all', [$auth, 'logoutAll']);

$router->get('/v1/me', [$account, 'show']);
$router->patch('/v1/me', [$account, 'update']);
$router->delete('/v1/me', [$account, 'destroy']);
$router->post('/v1/me/password', [$account, 'changePassword']);
$router->get('/v1/me/sessions', [$account, 'sessions']);
$router->delete('/v1/me/sessions/{id}', [$account, 'revokeSession']);
$router->get('/v1/me/security-events', [$account, 'securityEvents']);

$router->get('/v1/sync', [$sync, 'pull']);
$router->post('/v1/sync', [$sync, 'push']);

$router->get('/v1/resources', static function (): void {
    Response::ok(['resources' => ResourceRegistry::names()]);
});

$router->get('/v1/{resource}', [$resources, 'index']);
$router->post('/v1/{resource}', [$resources, 'store']);
$router->get('/v1/{resource}/{id}', [$resources, 'show']);
$router->patch('/v1/{resource}/{id}', [$resources, 'update']);
$router->delete('/v1/{resource}/{id}', [$resources, 'destroy']);

// ---- Dispatch ------------------------------------------------------------
try {
    $route = $router->match($request->method, $request->path);

    $context = [];
    if ($route['auth']) {
        $token = $request->bearerToken();
        if ($token === null) {
            throw ApiException::unauthorized('Provide a bearer token in the Authorization header.');
        }
        $context = Tokens::authenticate($token);

        // Per-account throttle on top of the per-endpoint ones.
        RateLimiter::hit(
            'api:user:' . $context['user']['id'],
            Config::int('RL_API_PER_MINUTE', 300),
            60
        );
    }

    // Replay protection for unsafe writes that carry an Idempotency-Key.
    $idempotencyKey = $request->header('idempotency-key');
    $useIdempotency = $idempotencyKey !== null
        && $idempotencyKey !== ''
        && in_array($request->method, ['POST', 'PATCH', 'DELETE'], true)
        && $context !== [];

    if ($useIdempotency) {
        $key = mb_substr($idempotencyKey, 0, 190);
        $endpoint = $request->method . ' ' . $request->path;
        $requestHash = hash('sha256', $request->rawBody());

        $existing = Database::selectOne(
            'SELECT request_hash, response_status, response_body
             FROM idempotency_keys WHERE user_id = ? AND idem_key = ? AND endpoint = ?',
            [$context['user']['id'], $key, $endpoint]
        );

        if ($existing !== null) {
            // Same key with a different body is a client bug, not a retry.
            if (!hash_equals($existing['request_hash'], $requestHash)) {
                throw ApiException::conflict('This Idempotency-Key was already used with a different request body.');
            }
            http_response_code((int) $existing['response_status']);
            header('Content-Type: application/json; charset=utf-8');
            header('Idempotent-Replay: true');
            echo $existing['response_body'];
            exit;
        }

        ob_start();
        $handler = $route['handler'];
        $handler($request, $context, $route['params']);
        $body = ob_get_clean() ?: '';
        $status = http_response_code();

        if (is_int($status) && $status < 400) {
            try {
                Database::execute(
                    'INSERT INTO idempotency_keys
                        (id, user_id, idem_key, endpoint, request_hash, response_status, response_body, created_at)
                     VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
                    [
                        Ids::uuid4(),
                        $context['user']['id'],
                        $key,
                        $endpoint,
                        $requestHash,
                        $status,
                        $body,
                        Clock::sql(),
                    ]
                );
            } catch (\PDOException) {
                // A concurrent identical request won the race; the response is still correct.
            }
        }
        echo $body;
        exit;
    }

    $handler = $route['handler'];
    $handler($request, $context, $route['params']);
} catch (ApiException $e) {
    Response::error($e);
} catch (\PDOException $e) {
    error_log('[goldenacres] db: ' . $e->getMessage());
    Response::error(new ApiException(500, 'server_error', 'Something went wrong on our side.'));
} catch (\Throwable $e) {
    error_log('[goldenacres] error: ' . $e->getMessage() . ' @ ' . $e->getFile() . ':' . $e->getLine());
    Response::error(new ApiException(500, 'server_error', 'Something went wrong on our side.'));
}
