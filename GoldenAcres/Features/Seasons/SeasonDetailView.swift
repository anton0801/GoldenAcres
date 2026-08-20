//
//  SeasonDetailView.swift
//  GoldenAcres
//
//  The season hub: plan, inputs, irrigation, harvest and closing.
//

import SwiftUI
import SwiftData

struct SeasonDetailView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appState: AppState
    @Query private var lots: [InventoryLot]

    var season: CropSeason

    @State private var showEditor = false
    @State private var showTaskEditor = false
    @State private var showApplication = false
    @State private var showHarvest = false
    @State private var showCloseConfirm = false
    @State private var showDeleteSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                headerCard
                if season.status == .closed { closedBanner }
                actionsRow
                tasksSection
                applicationsSection
                harvestSection
                if season.status == .closed { reviewLink }
            }
            .padding(Spacing.l)
            .padding(.bottom, Spacing.xxl)
        }
        .farmBackground()
        .navigationTitle(season.cropName.isEmpty ? "Season" : season.cropName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showEditor = true } label: { Label("Edit season", systemImage: "pencil") }
                    if season.status == .active {
                        Button { showCloseConfirm = true } label: {
                            Label("Close season", systemImage: "flag.checkered")
                        }
                    }
                    if season.status != .archived {
                        Button {
                            season.status = .archived
                            try? context.save()
                            appState.confirm("Season archived", detail: season.displayTitle)
                        } label: { Label("Archive", systemImage: "archivebox") }
                    }
                    Divider()
                    Button(role: .destructive) { showDeleteSheet = true } label: {
                        Label("Delete season…", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundStyle(Palette.gold)
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            if let farm = season.field?.farm {
                SeasonEditorView(farm: farm, field: season.field, season: season)
            }
        }
        .sheet(isPresented: $showTaskEditor) { TaskEditorView(season: season, task: nil) }
        .sheet(isPresented: $showApplication) {
            ApplicationEditorView(season: season, field: season.field)
        }
        .sheet(isPresented: $showHarvest) { HarvestLogView(season: season) }
        .sheet(isPresented: $showDeleteSheet) { deleteSheet }
        .alert("Close this season?", isPresented: $showCloseConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Close season") { closeSeason() }
        } message: {
            Text("A snapshot of the current figures is stored. Later edits elsewhere will not change it. Open tasks and open batches are recorded as gaps.")
        }
    }

    // MARK: - Cards

    private var headerCard: some View {
        GoldPlate {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(season.field?.name ?? "Detached from field").stampLabel(Palette.amber)
                        Text(season.displayTitle)
                            .font(TypeScale.display(24))
                            .foregroundStyle(Palette.cream)
                    }
                    Spacer()
                    StatusPill(text: season.status.label, tone: season.status.tone)
                }

                Divider().overlay(Palette.hairline)

                ValueRow(label: "Intended use", value: season.intendedUse?.rawValue)
                ValueRow(label: "Target area",
                         value: Fmt.number(season.targetAreaValue, decimals: 2),
                         unit: season.targetAreaUnit.symbol)
                ValueRow(label: "Planting window",
                         value: Fmt.dateRange(season.plantingWindowStart, season.plantingWindowEnd))
                ValueRow(label: "Actual planting", value: Fmt.date(season.actualPlantingDate),
                         onFill: { showEditor = true })
                ValueRow(label: "Expected harvest",
                         value: Fmt.dateRange(season.expectedHarvestStart, season.expectedHarvestEnd))
                ValueRow(label: "Seed lot", value: season.seedLotLabel,
                         unknownHint: "Not linked", onFill: { showEditor = true })
            }
            .padding(Spacing.l)
        }
    }

    private var closedBanner: some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Label("Season closed \(Fmt.dateTime(season.closedAt) ?? "")", systemImage: "flag.checkered")
                    .font(TypeScale.headline(14)).foregroundStyle(Palette.positive)
                Text("The figures below the snapshot are frozen. Corrections made later are recorded as revisions rather than overwriting this.")
                    .font(TypeScale.body(12)).foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let snapshot = season.closingSnapshot, !snapshot.gaps.isEmpty {
                    Divider().overlay(Palette.hairline)
                    Text("Gaps recorded at close").stampLabel(Palette.amber)
                    ForEach(snapshot.gaps, id: \.self) { gap in
                        Text("— \(gap)").font(.system(size: 11))
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var actionsRow: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.m) {
            ChipAction(title: "Add task", icon: "plus.circle") { showTaskEditor = true }
            ChipAction(title: "Record application", icon: "drop.triangle") { showApplication = true }
            ChipAction(title: "Harvest log", icon: "basket") { showHarvest = true }
            if let field = season.field {
                NavigationLink { IrrigationPlannerView(field: field) } label: {
                    ChipActionLabel(title: "Irrigation", icon: "drop")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeader(title: "Task plan",
                          subtitle: season.tasks.isEmpty ? "Empty — no work has been invented for you" : nil,
                          actionTitle: "Add", action: { showTaskEditor = true })
            if season.tasks.isEmpty {
                CardShell {
                    Text("This season has an empty plan. Add the work you actually intend to do, or create tasks from a weather window.")
                        .font(TypeScale.body(13)).foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                CardShell {
                    VStack(spacing: 0) {
                        let sorted = season.tasks.sorted {
                            ($0.dueEnd ?? .distantFuture) < ($1.dueEnd ?? .distantFuture)
                        }
                        ForEach(sorted) { task in
                            DrillRow(title: task.title,
                                     subtitle: "\(task.status.rawValue) · \(task.dueDisplay ?? "no due date")",
                                     trailing: task.weatherReviewNeeded ? "review" : nil,
                                     tone: task.isOverdue ? Palette.amber : Palette.cream) {
                                TaskDetailView(task: task)
                            }
                            if task.id != sorted.last?.id { Divider().overlay(Palette.hairline) }
                        }
                    }
                }
            }
        }
    }

    private var applicationsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeader(title: "Input applications", actionTitle: "Record",
                          action: { showApplication = true })
            let apps = season.applications.sorted { $0.date > $1.date }
            if apps.isEmpty {
                CardShell {
                    Text("Nothing applied yet. A confirmed application deducts the exact lot you select.")
                        .font(TypeScale.body(13)).foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                CardShell {
                    VStack(spacing: 0) {
                        ForEach(apps) { app in
                            DrillRow(title: app.productName,
                                     subtitle: "\(Fmt.date(app.date) ?? "") · \(Fmt.quantity(app.quantity, app.quantityUnit.symbol) ?? "")\(app.isVoided ? " · VOIDED" : "")",
                                     trailing: app.lotLabelSnapshot,
                                     tone: app.isVoided ? Palette.textTertiary : Palette.cream) {
                                ApplicationDetailView(application: app)
                            }
                            if app.id != apps.last?.id { Divider().overlay(Palette.hairline) }
                        }
                    }
                }
            }
        }
    }

    private var harvestSection: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeader(title: "Harvest", actionTitle: "Open log", action: { showHarvest = true })
            let batches = season.harvestBatches.sorted { $0.startedAt > $1.startedAt }
            if batches.isEmpty {
                CardShell {
                    Text("No harvest batches. Each load you record rolls up into a batch, and the batch total is always derived from its loads.")
                        .font(TypeScale.body(13)).foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                CardShell {
                    VStack(spacing: 0) {
                        ForEach(batches) { batch in
                            DrillRow(title: "Batch \(batch.batchCode)",
                                     subtitle: "\(batch.status.rawValue) · \(batch.loads.count) load(s)",
                                     trailing: Fmt.quantity(batch.totalGross, batch.commonUnit?.symbol)
                                        ?? "mixed units") {
                                HarvestBatchDetailView(batch: batch)
                            }
                            if batch.id != batches.last?.id { Divider().overlay(Palette.hairline) }
                        }
                    }
                }
            }
        }
    }

    private var reviewLink: some View {
        NavigationLink { SeasonReviewView(season: season) } label: {
            CardShell {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Season review").font(TypeScale.headline(15)).foregroundStyle(Palette.cream)
                        Text("Yield, tasks, inputs, water and observation counts — each opening to its records.")
                            .font(TypeScale.body(12)).foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Palette.gold)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func closeSeason() {
        HarvestService.closeSeason(season, context: context)
        do {
            try context.save()
            let snapshot = season.closingSnapshot
            appState.confirm("Season closed",
                             detail: snapshot.map { "\($0.gaps.count) gap(s) recorded in the snapshot" })
        } catch {
            appState.confirm("Could not close season", detail: error.localizedDescription)
        }
    }

    private var deleteSheet: some View {
        var consequences: [String] = []
        if !season.tasks.isEmpty {
            consequences.append("\(season.tasks.count) task(s) will be deleted with the season.")
        }
        if !season.applications.isEmpty {
            consequences.append("\(season.applications.count) application record(s) will be kept and detached — they are never deleted.")
        }
        if !season.harvestBatches.isEmpty {
            consequences.append("\(season.harvestBatches.count) harvest batch(es) will be kept and detached, so their traceability stays readable.")
        }
        let reservations = season.tasks.flatMap(\.requiredInputs).filter { $0.reservationID != nil }
        if !reservations.isEmpty {
            consequences.append("\(reservations.count) stock reservation(s) will be released back to available.")
        }

        return ConsequenceSheet(
            title: "Delete “\(season.displayTitle)”?",
            entityName: season.displayTitle,
            consequences: consequences,
            canDelete: season.status != .closed,
            deleteBlockedReason: season.status == .closed
                ? "A closed season is part of your record history. Archive it instead."
                : nil,
            onArchive: {
                season.status = .archived
                try? context.save()
                showDeleteSheet = false
                appState.confirm("Season archived", detail: season.displayTitle)
            },
            onDetach: nil,
            onDelete: { performDelete() },
            onCancel: { showDeleteSheet = false }
        )
    }

    private func performDelete() {
        // Release any stock this season's tasks were holding.
        for task in season.tasks {
            for input in task.requiredInputs {
                guard let lotID = input.lotID,
                      let lot = lots.first(where: { $0.id == lotID }),
                      let quantity = input.quantity else { continue }
                InventoryService.releaseReservation(lot: lot, quantity: quantity,
                                                    forTask: task.id, taskLabel: task.title,
                                                    context: context)
            }
        }
        AuditService.log(action: "Deleted", entityType: "Crop season", entityID: season.id,
                         summary: "Season “\(season.displayTitle)” deleted", context: context)
        season.field?.seasons.removeAll { $0.id == season.id }
        context.delete(season)
        try? context.save()
        showDeleteSheet = false
        appState.confirm("Season deleted", detail: "Applications and harvests were kept.")
    }
}

// MARK: - Chip action

struct ChipAction: View {
    var title: String
    var icon: String
    var action: () -> Void

    var body: some View {
        Button(action: action) { ChipActionLabel(title: title, icon: icon) }
            .buttonStyle(.plain)
    }
}

struct ChipActionLabel: View {
    var title: String
    var icon: String

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(Palette.gold)
            Text(title).font(TypeScale.headline(13)).foregroundStyle(Palette.cream)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
        .padding(.horizontal, Spacing.m)
        .background {
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .fill(Plating.plateDark)
                .overlay(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .strokeBorder(Palette.gold.opacity(0.22), lineWidth: 1))
        }
    }
}
