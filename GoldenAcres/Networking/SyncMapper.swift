//
//  SyncMapper.swift
//  GoldenAcres
//
//  Translation between the local SwiftData models and the API's JSON.
//
//  Every optional stays optional across the wire: a value the user never
//  entered is sent as null and comes back as nil, so "unknown" survives the
//  round trip instead of becoming zero on either side.
//

import Foundation
import SwiftData

enum SyncMapper {

    // MARK: - Helpers

    static func iso(_ date: Date?) -> Any {
        guard let date else { return NSNull() }
        return ISO8601DateFormatter.apiFormatter.string(from: date)
    }

    static func value(_ value: Any?) -> Any {
        value ?? NSNull()
    }

    /// Encodes a Codable payload as a JSON-object dictionary for the wire.
    static func jsonObject<T: Encodable>(_ payload: T?) -> Any {
        guard let payload else { return NSNull() }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(payload),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return NSNull()
        }
        return object
    }

    static func decodeJSON<T: Decodable>(_ type: T.Type, from any: Any?) -> T? {
        guard let any, !(any is NSNull) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? JSONSerialization.data(withJSONObject: any) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    static func batched(_ changes: [String: [[String: Any]]], limit: Int) -> [[String: [[String: Any]]]] {
        var batches: [[String: [[String: Any]]]] = []
        var current: [String: [[String: Any]]] = [:]
        var count = 0

        for (resource, records) in changes {
            for record in records {
                current[resource, default: []].append(record)
                count += 1
                if count >= limit {
                    batches.append(current)
                    current = [:]
                    count = 0
                }
            }
        }
        if !current.isEmpty { batches.append(current) }
        return batches
    }

    // MARK: - Collect local state

    /// Everything on this device, in dependency order so the server can
    /// resolve foreign keys as it walks the payload.
    static func collectLocalChanges(context: ModelContext) -> [String: [[String: Any]]] {
        var changes: [String: [[String: Any]]] = [:]

        func fetch<T: PersistentModel>(_ type: T.Type) -> [T] {
            (try? context.fetch(FetchDescriptor<T>())) ?? []
        }

        let farms = fetch(Farm.self)
        if !farms.isEmpty { changes["farms"] = farms.map(encodeFarm) }

        let fields = fetch(FarmField.self)
        if !fields.isEmpty { changes["fields"] = fields.map(encodeField) }

        let seasons = fetch(CropSeason.self)
        if !seasons.isEmpty { changes["crop-seasons"] = seasons.map(encodeSeason) }

        let lots = fetch(InventoryLot.self)
        if !lots.isEmpty { changes["inventory-lots"] = lots.map(encodeLot) }

        let movements = fetch(StockMovement.self)
        if !movements.isEmpty { changes["stock-movements"] = movements.map(encodeMovement) }

        let observations = fetch(FieldObservation.self)
        if !observations.isEmpty { changes["observations"] = observations.map(encodeObservation) }

        let soilTests = fetch(SoilTest.self)
        if !soilTests.isEmpty { changes["soil-tests"] = soilTests.map(encodeSoilTest) }

        let plans = fetch(IrrigationPlan.self)
        if !plans.isEmpty { changes["irrigation-plans"] = plans.map(encodePlan) }

        let runs = fetch(IrrigationRun.self)
        if !runs.isEmpty { changes["irrigation-runs"] = runs.map(encodeRun) }

        let tasks = fetch(FarmTask.self)
        if !tasks.isEmpty { changes["tasks"] = tasks.map(encodeTask) }

        let applications = fetch(InputApplication.self)
        if !applications.isEmpty { changes["input-applications"] = applications.map(encodeApplication) }

        let batches = fetch(HarvestBatch.self)
        if !batches.isEmpty { changes["harvest-batches"] = batches.map(encodeBatch) }

        let loads = fetch(HarvestLoad.self)
        if !loads.isEmpty { changes["harvest-loads"] = loads.map(encodeLoad) }

        let members = fetch(TeamMember.self)
        if !members.isEmpty { changes["team-members"] = members.map(encodeTeamMember) }

        let reviews = fetch(SeasonReviewRecord.self)
        if !reviews.isEmpty { changes["season-reviews"] = reviews.map(encodeReview) }

        // The change history goes up too, so traceability survives a reinstall.
        // The server treats these as append-only and ignores any later edit.
        let auditEvents = fetch(AuditEvent.self)
        if !auditEvents.isEmpty { changes["audit-events"] = auditEvents.map(encodeAuditEvent) }

        return changes
    }

    // MARK: - Encoders

    static func encodeFarm(_ farm: Farm) -> [String: Any] {
        [
            "id": farm.id.uuidString.lowercased(),
            "updated_at": iso(farm.updatedAt),
            "created_at": iso(farm.createdAt),
            "name": farm.name,
            "country": value(farm.country.isEmpty ? nil : farm.country),
            "time_zone": farm.timeZoneIdentifier,
            "unit_system": farm.unitSystemRaw,
            "currency_code": farm.currencyCode,
            "weather_source": farm.weatherSourceName,
            "retention_months": value(farm.retentionMonths),
            "is_archived": farm.isArchived,
        ]
    }

    static func encodeField(_ field: FarmField) -> [String: Any] {
        [
            "id": field.id.uuidString.lowercased(),
            "updated_at": iso(field.updatedAt),
            "created_at": iso(field.createdAt),
            "farm_id": value(field.farm?.id.uuidString.lowercased()),
            "name": field.name,
            "area_value": value(field.areaValue),
            "area_unit": field.areaUnitRaw,
            "soil_type": value(field.soilType),
            "irrigation_method": value(field.irrigationMethodRaw),
            "notes": value(field.notes),
            "latitude": value(field.latitude),
            "longitude": value(field.longitude),
            "boundary": jsonObject(field.boundary),
            "is_archived": field.isArchived,
        ]
    }

    static func encodeSeason(_ season: CropSeason) -> [String: Any] {
        [
            "id": season.id.uuidString.lowercased(),
            "updated_at": iso(season.updatedAt),
            "created_at": iso(season.createdAt),
            "field_id": value(season.field?.id.uuidString.lowercased()),
            "crop_name": season.cropName.isEmpty ? "Untitled crop" : season.cropName,
            "variety": value(season.variety),
            "intended_use": value(season.intendedUseRaw),
            "planting_window_start": iso(season.plantingWindowStart),
            "planting_window_end": iso(season.plantingWindowEnd),
            "actual_planting_date": iso(season.actualPlantingDate),
            "expected_harvest_start": iso(season.expectedHarvestStart),
            "expected_harvest_end": iso(season.expectedHarvestEnd),
            "target_area_value": value(season.targetAreaValue),
            "target_area_unit": season.targetAreaUnitRaw,
            "seed_lot_id": value(season.seedLotID?.uuidString.lowercased()),
            "seed_lot_label": value(season.seedLotLabel),
            "notes": value(season.notes),
            "status": season.statusRaw,
            "allows_intercropping": season.allowsIntercropping,
            "activated_at": iso(season.activatedAt),
            "closed_at": iso(season.closedAt),
            "closing_snapshot": jsonObject(season.closingSnapshot),
        ]
    }

    static func encodeObservation(_ observation: FieldObservation) -> [String: Any] {
        [
            "id": observation.id.uuidString.lowercased(),
            "updated_at": iso(observation.updatedAt),
            "created_at": iso(observation.createdAt),
            "field_id": value(observation.field?.id.uuidString.lowercased()),
            "season_id": value(observation.seasonID?.uuidString.lowercased()),
            "observed_at": iso(observation.date),
            "observation_type": observation.observationTypeRaw,
            "severity": value(observation.severityRaw),
            "notes": value(observation.notes),
            "affected_area_value": value(observation.affectedAreaValue),
            "affected_area_unit": observation.affectedAreaUnitRaw,
            "related_crop_stage": value(observation.relatedCropStage),
            "latitude": value(observation.latitude),
            "longitude": value(observation.longitude),
            "confirmed_category": value(observation.confirmedCategory),
            "review_requested": observation.reviewRequested,
            "field_name_snapshot": observation.fieldNameSnapshot,
            // Filenames only: the photo bytes stay on the device.
            "photo_filenames": observation.photoFilenames,
            "image_suggestion": jsonObject(observation.imageSuggestion),
            "is_archived": observation.isArchived,
        ]
    }

    static func encodeSoilTest(_ test: SoilTest) -> [String: Any] {
        [
            "id": test.id.uuidString.lowercased(),
            "updated_at": iso(test.updatedAt),
            "created_at": iso(test.createdAt),
            "field_id": value(test.field?.id.uuidString.lowercased()),
            "laboratory": value(test.laboratory),
            "sample_date": iso(test.sampleDate),
            "zone": value(test.zone),
            "depth_value": value(test.depthValue),
            "depth_unit": test.depthUnitRaw,
            "ph": value(test.ph),
            "organic_matter_percent": value(test.organicMatterPercent),
            "nitrogen_value": value(test.nitrogenValue),
            "nitrogen_unit": value(test.nitrogenUnitRaw),
            "phosphorus_value": value(test.phosphorusValue),
            "phosphorus_unit": value(test.phosphorusUnitRaw),
            "potassium_value": value(test.potassiumValue),
            "potassium_unit": value(test.potassiumUnitRaw),
            "salinity_value": value(test.salinityValue),
            "salinity_unit": value(test.salinityUnitRaw),
            "micronutrients": jsonObject(test.micronutrients),
            "parsed_suggestions": jsonObject(test.parsedSuggestions),
            "parse_provenance": jsonObject(test.parseProvenance),
            "parse_failed_reason": value(test.parseFailedReason),
            "original_file_name": value(test.originalFileName),
            "notes": value(test.notes),
            "status": test.statusRaw,
            "confirmed_at": iso(test.confirmedAt),
            "field_name_snapshot": test.fieldNameSnapshot,
        ]
    }

    static func encodePlan(_ plan: IrrigationPlan) -> [String: Any] {
        [
            "id": plan.id.uuidString.lowercased(),
            "updated_at": iso(plan.updatedAt),
            "created_at": iso(plan.createdAt),
            "field_id": value(plan.field?.id.uuidString.lowercased()),
            "season_id": value(plan.seasonID?.uuidString.lowercased()),
            "zone": value(plan.zone),
            "crop_stage": value(plan.cropStage),
            "method": value(plan.methodRaw),
            "available_flow_value": value(plan.availableFlowValue),
            "flow_unit": plan.flowUnitRaw,
            "target_depth_value": value(plan.targetDepthValue),
            "depth_unit": plan.depthUnitRaw,
            "rain_adjustment_mm": value(plan.rainAdjustmentMM),
            "rain_adjustment_source": value(plan.rainAdjustmentSource),
            "start_window": iso(plan.startWindow),
            "planned_duration_minutes": value(plan.plannedDurationMinutes),
            "water_source": value(plan.waterSource),
            "restrictions": value(plan.restrictions),
            "status": plan.statusRaw,
            "calculation": jsonObject(plan.calculation),
            "field_name_snapshot": plan.fieldNameSnapshot,
        ]
    }

    static func encodeRun(_ run: IrrigationRun) -> [String: Any] {
        [
            "id": run.id.uuidString.lowercased(),
            "updated_at": iso(run.recordedAt),
            "created_at": iso(run.recordedAt),
            "plan_id": value(run.plan?.id.uuidString.lowercased()),
            "started_at": iso(run.startedAt),
            "ended_at": iso(run.endedAt),
            "actual_volume_value": value(run.actualVolumeValue),
            "volume_unit": run.volumeUnitRaw,
            "meter_reading_start": value(run.meterReadingStart),
            "meter_reading_end": value(run.meterReadingEnd),
            "notes": value(run.notes),
            "recorded_at": iso(run.recordedAt),
        ]
    }

    static func encodeTask(_ task: FarmTask) -> [String: Any] {
        [
            "id": task.id.uuidString.lowercased(),
            "updated_at": iso(task.updatedAt),
            "created_at": iso(task.createdAt),
            "season_id": value(task.season?.id.uuidString.lowercased()),
            "field_id": value(task.fieldID?.uuidString.lowercased()),
            "field_name_snapshot": task.fieldNameSnapshot,
            "title": task.title.isEmpty ? "Untitled task" : task.title,
            "detail": value(task.detail),
            "due_start": iso(task.dueStart),
            "due_end": iso(task.dueEnd),
            "estimated_duration_minutes": value(task.estimatedDurationMinutes),
            "priority": task.priorityRaw,
            "assignee": value(task.assignee),
            "equipment": value(task.equipment),
            "required_inputs": jsonObject(task.requiredInputs),
            "dependency_ids": task.dependencyIDs.map { $0.uuidString.lowercased() },
            "status": task.statusRaw,
            "blocked_reason": value(task.blockedReason),
            "started_at": iso(task.startedAt),
            "completed_at": iso(task.completedAt),
            "actual_duration_minutes": value(task.actualDurationMinutes),
            "weather_review_needed": task.weatherReviewNeeded,
            "weather_review_note": value(task.weatherReviewNote),
            "source_window_description": value(task.sourceWindowDescription),
            "completion_key": value(task.completionKey?.uuidString.lowercased()),
        ]
    }

    static func encodeLot(_ lot: InventoryLot) -> [String: Any] {
        [
            "id": lot.id.uuidString.lowercased(),
            "updated_at": iso(lot.updatedAt),
            "created_at": iso(lot.createdAt),
            "farm_id": value(lot.farm?.id.uuidString.lowercased()),
            "item_name": lot.itemName.isEmpty ? "Untitled item" : lot.itemName,
            "category": lot.categoryRaw,
            "lot_code": lot.lotCode,
            "on_hand_quantity": lot.onHandQuantity,
            "reserved_quantity": lot.reservedQuantity,
            "unit": lot.unitRaw,
            "storage_location": value(lot.storageLocation),
            "received_date": iso(lot.receivedDate),
            "expiry_date": iso(lot.expiryDate),
            "unit_cost": value(lot.unitCost),
            "supplier": value(lot.supplier),
            "safety_file_name": value(lot.safetyFileName),
            "label_scan_provenance": jsonObject(lot.labelScanProvenance),
            "is_archived": lot.isArchived,
        ]
    }

    static func encodeMovement(_ movement: StockMovement) -> [String: Any] {
        [
            "id": movement.id.uuidString.lowercased(),
            "updated_at": iso(movement.timestamp),
            "created_at": iso(movement.timestamp),
            "lot_id": value(movement.lot?.id.uuidString.lowercased()),
            "type": movement.typeRaw,
            "quantity": movement.quantity,
            "unit": movement.unitRaw,
            "reason": value(movement.reason),
            "occurred_at": iso(movement.timestamp),
            "related_record_id": value(movement.relatedRecordID?.uuidString.lowercased()),
            "related_record_label": value(movement.relatedRecordLabel),
            "actor": value(movement.actor),
            "balance_after_on_hand": value(movement.balanceAfterOnHand),
            "balance_after_reserved": value(movement.balanceAfterReserved),
        ]
    }

    static func encodeApplication(_ application: InputApplication) -> [String: Any] {
        [
            "id": application.id.uuidString.lowercased(),
            "updated_at": iso(application.createdAt),
            "created_at": iso(application.createdAt),
            "season_id": value(application.season?.id.uuidString.lowercased()),
            "field_id": value(application.fieldID?.uuidString.lowercased()),
            "field_name_snapshot": application.fieldNameSnapshot,
            "product_name": application.productName.isEmpty ? "Unnamed product" : application.productName,
            "category": application.categoryRaw,
            "registration_note": value(application.registrationNote),
            "lot_id": value(application.lotID?.uuidString.lowercased()),
            "lot_label_snapshot": value(application.lotLabelSnapshot),
            "quantity": application.quantity,
            "quantity_unit": application.quantityUnitRaw,
            "area_treated_value": value(application.areaTreatedValue),
            "area_unit": application.areaUnitRaw,
            "applied_at": iso(application.date),
            "operator_name": value(application.operatorName),
            "purpose": value(application.purpose),
            "weather_snapshot": jsonObject(application.weatherSnapshot),
            "attachment_names": application.attachmentNames,
            "voided_at": iso(application.voidedAt),
            "void_reason": value(application.voidReason),
            "supersedes_id": value(application.supersedesID?.uuidString.lowercased()),
            "label_scan_provenance": jsonObject(application.labelScanProvenance),
        ]
    }

    static func encodeBatch(_ batch: HarvestBatch) -> [String: Any] {
        [
            "id": batch.id.uuidString.lowercased(),
            "updated_at": iso(batch.closedAt ?? batch.createdAt),
            "created_at": iso(batch.createdAt),
            "season_id": value(batch.season?.id.uuidString.lowercased()),
            "field_id": value(batch.fieldID?.uuidString.lowercased()),
            "field_name_snapshot": batch.fieldNameSnapshot,
            "batch_code": batch.batchCode.isEmpty ? "B000" : batch.batchCode,
            "started_at": iso(batch.startedAt),
            "closed_at": iso(batch.closedAt),
            "status": batch.statusRaw,
            "quality_grade": value(batch.qualityGrade),
            "storage_destination": value(batch.storageDestination),
            "crew": value(batch.crew),
            "notes": value(batch.notes),
            "revisions": jsonObject(batch.revisions),
        ]
    }

    static func encodeLoad(_ load: HarvestLoad) -> [String: Any] {
        [
            "id": load.id.uuidString.lowercased(),
            "updated_at": iso(load.createdAt),
            "created_at": iso(load.createdAt),
            "batch_id": value(load.batch?.id.uuidString.lowercased()),
            "occurred_at": iso(load.date),
            "gross_quantity": load.grossQuantity,
            "marketable_quantity": value(load.marketableQuantity),
            "waste_quantity": value(load.wasteQuantity),
            "unit": load.unitRaw,
            "notes": value(load.notes),
            "idempotency_key": load.idempotencyKey,
            "recorded_by": value(load.recordedBy),
        ]
    }

    static func encodeTeamMember(_ member: TeamMember) -> [String: Any] {
        [
            "id": member.id.uuidString.lowercased(),
            "updated_at": iso(member.invitedAt),
            "created_at": iso(member.invitedAt),
            "farm_id": value(member.farm?.id.uuidString.lowercased()),
            "name": member.name.isEmpty ? "Unnamed" : member.name,
            "email": value(member.email),
            "role": member.roleRaw,
            "invited_at": iso(member.invitedAt),
            "is_active": member.isActive,
        ]
    }

    static func encodeAuditEvent(_ event: AuditEvent) -> [String: Any] {
        [
            "id": event.id.uuidString.lowercased(),
            "updated_at": iso(event.timestamp),
            "created_at": iso(event.timestamp),
            "occurred_at": iso(event.timestamp),
            "actor": event.actor,
            "action": event.action.isEmpty ? "Changed" : event.action,
            "entity_type": event.entityType.isEmpty ? "Record" : event.entityType,
            "entity_id": value(event.entityID?.uuidString.lowercased()),
            "summary": event.summary.isEmpty ? "Change recorded" : event.summary,
            "detail": value(event.details),
        ]
    }

    static func encodeReview(_ review: SeasonReviewRecord) -> [String: Any] {
        [
            "id": review.id.uuidString.lowercased(),
            "updated_at": iso(review.createdAt),
            "created_at": iso(review.createdAt),
            "season_id": review.seasonID.uuidString.lowercased(),
            "completed_at": iso(review.completedAt),
            "lessons": jsonObject(review.lessons),
        ]
    }

    // MARK: - Apply remote changes

    /// Applies server records to the local store, in dependency order.
    /// Returns how many rows were created or updated.
    @MainActor
    static func applyRemoteChanges(
        _ changes: [String: [[String: AnyDecodable]]],
        context: ModelContext
    ) -> Int {
        var applied = 0
        let order = [
            "farms", "fields", "crop-seasons", "inventory-lots", "stock-movements",
            "observations", "soil-tests", "irrigation-plans", "irrigation-runs",
            "tasks", "input-applications", "harvest-batches", "harvest-loads",
            "team-members", "season-reviews",
        ]

        for resource in order {
            guard let records = changes[resource] else { continue }
            for record in records {
                guard let idText = record["id"]?.stringValue,
                      let id = UUID(uuidString: idText) else { continue }

                let isDeleted = record["deleted_at"]?.stringValue != nil
                if isDeleted {
                    if deleteLocal(resource: resource, id: id, context: context) { applied += 1 }
                    continue
                }

                if applyRecord(resource: resource, id: id, record: record, context: context) {
                    applied += 1
                }
            }
        }

        try? context.save()
        return applied
    }

    @MainActor
    private static func find<T: PersistentModel>(_ type: T.Type, id: UUID, context: ModelContext,
                                                 keyPath: KeyPath<T, UUID>) -> T? {
        let all = (try? context.fetch(FetchDescriptor<T>())) ?? []
        return all.first { $0[keyPath: keyPath] == id }
    }

    @MainActor
    private static func deleteLocal(resource: String, id: UUID, context: ModelContext) -> Bool {
        switch resource {
        case "farms":
            if let row = find(Farm.self, id: id, context: context, keyPath: \.id) {
                context.delete(row); return true
            }
        case "fields":
            if let row = find(FarmField.self, id: id, context: context, keyPath: \.id) {
                context.delete(row); return true
            }
        case "crop-seasons":
            if let row = find(CropSeason.self, id: id, context: context, keyPath: \.id) {
                context.delete(row); return true
            }
        case "observations":
            if let row = find(FieldObservation.self, id: id, context: context, keyPath: \.id) {
                context.delete(row); return true
            }
        case "soil-tests":
            if let row = find(SoilTest.self, id: id, context: context, keyPath: \.id) {
                context.delete(row); return true
            }
        case "irrigation-plans":
            if let row = find(IrrigationPlan.self, id: id, context: context, keyPath: \.id) {
                context.delete(row); return true
            }
        case "irrigation-runs":
            if let row = find(IrrigationRun.self, id: id, context: context, keyPath: \.id) {
                context.delete(row); return true
            }
        case "tasks":
            if let row = find(FarmTask.self, id: id, context: context, keyPath: \.id) {
                context.delete(row); return true
            }
        case "inventory-lots":
            if let row = find(InventoryLot.self, id: id, context: context, keyPath: \.id) {
                context.delete(row); return true
            }
        case "harvest-batches":
            if let row = find(HarvestBatch.self, id: id, context: context, keyPath: \.id) {
                context.delete(row); return true
            }
        case "harvest-loads":
            if let row = find(HarvestLoad.self, id: id, context: context, keyPath: \.id) {
                context.delete(row); return true
            }
        default:
            return false
        }
        return false
    }

    @MainActor
    private static func applyRecord(
        resource: String,
        id: UUID,
        record: [String: AnyDecodable],
        context: ModelContext
    ) -> Bool {
        func string(_ key: String) -> String? { record[key]?.stringValue }
        func double(_ key: String) -> Double? { record[key]?.doubleValue }
        func bool(_ key: String) -> Bool? { record[key]?.boolValue }
        func date(_ key: String) -> Date? { record[key]?.dateValue }
        func uuid(_ key: String) -> UUID? { record[key]?.stringValue.flatMap(UUID.init(uuidString:)) }
        func json(_ key: String) -> Any? { record[key]?.value }

        switch resource {
        case "farms":
            let farm = find(Farm.self, id: id, context: context, keyPath: \.id) ?? {
                let created = Farm()
                created.id = id
                context.insert(created)
                return created
            }()
            farm.name = string("name") ?? farm.name
            farm.country = string("country") ?? ""
            farm.timeZoneIdentifier = string("time_zone") ?? farm.timeZoneIdentifier
            farm.unitSystemRaw = string("unit_system") ?? farm.unitSystemRaw
            farm.currencyCode = string("currency_code") ?? farm.currencyCode
            farm.weatherSourceName = string("weather_source") ?? farm.weatherSourceName
            farm.retentionMonths = double("retention_months").map(Int.init)
            farm.isArchived = bool("is_archived") ?? false
            farm.updatedAt = date("updated_at") ?? Date()
            return true

        case "fields":
            let field = find(FarmField.self, id: id, context: context, keyPath: \.id) ?? {
                let created = FarmField()
                created.id = id
                context.insert(created)
                return created
            }()
            field.name = string("name") ?? field.name
            field.areaValue = double("area_value")
            field.areaUnitRaw = string("area_unit") ?? field.areaUnitRaw
            field.soilType = string("soil_type")
            field.irrigationMethodRaw = string("irrigation_method")
            field.notes = string("notes")
            field.latitude = double("latitude")
            field.longitude = double("longitude")
            if let boundary = decodeJSON(FieldBoundary.self, from: json("boundary")) {
                field.boundary = boundary
            }
            field.isArchived = bool("is_archived") ?? false
            field.updatedAt = date("updated_at") ?? Date()
            if let farmID = uuid("farm_id") {
                field.farm = find(Farm.self, id: farmID, context: context, keyPath: \.id)
            }
            return true

        case "crop-seasons":
            let season = find(CropSeason.self, id: id, context: context, keyPath: \.id) ?? {
                let created = CropSeason()
                created.id = id
                context.insert(created)
                return created
            }()
            season.cropName = string("crop_name") ?? season.cropName
            season.variety = string("variety")
            season.intendedUseRaw = string("intended_use")
            season.plantingWindowStart = date("planting_window_start")
            season.plantingWindowEnd = date("planting_window_end")
            season.actualPlantingDate = date("actual_planting_date")
            season.expectedHarvestStart = date("expected_harvest_start")
            season.expectedHarvestEnd = date("expected_harvest_end")
            season.targetAreaValue = double("target_area_value")
            season.targetAreaUnitRaw = string("target_area_unit") ?? season.targetAreaUnitRaw
            season.seedLotID = uuid("seed_lot_id")
            season.seedLotLabel = string("seed_lot_label")
            season.notes = string("notes")
            season.statusRaw = string("status") ?? season.statusRaw
            season.allowsIntercropping = bool("allows_intercropping") ?? false
            season.activatedAt = date("activated_at")
            season.closedAt = date("closed_at")
            season.closingSnapshot = decodeJSON(SeasonSnapshot.self, from: json("closing_snapshot"))
            season.updatedAt = date("updated_at") ?? Date()
            if let fieldID = uuid("field_id") {
                season.field = find(FarmField.self, id: fieldID, context: context, keyPath: \.id)
            }
            return true

        case "inventory-lots":
            let lot = find(InventoryLot.self, id: id, context: context, keyPath: \.id) ?? {
                let created = InventoryLot()
                created.id = id
                context.insert(created)
                return created
            }()
            lot.itemName = string("item_name") ?? lot.itemName
            lot.categoryRaw = string("category") ?? lot.categoryRaw
            lot.lotCode = string("lot_code") ?? ""
            lot.onHandQuantity = double("on_hand_quantity") ?? 0
            lot.reservedQuantity = double("reserved_quantity") ?? 0
            lot.unitRaw = string("unit") ?? lot.unitRaw
            lot.storageLocation = string("storage_location")
            lot.receivedDate = date("received_date")
            lot.expiryDate = date("expiry_date")
            lot.unitCost = double("unit_cost")
            lot.supplier = string("supplier")
            lot.safetyFileName = string("safety_file_name")
            lot.isArchived = bool("is_archived") ?? false
            lot.updatedAt = date("updated_at") ?? Date()
            if let farmID = uuid("farm_id") {
                lot.farm = find(Farm.self, id: farmID, context: context, keyPath: \.id)
            }
            return true

        case "observations":
            let observation = find(FieldObservation.self, id: id, context: context, keyPath: \.id) ?? {
                let created = FieldObservation()
                created.id = id
                context.insert(created)
                return created
            }()
            observation.date = date("observed_at") ?? observation.date
            observation.observationTypeRaw = string("observation_type") ?? observation.observationTypeRaw
            observation.severityRaw = string("severity")
            observation.notes = string("notes")
            observation.affectedAreaValue = double("affected_area_value")
            observation.affectedAreaUnitRaw = string("affected_area_unit") ?? observation.affectedAreaUnitRaw
            observation.relatedCropStage = string("related_crop_stage")
            observation.latitude = double("latitude")
            observation.longitude = double("longitude")
            observation.confirmedCategory = string("confirmed_category")
            observation.reviewRequested = bool("review_requested") ?? false
            observation.fieldNameSnapshot = string("field_name_snapshot") ?? ""
            observation.seasonID = uuid("season_id")
            if let names = json("photo_filenames") as? [Any] {
                observation.photoFilenames = names.compactMap { $0 as? String }
            }
            observation.imageSuggestion = decodeJSON(ImageSuggestion.self, from: json("image_suggestion"))
            observation.isArchived = bool("is_archived") ?? false
            observation.updatedAt = date("updated_at") ?? Date()
            if let fieldID = uuid("field_id") {
                observation.field = find(FarmField.self, id: fieldID, context: context, keyPath: \.id)
            }
            return true

        case "soil-tests":
            let test = find(SoilTest.self, id: id, context: context, keyPath: \.id) ?? {
                let created = SoilTest()
                created.id = id
                context.insert(created)
                return created
            }()
            test.laboratory = string("laboratory")
            test.sampleDate = date("sample_date") ?? test.sampleDate
            test.zone = string("zone")
            test.depthValue = double("depth_value")
            test.depthUnitRaw = string("depth_unit") ?? test.depthUnitRaw
            test.ph = double("ph")
            test.organicMatterPercent = double("organic_matter_percent")
            test.nitrogenValue = double("nitrogen_value")
            test.nitrogenUnitRaw = string("nitrogen_unit")
            test.phosphorusValue = double("phosphorus_value")
            test.phosphorusUnitRaw = string("phosphorus_unit")
            test.potassiumValue = double("potassium_value")
            test.potassiumUnitRaw = string("potassium_unit")
            test.salinityValue = double("salinity_value")
            test.salinityUnitRaw = string("salinity_unit")
            test.micronutrients = decodeJSON([SoilNutrientValue].self, from: json("micronutrients")) ?? []
            test.parsedSuggestions = decodeJSON([ParsedFieldSuggestion].self, from: json("parsed_suggestions")) ?? []
            test.parseProvenance = decodeJSON(Provenance.self, from: json("parse_provenance"))
            test.parseFailedReason = string("parse_failed_reason")
            test.originalFileName = string("original_file_name")
            test.notes = string("notes")
            test.statusRaw = string("status") ?? test.statusRaw
            test.confirmedAt = date("confirmed_at")
            test.fieldNameSnapshot = string("field_name_snapshot") ?? ""
            test.updatedAt = date("updated_at") ?? Date()
            if let fieldID = uuid("field_id") {
                test.field = find(FarmField.self, id: fieldID, context: context, keyPath: \.id)
            }
            return true

        case "irrigation-plans":
            let plan = find(IrrigationPlan.self, id: id, context: context, keyPath: \.id) ?? {
                let created = IrrigationPlan()
                created.id = id
                context.insert(created)
                return created
            }()
            plan.zone = string("zone")
            plan.cropStage = string("crop_stage")
            plan.methodRaw = string("method")
            plan.availableFlowValue = double("available_flow_value")
            plan.flowUnitRaw = string("flow_unit") ?? plan.flowUnitRaw
            plan.targetDepthValue = double("target_depth_value")
            plan.depthUnitRaw = string("depth_unit") ?? plan.depthUnitRaw
            plan.rainAdjustmentMM = double("rain_adjustment_mm")
            plan.rainAdjustmentSource = string("rain_adjustment_source")
            plan.startWindow = date("start_window")
            plan.plannedDurationMinutes = double("planned_duration_minutes")
            plan.waterSource = string("water_source")
            plan.restrictions = string("restrictions")
            plan.statusRaw = string("status") ?? plan.statusRaw
            plan.calculation = decodeJSON(IrrigationCalculation.self, from: json("calculation"))
            plan.fieldNameSnapshot = string("field_name_snapshot") ?? ""
            plan.seasonID = uuid("season_id")
            plan.updatedAt = date("updated_at") ?? Date()
            if let fieldID = uuid("field_id") {
                plan.field = find(FarmField.self, id: fieldID, context: context, keyPath: \.id)
            }
            return true

        case "irrigation-runs":
            let run = find(IrrigationRun.self, id: id, context: context, keyPath: \.id) ?? {
                let created = IrrigationRun()
                created.id = id
                context.insert(created)
                return created
            }()
            run.startedAt = date("started_at") ?? run.startedAt
            run.endedAt = date("ended_at")
            run.actualVolumeValue = double("actual_volume_value")
            run.volumeUnitRaw = string("volume_unit") ?? run.volumeUnitRaw
            run.meterReadingStart = double("meter_reading_start")
            run.meterReadingEnd = double("meter_reading_end")
            run.notes = string("notes")
            run.recordedAt = date("recorded_at") ?? run.recordedAt
            if let planID = uuid("plan_id") {
                run.plan = find(IrrigationPlan.self, id: planID, context: context, keyPath: \.id)
            }
            return true

        case "tasks":
            let task = find(FarmTask.self, id: id, context: context, keyPath: \.id) ?? {
                let created = FarmTask()
                created.id = id
                context.insert(created)
                return created
            }()
            task.title = string("title") ?? task.title
            task.detail = string("detail")
            task.dueStart = date("due_start")
            task.dueEnd = date("due_end")
            task.estimatedDurationMinutes = double("estimated_duration_minutes")
            task.priorityRaw = string("priority") ?? task.priorityRaw
            task.assignee = string("assignee")
            task.equipment = string("equipment")
            task.requiredInputs = decodeJSON([RequiredInput].self, from: json("required_inputs")) ?? []
            if let ids = json("dependency_ids") as? [Any] {
                task.dependencyIDs = ids.compactMap { ($0 as? String).flatMap(UUID.init(uuidString:)) }
            }
            task.statusRaw = string("status") ?? task.statusRaw
            task.blockedReason = string("blocked_reason")
            task.startedAt = date("started_at")
            task.completedAt = date("completed_at")
            task.actualDurationMinutes = double("actual_duration_minutes")
            task.weatherReviewNeeded = bool("weather_review_needed") ?? false
            task.weatherReviewNote = string("weather_review_note")
            task.sourceWindowDescription = string("source_window_description")
            task.completionKey = uuid("completion_key")
            task.fieldID = uuid("field_id")
            task.fieldNameSnapshot = string("field_name_snapshot") ?? ""
            task.updatedAt = date("updated_at") ?? Date()
            if let seasonID = uuid("season_id") {
                task.season = find(CropSeason.self, id: seasonID, context: context, keyPath: \.id)
            }
            return true

        case "input-applications":
            let application = find(InputApplication.self, id: id, context: context, keyPath: \.id) ?? {
                let created = InputApplication()
                created.id = id
                context.insert(created)
                return created
            }()
            application.productName = string("product_name") ?? application.productName
            application.categoryRaw = string("category") ?? application.categoryRaw
            application.registrationNote = string("registration_note")
            application.lotID = uuid("lot_id")
            application.lotLabelSnapshot = string("lot_label_snapshot")
            application.quantity = double("quantity") ?? application.quantity
            application.quantityUnitRaw = string("quantity_unit") ?? application.quantityUnitRaw
            application.areaTreatedValue = double("area_treated_value")
            application.areaUnitRaw = string("area_unit") ?? application.areaUnitRaw
            application.date = date("applied_at") ?? application.date
            application.operatorName = string("operator_name")
            application.purpose = string("purpose")
            application.weatherSnapshot = decodeJSON(WeatherSnapshot.self, from: json("weather_snapshot"))
            if let names = json("attachment_names") as? [Any] {
                application.attachmentNames = names.compactMap { $0 as? String }
            }
            application.voidedAt = date("voided_at")
            application.voidReason = string("void_reason")
            application.supersedesID = uuid("supersedes_id")
            application.fieldID = uuid("field_id")
            application.fieldNameSnapshot = string("field_name_snapshot") ?? ""
            if let seasonID = uuid("season_id") {
                application.season = find(CropSeason.self, id: seasonID, context: context, keyPath: \.id)
            }
            return true

        case "harvest-batches":
            let batch = find(HarvestBatch.self, id: id, context: context, keyPath: \.id) ?? {
                let created = HarvestBatch()
                created.id = id
                context.insert(created)
                return created
            }()
            batch.batchCode = string("batch_code") ?? batch.batchCode
            batch.startedAt = date("started_at") ?? batch.startedAt
            batch.closedAt = date("closed_at")
            batch.statusRaw = string("status") ?? batch.statusRaw
            batch.qualityGrade = string("quality_grade")
            batch.storageDestination = string("storage_destination")
            batch.crew = string("crew")
            batch.notes = string("notes")
            batch.revisions = decodeJSON([HarvestRevision].self, from: json("revisions")) ?? []
            batch.fieldID = uuid("field_id")
            batch.fieldNameSnapshot = string("field_name_snapshot") ?? ""
            if let seasonID = uuid("season_id") {
                batch.season = find(CropSeason.self, id: seasonID, context: context, keyPath: \.id)
            }
            return true

        case "harvest-loads":
            let load = find(HarvestLoad.self, id: id, context: context, keyPath: \.id) ?? {
                let created = HarvestLoad()
                created.id = id
                context.insert(created)
                return created
            }()
            load.date = date("occurred_at") ?? load.date
            load.grossQuantity = double("gross_quantity") ?? load.grossQuantity
            load.marketableQuantity = double("marketable_quantity")
            load.wasteQuantity = double("waste_quantity")
            load.unitRaw = string("unit") ?? load.unitRaw
            load.notes = string("notes")
            load.idempotencyKey = string("idempotency_key") ?? load.idempotencyKey
            load.recordedBy = string("recorded_by")
            if let batchID = uuid("batch_id") {
                load.batch = find(HarvestBatch.self, id: batchID, context: context, keyPath: \.id)
            }
            return true

        case "team-members":
            let member = find(TeamMember.self, id: id, context: context, keyPath: \.id) ?? {
                let created = TeamMember()
                created.id = id
                context.insert(created)
                return created
            }()
            member.name = string("name") ?? member.name
            member.email = string("email")
            member.roleRaw = string("role") ?? member.roleRaw
            member.invitedAt = date("invited_at") ?? member.invitedAt
            member.isActive = bool("is_active") ?? true
            if let farmID = uuid("farm_id") {
                member.farm = find(Farm.self, id: farmID, context: context, keyPath: \.id)
            }
            return true

        case "season-reviews":
            guard let seasonID = uuid("season_id") else { return false }
            let review = find(SeasonReviewRecord.self, id: id, context: context, keyPath: \.id) ?? {
                let created = SeasonReviewRecord(seasonID: seasonID)
                created.id = id
                context.insert(created)
                return created
            }()
            review.seasonID = seasonID
            review.completedAt = date("completed_at")
            review.lessons = decodeJSON([SeasonLesson].self, from: json("lessons")) ?? []
            return true

        default:
            return false
        }
    }
}
