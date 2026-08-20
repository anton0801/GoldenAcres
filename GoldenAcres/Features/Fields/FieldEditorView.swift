//
//  FieldEditorView.swift
//  GoldenAcres
//
//  Screen 2 (field half). Name, area and unit are required. A boundary is
//  optional and may be pins, imported GeoJSON, or an explicit
//  "approximate area only" — the app never implies precision it doesn't have.
//

import SwiftUI
import SwiftData

struct FieldEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var drafts: DraftStore

    var farm: Farm
    var field: FarmField?

    @State private var name = ""
    @State private var areaText = ""
    @State private var areaUnit: AreaUnit = .hectare
    @State private var soilType = ""
    @State private var irrigationMethod: IrrigationMethod?
    @State private var notes = ""
    @State private var latitudeText = ""
    @State private var longitudeText = ""
    @State private var boundaryKind: BoundaryKind = .none
    @State private var pins: [GeoPoint] = []
    @State private var geoJSONText = ""

    @State private var errors: [String: String] = [:]
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var showBoundarySheet = false
    @State private var showImportSheet = false
    @State private var showAreaRecalcPrompt = false
    @State private var derivedArea: Double?

    private var isEditing: Bool { field != nil }
    private var draftKey: String { "field.\(field?.id.uuidString ?? "new")" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    if let saveError {
                        ErrorBanner(title: "Could not save", message: saveError,
                                    onRetry: { save() }, onDismiss: { self.saveError = nil })
                    }

                    identityCard
                    boundaryCard
                    detailsCard

                    AmberButton(title: isEditing ? "Save field" : "Add field",
                                systemImage: "checkmark", isBusy: isSaving) { save() }
                }
                .padding(Spacing.l)
            }
            .farmBackground()
            .navigationTitle(isEditing ? "Edit field" : "Add field")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { cancel() }.foregroundStyle(Palette.textSecondary)
                }
            }
            .onAppear(perform: load)
            .sheet(isPresented: $showBoundarySheet) {
                BoundaryPinEditor(pins: $pins) { computed in
                    derivedArea = computed
                    boundaryKind = pins.count >= 3 ? .pins : .none
                    if computed != nil { showAreaRecalcPrompt = true }
                }
            }
            .sheet(isPresented: $showImportSheet) {
                GeoJSONImportView(text: $geoJSONText) { points, computed in
                    pins = points
                    derivedArea = computed
                    boundaryKind = .geoJSON
                    if computed != nil { showAreaRecalcPrompt = true }
                }
            }
            .alert("Recalculate area from boundary?", isPresented: $showAreaRecalcPrompt) {
                Button("Keep my entered area", role: .cancel) { }
                Button("Use boundary area") { applyDerivedArea() }
            } message: {
                if let derivedArea {
                    let converted = derivedArea / areaUnit.inSquareMeters
                    Text("The boundary encloses about \(Fmt.number(converted, decimals: 3) ?? "") \(areaUnit.symbol). Your entered area stays unless you choose to replace it.")
                } else {
                    Text("No area could be derived from this boundary.")
                }
            }
        }
    }

    // MARK: - Cards

    private var identityCard: some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.m) {
                PlateTextField(label: "Field name", placeholder: "e.g. North Paddock",
                               text: $name, isRequired: true, error: errors["name"])

                HStack(alignment: .top, spacing: Spacing.m) {
                    PlateTextField(label: "Area", placeholder: "0.00", text: $areaText,
                                   isRequired: true, keyboard: .decimalPad, error: errors["area"])
                    PlateField(label: "Unit", isRequired: true) {
                        Picker("", selection: $areaUnit) {
                            ForEach(AreaUnit.allCases) { Text($0.symbol).tag($0) }
                        }
                        .pickerStyle(.menu).tint(Palette.gold)
                    }
                    .frame(width: 108)
                }

                if isEditing, let existing = field, existing.areaValue != nil,
                   let entered = Double(areaText.replacingOccurrences(of: ",", with: ".")),
                   entered != existing.areaValue {
                    Label("Changing the area does not rewrite past calculations. Irrigation plans will offer to recalculate.",
                          systemImage: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.amber)
                }
            }
        }
    }

    private var boundaryCard: some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.m) {
                SectionHeader(title: "Boundary", subtitle: "Optional — precise coordinates are not required.")

                HStack {
                    StatusPill(text: boundaryKind.label,
                               tone: boundaryKind == .none ? .neutral : .gold)
                    Spacer()
                    if !pins.isEmpty {
                        Text("\(pins.count) point(s)")
                            .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                    }
                }

                if let derivedArea {
                    ValueRow(label: "Area enclosed by boundary",
                             value: Fmt.number(derivedArea / areaUnit.inSquareMeters, decimals: 3),
                             unit: areaUnit.symbol)
                }

                HStack(spacing: Spacing.s) {
                    ChipButton(title: "Draw boundary", systemImage: "mappin.and.ellipse") {
                        showBoundarySheet = true
                    }
                    ChipButton(title: "Import", systemImage: "square.and.arrow.down") {
                        showImportSheet = true
                    }
                }

                Toggle(isOn: Binding(
                    get: { boundaryKind == .approximateArea },
                    set: { boundaryKind = $0 ? .approximateArea : .none }
                )) {
                    Text("Area is approximate only")
                        .font(TypeScale.body(13)).foregroundStyle(Palette.cream)
                }
                .tint(Palette.amber)

                Divider().overlay(Palette.hairline)

                Text("Field centre (for forecasts)").stampLabel(Palette.textSecondary)
                HStack(spacing: Spacing.m) {
                    PlateTextField(label: "Latitude", placeholder: "—", text: $latitudeText,
                                   keyboard: .numbersAndPunctuation, error: errors["lat"])
                    PlateTextField(label: "Longitude", placeholder: "—", text: $longitudeText,
                                   keyboard: .numbersAndPunctuation, error: errors["lon"])
                }
                Text("Without a coordinate no forecast can be requested — the weather screen will say so rather than show a default location.")
                    .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var detailsCard: some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.m) {
                PlateTextField(label: "Soil type", placeholder: "Optional — leave blank if unknown",
                               text: $soilType)
                PlateField(label: "Irrigation method") {
                    Picker("", selection: $irrigationMethod) {
                        Text("Unknown").tag(IrrigationMethod?.none)
                        ForEach(IrrigationMethod.allCases) {
                            Text($0.rawValue).tag(IrrigationMethod?.some($0))
                        }
                    }
                    .pickerStyle(.menu).tint(Palette.gold)
                }
                PlateTextField(label: "Notes", placeholder: "Anything worth remembering",
                               text: $notes, axis: .vertical)
            }
        }
    }

    // MARK: - Logic

    private func load() {
        if let field {
            name = field.name
            areaText = field.areaValue.map { String($0) } ?? ""
            areaUnit = field.areaUnit
            soilType = field.soilType ?? ""
            irrigationMethod = field.irrigationMethod
            notes = field.notes ?? ""
            latitudeText = field.latitude.map { String($0) } ?? ""
            longitudeText = field.longitude.map { String($0) } ?? ""
            boundaryKind = field.boundary.kind
            pins = field.boundary.points
            geoJSONText = field.boundary.geoJSONText ?? ""
            derivedArea = field.boundary.derivedAreaSquareMeters
        } else if let draft = drafts.load(FieldDraft.self, key: draftKey) {
            name = draft.name
            areaText = draft.areaText
            areaUnit = draft.areaUnit
            soilType = draft.soilType
            notes = draft.notes
        }
    }

    private func cancel() {
        let hasContent = !name.isEmpty || !areaText.isEmpty || !notes.isEmpty || !soilType.isEmpty
        if hasContent && !isEditing {
            drafts.save(FieldDraft(name: name, areaText: areaText, areaUnit: areaUnit,
                                   soilType: soilType, notes: notes), key: draftKey)
            appState.confirm("Draft saved", detail: "Your entries are kept for next time.")
        }
        dismiss()
    }

    private func applyDerivedArea() {
        guard let derivedArea else { return }
        areaText = String(format: "%.4f", derivedArea / areaUnit.inSquareMeters)
    }

    private func save() {
        guard !isSaving else { return }
        errors = [:]
        saveError = nil

        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if trimmedName.isEmpty { errors["name"] = "Enter a field name." }

        let normalized = areaText.replacingOccurrences(of: ",", with: ".")
        let area = Double(normalized)
        if area == nil {
            errors["area"] = areaText.isEmpty ? "Enter the field area." : "Enter a valid number."
        } else if area! <= 0 {
            errors["area"] = "Area must be greater than zero."
        }

        var latitude: Double?
        var longitude: Double?
        if !latitudeText.isEmpty || !longitudeText.isEmpty {
            latitude = Double(latitudeText.replacingOccurrences(of: ",", with: "."))
            longitude = Double(longitudeText.replacingOccurrences(of: ",", with: "."))
            if latitude == nil || latitude! < -90 || latitude! > 90 {
                errors["lat"] = "Latitude must be between −90 and 90."
            }
            if longitude == nil || longitude! < -180 || longitude! > 180 {
                errors["lon"] = "Longitude must be between −180 and 180."
            }
        }

        if pins.count >= 3, BoundaryGeometry.selfIntersects(pins) {
            errors["name"] = "The boundary crosses itself. Fix the outline before saving."
        }

        guard errors.isEmpty, let finalArea = area else { return }

        isSaving = true
        let target = field ?? FarmField()
        let isNew = field == nil

        target.name = trimmedName
        target.areaValue = finalArea
        target.areaUnit = areaUnit
        target.soilType = soilType.trimmingCharacters(in: .whitespaces).isEmpty
            ? nil : soilType.trimmingCharacters(in: .whitespaces)
        target.irrigationMethod = irrigationMethod
        target.notes = notes.trimmingCharacters(in: .whitespaces).isEmpty ? nil : notes
        target.latitude = latitude
        target.longitude = longitude
        target.boundary = FieldBoundary(
            kind: boundaryKind,
            points: pins,
            geoJSONText: geoJSONText.isEmpty ? nil : geoJSONText,
            derivedAreaSquareMeters: derivedArea
        )
        target.updatedAt = Date()

        if isNew {
            target.farm = farm
            context.insert(target)
            farm.fields.append(target)
        }

        AuditService.log(action: isNew ? "Created" : "Updated", entityType: "Field",
                         entityID: target.id,
                         summary: "\(isNew ? "Created" : "Updated") field “\(target.name)”",
                         details: "Area \(Fmt.quantity(finalArea, areaUnit.symbol) ?? "")",
                         context: context)

        do {
            try context.save()
            drafts.clear(key: draftKey)
            appState.confirm(isNew ? "Field added" : "Field saved",
                             detail: "\(target.name) · \(Fmt.quantity(finalArea, areaUnit.symbol) ?? "")")
            isSaving = false
            dismiss()
        } catch {
            isSaving = false
            saveError = error.localizedDescription
        }
    }
}

// MARK: - Draft

struct FieldDraft: Codable {
    var name: String
    var areaText: String
    var areaUnit: AreaUnit
    var soilType: String
    var notes: String
}

// MARK: - Boundary geometry

enum BoundaryGeometry {

    /// Spherical-excess area for a small polygon, in square metres.
    static func area(of points: [GeoPoint]) -> Double? {
        guard points.count >= 3 else { return nil }
        let earthRadius = 6_378_137.0
        var total: Double = 0
        for index in 0..<points.count {
            let p1 = points[index]
            let p2 = points[(index + 1) % points.count]
            let lon1 = p1.longitude * .pi / 180
            let lon2 = p2.longitude * .pi / 180
            let lat1 = p1.latitude * .pi / 180
            let lat2 = p2.latitude * .pi / 180
            total += (lon2 - lon1) * (2 + sin(lat1) + sin(lat2))
        }
        let value = abs(total * earthRadius * earthRadius / 2)
        return value.isFinite && value > 0 ? value : nil
    }

    /// Rejects an outline whose edges cross, which would make the area meaningless.
    static func selfIntersects(_ points: [GeoPoint]) -> Bool {
        guard points.count >= 4 else { return false }
        let count = points.count
        for i in 0..<count {
            let a1 = points[i], a2 = points[(i + 1) % count]
            for j in (i + 1)..<count {
                // Skip adjacent edges, which legitimately share a vertex.
                if j == i || (j + 1) % count == i || j == (i + 1) % count { continue }
                let b1 = points[j], b2 = points[(j + 1) % count]
                if segmentsIntersect(a1, a2, b1, b2) { return true }
            }
        }
        return false
    }

    private static func segmentsIntersect(_ p1: GeoPoint, _ p2: GeoPoint,
                                          _ p3: GeoPoint, _ p4: GeoPoint) -> Bool {
        func orientation(_ a: GeoPoint, _ b: GeoPoint, _ c: GeoPoint) -> Int {
            let value = (b.latitude - a.latitude) * (c.longitude - b.longitude)
                - (b.longitude - a.longitude) * (c.latitude - b.latitude)
            if abs(value) < 1e-12 { return 0 }
            return value > 0 ? 1 : 2
        }
        let o1 = orientation(p1, p2, p3)
        let o2 = orientation(p1, p2, p4)
        let o3 = orientation(p3, p4, p1)
        let o4 = orientation(p3, p4, p2)
        return o1 != o2 && o3 != o4
    }
}

// MARK: - Pin editor

struct BoundaryPinEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var pins: [GeoPoint]
    var onDone: (Double?) -> Void

    @State private var latText = ""
    @State private var lonText = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    Text("Add the corner points of the field. Three or more points give an enclosed area. You can also skip this and record an approximate area instead.")
                        .font(TypeScale.body(13)).foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    CardShell {
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            HStack(spacing: Spacing.m) {
                                PlateTextField(label: "Latitude", placeholder: "0.0000",
                                               text: $latText, keyboard: .numbersAndPunctuation)
                                PlateTextField(label: "Longitude", placeholder: "0.0000",
                                               text: $lonText, keyboard: .numbersAndPunctuation)
                            }
                            if let error {
                                Label(error, systemImage: "exclamationmark.circle.fill")
                                    .font(.system(size: 11)).foregroundStyle(Palette.burgundy)
                            }
                            ChipButton(title: "Add point", systemImage: "plus") { addPin() }
                        }
                    }

                    if pins.isEmpty {
                        HonestEmptyState(icon: "mappin.slash", title: "No points yet",
                                         message: "Points you add appear here with their coordinates.")
                    } else {
                        CardShell {
                            VStack(spacing: 0) {
                                ForEach(Array(pins.enumerated()), id: \.element.id) { index, pin in
                                    HStack {
                                        Text("\(index + 1)")
                                            .font(TypeScale.mono(12))
                                            .foregroundStyle(Palette.gold)
                                            .frame(width: 22)
                                        Text("\(String(format: "%.5f", pin.latitude)), \(String(format: "%.5f", pin.longitude))")
                                            .font(TypeScale.mono(12))
                                            .foregroundStyle(Palette.cream)
                                        Spacer()
                                        Button {
                                            pins.removeAll { $0.id == pin.id }
                                        } label: {
                                            Image(systemName: "minus.circle")
                                                .foregroundStyle(Palette.burgundy)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.vertical, Spacing.s)
                                    if pin.id != pins.last?.id { Divider().overlay(Palette.hairline) }
                                }
                            }
                        }

                        if pins.count >= 3 {
                            let crosses = BoundaryGeometry.selfIntersects(pins)
                            if crosses {
                                ErrorBanner(title: "Outline crosses itself",
                                            message: "Reorder or remove points so the edges don't intersect. An area cannot be derived from a crossed outline.",
                                            onRetry: nil, onDismiss: nil)
                            } else if let area = BoundaryGeometry.area(of: pins) {
                                CardShell {
                                    ValueRow(label: "Enclosed area",
                                             value: Fmt.number(area / 10_000, decimals: 4),
                                             unit: "ha")
                                }
                            }
                        }
                    }
                }
                .padding(Spacing.l)
            }
            .farmBackground()
            .navigationTitle("Draw boundary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Use boundary") {
                        onDone(BoundaryGeometry.selfIntersects(pins) ? nil : BoundaryGeometry.area(of: pins))
                        dismiss()
                    }
                    .foregroundStyle(Palette.gold)
                    .disabled(pins.count >= 3 && BoundaryGeometry.selfIntersects(pins))
                }
            }
        }
    }

    private func addPin() {
        error = nil
        guard let lat = Double(latText.replacingOccurrences(of: ",", with: ".")),
              lat >= -90, lat <= 90 else {
            error = "Latitude must be a number between −90 and 90."
            return
        }
        guard let lon = Double(lonText.replacingOccurrences(of: ",", with: ".")),
              lon >= -180, lon <= 180 else {
            error = "Longitude must be a number between −180 and 180."
            return
        }
        pins.append(GeoPoint(latitude: lat, longitude: lon))
        latText = ""
        lonText = ""
    }
}

// MARK: - GeoJSON import

struct GeoJSONImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var text: String
    var onImport: ([GeoPoint], Double?) -> Void

    @State private var error: String?
    @State private var parsedCount: Int?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    Text("Paste a GeoJSON Polygon. The original text is kept with the field exactly as provided.")
                        .font(TypeScale.body(13)).foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    CardShell {
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            PlateTextField(label: "GeoJSON", placeholder: "{ \"type\": \"Polygon\", ... }",
                                           text: $text, error: error, axis: .vertical)
                            if let parsedCount {
                                Label("\(parsedCount) point(s) read", systemImage: "checkmark.seal.fill")
                                    .font(.system(size: 12)).foregroundStyle(Palette.positive)
                            }
                            ChipButton(title: "Parse", systemImage: "wand.and.stars") { parse() }
                        }
                    }
                }
                .padding(Spacing.l)
            }
            .farmBackground()
            .navigationTitle("Import boundary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.textSecondary)
                }
            }
        }
    }

    private func parse() {
        error = nil
        parsedCount = nil
        guard let data = text.data(using: .utf8) else {
            error = "The text could not be read."
            return
        }
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                error = "Expected a GeoJSON object."
                return
            }
            let geometry = (object["geometry"] as? [String: Any]) ?? object
            guard let type = geometry["type"] as? String, type.lowercased() == "polygon",
                  let coordinates = geometry["coordinates"] as? [[[Double]]],
                  let ring = coordinates.first else {
                error = "Only a Polygon geometry is supported here."
                return
            }
            let points = ring.compactMap { pair -> GeoPoint? in
                guard pair.count >= 2 else { return nil }
                return GeoPoint(latitude: pair[1], longitude: pair[0])
            }
            guard points.count >= 3 else {
                error = "The polygon needs at least three points."
                return
            }
            if BoundaryGeometry.selfIntersects(points) {
                error = "This outline crosses itself, so no area can be derived from it."
                return
            }
            parsedCount = points.count
            onImport(points, BoundaryGeometry.area(of: points))
            dismiss()
        } catch {
            self.error = "Could not parse: \(error.localizedDescription)"
        }
    }
}
