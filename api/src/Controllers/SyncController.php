<?php
declare(strict_types=1);

namespace GoldenAcres\Controllers;

use GoldenAcres\Core\ApiException;
use GoldenAcres\Core\Clock;
use GoldenAcres\Core\Database;
use GoldenAcres\Core\Ids;
use GoldenAcres\Core\Request;
use GoldenAcres\Core\Response;
use GoldenAcres\Domain\ResourceRegistry;

/**
 * Bulk push/pull for the offline-first client.
 *
 * Conflict rule: last write wins per record, decided by `updated_at`. When the
 * server copy is newer the push is *rejected for that record* and the server
 * version is returned, so the client can reconcile rather than lose data
 * silently. Nothing is merged behind the user's back.
 */
final class SyncController
{
    private const MAX_RECORDS_PER_PUSH = 500;

    public function __construct(private readonly ResourceController $resources)
    {
    }

    /** GET /v1/sync?since=... — everything that changed after the cursor. */
    public function pull(Request $request, array $context): void
    {
        $userId = $context['user']['id'];
        $since = $request->queryString('since');
        $sinceSql = null;
        if ($since !== null && $since !== '') {
            $sinceSql = Clock::parse($since);
            if ($sinceSql === null) {
                throw ApiException::badRequest('since must be an ISO-8601 timestamp.');
            }
        }

        $limitPerType = max(1, min($request->queryInt('limit', 200), 500));
        $changes = [];
        $counts = [];
        $truncated = [];

        foreach (ResourceRegistry::all() as $name => $resource) {
            $sql = "SELECT * FROM {$resource['table']} WHERE user_id = ?";
            $bind = [$userId];
            if ($sinceSql !== null) {
                $sql .= ' AND updated_at > ?';
                $bind[] = $sinceSql;
            }
            $sql .= " ORDER BY updated_at ASC, id ASC LIMIT " . ($limitPerType + 1);

            $rows = Database::select($sql, $bind);
            if (count($rows) > $limitPerType) {
                $truncated[] = $name;
                $rows = array_slice($rows, 0, $limitPerType);
            }

            $changes[$name] = array_map(
                fn (array $row): array => $this->resources->present($row, $resource),
                $rows
            );
            $counts[$name] = count($rows);
        }

        Response::ok([
            'changes' => $changes,
            'cursor'  => Clock::iso(Clock::sql()),
        ], [
            'counts' => array_filter($counts),
            // If a type was truncated the client must pull again before
            // trusting the cursor, so say so rather than implying completeness.
            'truncated' => $truncated,
            'complete'  => $truncated === [],
        ]);
    }

    /**
     * POST /v1/sync — push local changes.
     * Body: { "changes": { "fields": [ {...}, ... ], ... } }
     */
    public function push(Request $request, array $context): void
    {
        $userId = $context['user']['id'];
        $body = $request->body();
        $changes = $body['changes'] ?? null;
        if (!is_array($changes) || $changes === []) {
            throw ApiException::badRequest('Provide a "changes" object keyed by resource name.');
        }

        $total = 0;
        foreach ($changes as $records) {
            if (is_array($records)) {
                $total += count($records);
            }
        }
        if ($total > self::MAX_RECORDS_PER_PUSH) {
            throw ApiException::badRequest(
                'Too many records in one push. Send at most ' . self::MAX_RECORDS_PER_PUSH . '.'
            );
        }

        $applied = [];
        $conflicts = [];
        $rejected = [];

        foreach ($changes as $name => $records) {
            if (!is_string($name) || !ResourceRegistry::exists($name)) {
                $rejected[] = ['resource' => (string) $name, 'reason' => 'Unknown resource type.'];
                continue;
            }
            if (!is_array($records) || !array_is_list($records)) {
                $rejected[] = ['resource' => $name, 'reason' => 'Expected a list of records.'];
                continue;
            }

            $resource = ResourceRegistry::resource($name);
            foreach ($records as $record) {
                if (!is_array($record)) {
                    $rejected[] = ['resource' => $name, 'reason' => 'Record must be an object.'];
                    continue;
                }
                try {
                    $result = $this->upsert($name, $resource, $record, $userId);
                    if ($result['status'] === 'conflict') {
                        $conflicts[] = ['resource' => $name] + $result;
                    } else {
                        $applied[] = ['resource' => $name, 'id' => $result['id'], 'status' => $result['status']];
                    }
                } catch (ApiException $e) {
                    $rejected[] = [
                        'resource' => $name,
                        'id'       => is_string($record['id'] ?? null) ? $record['id'] : null,
                        'reason'   => $e->getMessage(),
                        'details'  => $e->details,
                    ];
                }
            }
        }

        Response::ok([
            'applied'   => $applied,
            'conflicts' => $conflicts,
            'rejected'  => $rejected,
            'cursor'    => Clock::iso(Clock::sql()),
        ], [
            'applied_count'   => count($applied),
            'conflict_count'  => count($conflicts),
            'rejected_count'  => count($rejected),
        ]);
    }

    /**
     * @return array{status:string, id:string, server_record?:array}
     */
    private function upsert(string $name, array $resource, array $record, string $userId): array
    {
        $id = is_string($record['id'] ?? null) ? strtolower(trim($record['id'])) : '';
        if (!Ids::isUuid($id)) {
            throw ApiException::unprocessable('Some fields need attention.', ['id' => 'Each record needs a UUID id.']);
        }

        $table = $resource['table'];
        $existing = Database::selectOne(
            "SELECT * FROM {$table} WHERE id = ? AND user_id = ?",
            [$id, $userId]
        );

        // An id that belongs to another account is never touched.
        if ($existing === null) {
            $foreign = Database::selectOne("SELECT id FROM {$table} WHERE id = ?", [$id]);
            if ($foreign !== null) {
                throw ApiException::conflict('That id is already in use.');
            }
        }

        $clientUpdatedAt = isset($record['updated_at']) && is_string($record['updated_at'])
            ? Clock::parse($record['updated_at'])
            : null;

        // A tombstone from the client.
        if (!empty($record['deleted_at'])) {
            if ($existing === null) {
                return ['status' => 'skipped', 'id' => $id];
            }
            Database::execute(
                "UPDATE {$table} SET deleted_at = ?, updated_at = ?, revision = revision + 1
                 WHERE id = ? AND user_id = ?",
                [Clock::sql(), Clock::sql(), $id, $userId]
            );
            return ['status' => 'deleted', 'id' => $id];
        }

        if ($existing !== null) {
            if (($resource['append_only'] ?? false) === true) {
                return ['status' => 'skipped', 'id' => $id];
            }
            // Server wins when its copy is strictly newer.
            if ($clientUpdatedAt !== null && $existing['updated_at'] > $clientUpdatedAt) {
                return [
                    'status'        => 'conflict',
                    'id'            => $id,
                    'server_record' => $this->resources->present($existing, $resource),
                ];
            }

            $values = $this->resources->validateFields($record, $resource, false);
            if ($values === []) {
                return ['status' => 'skipped', 'id' => $id];
            }
            $this->resources->assertReferencesOwned($values, $resource, $userId);

            $assignments = [];
            $bind = [];
            foreach ($values as $column => $value) {
                $assignments[] = "{$column} = ?";
                $bind[] = $value;
            }
            $assignments[] = 'revision = revision + 1';
            $assignments[] = 'updated_at = ?';
            $assignments[] = 'deleted_at = NULL';
            $bind[] = Clock::sql();
            $bind[] = $id;
            $bind[] = $userId;

            Database::execute(
                "UPDATE {$table} SET " . implode(', ', $assignments) . ' WHERE id = ? AND user_id = ?',
                $bind
            );
            return ['status' => 'updated', 'id' => $id];
        }

        $values = $this->resources->validateFields($record, $resource, true);
        $this->resources->assertReferencesOwned($values, $resource, $userId);

        $createdAt = isset($record['created_at']) && is_string($record['created_at'])
            ? (Clock::parse($record['created_at']) ?? Clock::sql())
            : Clock::sql();

        $columns = array_merge(['id', 'user_id', 'revision', 'created_at', 'updated_at'], array_keys($values));
        $bind = array_merge([$id, $userId, 1, $createdAt, Clock::sql()], array_values($values));
        $placeholders = implode(', ', array_fill(0, count($columns), '?'));

        Database::execute(
            "INSERT INTO {$table} (" . implode(', ', $columns) . ") VALUES ({$placeholders})",
            $bind
        );
        return ['status' => 'created', 'id' => $id];
    }
}
