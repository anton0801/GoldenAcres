<?php
declare(strict_types=1);

namespace GoldenAcres\Core;

use PDO;

/**
 * Thin PDO wrapper. Every query in the codebase goes through here with bound
 * parameters — no string interpolation of user input into SQL, anywhere.
 * Emulated prepares are disabled so the driver really does send parameters
 * separately from the statement.
 */
final class Database
{
    private static ?PDO $pdo = null;

    public static function connection(): PDO
    {
        if (self::$pdo instanceof PDO) {
            return self::$pdo;
        }

        $host = Config::get('DB_HOST', '127.0.0.1');
        $port = Config::int('DB_PORT', 3306);
        $name = Config::require('DB_NAME');
        $user = Config::require('DB_USER');
        $pass = Config::get('DB_PASSWORD', '') ?? '';
        $socket = Config::get('DB_SOCKET', '');

        $dsn = $socket !== null && $socket !== ''
            ? "mysql:unix_socket={$socket};dbname={$name};charset=utf8mb4"
            : "mysql:host={$host};port={$port};dbname={$name};charset=utf8mb4";

        $options = [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES   => false,
            PDO::ATTR_STRINGIFY_FETCHES  => false,
        ];

        if (Config::bool('DB_SSL', false)) {
            $ca = Config::get('DB_SSL_CA', '');
            if ($ca !== null && $ca !== '') {
                $options[PDO::MYSQL_ATTR_SSL_CA] = $ca;
            }
            $options[PDO::MYSQL_ATTR_SSL_VERIFY_SERVER_CERT] = true;
        }

        self::$pdo = new PDO($dsn, $user, $pass, $options);
        // Force UTC so every timestamp the API stores and returns is unambiguous.
        self::$pdo->exec("SET time_zone = '+00:00'");
        return self::$pdo;
    }

    public static function select(string $sql, array $params = []): array
    {
        $statement = self::connection()->prepare($sql);
        $statement->execute($params);
        return $statement->fetchAll();
    }

    public static function selectOne(string $sql, array $params = []): ?array
    {
        $statement = self::connection()->prepare($sql);
        $statement->execute($params);
        $row = $statement->fetch();
        return $row === false ? null : $row;
    }

    public static function execute(string $sql, array $params = []): int
    {
        $statement = self::connection()->prepare($sql);
        $statement->execute($params);
        return $statement->rowCount();
    }

    public static function transaction(callable $work): mixed
    {
        $pdo = self::connection();
        if ($pdo->inTransaction()) {
            return $work();
        }
        $pdo->beginTransaction();
        try {
            $result = $work();
            $pdo->commit();
            return $result;
        } catch (\Throwable $e) {
            if ($pdo->inTransaction()) {
                $pdo->rollBack();
            }
            throw $e;
        }
    }
}
