//
//  FarmDashboardView.swift
//  GoldenAcres
//
//  Screen 1. Every card is built from records the user created. A metric with
//  no underlying data shows the reason and the action that would fill it in,
//  rather than a zero.
//

import SwiftUI
import SwiftData

struct FarmDashboardView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appState: AppState

    @Query(sort: \Farm.createdAt) private var farms: [Farm]
    @Query(sort: \FarmTask.dueEnd) private var tasks: [FarmTask]
    @Query private var lots: [InventoryLot]
    @Query(sort: \HarvestBatch.startedAt, order: .reverse) private var batches: [HarvestBatch]

    var onNavigate: (MainTabView.Tab) -> Void

    @State private var showFarmSetup = false
    @State private var showFieldEditor = false
    @State private var showSeasonEditor = false
    @State private var showObservationEditor = false
    @State private var showAlerts = false

    private var farm: Farm? { farms.first(where: { !$0.isArchived }) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                if let farm {
                    heroCard(farm)
                    quickActions
                    attentionSection(farm)
                    seasonsSection(farm)
                    tasksSection(farm)
                    weatherSection(farm)
                    irrigationSection(farm)
                    stockSection(farm)
                    harvestSection(farm)
                } else {
                    HonestEmptyState(
                        icon: "square.dashed",
                        title: "Start by adding your first field",
                        message: "There is nothing here yet, and nothing has been made up for you. Create a farm and a field, and this dashboard will fill in from your own records.",
                        actionTitle: "Create farm",
                        action: { showFarmSetup = true }
                    )
                    .padding(.top, Spacing.xxl)
                }
            }
            .padding(.horizontal, Spacing.l)
            .padding(.bottom, Spacing.xxl)
        }
        .farmBackground()
        .navigationTitle("Farm")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { SettingsView() } label: {
                    Image(systemName: "gearshape").foregroundStyle(Palette.gold)
                }
            }
        }
        .sheet(isPresented: $showFarmSetup) { FarmSetupView() }
        .sheet(isPresented: $showFieldEditor) {
            if let farm { FieldEditorView(farm: farm, field: nil) }
        }
        .sheet(isPresented: $showSeasonEditor) {
            if let farm { SeasonEditorView(farm: farm, field: nil, season: nil) }
        }
        .sheet(isPresented: $showObservationEditor) {
            if let farm { ObservationEditorView(farm: farm, field: nil, observation: nil) }
        }
        .sheet(isPresented: $showAlerts) {
            if let farm { AlertReviewView(farm: farm) }
        }
    }

    // MARK: - Hero

    private func heroCard(_ farm: Farm) -> some View {
        GoldPlate {
            VStack(alignment: .leading, spacing: Spacing.l) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Active farm").stampLabel(Palette.amber)
                        Text(farm.name)
                            .font(TypeScale.display(26))
                            .foregroundStyle(Palette.cream)
                        Text("\(farm.activeFields.count) field(s) · \(farm.unitSystem.label) · \(farm.currencyCode)")
                            .font(TypeScale.body(12))
                            .foregroundStyle(Palette.textSecondary)
                    }
                    Spacer()
                    WheatMark(size: 26)
                }

                HStack(spacing: Spacing.xl) {
                    Medallion(value: taskCompletionRatio(farm),
                              caption: "Tasks done",
                              detail: taskDetail(farm),
                              diameter: 86)
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        KeyStat(value: "\(farm.activeSeasons.count)", unit: nil, label: "Active seasons")
                        KeyStat(value: totalAreaDisplay(farm), unit: nil, label: "Recorded area")
                    }
                    Spacer()
                }
            }
            .padding(Spacing.l)
        }
    }

    private func taskCompletionRatio(_ farm: Farm) -> Double? {
        let seasonTasks = farm.activeSeasons.flatMap(\.tasks)
        guard !seasonTasks.isEmpty else { return nil }
        let done = seasonTasks.filter { $0.status == .completed }.count
        return Double(done) / Double(seasonTasks.count)
    }

    private func taskDetail(_ farm: Farm) -> String? {
        let seasonTasks = farm.activeSeasons.flatMap(\.tasks)
        guard !seasonTasks.isEmpty else { return "no tasks" }
        return "\(seasonTasks.filter { $0.status == .completed }.count)/\(seasonTasks.count)"
    }

    /// Sums area only across fields that actually have one, and says so.
    private func totalAreaDisplay(_ farm: Farm) -> String? {
        let withArea = farm.activeFields.compactMap(\.areaSquareMeters)
        guard !withArea.isEmpty else { return nil }
        let unit = farm.unitSystem.defaultArea
        let total = withArea.reduce(0, +) / unit.inSquareMeters
        let missing = farm.activeFields.count - withArea.count
        let base = "\(Fmt.number(total, decimals: 2) ?? "") \(unit.symbol)"
        return missing > 0 ? "\(base)*" : base
    }

    // MARK: - Quick actions

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeader(title: "Quick actions")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.m) {
                DashAction(title: "Add Field", icon: "plus.viewfinder") { showFieldEditor = true }
                DashAction(title: "Start Crop Season", icon: "calendar.badge.plus") { showSeasonEditor = true }
                DashAction(title: "Record Observation", icon: "eye") { showObservationEditor = true }
                DashAction(title: "Open Today's Plan", icon: "checklist") { onNavigate(.today) }
            }
            GhostButton(title: "Review Alerts", systemImage: "bell.badge") { showAlerts = true }
        }
    }

    // MARK: - Attention

    private func attentionSection(_ farm: Farm) -> some View {
        let items = AttentionEngine.items(farm: farm, tasks: tasks, lots: lots)
        return VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeader(title: "Fields needing attention",
                          subtitle: items.isEmpty ? nil : "\(items.count) item(s) from your records")
            if items.isEmpty {
                CardShell {
                    Text("Nothing is flagged. This reflects the records you have entered — it is not a statement that the fields are in good condition.")
                        .font(TypeScale.body(13))
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                CardShell {
                    VStack(spacing: 0) {
                        ForEach(items.prefix(5)) { item in
                            AttentionRow(item: item)
                            if item.id != items.prefix(5).last?.id {
                                Divider().overlay(Palette.hairline)
                            }
                        }
                        if items.count > 5 {
                            Button {
                                showAlerts = true
                            } label: {
                                Text("See all \(items.count)")
                                    .font(TypeScale.headline(13))
                                    .foregroundStyle(Palette.gold)
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, Spacing.s)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Seasons

    private func seasonsSection(_ farm: Farm) -> some View {
        let active = farm.activeSeasons
        return VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeader(title: "Active seasons",
                          actionTitle: "Start", action: { showSeasonEditor = true })
            if active.isEmpty {
                CardShell {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Text("No active season")
                            .font(TypeScale.headline(14)).foregroundStyle(Palette.cream)
                        Text("Open a crop season on a field to start linking tasks, inputs and harvest to it.")
                            .font(TypeScale.body(13)).foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        ChipButton(title: "Start crop season", systemImage: "plus") {
                            showSeasonEditor = true
                        }
                        .padding(.top, Spacing.xs)
                    }
                }
            } else {
                CardShell {
                    VStack(spacing: 0) {
                        ForEach(active) { season in
                            DrillRow(
                                title: season.displayTitle,
                                subtitle: "\(season.field?.name ?? "Detached") · \(season.openTasks.count) open task(s)",
                                trailing: Fmt.date(season.actualPlantingDate) ?? "no date"
                            ) {
                                SeasonDetailView(season: season)
                            }
                            if season.id != active.last?.id { Divider().overlay(Palette.hairline) }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Tasks

    private func tasksSection(_ farm: Farm) -> some View {
        let due = tasks.filter { $0.status.isOpen }
            .sorted { ($0.dueEnd ?? .distantFuture) < ($1.dueEnd ?? .distantFuture) }
        return VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeader(title: "Tasks due",
                          actionTitle: "Open plan", action: { onNavigate(.today) })
            if due.isEmpty {
                CardShell {
                    Text("No open tasks. Activating a season creates an empty plan — it does not invent work.")
                        .font(TypeScale.body(13)).foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                CardShell {
                    VStack(spacing: 0) {
                        ForEach(due.prefix(4)) { task in
                            DrillRow(
                                title: task.title,
                                subtitle: "\(task.fieldNameSnapshot.isEmpty ? "No field" : task.fieldNameSnapshot) · \(task.dueDisplay ?? "no due date")",
                                trailing: task.isOverdue ? "overdue" : nil,
                                tone: task.isOverdue ? Palette.amber : Palette.cream
                            ) {
                                TaskDetailView(task: task)
                            }
                            if task.id != due.prefix(4).last?.id { Divider().overlay(Palette.hairline) }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Weather

    private func weatherSection(_ farm: Farm) -> some View {
        let fieldsWithForecast = farm.activeFields.filter { $0.cachedForecast != nil }
        return VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeader(title: "Weather risks")
            CardShell {
                if fieldsWithForecast.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Text("No forecast downloaded yet")
                            .font(TypeScale.headline(14)).foregroundStyle(Palette.cream)
                        Text("Add coordinates to a field and fetch a forecast. Until then there is no weather data to show — nothing is estimated.")
                            .font(TypeScale.body(13)).foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    VStack(spacing: Spacing.m) {
                        ForEach(fieldsWithForecast) { field in
                            if let snapshot = field.cachedForecast {
                                NavigationLink {
                                    WeatherWindowsView(field: field)
                                } label: {
                                    WeatherRiskRow(field: field, snapshot: snapshot)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Irrigation

    private func irrigationSection(_ farm: Farm) -> some View {
        let plans = farm.activeFields.flatMap(\.irrigationPlans)
        return VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeader(title: "Irrigation status")
            CardShell {
                if plans.isEmpty {
                    Text("No irrigation plans yet. Build one from a field to see planned volume against water actually recorded.")
                        .font(TypeScale.body(13)).foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: Spacing.s) {
                        ForEach(plans.prefix(3)) { plan in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(plan.fieldNameSnapshot.isEmpty ? "Field" : plan.fieldNameSnapshot)
                                        .font(TypeScale.headline(13)).foregroundStyle(Palette.cream)
                                    Text(plan.zone ?? "Whole field")
                                        .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(Fmt.number(plan.calculation?.volumeLiters, decimals: 0)
                                        .map { "\($0) L planned" } ?? "not calculated")
                                        .font(TypeScale.mono(12)).foregroundStyle(Palette.gold)
                                    Text(Fmt.number(plan.totalActualLiters(), decimals: 0)
                                        .map { "\($0) L recorded" } ?? "no actual water")
                                        .font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Stock

    private func stockSection(_ farm: Farm) -> some View {
        let active = farm.inventoryLots.filter { !$0.isArchived }
        let flagged = active.filter { $0.isExpired || $0.expiresSoon || $0.availableQuantity <= 0 }
        return VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeader(title: "Input stock",
                          actionTitle: "Open", action: { onNavigate(.inventory) })
            CardShell {
                if active.isEmpty {
                    Text("No stock recorded. Add a lot to reserve it for tasks and deduct it when an application is confirmed.")
                        .font(TypeScale.body(13)).foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        HStack {
                            KeyStat(value: "\(active.count)", unit: nil, label: "Active lots")
                            Spacer()
                            KeyStat(value: "\(flagged.count)", unit: nil, label: "Need review",
                                    tone: flagged.isEmpty ? Palette.gold : Palette.amber)
                        }
                        if !flagged.isEmpty {
                            Divider().overlay(Palette.hairline)
                            ForEach(flagged.prefix(3)) { lot in
                                HStack {
                                    Text(lot.displayLabel)
                                        .font(TypeScale.body(13)).foregroundStyle(Palette.cream)
                                    Spacer()
                                    StatusPill(
                                        text: lot.isExpired ? "expired"
                                            : (lot.expiresSoon ? "expiring" : "none available"),
                                        tone: lot.isExpired ? .risk : .warning
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Harvest

    private func harvestSection(_ farm: Farm) -> some View {
        let recent = batches.filter { batch in
            farm.fields.contains { $0.id == batch.fieldID }
        }
        return VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeader(title: "Recent harvests",
                          actionTitle: "Records", action: { onNavigate(.records) })
            CardShell {
                if recent.isEmpty {
                    Text("No harvest recorded yet. Loads recorded against a batch roll up into a traceable lot.")
                        .font(TypeScale.body(13)).foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: 0) {
                        ForEach(recent.prefix(3)) { batch in
                            DrillRow(
                                title: "Batch \(batch.batchCode)",
                                subtitle: "\(batch.fieldNameSnapshot) · \(batch.loads.count) load(s)",
                                trailing: Fmt.quantity(batch.totalGross, batch.commonUnit?.symbol)
                                    ?? "mixed units"
                            ) {
                                HarvestBatchDetailView(batch: batch)
                            }
                            if batch.id != recent.prefix(3).last?.id {
                                Divider().overlay(Palette.hairline)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Supporting views

struct CardShell<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        GoldPlate {
            content
                .padding(Spacing.l)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DashAction: View {
    var title: String
    var icon: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Palette.gold)
                Text(title)
                    .font(TypeScale.headline(13))
                    .foregroundStyle(Palette.cream)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
            .padding(Spacing.m)
            .background {
                RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .fill(Plating.plateDark)
                    .overlay(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                        .strokeBorder(Palette.gold.opacity(0.22), lineWidth: 1))
            }
        }
        .buttonStyle(.plain)
    }
}

private struct WeatherRiskRow: View {
    var field: FarmField
    var snapshot: ForecastSnapshot

    var body: some View {
        let stale = snapshot.provenance.isStale()
        let next24 = snapshot.hours.filter {
            $0.time > Date() && $0.time < Date().addingTimeInterval(86400)
        }
        let rain = next24.compactMap(\.precipitationMM)
        let wind = next24.compactMap(\.windSpeedKMH).max()

        return VStack(alignment: .leading, spacing: Spacing.s) {
            HStack {
                Text(field.name).font(TypeScale.headline(14)).foregroundStyle(Palette.cream)
                Spacer()
                ProvenanceBadge(source: snapshot.provenance.source,
                                lastUpdated: snapshot.provenance.retrievedAt,
                                isStale: stale || snapshot.provenance.isCachedSnapshot)
            }
            HStack(spacing: Spacing.l) {
                ValueColumn(label: "Rain 24 h",
                            value: rain.isEmpty ? nil : Fmt.number(rain.reduce(0, +), decimals: 1),
                            unit: "mm")
                ValueColumn(label: "Peak wind",
                            value: Fmt.number(wind, decimals: 0), unit: "km/h")
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .padding(.vertical, Spacing.xs)
    }
}

struct ValueColumn: View {
    var label: String
    var value: String?
    var unit: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value ?? "—")
                    .font(TypeScale.mono(14))
                    .foregroundStyle(value == nil ? Palette.textTertiary : Palette.cream)
                if let unit, value != nil {
                    Text(unit).font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                }
            }
            Text(label).font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
        }
    }
}

private struct AttentionRow: View {
    var item: AttentionItem

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: item.icon)
                .font(.system(size: 13))
                .foregroundStyle(item.tone.color)
                .frame(width: 20)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(TypeScale.headline(13))
                    .foregroundStyle(Palette.cream)
                Text(item.detail)
                    .font(TypeScale.body(12))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.s)
    }
}
