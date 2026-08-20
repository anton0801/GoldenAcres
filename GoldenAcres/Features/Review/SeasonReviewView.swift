//
//  SeasonReviewView.swift
//  GoldenAcres
//
//  Screen 13. Metrics with drill-down, lessons the user writes themselves, and
//  cross-season comparison that refuses to run when units or areas are not
//  comparable. Co-occurrence is never described as cause.
//

import SwiftUI
import SwiftData

struct SeasonReviewView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appState: AppState
    @Query private var lots: [InventoryLot]
    @Query private var reviews: [SeasonReviewRecord]

    var season: CropSeason

    @State private var showCloseConfirm = false
    @State private var showLessonSheet = false
    @State private var lessonText = ""

    private var metrics: SeasonMetrics {
        SeasonInsights.metrics(for: season, allLots: lots)
    }

    private var review: SeasonReviewRecord? {
        reviews.first { $0.seasonID == season.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                if season.status != .closed { openBanner }
                yieldCard
                tasksCard
                inputsCard
                waterCard
                observationsCard
                if !metrics.gaps.isEmpty { gapsCard }
                lessonsCard
            }
            .padding(Spacing.l)
            .padding(.bottom, Spacing.xxl)
        }
        .farmBackground()
        .navigationTitle("Season review")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showLessonSheet) { lessonSheet }
        .alert("Close this season?", isPresented: $showCloseConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Close season") {
                HarvestService.closeSeason(season, context: context)
                try? context.save()
                appState.confirm("Season closed", detail: "A snapshot of these figures was stored.")
            }
        } message: {
            Text("A snapshot is stored so later edits elsewhere cannot change this season's outcome.")
        }
    }

    // MARK: - Cards

    private var openBanner: some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Label("Season is still \(season.status.label.lowercased())",
                      systemImage: "hourglass")
                    .font(TypeScale.headline(14)).foregroundStyle(Palette.amber)
                Text("These figures are provisional and will change as you record more. Closing the season freezes them.")
                    .font(TypeScale.body(12)).foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if season.status == .active {
                    AmberButton(title: "Close season", systemImage: "flag.checkered") {
                        showCloseConfirm = true
                    }
                }
            }
        }
    }

    private var yieldCard: some View {
        GoldPlate {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Text("Yield").stampLabel(Palette.amber)
                HStack(spacing: Spacing.xl) {
                    Medallion(value: metrics.wasteRatio.map { 1 - $0 },
                              caption: "Marketable share",
                              detail: metrics.wasteRatio == nil ? "not recorded" : nil,
                              diameter: 88)
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        KeyStat(value: Fmt.number(metrics.marketable, decimals: 1),
                                unit: metrics.unit?.symbol, label: "Marketable",
                                tone: Palette.positive)
                        KeyStat(value: Fmt.number(metrics.gross, decimals: 1),
                                unit: metrics.unit?.symbol, label: "Gross")
                        KeyStat(value: Fmt.number(metrics.yieldPerHectare, decimals: 1),
                                unit: metrics.unit.map { "\($0.symbol)/ha" }, label: "Per hectare")
                    }
                    Spacer()
                }

                Divider().overlay(Palette.hairline)

                if season.harvestBatches.isEmpty {
                    Text("No harvest batches recorded for this season.")
                        .font(TypeScale.body(12)).foregroundStyle(Palette.textSecondary)
                } else {
                    Text("From \(season.harvestBatches.count) batch(es)").stampLabel(Palette.textSecondary)
                    ForEach(season.harvestBatches) { batch in
                        DrillRow(title: "Batch \(batch.batchCode)",
                                 subtitle: "\(batch.loads.count) load(s) · \(batch.status.rawValue)",
                                 trailing: Fmt.quantity(batch.totalGross,
                                                        batch.commonUnit?.symbol)) {
                            HarvestBatchDetailView(batch: batch)
                        }
                    }
                }
            }
            .padding(Spacing.l)
        }
    }

    private var tasksCard: some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader(title: "Planned vs actual tasks")
                HStack(spacing: Spacing.xl) {
                    KeyStat(value: "\(metrics.plannedTasks)", unit: nil, label: "Planned")
                    KeyStat(value: "\(metrics.completedTasks)", unit: nil, label: "Completed",
                            tone: Palette.positive)
                    KeyStat(value: "\(metrics.lateTasks)", unit: nil, label: "Late",
                            tone: metrics.lateTasks > 0 ? Palette.amber : Palette.gold)
                    Spacer()
                }
                if metrics.weatherFlaggedTasks > 0 {
                    Text("\(metrics.weatherFlaggedTasks) task(s) were flagged when the forecast changed.")
                        .font(.system(size: 11)).foregroundStyle(Palette.amber)
                }
                if metrics.plannedTasks > 0 {
                    Divider().overlay(Palette.hairline)
                    ForEach(season.tasks.sorted { ($0.dueEnd ?? .distantFuture) < ($1.dueEnd ?? .distantFuture) }) { task in
                        DrillRow(title: task.title,
                                 subtitle: "\(task.status.rawValue) · \(task.dueDisplay ?? "no due date")",
                                 trailing: Fmt.duration(minutes: task.actualDurationMinutes)) {
                            TaskDetailView(task: task)
                        }
                    }
                }
            }
        }
    }

    private var inputsCard: some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader(title: "Input use")
                HStack(spacing: Spacing.xl) {
                    KeyStat(value: "\(metrics.applicationCount)", unit: nil, label: "Applications")
                    KeyStat(value: Fmt.currency(metrics.costTotal,
                                                code: season.field?.farm?.currencyCode ?? "USD"),
                            unit: nil, label: "Input cost")
                    Spacer()
                }
                if metrics.costTotal == nil {
                    Text("No cost is shown because no unit costs are recorded on the lots used. It is not counted as zero.")
                        .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let perHa = metrics.costPerHectare {
                    ValueRow(label: "Cost per hectare",
                             value: Fmt.currency(perHa, code: season.field?.farm?.currencyCode ?? "USD"))
                }
                if !season.applications.isEmpty {
                    Divider().overlay(Palette.hairline)
                    ForEach(season.applications.sorted { $0.date > $1.date }) { application in
                        DrillRow(title: application.productName,
                                 subtitle: "\(Fmt.date(application.date) ?? "") · lot \(application.lotLabelSnapshot ?? "not recorded")",
                                 trailing: Fmt.quantity(application.quantity,
                                                        application.quantityUnit.symbol)) {
                            ApplicationDetailView(application: application)
                        }
                    }
                }
            }
        }
    }

    private var waterCard: some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader(title: "Water recorded")
                KeyStat(value: Fmt.number(metrics.waterLiters, decimals: 0), unit: "L",
                        label: "Total recorded")
                Text("This is water you logged as actually applied, not the planned volume.")
                    .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                let plans = (season.field?.irrigationPlans ?? []).filter { $0.seasonID == season.id }
                if !plans.isEmpty {
                    Divider().overlay(Palette.hairline)
                    ForEach(plans) { plan in
                        HStack {
                            Text(plan.zone ?? "Plan")
                                .font(TypeScale.body(13)).foregroundStyle(Palette.cream)
                            Spacer()
                            Text("planned \(Fmt.number(plan.calculation?.volumeLiters, decimals: 0) ?? "—") L · recorded \(Fmt.number(plan.totalActualLiters(), decimals: 0) ?? "—") L")
                                .font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                        }
                    }
                }
            }
        }
    }

    private var observationsCard: some View {
        let observations = (season.field?.observations ?? []).filter { $0.seasonID == season.id }
        return CardShell {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader(title: "Observations")
                KeyStat(value: "\(metrics.observationCount)", unit: nil, label: "Recorded")
                if observations.isEmpty {
                    Text("None linked to this season.")
                        .font(TypeScale.body(12)).foregroundStyle(Palette.textSecondary)
                } else {
                    Divider().overlay(Palette.hairline)
                    ForEach(observations.sorted { $0.date > $1.date }.prefix(5)) { observation in
                        DrillRow(title: observation.confirmedCategory
                                    ?? observation.observationType.rawValue,
                                 subtitle: observation.summaryLine,
                                 trailing: Fmt.date(observation.date)) {
                            ObservationDetailView(observation: observation)
                        }
                    }
                }
            }
        }
    }

    private var gapsCard: some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Label("What is missing", systemImage: "questionmark.circle")
                    .font(TypeScale.headline(14)).foregroundStyle(Palette.amber)
                ForEach(metrics.gaps, id: \.self) { gap in
                    Text("— \(gap)")
                        .font(TypeScale.body(12)).foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var lessonsCard: some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader(title: "Your lessons", actionTitle: "Add",
                              action: { showLessonSheet = true })
                if let review, !review.lessons.isEmpty {
                    ForEach(review.lessons) { lesson in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lesson.text)
                                .font(TypeScale.body(13)).foregroundStyle(Palette.cream)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(Fmt.date(lesson.createdAt) ?? "")
                                .font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                        }
                        .padding(.vertical, 2)
                    }
                } else {
                    Text("Nothing written yet. The app draws no conclusions of its own — what you note here is yours.")
                        .font(TypeScale.body(12)).foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var lessonSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    CardShell {
                        PlateTextField(label: "Lesson",
                                       placeholder: "What would you do differently?",
                                       text: $lessonText, axis: .vertical)
                    }
                    AmberButton(title: "Save lesson", systemImage: "checkmark") { saveLesson() }
                }
                .padding(Spacing.l)
            }
            .farmBackground()
            .navigationTitle("Add lesson")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { showLessonSheet = false }
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }
    }

    private func saveLesson() {
        let text = lessonText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let record = review ?? {
            let created = SeasonReviewRecord(seasonID: season.id)
            context.insert(created)
            return created
        }()
        record.lessons.append(SeasonLesson(text: text, createdAt: Date()))
        try? context.save()
        lessonText = ""
        showLessonSheet = false
        appState.confirm("Lesson saved")
    }
}

// MARK: - Comparison

struct SeasonComparisonView: View {
    @Query private var lots: [InventoryLot]
    var seasons: [CropSeason]

    @State private var selected: Set<UUID> = []

    private var chosen: [CropSeason] {
        seasons.filter { selected.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                let availability = SeasonInsights.insightsAvailable(closedSeasons: seasons)
                if !availability.available {
                    CardShell {
                        Label(availability.reason ?? "", systemImage: "hourglass")
                            .font(TypeScale.body(13)).foregroundStyle(Palette.amber)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    if let caveat = availability.reason {
                        CardShell {
                            Label(caveat, systemImage: "info.circle")
                                .font(TypeScale.body(12)).foregroundStyle(Palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    CardShell {
                        VStack(alignment: .leading, spacing: Spacing.s) {
                            SectionHeader(title: "Choose seasons to compare")
                            ForEach(seasons) { season in
                                Button {
                                    if selected.contains(season.id) { selected.remove(season.id) }
                                    else { selected.insert(season.id) }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(season.displayTitle)
                                                .font(TypeScale.body(14)).foregroundStyle(Palette.cream)
                                            Text("\(season.field?.name ?? "Detached") · closed \(Fmt.date(season.closedAt) ?? "")")
                                                .font(.system(size: 11))
                                                .foregroundStyle(Palette.textTertiary)
                                        }
                                        Spacer()
                                        Image(systemName: selected.contains(season.id)
                                              ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selected.contains(season.id)
                                                             ? Palette.positive : Palette.textTertiary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if chosen.count >= 2 {
                        let comparison = SeasonInsights.compare(chosen, allLots: lots)
                        if !comparison.blockedReasons.isEmpty {
                            CardShell {
                                VStack(alignment: .leading, spacing: Spacing.s) {
                                    Label("Some comparisons are blocked",
                                          systemImage: "exclamationmark.triangle")
                                        .font(TypeScale.headline(14)).foregroundStyle(Palette.amber)
                                    ForEach(comparison.blockedReasons, id: \.self) { reason in
                                        Text("— \(reason)")
                                            .font(TypeScale.body(12))
                                            .foregroundStyle(Palette.textSecondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }

                        CardShell {
                            VStack(alignment: .leading, spacing: Spacing.m) {
                                ForEach(comparison.rows) { row in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(row.label).stampLabel(Palette.textSecondary)
                                        HStack(spacing: Spacing.m) {
                                            ForEach(Array(row.values.enumerated()), id: \.offset) { _, value in
                                                Text(value ?? "—")
                                                    .font(TypeScale.mono(12))
                                                    .foregroundStyle(value == nil
                                                                     ? Palette.textTertiary : Palette.cream)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                        }
                                        if let note = row.note {
                                            Text(note).font(.system(size: 10))
                                                .foregroundStyle(Palette.textTertiary)
                                        }
                                    }
                                    Divider().overlay(Palette.hairline)
                                }
                            }
                        }

                        let patterns = SeasonInsights.observationPatterns(for: chosen)
                        if !patterns.isEmpty {
                            CardShell {
                                VStack(alignment: .leading, spacing: Spacing.s) {
                                    SectionHeader(title: "Observation patterns")
                                    Text("Counts of what you recorded. A pattern here is a co-occurrence, not a cause.")
                                        .font(.system(size: 11)).foregroundStyle(Palette.amber)
                                        .fixedSize(horizontal: false, vertical: true)
                                    ForEach(patterns) { pattern in
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(pattern.category)
                                                .font(TypeScale.headline(13))
                                                .foregroundStyle(Palette.cream)
                                            Text(pattern.statement)
                                                .font(.system(size: 11))
                                                .foregroundStyle(Palette.textSecondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        .padding(.vertical, 2)
                                    }
                                }
                            }
                        }
                    } else {
                        CardShell {
                            Text("Select at least two seasons above.")
                                .font(TypeScale.body(13)).foregroundStyle(Palette.textSecondary)
                        }
                    }
                }
            }
            .padding(Spacing.l)
            .padding(.bottom, Spacing.xxl)
        }
        .farmBackground()
        .navigationTitle("Compare seasons")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if selected.isEmpty {
                selected = Set(seasons.prefix(2).map(\.id))
            }
        }
    }
}
