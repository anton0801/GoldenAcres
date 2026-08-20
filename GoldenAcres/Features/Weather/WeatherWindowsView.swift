//
//  WeatherWindowsView.swift
//  GoldenAcres
//
//  Screen 5. Hourly conditions plus user-defined thresholds. Every accepted
//  and rejected interval states its reason, the forecast horizon is explicit,
//  and a cached snapshot is always labelled as such.
//

import SwiftUI
import SwiftData

struct WeatherWindowsView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appState: AppState

    var field: FarmField

    @State private var conditions = WorkWindowEngine.startingThresholds(for: .spraying)
    @State private var analysis: WorkWindowAnalysis?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var fallbackReason: String?
    @State private var showConditions = false
    @State private var explainWindow: WorkWindow?
    @State private var addToPlanWindow: WorkWindow?

    private var snapshot: ForecastSnapshot? { field.cachedForecast }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                if field.resolvedCoordinate == nil {
                    HonestEmptyState(
                        icon: "location.slash",
                        title: "No location for this field",
                        message: "A forecast can only be requested for a coordinate. Add a field centre or a boundary, and no default location will be substituted."
                    )
                    .padding(.top, Spacing.xl)
                } else {
                    sourceCard
                    if let errorMessage {
                        ErrorBanner(title: "Forecast unavailable", message: errorMessage,
                                    onRetry: { refresh() }, onDismiss: { self.errorMessage = nil })
                    }
                    if let fallbackReason {
                        CachedNotice(source: snapshot?.provenance.source ?? "Forecast",
                                     capturedAt: snapshot?.provenance.retrievedAt)
                        Text(fallbackReason)
                            .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if isLoading && snapshot == nil {
                        CardShell { LoadingBlock(lines: 4) }
                    } else if let snapshot {
                        hourlyCard(snapshot)
                        conditionsCard
                        windowsCard
                    } else {
                        HonestEmptyState(
                            icon: "cloud.sun",
                            title: "No forecast downloaded",
                            message: "Fetch a forecast to compare it against your own work thresholds.",
                            actionTitle: "Fetch forecast",
                            action: { refresh() }
                        )
                    }
                }
            }
            .padding(Spacing.l)
            .padding(.bottom, Spacing.xxl)
        }
        .farmBackground()
        .navigationTitle("Weather")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { refresh() } label: {
                    Image(systemName: "arrow.clockwise").foregroundStyle(Palette.gold)
                }
                .disabled(isLoading || field.resolvedCoordinate == nil)
            }
        }
        .sheet(isPresented: $showConditions) {
            WorkConditionsEditor(conditions: $conditions) { runAnalysis() }
        }
        .sheet(item: $explainWindow) { window in
            WindowExplanationView(window: window, conditions: conditions)
        }
        .sheet(item: $addToPlanWindow) { window in
            AddWindowToPlanView(field: field, window: window, conditions: conditions)
        }
        .onAppear {
            if snapshot == nil { refresh() } else { runAnalysis() }
        }
    }

    // MARK: - Cards

    private var sourceCard: some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack {
                    Text(field.name).font(TypeScale.headline(15)).foregroundStyle(Palette.cream)
                    Spacer()
                    if let snapshot {
                        ProvenanceBadge(
                            source: snapshot.provenance.source,
                            lastUpdated: snapshot.provenance.retrievedAt,
                            isStale: snapshot.provenance.isStale() || snapshot.provenance.isCachedSnapshot
                        )
                    }
                }
                if let coordinate = field.resolvedCoordinate {
                    Text("Requested for \(String(format: "%.4f", coordinate.lat)), \(String(format: "%.4f", coordinate.lon))")
                        .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                }
                if let snapshot, let horizon = snapshot.horizonEnd {
                    Text("Forecast horizon ends \(Fmt.dateTime(horizon) ?? ""). Beyond it this screen shows no reliable forecast rather than an estimate.")
                        .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if isLoading {
                    HStack(spacing: Spacing.s) {
                        ProgressView().tint(Palette.gold).scaleEffect(0.7)
                        Text("Fetching…").font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                    }
                }
            }
        }
    }

    private func hourlyCard(_ snapshot: ForecastSnapshot) -> some View {
        let upcoming = snapshot.hours.filter { $0.time > Date().addingTimeInterval(-3600) }.prefix(24)
        return VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeader(title: "Next hours", subtitle: "Values the provider supplied; blanks are gaps.")
            CardShell {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.l) {
                        ForEach(Array(upcoming)) { hour in
                            VStack(spacing: Spacing.xs) {
                                Text(hour.time.formatted(.dateTime.hour()))
                                    .font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                                Text(Fmt.number(hour.temperatureC, decimals: 0).map { "\($0)°" } ?? "—")
                                    .font(TypeScale.mono(15))
                                    .foregroundStyle(hour.temperatureC == nil ? Palette.textTertiary : Palette.cream)
                                Image(systemName: (hour.precipitationMM ?? 0) > 0.1 ? "cloud.rain" : "sun.max")
                                    .font(.system(size: 11))
                                    .foregroundStyle((hour.precipitationMM ?? 0) > 0.1 ? Palette.amber : Palette.gold)
                                Text(Fmt.number(hour.windSpeedKMH, decimals: 0).map { "\($0)" } ?? "—")
                                    .font(.system(size: 10)).foregroundStyle(Palette.textSecondary)
                                Text("km/h").font(.system(size: 8)).foregroundStyle(Palette.textTertiary)
                            }
                            .frame(width: 44)
                        }
                    }
                }
            }
        }
    }

    private var conditionsCard: some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.m) {
                SectionHeader(title: "Your work conditions",
                              actionTitle: "Edit", action: { showConditions = true })
                HStack {
                    Image(systemName: conditions.workType.icon).foregroundStyle(Palette.gold)
                    Text(conditions.workType.rawValue)
                        .font(TypeScale.headline(14)).foregroundStyle(Palette.cream)
                    Spacer()
                }
                if conditions.hasAnyThreshold {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(thresholdSummary, id: \.self) { line in
                            Text("• \(line)").font(.system(size: 12))
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                } else {
                    Text("No thresholds set, so every hour with data passes. Set limits to make this meaningful.")
                        .font(TypeScale.body(12)).foregroundStyle(Palette.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
                AmberButton(title: "Find window", systemImage: "magnifyingglass") { runAnalysis() }
            }
        }
    }

    private var thresholdSummary: [String] {
        var out: [String] = []
        if let v = conditions.minTemperatureC { out.append("Temperature at least \(Fmt.number(v, decimals: 0) ?? "") °C") }
        if let v = conditions.maxTemperatureC { out.append("Temperature at most \(Fmt.number(v, decimals: 0) ?? "") °C") }
        if let v = conditions.maxWindKMH { out.append("Wind at most \(Fmt.number(v, decimals: 0) ?? "") km/h") }
        if let v = conditions.maxPrecipitationMM { out.append("Rain at most \(Fmt.number(v, decimals: 1) ?? "") mm/h") }
        if let v = conditions.minHumidityPercent { out.append("Humidity at least \(Fmt.number(v, decimals: 0) ?? "") %") }
        if let v = conditions.maxHumidityPercent { out.append("Humidity at most \(Fmt.number(v, decimals: 0) ?? "") %") }
        if let v = conditions.minSoilTemperatureC { out.append("Soil temperature at least \(Fmt.number(v, decimals: 0) ?? "") °C") }
        out.append("Minimum stretch \(conditions.minimumDurationHours) h")
        if conditions.daylightOnly { out.append("Daylight only") }
        return out
    }

    private var windowsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeader(title: "Work windows",
                          subtitle: "A planning hint from forecast data — not a guarantee of conditions.")

            if let analysis {
                if !analysis.unavailableVariables.isEmpty {
                    CardShell {
                        Label("The forecast did not supply: \(analysis.unavailableVariables.joined(separator: ", ")). Thresholds on those could not be checked, so affected hours are marked “cannot verify” rather than passed.",
                              systemImage: "questionmark.circle")
                            .font(TypeScale.body(12)).foregroundStyle(Palette.amber)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if analysis.accepted.isEmpty {
                    CardShell {
                        VStack(alignment: .leading, spacing: Spacing.s) {
                            Text("No window matches your conditions")
                                .font(TypeScale.headline(14)).foregroundStyle(Palette.cream)
                            Text("Checked \(analysis.evaluatedHourCount) forecast hour(s). The rejected stretches below explain why.")
                                .font(TypeScale.body(12)).foregroundStyle(Palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    ForEach(analysis.accepted) { window in
                        WindowCard(window: window, isAccepted: true,
                                   onExplain: { explainWindow = window },
                                   onAdd: { addToPlanWindow = window })
                    }
                }

                if !analysis.rejected.isEmpty {
                    Text("Rejected stretches").stampLabel(Palette.textSecondary)
                    ForEach(analysis.rejected.prefix(6)) { window in
                        WindowCard(window: window, isAccepted: false,
                                   onExplain: { explainWindow = window }, onAdd: nil)
                    }
                }
            } else {
                CardShell {
                    Text("Set your conditions and tap Find window.")
                        .font(TypeScale.body(13)).foregroundStyle(Palette.textSecondary)
                }
            }
        }
    }

    // MARK: - Logic

    private func refresh() {
        guard let coordinate = field.resolvedCoordinate else { return }
        isLoading = true
        errorMessage = nil
        fallbackReason = nil

        Task {
            let result = await WeatherService.shared.forecast(
                latitude: coordinate.lat,
                longitude: coordinate.lon,
                cached: field.cachedForecast
            )
            await MainActor.run {
                isLoading = false
                switch result {
                case .success(let fetch):
                    field.cachedForecast = fetch.snapshot
                    try? context.save()
                    fallbackReason = fetch.fallbackReason
                    runAnalysis()
                case .failure(let error):
                    errorMessage = error.errorDescription
                }
            }
        }
    }

    private func runAnalysis() {
        guard let snapshot else { return }
        analysis = WorkWindowEngine.analyze(snapshot: snapshot, conditions: conditions)
    }
}

// MARK: - Window card

private struct WindowCard: View {
    var window: WorkWindow
    var isAccepted: Bool
    var onExplain: () -> Void
    var onAdd: (() -> Void)?

    var body: some View {
        GoldPlate(accent: isAccepted ? Palette.positive : Palette.burgundy) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack {
                    Text(window.summary)
                        .font(TypeScale.headline(14)).foregroundStyle(Palette.cream)
                    Spacer()
                    StatusPill(text: isAccepted ? "\(window.durationHours) h fits" : "rejected",
                               tone: isAccepted ? .positive : .risk)
                }

                if isAccepted {
                    HStack(spacing: Spacing.l) {
                        ValueColumn(label: "Peak wind",
                                    value: Fmt.number(window.peakWind, decimals: 0), unit: "km/h")
                        ValueColumn(label: "Total rain",
                                    value: Fmt.number(window.totalRain, decimals: 1), unit: "mm")
                        if let range = window.temperatureRange {
                            ValueColumn(label: "Temp range",
                                        value: "\(Fmt.number(range.min, decimals: 0) ?? "")–\(Fmt.number(range.max, decimals: 0) ?? "")",
                                        unit: "°C")
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(window.rejectionReasons, id: \.self) { reason in
                            Text("• \(reason)")
                                .font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                HStack(spacing: Spacing.s) {
                    ChipButton(title: "Why this window?", systemImage: "info.circle", action: onExplain)
                    if let onAdd {
                        ChipButton(title: "Add to plan", systemImage: "plus", action: onAdd)
                    }
                }
            }
            .padding(Spacing.l)
        }
    }
}

// MARK: - Conditions editor

struct WorkConditionsEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var conditions: WorkConditions
    var onApply: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    Text("These are your limits, not recommendations. The app has no opinion on what is safe or effective for your crop — check the product label and local rules.")
                        .font(TypeScale.body(12)).foregroundStyle(Palette.amber)
                        .fixedSize(horizontal: false, vertical: true)

                    CardShell {
                        PlateField(label: "Work type") {
                            Picker("", selection: $conditions.workType) {
                                ForEach(WorkType.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.menu).tint(Palette.gold)
                        }
                    }

                    CardShell {
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            SectionHeader(title: "Thresholds",
                                          subtitle: "Leave blank to not check that variable.")
                            OptionalNumberRow(label: "Min temperature", unit: "°C",
                                              value: $conditions.minTemperatureC)
                            OptionalNumberRow(label: "Max temperature", unit: "°C",
                                              value: $conditions.maxTemperatureC)
                            OptionalNumberRow(label: "Max wind", unit: "km/h",
                                              value: $conditions.maxWindKMH)
                            OptionalNumberRow(label: "Max rain per hour", unit: "mm",
                                              value: $conditions.maxPrecipitationMM)
                            OptionalNumberRow(label: "Min humidity", unit: "%",
                                              value: $conditions.minHumidityPercent)
                            OptionalNumberRow(label: "Max humidity", unit: "%",
                                              value: $conditions.maxHumidityPercent)
                            OptionalNumberRow(label: "Min soil temperature", unit: "°C",
                                              value: $conditions.minSoilTemperatureC)
                        }
                    }

                    CardShell {
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            Stepper("Minimum stretch: \(conditions.minimumDurationHours) h",
                                    value: $conditions.minimumDurationHours, in: 1...24)
                                .font(TypeScale.body(14))
                                .foregroundStyle(Palette.cream)
                                .tint(Palette.gold)
                            Toggle(isOn: $conditions.daylightOnly) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Daylight only").font(TypeScale.body(14))
                                        .foregroundStyle(Palette.cream)
                                    Text("Uses sunrise/sunset from the provider. Days without those values are marked “cannot verify”.")
                                        .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                                }
                            }
                            .tint(Palette.amber)
                        }
                    }

                    AmberButton(title: "Apply and find windows", systemImage: "checkmark") {
                        onApply()
                        dismiss()
                    }

                    GhostButton(title: "Reset to a starting point for \(conditions.workType.rawValue)",
                                systemImage: "arrow.counterclockwise") {
                        conditions = WorkWindowEngine.startingThresholds(for: conditions.workType)
                    }
                }
                .padding(Spacing.l)
            }
            .farmBackground()
            .navigationTitle("Work conditions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.textSecondary)
                }
            }
        }
    }
}

struct OptionalNumberRow: View {
    var label: String
    var unit: String
    @Binding var value: Double?
    @State private var text = ""

    var body: some View {
        HStack {
            Text(label).font(TypeScale.body(13)).foregroundStyle(Palette.textSecondary)
            Spacer()
            TextField("—", text: $text)
                .font(TypeScale.mono(14))
                .foregroundStyle(Palette.cream)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
                .padding(.vertical, 6).padding(.horizontal, Spacing.s)
                .background(RoundedRectangle(cornerRadius: 8).fill(Palette.graphite.opacity(0.7)))
                .onChange(of: text) { _, newValue in
                    value = Double(newValue.replacingOccurrences(of: ",", with: "."))
                }
            Text(unit).font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                .frame(width: 34, alignment: .leading)
        }
        .onAppear {
            if let value { text = Fmt.number(value, decimals: 1) ?? "" }
        }
    }
}

// MARK: - Explanation

struct WindowExplanationView: View {
    @Environment(\.dismiss) private var dismiss
    var window: WorkWindow
    var conditions: WorkConditions

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    Text(window.summary).font(TypeScale.title(18)).foregroundStyle(Palette.cream)
                    Text("Each hour was checked against your thresholds. This is forecast data, so it describes what is predicted, not what will happen.")
                        .font(TypeScale.body(12)).foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(window.verdicts) { verdict in
                        CardShell {
                            VStack(alignment: .leading, spacing: Spacing.s) {
                                HStack {
                                    Text(verdict.hour.time.formatted(date: .omitted, time: .shortened))
                                        .font(TypeScale.mono(14)).foregroundStyle(Palette.cream)
                                    Spacer()
                                    StatusPill(
                                        text: verdict.outcome == .pass ? "passes"
                                            : (verdict.outcome == .fail ? "fails" : "cannot verify"),
                                        tone: verdict.outcome == .pass ? .positive
                                            : (verdict.outcome == .fail ? .risk : .warning)
                                    )
                                }
                                HStack(spacing: Spacing.l) {
                                    ValueColumn(label: "Temp",
                                                value: Fmt.number(verdict.hour.temperatureC, decimals: 1),
                                                unit: "°C")
                                    ValueColumn(label: "Wind",
                                                value: Fmt.number(verdict.hour.windSpeedKMH, decimals: 0),
                                                unit: "km/h")
                                    ValueColumn(label: "Rain",
                                                value: Fmt.number(verdict.hour.precipitationMM, decimals: 1),
                                                unit: "mm")
                                    ValueColumn(label: "Humidity",
                                                value: Fmt.number(verdict.hour.humidityPercent, decimals: 0),
                                                unit: "%")
                                }
                                ForEach(verdict.failures, id: \.self) { failure in
                                    Label(failure, systemImage: "xmark.circle")
                                        .font(.system(size: 11)).foregroundStyle(Palette.burgundy)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                ForEach(verdict.unverified, id: \.self) { note in
                                    Label(note, systemImage: "questionmark.circle")
                                        .font(.system(size: 11)).foregroundStyle(Palette.amber)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                .padding(Spacing.l)
            }
            .farmBackground()
            .navigationTitle("Why this window?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(Palette.gold)
                }
            }
        }
    }
}

// MARK: - Add to plan

struct AddWindowToPlanView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    var field: FarmField
    var window: WorkWindow
    var conditions: WorkConditions

    @State private var title = ""
    @State private var selectedSeason: CropSeason?
    @State private var error: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    CardShell {
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            Text("A task will be created with this window as its due period. The window is recorded as the source; it is not a commitment about conditions.")
                                .font(TypeScale.body(12)).foregroundStyle(Palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)

                            PlateTextField(label: "Task title",
                                           placeholder: "e.g. \(conditions.workType.rawValue) — \(field.name)",
                                           text: $title, isRequired: true, error: error)

                            PlateField(label: "Season") {
                                Picker("", selection: $selectedSeason) {
                                    Text("No season").tag(CropSeason?.none)
                                    ForEach(field.seasons.filter { $0.status == .active }) { season in
                                        Text(season.displayTitle).tag(CropSeason?.some(season))
                                    }
                                }
                                .pickerStyle(.menu).tint(Palette.gold)
                            }

                            ValueRow(label: "Due window", value: window.summary)
                        }
                    }

                    AmberButton(title: "Add to plan", systemImage: "plus", isBusy: isSaving) { save() }
                }
                .padding(Spacing.l)
            }
            .farmBackground()
            .navigationTitle("Add to plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.textSecondary)
                }
            }
            .onAppear {
                if title.isEmpty { title = "\(conditions.workType.rawValue) — \(field.name)" }
                selectedSeason = field.currentSeason
            }
        }
    }

    private func save() {
        guard !isSaving else { return }
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            error = "Enter a task title."
            return
        }
        isSaving = true

        let task = FarmTask(title: title.trimmingCharacters(in: .whitespaces), season: selectedSeason)
        task.dueStart = window.start
        task.dueEnd = window.end
        task.fieldID = field.id
        task.fieldNameSnapshot = field.name
        task.sourceWindowDescription = "\(conditions.workType.rawValue) window from forecast: \(window.summary)"
        context.insert(task)
        selectedSeason?.tasks.append(task)

        AuditService.log(action: "Created", entityType: "Task", entityID: task.id,
                         summary: "Task “\(task.title)” created from a forecast window",
                         details: task.sourceWindowDescription, context: context)

        do {
            try context.save()
            appState.confirm("Task added to plan", detail: window.summary)
            isSaving = false
            dismiss()
        } catch {
            isSaving = false
            self.error = error.localizedDescription
        }
    }
}
