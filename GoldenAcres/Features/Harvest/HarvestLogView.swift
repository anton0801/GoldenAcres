//
//  HarvestLogView.swift
//  GoldenAcres
//
//  Screen 11. Loads roll up into a batch; the total is always derived from the
//  lines. Marketable + waste can never exceed gross, a repeated submit is
//  ignored, and edits after closing become revisions.
//

import SwiftUI
import SwiftData

struct HarvestLogView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    var season: CropSeason

    @State private var showNewBatch = false
    @State private var newBatchCode = ""

    private var batches: [HarvestBatch] {
        season.harvestBatches.sorted { $0.startedAt > $1.startedAt }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    if batches.isEmpty {
                        HonestEmptyState(
                            icon: "basket",
                            title: "No harvest yet",
                            message: "Start a batch, then add each load as it comes off the field. The batch total is always the sum of its loads.",
                            actionTitle: "Start harvest",
                            action: { showNewBatch = true }
                        )
                        .padding(.top, Spacing.xl)
                    } else {
                        seasonTotalCard
                        ForEach(batches) { batch in
                            NavigationLink { HarvestBatchDetailView(batch: batch) } label: {
                                HarvestBatchCard(batch: batch)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(Spacing.l)
                .padding(.bottom, Spacing.xxl)
            }
            .farmBackground()
            .navigationTitle("Harvest log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }.foregroundStyle(Palette.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNewBatch = true } label: {
                        Image(systemName: "plus").foregroundStyle(Palette.gold)
                    }
                }
            }
            .alert("Start a harvest batch", isPresented: $showNewBatch) {
                TextField("Batch code", text: $newBatchCode)
                Button("Cancel", role: .cancel) { newBatchCode = "" }
                Button("Create") { createBatch() }
            } message: {
                Text("A batch groups the loads from one harvest run so it can be traced as a lot.")
            }
        }
    }

    private var seasonTotalCard: some View {
        let allLoads = batches.flatMap(\.loads)
        let units = Set(allLoads.map(\.unitRaw))
        let mixed = units.count > 1

        return GoldPlate {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Text("Season total").stampLabel(Palette.amber)
                if allLoads.isEmpty {
                    Text("No loads recorded yet.")
                        .font(TypeScale.body(13)).foregroundStyle(Palette.textSecondary)
                } else if mixed {
                    Label("Loads use \(units.count) different units, so no season total is shown. Totals are only summed within one unit.",
                          systemImage: "exclamationmark.triangle")
                        .font(TypeScale.body(12)).foregroundStyle(Palette.amber)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let unit = QuantityUnit(rawValue: units.first ?? "") {
                    let gross = allLoads.map(\.grossQuantity).reduce(0, +)
                    let marketableValues = allLoads.compactMap(\.marketableQuantity)
                    let marketable = marketableValues.isEmpty ? nil : marketableValues.reduce(0, +)
                    HStack(spacing: Spacing.xl) {
                        Medallion(value: marketable.map { gross > 0 ? $0 / gross : 0 },
                                  caption: "Marketable share",
                                  detail: marketable == nil ? "not recorded" : nil,
                                  diameter: 82)
                        VStack(alignment: .leading, spacing: Spacing.s) {
                            KeyStat(value: Fmt.number(gross, decimals: 1), unit: unit.symbol,
                                    label: "Gross")
                            KeyStat(value: Fmt.number(marketable, decimals: 1), unit: unit.symbol,
                                    label: "Marketable", tone: Palette.positive)
                        }
                        Spacer()
                    }
                    if marketableValues.count < allLoads.count {
                        Text("\(allLoads.count - marketableValues.count) load(s) have no marketable figure — they are excluded, not counted as zero.")
                            .font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(Spacing.l)
        }
    }

    private func createBatch() {
        let code = newBatchCode.trimmingCharacters(in: .whitespaces)
        let batch = HarvestBatch(
            batchCode: code.isEmpty
                ? "B\(String(format: "%03d", season.harvestBatches.count + 1))"
                : code,
            season: season
        )
        context.insert(batch)
        season.harvestBatches.append(batch)
        AuditService.log(action: "Created", entityType: "Harvest batch", entityID: batch.id,
                         summary: "Batch \(batch.batchCode) started for \(season.displayTitle)",
                         context: context)
        try? context.save()
        newBatchCode = ""
        appState.confirm("Batch started", detail: "Batch \(batch.batchCode)")
    }
}

// MARK: - Batch card

struct HarvestBatchCard: View {
    var batch: HarvestBatch

    var body: some View {
        GoldPlate(accent: batch.isClosed ? Palette.positive : Palette.gold) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Batch \(batch.batchCode)")
                            .font(TypeScale.headline(15)).foregroundStyle(Palette.cream)
                        Text("\(batch.loads.count) load(s) · started \(Fmt.date(batch.startedAt) ?? "")")
                            .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                    }
                    Spacer()
                    StatusPill(text: batch.status.rawValue, tone: batch.status.tone)
                }
                HStack(spacing: Spacing.l) {
                    ValueColumn(label: "Gross",
                                value: Fmt.number(batch.totalGross, decimals: 1),
                                unit: batch.commonUnit?.symbol)
                    ValueColumn(label: "Marketable",
                                value: Fmt.number(batch.totalMarketable, decimals: 1),
                                unit: batch.commonUnit?.symbol)
                    ValueColumn(label: "Waste",
                                value: Fmt.number(batch.totalWaste, decimals: 1),
                                unit: batch.commonUnit?.symbol)
                }
                if batch.commonUnit == nil && !batch.loads.isEmpty {
                    Label("Mixed units — no total calculated.", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11)).foregroundStyle(Palette.amber)
                }
                if !batch.revisions.isEmpty {
                    StatusPill(text: "\(batch.revisions.count) revision(s)", tone: .warning)
                }
            }
            .padding(Spacing.l)
        }
    }
}

// MARK: - Batch detail

struct HarvestBatchDetailView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appState: AppState
    var batch: HarvestBatch

    @State private var showAddLoad = false
    @State private var showClose = false
    @State private var showReopen = false
    @State private var reopenReason = ""
    @State private var showQuality = false
    @State private var qualityGrade = ""
    @State private var storageDestination = ""
    @State private var crew = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                totalsCard
                if batch.isClosed { closedCard }
                loadsCard
                if !batch.revisions.isEmpty { revisionsCard }
                actionsCard
            }
            .padding(Spacing.l)
            .padding(.bottom, Spacing.xxl)
        }
        .farmBackground()
        .navigationTitle("Batch \(batch.batchCode)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { TraceabilityView(batch: batch) } label: {
                    Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                        .foregroundStyle(Palette.gold)
                }
            }
        }
        .sheet(isPresented: $showAddLoad) { AddLoadView(batch: batch) }
        .sheet(isPresented: $showQuality) { qualitySheet }
        .alert("Close this batch?", isPresented: $showClose) {
            Button("Cancel", role: .cancel) { }
            Button("Close batch") {
                HarvestService.close(batch: batch, context: context)
                try? context.save()
                appState.confirm("Batch closed",
                                 detail: "\(batch.loads.count) load(s), totals frozen")
            }
        } message: {
            Text("Closing records the batch as final. Later corrections are added as revisions rather than editing the loads.")
        }
        .alert("Reopen batch", isPresented: $showReopen) {
            TextField("Reason", text: $reopenReason)
            Button("Cancel", role: .cancel) { }
            Button("Reopen") {
                HarvestService.reopen(batch: batch,
                                      reason: reopenReason.isEmpty ? "No reason given" : reopenReason,
                                      context: context)
                try? context.save()
                reopenReason = ""
                appState.confirm("Batch reopened", detail: "A revision was recorded.")
            }
        }
    }

    private var totalsCard: some View {
        GoldPlate {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack(spacing: Spacing.xl) {
                    Medallion(value: batch.marketableRatio, caption: "Marketable",
                              detail: batch.marketableRatio == nil ? "not recorded" : nil,
                              diameter: 84)
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        KeyStat(value: Fmt.number(batch.totalGross, decimals: 1),
                                unit: batch.commonUnit?.symbol, label: "Gross")
                        KeyStat(value: Fmt.number(batch.totalMarketable, decimals: 1),
                                unit: batch.commonUnit?.symbol, label: "Marketable",
                                tone: Palette.positive)
                        KeyStat(value: Fmt.number(batch.totalWaste, decimals: 1),
                                unit: batch.commonUnit?.symbol, label: "Waste",
                                tone: Palette.amber)
                    }
                    Spacer()
                }
                Text("Totals are the sum of the \(batch.loads.count) load line(s) below — they are not entered directly.")
                    .font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().overlay(Palette.hairline)
                ValueRow(label: "Quality grade", value: batch.qualityGrade,
                         unknownHint: "Not graded", onFill: { showQuality = true })
                ValueRow(label: "Storage", value: batch.storageDestination,
                         onFill: { showQuality = true })
                ValueRow(label: "Crew", value: batch.crew, onFill: { showQuality = true })
            }
            .padding(Spacing.l)
        }
    }

    private var closedCard: some View {
        CardShell {
            Label("Closed \(Fmt.dateTime(batch.closedAt) ?? "")", systemImage: "lock")
                .font(TypeScale.headline(14)).foregroundStyle(Palette.positive)
        }
    }

    private var loadsCard: some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader(title: "Loads",
                              actionTitle: batch.isClosed ? nil : "Add",
                              action: batch.isClosed ? nil : { showAddLoad = true })
                if batch.loads.isEmpty {
                    Text("No loads recorded. Each load you add updates the totals above.")
                        .font(TypeScale.body(13)).foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    let sorted = batch.loads.sorted { $0.date > $1.date }
                    ForEach(sorted) { load in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(Fmt.dateTime(load.date) ?? "")
                                    .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                                Spacer()
                                Text(Fmt.quantity(load.grossQuantity, load.unit.symbol) ?? "")
                                    .font(TypeScale.mono(13)).foregroundStyle(Palette.gold)
                            }
                            HStack(spacing: Spacing.l) {
                                ValueColumn(label: "Marketable",
                                            value: Fmt.number(load.marketableQuantity, decimals: 1),
                                            unit: load.unit.symbol)
                                ValueColumn(label: "Waste",
                                            value: Fmt.number(load.wasteQuantity, decimals: 1),
                                            unit: load.unit.symbol)
                                if let unclassified = load.unclassifiedQuantity, unclassified > 0.001 {
                                    ValueColumn(label: "Unclassified",
                                                value: Fmt.number(unclassified, decimals: 1),
                                                unit: load.unit.symbol)
                                }
                            }
                            if !load.isConsistent {
                                Label("Marketable + waste exceeds gross on this load.",
                                      systemImage: "exclamationmark.triangle")
                                    .font(.system(size: 10)).foregroundStyle(Palette.burgundy)
                            }
                            if let notes = load.notes {
                                Text(notes).font(.system(size: 11))
                                    .foregroundStyle(Palette.textSecondary)
                            }
                            if !batch.isClosed {
                                Button("Remove load") {
                                    HarvestService.removeLoad(load, from: batch, context: context)
                                    try? context.save()
                                    appState.confirm("Load removed")
                                }
                                .font(.system(size: 11)).foregroundStyle(Palette.burgundy)
                            }
                        }
                        .padding(.vertical, 4)
                        if load.id != sorted.last?.id { Divider().overlay(Palette.hairline) }
                    }
                }
            }
        }
    }

    private var revisionsCard: some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader(title: "Revisions after closing")
                ForEach(batch.revisions) { revision in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Fmt.dateTime(revision.timestamp) ?? "")
                            .font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                        Text(revision.changeSummary)
                            .font(TypeScale.body(12)).foregroundStyle(Palette.cream)
                        Text("Reason: \(revision.reason)")
                            .font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var actionsCard: some View {
        VStack(spacing: Spacing.s) {
            if batch.isClosed {
                GhostButton(title: "Reopen batch", systemImage: "lock.open") { showReopen = true }
            } else {
                AmberButton(title: "Add load", systemImage: "plus") { showAddLoad = true }
                GhostButton(title: "Record quality & storage", systemImage: "tag") {
                    showQuality = true
                }
                if !batch.loads.isEmpty {
                    GhostButton(title: "Close harvest", systemImage: "flag.checkered") {
                        showClose = true
                    }
                }
            }
        }
    }

    private var qualitySheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    CardShell {
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            PlateTextField(label: "Quality grade",
                                           placeholder: "Your own grading, e.g. Class 1",
                                           text: $qualityGrade,
                                           helper: "Free text — the app applies no grading standard.")
                            PlateTextField(label: "Storage destination", placeholder: "Optional",
                                           text: $storageDestination)
                            PlateTextField(label: "Crew", placeholder: "Optional", text: $crew)
                        }
                    }
                    AmberButton(title: "Save", systemImage: "checkmark") { saveQuality() }
                }
                .padding(Spacing.l)
            }
            .farmBackground()
            .navigationTitle("Quality & storage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { showQuality = false }.foregroundStyle(Palette.textSecondary)
                }
            }
            .onAppear {
                qualityGrade = batch.qualityGrade ?? ""
                storageDestination = batch.storageDestination ?? ""
                crew = batch.crew ?? ""
            }
        }
    }

    private func saveQuality() {
        let wasClosed = batch.isClosed
        let before = batch.qualityGrade ?? "none"

        batch.qualityGrade = qualityGrade.isEmpty ? nil : qualityGrade
        batch.storageDestination = storageDestination.isEmpty ? nil : storageDestination
        batch.crew = crew.isEmpty ? nil : crew

        if wasClosed {
            HarvestService.addRevision(
                to: batch,
                reason: "Detail updated after closing",
                changeSummary: "Quality grade changed from “\(before)” to “\(batch.qualityGrade ?? "none")”",
                context: context
            )
        }
        try? context.save()
        showQuality = false
        appState.confirm("Batch details saved",
                         detail: wasClosed ? "Recorded as a revision" : nil)
    }
}

// MARK: - Add load

struct AddLoadView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    var batch: HarvestBatch

    @State private var grossText = ""
    @State private var marketableText = ""
    @State private var wasteText = ""
    @State private var unit: QuantityUnit = .kilogram
    @State private var date = Date()
    @State private var notes = ""
    @State private var recordedBy = ""
    @State private var error: String?
    @State private var isSaving = false
    /// Generated once per form instance, so a double tap cannot double-record.
    @State private var idempotencyKey = UUID().uuidString

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    if let error {
                        ErrorBanner(title: "Could not add load", message: error,
                                    onRetry: nil, onDismiss: { self.error = nil })
                    }

                    CardShell {
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            HStack(alignment: .top, spacing: Spacing.m) {
                                PlateTextField(label: "Gross quantity", placeholder: "0",
                                               text: $grossText, isRequired: true,
                                               keyboard: .decimalPad)
                                PlateField(label: "Unit", isRequired: true) {
                                    Picker("", selection: $unit) {
                                        ForEach(QuantityUnit.allCases) { Text($0.symbol).tag($0) }
                                    }
                                    .pickerStyle(.menu).tint(Palette.gold)
                                    .disabled(batch.commonUnit != nil)
                                }
                                .frame(width: 108)
                            }
                            if let existing = batch.commonUnit {
                                Text("This batch already records loads in \(existing.symbol). To use a different unit, start a separate batch.")
                                    .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            HStack(spacing: Spacing.m) {
                                PlateTextField(label: "Marketable", placeholder: "Optional",
                                               text: $marketableText, keyboard: .decimalPad)
                                PlateTextField(label: "Waste", placeholder: "Optional",
                                               text: $wasteText, keyboard: .decimalPad)
                            }

                            if let remainder = previewUnclassified {
                                ValueRow(label: "Unclassified remainder",
                                         value: Fmt.number(remainder, decimals: 2),
                                         unit: unit.symbol, tone: Palette.amber)
                            }
                            Text("Leaving marketable or waste blank keeps it Unknown. It is never treated as zero.")
                                .font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)

                            PlateField(label: "Date & time", isRequired: true) {
                                DatePicker("", selection: $date).labelsHidden().tint(Palette.gold)
                            }
                            PlateTextField(label: "Recorded by", placeholder: "Optional",
                                           text: $recordedBy)
                            PlateTextField(label: "Notes", placeholder: "Optional",
                                           text: $notes, axis: .vertical)
                        }
                    }

                    AmberButton(title: "Add load", systemImage: "plus", isBusy: isSaving) { save() }
                }
                .padding(Spacing.l)
            }
            .farmBackground()
            .navigationTitle("Add load")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.textSecondary)
                }
            }
            .onAppear {
                if let existing = batch.commonUnit { unit = existing }
            }
        }
    }

    private var previewUnclassified: Double? {
        guard let gross = Double(grossText.replacingOccurrences(of: ",", with: ".")) else { return nil }
        let m = Double(marketableText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let w = Double(wasteText.replacingOccurrences(of: ",", with: ".")) ?? 0
        guard !marketableText.isEmpty || !wasteText.isEmpty else { return nil }
        return max(gross - m - w, 0)
    }

    private func save() {
        guard !isSaving else { return }
        error = nil

        guard let gross = Double(grossText.replacingOccurrences(of: ",", with: ".")) else {
            error = grossText.isEmpty ? "Enter the gross quantity." : "Enter a valid number."
            return
        }

        isSaving = true
        do {
            try HarvestService.addLoad(
                to: batch,
                gross: gross,
                marketable: Double(marketableText.replacingOccurrences(of: ",", with: ".")),
                waste: Double(wasteText.replacingOccurrences(of: ",", with: ".")),
                unit: unit,
                date: date,
                notes: notes.isEmpty ? nil : notes,
                recordedBy: recordedBy.isEmpty ? nil : recordedBy,
                idempotencyKey: idempotencyKey,
                context: context
            )
            try context.save()
            appState.confirm("Load added",
                             detail: "\(Fmt.quantity(gross, unit.symbol) ?? "") · batch total now \(Fmt.quantity(batch.totalGross, batch.commonUnit?.symbol) ?? "")")
            isSaving = false
            dismiss()
        } catch {
            isSaving = false
            self.error = error.localizedDescription
        }
    }
}
