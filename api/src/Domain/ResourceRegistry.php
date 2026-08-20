<?php
declare(strict_types=1);

namespace GoldenAcres\Domain;

use GoldenAcres\Core\ApiException;

/**
 * Declarative description of every domain resource.
 *
 * One validated, ownership-scoped code path serves all of them, so a mistake
 * cannot be made in one hand-written controller and missed in fifteen others.
 *
 * Field spec: [type, options]
 *   type: string|text|number|bool|timestamp|uuid|json|enum
 */
final class ResourceRegistry
{
    /** @return array<string, array{table:string, fields:array<string,array>}> */
    public static function all(): array
    {
        static $registry = null;
        if ($registry !== null) {
            return $registry;
        }

        $registry = [
            'farms' => [
                'table'  => 'farms',
                'fields' => [
                    'name'             => ['string', ['required' => true, 'max' => 160]],
                    'country'          => ['string', ['max' => 80]],
                    'time_zone'        => ['string', ['max' => 64]],
                    'unit_system'      => ['enum', ['values' => ['metric', 'imperial']]],
                    'currency_code'    => ['string', ['max' => 3]],
                    'weather_source'   => ['string', ['max' => 80]],
                    'retention_months' => ['number', ['min' => 0, 'max' => 1200, 'integer' => true]],
                    'is_archived'      => ['bool', []],
                ],
            ],
            'fields' => [
                'table'  => 'fields',
                'fields' => [
                    'farm_id'           => ['uuid', ['references' => 'farms']],
                    'name'              => ['string', ['required' => true, 'max' => 160]],
                    'area_value'        => ['number', ['min' => 0]],
                    'area_unit'         => ['string', ['max' => 12]],
                    'soil_type'         => ['string', ['max' => 120]],
                    'irrigation_method' => ['string', ['max' => 40]],
                    'notes'             => ['text', []],
                    'latitude'          => ['number', ['min' => -90, 'max' => 90]],
                    'longitude'         => ['number', ['min' => -180, 'max' => 180]],
                    'boundary'          => ['json', []],
                    'is_archived'       => ['bool', []],
                ],
            ],
            'crop-seasons' => [
                'table'  => 'crop_seasons',
                'fields' => [
                    'field_id'               => ['uuid', ['references' => 'fields']],
                    'crop_name'              => ['string', ['required' => true, 'max' => 160]],
                    'variety'                => ['string', ['max' => 160]],
                    'intended_use'           => ['string', ['max' => 60]],
                    'planting_window_start'  => ['timestamp', []],
                    'planting_window_end'    => ['timestamp', []],
                    'actual_planting_date'   => ['timestamp', []],
                    'expected_harvest_start' => ['timestamp', []],
                    'expected_harvest_end'   => ['timestamp', []],
                    'target_area_value'      => ['number', ['min' => 0]],
                    'target_area_unit'       => ['string', ['max' => 12]],
                    'seed_lot_id'            => ['uuid', ['references' => 'inventory_lots']],
                    'seed_lot_label'         => ['string', ['max' => 200]],
                    'notes'                  => ['text', []],
                    'status'                 => ['enum', ['values' => ['draft', 'active', 'closed', 'archived']]],
                    'allows_intercropping'   => ['bool', []],
                    'activated_at'           => ['timestamp', []],
                    'closed_at'              => ['timestamp', []],
                    'closing_snapshot'       => ['json', []],
                ],
            ],
            'observations' => [
                'table'  => 'observations',
                'fields' => [
                    'field_id'            => ['uuid', ['references' => 'fields']],
                    'season_id'           => ['uuid', ['references' => 'crop_seasons']],
                    'observed_at'         => ['timestamp', ['required' => true]],
                    'observation_type'    => ['string', ['required' => true, 'max' => 60]],
                    'severity'            => ['string', ['max' => 20]],
                    'notes'               => ['text', []],
                    'affected_area_value' => ['number', ['min' => 0]],
                    'affected_area_unit'  => ['string', ['max' => 12]],
                    'related_crop_stage'  => ['string', ['max' => 120]],
                    'latitude'            => ['number', ['min' => -90, 'max' => 90]],
                    'longitude'           => ['number', ['min' => -180, 'max' => 180]],
                    'confirmed_category'  => ['string', ['max' => 160]],
                    'review_requested'    => ['bool', []],
                    'field_name_snapshot' => ['string', ['max' => 160]],
                    'photo_filenames'     => ['json', []],
                    'image_suggestion'    => ['json', []],
                    'is_archived'         => ['bool', []],
                ],
            ],
            'soil-tests' => [
                'table'  => 'soil_tests',
                'fields' => [
                    'field_id'               => ['uuid', ['references' => 'fields']],
                    'laboratory'             => ['string', ['max' => 160]],
                    'sample_date'            => ['timestamp', ['required' => true]],
                    'zone'                   => ['string', ['max' => 120]],
                    'depth_value'            => ['number', ['min' => 0]],
                    'depth_unit'             => ['string', ['max' => 12]],
                    'ph'                     => ['number', ['min' => 0, 'max' => 14]],
                    'organic_matter_percent' => ['number', ['min' => 0, 'max' => 100]],
                    'nitrogen_value'         => ['number', ['min' => 0]],
                    'nitrogen_unit'          => ['string', ['max' => 16]],
                    'phosphorus_value'       => ['number', ['min' => 0]],
                    'phosphorus_unit'        => ['string', ['max' => 16]],
                    'potassium_value'        => ['number', ['min' => 0]],
                    'potassium_unit'         => ['string', ['max' => 16]],
                    'salinity_value'         => ['number', ['min' => 0]],
                    'salinity_unit'          => ['string', ['max' => 16]],
                    'micronutrients'         => ['json', []],
                    'parsed_suggestions'     => ['json', []],
                    'parse_provenance'       => ['json', []],
                    'parse_failed_reason'    => ['string', ['max' => 500]],
                    'original_file_name'     => ['string', ['max' => 200]],
                    'notes'                  => ['text', []],
                    'status'                 => ['enum', ['values' => ['draft', 'confirmed']]],
                    'confirmed_at'           => ['timestamp', []],
                    'field_name_snapshot'    => ['string', ['max' => 160]],
                ],
            ],
            'irrigation-plans' => [
                'table'  => 'irrigation_plans',
                'fields' => [
                    'field_id'                 => ['uuid', ['references' => 'fields']],
                    'season_id'                => ['uuid', ['references' => 'crop_seasons']],
                    'zone'                     => ['string', ['max' => 120]],
                    'crop_stage'               => ['string', ['max' => 120]],
                    'method'                   => ['string', ['max' => 40]],
                    'available_flow_value'     => ['number', ['min' => 0]],
                    'flow_unit'                => ['string', ['max' => 16]],
                    'target_depth_value'       => ['number', ['min' => 0]],
                    'depth_unit'               => ['string', ['max' => 12]],
                    'rain_adjustment_mm'       => ['number', ['min' => 0]],
                    'rain_adjustment_source'   => ['string', ['max' => 120]],
                    'start_window'             => ['timestamp', []],
                    'planned_duration_minutes' => ['number', ['min' => 0]],
                    'water_source'             => ['string', ['max' => 160]],
                    'restrictions'             => ['text', []],
                    'status'                   => ['string', ['max' => 20]],
                    'calculation'              => ['json', []],
                    'field_name_snapshot'      => ['string', ['max' => 160]],
                ],
            ],
            'irrigation-runs' => [
                'table'  => 'irrigation_runs',
                'fields' => [
                    'plan_id'             => ['uuid', ['references' => 'irrigation_plans']],
                    'started_at'          => ['timestamp', ['required' => true]],
                    'ended_at'            => ['timestamp', []],
                    'actual_volume_value' => ['number', ['min' => 0]],
                    'volume_unit'         => ['string', ['max' => 12]],
                    'meter_reading_start' => ['number', []],
                    'meter_reading_end'   => ['number', []],
                    'notes'               => ['text', []],
                    'recorded_at'         => ['timestamp', ['required' => true]],
                ],
            ],
            'tasks' => [
                'table'  => 'tasks',
                'fields' => [
                    'season_id'                  => ['uuid', ['references' => 'crop_seasons']],
                    'field_id'                   => ['uuid', ['references' => 'fields']],
                    'field_name_snapshot'        => ['string', ['max' => 160]],
                    'title'                      => ['string', ['required' => true, 'max' => 200]],
                    'detail'                     => ['text', []],
                    'due_start'                  => ['timestamp', []],
                    'due_end'                    => ['timestamp', []],
                    'estimated_duration_minutes' => ['number', ['min' => 0]],
                    'priority'                   => ['string', ['max' => 20]],
                    'assignee'                   => ['string', ['max' => 120]],
                    'equipment'                  => ['string', ['max' => 160]],
                    'required_inputs'            => ['json', []],
                    'dependency_ids'             => ['json', []],
                    'status'                     => ['string', ['max' => 20]],
                    'blocked_reason'             => ['string', ['max' => 500]],
                    'started_at'                 => ['timestamp', []],
                    'completed_at'               => ['timestamp', []],
                    'actual_duration_minutes'    => ['number', ['min' => 0]],
                    'weather_review_needed'      => ['bool', []],
                    'weather_review_note'        => ['string', ['max' => 500]],
                    'source_window_description'  => ['string', ['max' => 500]],
                    'completion_key'             => ['uuid', []],
                ],
            ],
            'inventory-lots' => [
                'table'  => 'inventory_lots',
                'fields' => [
                    'farm_id'               => ['uuid', ['references' => 'farms']],
                    'item_name'             => ['string', ['required' => true, 'max' => 200]],
                    'category'              => ['string', ['max' => 60]],
                    'lot_code'              => ['string', ['max' => 120]],
                    'on_hand_quantity'      => ['number', ['min' => 0]],
                    'reserved_quantity'     => ['number', ['min' => 0]],
                    'unit'                  => ['string', ['max' => 16]],
                    'storage_location'      => ['string', ['max' => 160]],
                    'received_date'         => ['timestamp', []],
                    'expiry_date'           => ['timestamp', []],
                    'unit_cost'             => ['number', ['min' => 0]],
                    'supplier'              => ['string', ['max' => 160]],
                    'safety_file_name'      => ['string', ['max' => 200]],
                    'label_scan_provenance' => ['json', []],
                    'is_archived'           => ['bool', []],
                ],
            ],
            'stock-movements' => [
                'table'  => 'stock_movements',
                'fields' => [
                    'lot_id'                 => ['uuid', ['references' => 'inventory_lots']],
                    'type'                   => ['string', ['required' => true, 'max' => 40]],
                    'quantity'               => ['number', ['min' => 0]],
                    'unit'                   => ['string', ['max' => 16]],
                    'reason'                 => ['string', ['max' => 500]],
                    'occurred_at'            => ['timestamp', ['required' => true]],
                    'related_record_id'      => ['uuid', []],
                    'related_record_label'   => ['string', ['max' => 200]],
                    'actor'                  => ['string', ['max' => 120]],
                    'balance_after_on_hand'  => ['number', []],
                    'balance_after_reserved' => ['number', []],
                ],
            ],
            'input-applications' => [
                'table'  => 'input_applications',
                'fields' => [
                    'season_id'             => ['uuid', ['references' => 'crop_seasons']],
                    'field_id'              => ['uuid', ['references' => 'fields']],
                    'field_name_snapshot'   => ['string', ['max' => 160]],
                    'product_name'          => ['string', ['required' => true, 'max' => 200]],
                    'category'              => ['string', ['max' => 60]],
                    'registration_note'     => ['string', ['max' => 500]],
                    'lot_id'                => ['uuid', ['references' => 'inventory_lots']],
                    'lot_label_snapshot'    => ['string', ['max' => 200]],
                    'quantity'              => ['number', ['required' => true, 'min' => 0]],
                    'quantity_unit'         => ['string', ['max' => 16]],
                    'area_treated_value'    => ['number', ['min' => 0]],
                    'area_unit'             => ['string', ['max' => 12]],
                    'applied_at'            => ['timestamp', ['required' => true]],
                    'operator_name'         => ['string', ['max' => 120]],
                    'purpose'               => ['text', []],
                    'weather_snapshot'      => ['json', []],
                    'attachment_names'      => ['json', []],
                    'voided_at'             => ['timestamp', []],
                    'void_reason'           => ['string', ['max' => 500]],
                    'supersedes_id'         => ['uuid', []],
                    'label_scan_provenance' => ['json', []],
                ],
                // An application is a legal record: it may be voided, never rewritten.
                'immutable_after_create' => [
                    'product_name', 'quantity', 'quantity_unit', 'lot_id',
                    'lot_label_snapshot', 'applied_at', 'area_treated_value', 'area_unit',
                ],
            ],
            'harvest-batches' => [
                'table'  => 'harvest_batches',
                'fields' => [
                    'season_id'           => ['uuid', ['references' => 'crop_seasons']],
                    'field_id'            => ['uuid', ['references' => 'fields']],
                    'field_name_snapshot' => ['string', ['max' => 160]],
                    'batch_code'          => ['string', ['required' => true, 'max' => 80]],
                    'started_at'          => ['timestamp', ['required' => true]],
                    'closed_at'           => ['timestamp', []],
                    'status'              => ['enum', ['values' => ['Open', 'Closed']]],
                    'quality_grade'       => ['string', ['max' => 120]],
                    'storage_destination' => ['string', ['max' => 160]],
                    'crew'                => ['string', ['max' => 160]],
                    'notes'               => ['text', []],
                    'revisions'           => ['json', []],
                ],
            ],
            'harvest-loads' => [
                'table'  => 'harvest_loads',
                'fields' => [
                    'batch_id'            => ['uuid', ['references' => 'harvest_batches']],
                    'occurred_at'         => ['timestamp', ['required' => true]],
                    'gross_quantity'      => ['number', ['required' => true, 'min' => 0]],
                    'marketable_quantity' => ['number', ['min' => 0]],
                    'waste_quantity'      => ['number', ['min' => 0]],
                    'unit'                => ['string', ['max' => 16]],
                    'notes'               => ['text', []],
                    'idempotency_key'     => ['string', ['required' => true, 'max' => 120]],
                    'recorded_by'         => ['string', ['max' => 120]],
                ],
            ],
            'team-members' => [
                'table'  => 'team_members',
                'fields' => [
                    'farm_id'    => ['uuid', ['references' => 'farms']],
                    'name'       => ['string', ['required' => true, 'max' => 160]],
                    'email'      => ['string', ['max' => 320]],
                    'role'       => ['enum', ['values' => ['Owner', 'Manager', 'Worker', 'Viewer']]],
                    'invited_at' => ['timestamp', ['required' => true]],
                    'is_active'  => ['bool', []],
                ],
            ],
            'season-reviews' => [
                'table'  => 'season_reviews',
                'fields' => [
                    'season_id'    => ['uuid', ['required' => true, 'references' => 'crop_seasons']],
                    'completed_at' => ['timestamp', []],
                    'lessons'      => ['json', []],
                ],
            ],
            'audit-events' => [
                'table'  => 'domain_audit_events',
                'fields' => [
                    'occurred_at' => ['timestamp', ['required' => true]],
                    'actor'       => ['string', ['max' => 120]],
                    'action'      => ['string', ['required' => true, 'max' => 80]],
                    'entity_type' => ['string', ['required' => true, 'max' => 80]],
                    'entity_id'   => ['uuid', []],
                    'summary'     => ['string', ['required' => true, 'max' => 500]],
                    'detail'      => ['text', []],
                ],
                // The app's own audit trail is append-only on the server too.
                'append_only' => true,
            ],
        ];

        return $registry;
    }

    public static function resource(string $name): array
    {
        $all = self::all();
        if (!isset($all[$name])) {
            throw ApiException::notFound('Unknown resource type.');
        }
        return $all[$name];
    }

    public static function exists(string $name): bool
    {
        return isset(self::all()[$name]);
    }

    /** @return string[] */
    public static function names(): array
    {
        return array_keys(self::all());
    }

    /** @return string[] */
    public static function tables(): array
    {
        return array_map(static fn (array $r): string => $r['table'], array_values(self::all()));
    }
}
