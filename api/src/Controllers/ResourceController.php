<?php
declare(strict_types=1);

namespace GoldenAcres\Controllers;

use GoldenAcres\Core\ApiException;
use GoldenAcres\Core\Clock;
use GoldenAcres\Core\Database;
use GoldenAcres\Core\Ids;
use GoldenAcres\Core\Request;
use GoldenAcres\Core\Response;
use GoldenAcres\Core\Validator;
use GoldenAcres\Domain\ResourceRegistry;

/**
 * Typed CRUD for every domain resource.
 *
 * Two rules hold on every single statement here:
 *   1. `user_id = ?` is always in the WHERE clause — a row belonging to another
 *      account is invisible and untouchable, and reads 404 rather than 403 so
 *      the API never confirms that someone else's id exists.
 *   2. Column names come from the registry, never from the request, so a
 *      client cannot name a column it was not offered.
 */
final class ResourceController
{
    private const MAX_PAGE_SIZE = 200;

    /** GET /v1/{resource} */
    public function index(Request $request, array $context, array $params): void
    {
        $name = $params['resource'];
        $resource = ResourceRegistry::resource($name);
        $table = $resource['table'];
        $userId = $context['user']['id'];

        $where = ['user_id = ?'];
        $bind = [$userId];

        if ($request->queryString('include_deleted') !== '1') {
            $where[] = 'deleted_at IS NULL';
        }

        // Cursor for incremental sync.
        $since = $request->queryString('updated_since');
        if ($since !== null && $since !== '') {
            $parsed = Clock::parse($since);
            if ($parsed === null) {
                throw ApiException::badRequest('updated_since must be an ISO-8601 timestamp.');
            }
            $where[] = 'updated_at > ?';
            $bind[] = $parsed;
        }

        // Filter by any declared uuid column, e.g. ?field_id=...
        foreach ($resource['fields'] as $column => $spec) {
            if ($spec[0] !== 'uuid') {
                continue;
            }
            $value = $request->queryString($column);
            if ($value === null || $value === '') {
                continue;
            }
            if (!Ids::isUuid($value)) {
                throw ApiException::badRequest("Filter {$column} must be a UUID.");
            }
            $where[] = "{$column} = ?";
            $bind[] = strtolower($value);
        }

        $limit = max(1, min($request->queryInt('limit', 100), self::MAX_PAGE_SIZE));
        $offset = max(0, $request->queryInt('offset', 0));

        $countRow = Database::selectOne(
            "SELECT COUNT(*) AS c FROM {$table} WHERE " . implode(' AND ', $where),
            $bind
        );

        $rows = Database::select(
            "SELECT * FROM {$table} WHERE " . implode(' AND ', $where)
            . " ORDER BY updated_at ASC, id ASC LIMIT {$limit} OFFSET {$offset}",
            $bind
        );

        $items = array_map(fn (array $row): array => $this->present($row, $resource), $rows);

        Response::ok($items, [
            'total'  => (int) ($countRow['c'] ?? 0),
            'limit'  => $limit,
            'offset' => $offset,
            'cursor' => $items === [] ? $since : ($items[count($items) - 1]['updated_at'] ?? null),
        ]);
    }

    /** GET /v1/{resource}/{id} */
    public function show(Request $request, array $context, array $params): void
    {
        $resource = ResourceRegistry::resource($params['resource']);
        $row = $this->findOwned($resource['table'], $params['id'], $context['user']['id']);
        Response::ok($this->present($row, $resource));
    }

    /** POST /v1/{resource} */
    public function store(Request $request, array $context, array $params): void
    {
        $name = $params['resource'];
        $resource = ResourceRegistry::resource($name);
        $userId = $context['user']['id'];
        $body = $request->body();

        // The client may supply the id so an offline-created record keeps its
        // identity; otherwise the server mints one.
        $id = isset($body['id']) && is_string($body['id']) ? strtolower(trim($body['id'])) : Ids::uuid4();
        if (!Ids::isUuid($id)) {
            throw ApiException::unprocessable('Some fields need attention.', ['id' => 'Must be a UUID.']);
        }

        $existing = Database::selectOne(
            "SELECT id, user_id FROM {$resource['table']} WHERE id = ?",
            [$id]
        );
        if ($existing !== null) {
            // Never reveal that another account owns this id.
            if ($existing['user_id'] !== $userId) {
                throw ApiException::conflict('That id is already in use.');
            }
            throw ApiException::conflict('A record with that id already exists.', ['id' => $id]);
        }

        $values = $this->validateFields($body, $resource, true);
        $this->assertReferencesOwned($values, $resource, $userId);

        $now = Clock::sql();
        $columns = array_merge(['id', 'user_id', 'revision', 'created_at', 'updated_at'], array_keys($values));
        $bind = array_merge([$id, $userId, 1, $now, $now], array_values($values));
        $placeholders = implode(', ', array_fill(0, count($columns), '?'));

        try {
            Database::execute(
                "INSERT INTO {$resource['table']} (" . implode(', ', $columns) . ") VALUES ({$placeholders})",
                $bind
            );
        } catch (\PDOException $e) {
            throw $this->translateConstraint($e);
        }

        $row = $this->findOwned($resource['table'], $id, $userId);
        Response::ok($this->present($row, $resource), [], 201);
    }

    /** PATCH /v1/{resource}/{id} */
    public function update(Request $request, array $context, array $params): void
    {
        $resource = ResourceRegistry::resource($params['resource']);
        $userId = $context['user']['id'];
        $id = $params['id'];
        $body = $request->body();

        if (($resource['append_only'] ?? false) === true) {
            throw ApiException::forbidden('Records of this type cannot be modified after they are written.');
        }

        $current = $this->findOwned($resource['table'], $id, $userId);

        // Optimistic concurrency: the client states the revision it saw.
        $expected = $body['revision'] ?? $request->header('if-match');
        if ($expected !== null && $expected !== '') {
            if ((int) $expected !== (int) $current['revision']) {
                throw ApiException::conflict(
                    'This record changed on the server since you loaded it.',
                    ['current_revision' => (int) $current['revision'], 'server_record' => $this->present($current, $resource)]
                );
            }
        }

        // Fields that are frozen once written (e.g. an application's quantity).
        foreach ($resource['immutable_after_create'] ?? [] as $frozen) {
            if (!array_key_exists($frozen, $body)) {
                continue;
            }
            $incoming = $body[$frozen];
            $stored = $current[$frozen];
            $same = is_numeric($incoming) && is_numeric($stored)
                ? abs((float) $incoming - (float) $stored) < 0.000001
                : (string) $incoming === (string) $stored;
            if (!$same) {
                throw ApiException::forbidden(
                    "Field '{$frozen}' cannot be changed after the record is created. Void it and write a new record instead."
                );
            }
        }

        $values = $this->validateFields($body, $resource, false);
        if ($values === []) {
            throw ApiException::badRequest('No supported fields were supplied.');
        }
        $this->assertReferencesOwned($values, $resource, $userId);

        $assignments = [];
        $bind = [];
        foreach ($values as $column => $value) {
            $assignments[] = "{$column} = ?";
            $bind[] = $value;
        }
        $assignments[] = 'revision = revision + 1';
        $assignments[] = 'updated_at = ?';
        $bind[] = Clock::sql();
        $bind[] = $id;
        $bind[] = $userId;

        try {
            Database::execute(
                "UPDATE {$resource['table']} SET " . implode(', ', $assignments)
                . ' WHERE id = ? AND user_id = ?',
                $bind
            );
        } catch (\PDOException $e) {
            throw $this->translateConstraint($e);
        }

        Response::ok($this->present($this->findOwned($resource['table'], $id, $userId), $resource));
    }

    /**
     * DELETE /v1/{resource}/{id}
     * Soft delete by default so other devices can converge on the removal;
     * ?purge=1 removes the row outright.
     */
    public function destroy(Request $request, array $context, array $params): void
    {
        $resource = ResourceRegistry::resource($params['resource']);
        $userId = $context['user']['id'];
        $id = $params['id'];

        $this->findOwned($resource['table'], $id, $userId, true);

        if ($request->queryString('purge') === '1') {
            Database::execute(
                "DELETE FROM {$resource['table']} WHERE id = ? AND user_id = ?",
                [$id, $userId]
            );
        } else {
            Database::execute(
                "UPDATE {$resource['table']}
                    SET deleted_at = ?, updated_at = ?, revision = revision + 1
                  WHERE id = ? AND user_id = ?",
                [Clock::sql(), Clock::sql(), $id, $userId]
            );
        }

        Response::noContent();
    }

    // -----------------------------------------------------------------
    // Shared helpers, also used by the sync endpoint.
    // -----------------------------------------------------------------

    public function findOwned(string $table, string $id, string $userId, bool $allowDeleted = false): array
    {
        if (!Ids::isUuid($id)) {
            throw ApiException::notFound('Resource not found.');
        }
        $sql = "SELECT * FROM {$table} WHERE id = ? AND user_id = ?";
        if (!$allowDeleted) {
            $sql .= ' AND deleted_at IS NULL';
        }
        $row = Database::selectOne($sql, [$id, $userId]);
        if ($row === null) {
            // Deliberately 404 even when the row exists under another account.
            throw ApiException::notFound('Resource not found.');
        }
        return $row;
    }

    /**
     * Validates the incoming payload against the registry.
     *
     * @param bool $forCreate when true, required fields must be present
     * @return array<string, mixed> column => value, ready to bind
     */
    public function validateFields(array $body, array $resource, bool $forCreate): array
    {
        $validator = new Validator($body);
        $values = [];

        foreach ($resource['fields'] as $column => $spec) {
            [$type, $options] = [$spec[0], $spec[1] ?? []];
            $required = ($options['required'] ?? false) === true;
            $present = array_key_exists($column, $body);

            if (!$present) {
                if ($forCreate && $required) {
                    $validator->fail($column, 'This field is required.');
                }
                continue;
            }

            // An explicit null clears a nullable column.
            if ($body[$column] === null) {
                if ($required) {
                    $validator->fail($column, 'This field is required.');
                    continue;
                }
                $values[$column] = null;
                continue;
            }

            $values[$column] = match ($type) {
                'string' => $validator->string($column, $forCreate && $required, 0, $options['max'] ?? 255),
                'text'   => $validator->text($column, $options['max'] ?? 20000),
                'number' => $this->number($validator, $column, $options, $forCreate && $required),
                'bool'   => $validator->bool($column) === true ? 1 : 0,
                'timestamp' => $validator->timestamp($column, $forCreate && $required),
                'uuid'   => $validator->uuid($column, $forCreate && $required),
                'json'   => $validator->json($column),
                'enum'   => $validator->enum($column, $options['values'] ?? [], $forCreate && $required),
                default  => throw new \LogicException("Unknown field type {$type}"),
            };
        }

        $validator->assertValid();
        return $values;
    }

    private function number(Validator $validator, string $column, array $options, bool $required): int|float|null
    {
        $value = $validator->number($column, $required, $options['min'] ?? null, $options['max'] ?? null);
        if ($value === null) {
            return null;
        }
        return ($options['integer'] ?? false) === true ? (int) round($value) : $value;
    }

    /**
     * A foreign key may only point at a row the same account owns. Without
     * this a caller could attach their record to someone else's field.
     */
    public function assertReferencesOwned(array $values, array $resource, string $userId): void
    {
        foreach ($resource['fields'] as $column => $spec) {
            $referenced = $spec[1]['references'] ?? null;
            if ($referenced === null) {
                continue;
            }
            $value = $values[$column] ?? null;
            if ($value === null || $value === '') {
                continue;
            }
            $row = Database::selectOne(
                "SELECT id FROM {$referenced} WHERE id = ? AND user_id = ?",
                [$value, $userId]
            );
            if ($row === null) {
                throw ApiException::unprocessable('Some fields need attention.', [
                    $column => 'That record does not exist in your account.',
                ]);
            }
        }
    }

    /** Shapes a database row into the JSON the client receives. */
    public function present(array $row, array $resource): array
    {
        $out = [
            'id'         => $row['id'],
            'revision'   => (int) $row['revision'],
            'created_at' => Clock::iso($row['created_at']),
            'updated_at' => Clock::iso($row['updated_at']),
            'deleted_at' => Clock::iso($row['deleted_at'] ?? null),
        ];

        foreach ($resource['fields'] as $column => $spec) {
            $value = $row[$column] ?? null;
            $out[$column] = match ($spec[0]) {
                'number'    => $value === null ? null : (float) $value,
                'bool'      => $value === null ? null : ((int) $value === 1),
                'timestamp' => Clock::iso($value),
                'json'      => $value === null ? null : json_decode((string) $value, true),
                default     => $value,
            };
        }

        return $out;
    }

    private function translateConstraint(\PDOException $e): ApiException
    {
        $message = $e->getMessage();
        if (str_contains($message, 'uq_load_idem')) {
            return ApiException::conflict('That harvest load was already recorded for this batch.');
        }
        if (str_contains($message, 'chk_load_split')) {
            return ApiException::unprocessable('Some fields need attention.', [
                'marketable_quantity' => 'Marketable plus waste cannot exceed the gross quantity.',
            ]);
        }
        if (str_contains($message, 'chk_lots_nonneg')) {
            return ApiException::unprocessable('Some fields need attention.', [
                'on_hand_quantity' => 'Stock quantities cannot be negative.',
            ]);
        }
        if ($e->getCode() === '23000') {
            return ApiException::conflict('That record conflicts with one that already exists.');
        }
        throw $e;
    }
}
