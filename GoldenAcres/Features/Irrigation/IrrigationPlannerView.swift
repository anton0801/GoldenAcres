//
//  IrrigationPlannerView.swift
//  GoldenAcres
//
//  Screen 7. Planned volume is derived from area × depth, with every input,
//  unit and assumption visible. Actual water is stored separately from the
//  plan, and the app controls no equipment.
//

import SwiftUI
import SwiftData

struct IrrigationPlannerView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appState: AppState
    var field: FarmField

    @State private var showEditor = false
    @State private var editingPlan: IrrigationPlan?

    private var plans: [IrrigationPlan] {
        field.irrigationPlans.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                if field.areaValue == nil {
                    CardShell {
                        VStack(alignment: .leading, spacing: Spacing.s) {
                            Label("Field area unknown", systemImage: "exclamationmark.triangle")
                                .font(TypeScale.headline(14)).foregroundStyle(Palette.amber)
                            Text("Volume cannot be calculated without an area. You can still record a plan and actual water — the volume will simply show as “cannot compute”.")
                                .font(TypeScale.body(12)).foregroundStyle(Palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if plans.isEmpty {
                    HonestEmptyState(
                        icon: "drop",
                        title: "No irrigation plans",
                        message: "Build a plan to see the volume your target depth implies over this field's area, with the arithmetic shown.",
                        actionTitle: "Build irrigation plan",
                        action: { showEditor = true }
                    )
                    .padding(.top, Spacing.xl)
                } else {
                    ForEach(plans) { plan in
                        IrrigationPlanCard(plan: plan, field: field) { editingPlan = plan }
                    }
                }
            }
            .padding(Spacing.l)
            .padding(.bottom, Spacing.xxl)
        }
        .farmBackground()
        .navigationTitle("Irrigation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showEditor = true } label: {
                    Image(systemName: "plus").foregroundStyle(Palette.gold)
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            IrrigationPlanEditor(field: field, plan: nil)
        }
        .sheet(item: $editingPlan) { plan in
            IrrigationPlanEditor(field: field, plan: plan)
        }
    }
}

// MARK: - Plan card

struct IrrigationPlanCard: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appState: AppState
    var plan: IrrigationPlan
    var field: FarmField
    var onEdit: () -> Void

    @State private var showRunEditor = false

    var body: some View {
        GoldPlate {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plan.zone ?? "Whole field")
                            .font(TypeScale.headline(15)).foregroundStyle(Palette.cream)
                        Text(plan.method?.rawValue ?? "Method not set")
                            .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                    }
                    Spacer()
                    StatusPill(text: plan.statusRaw, tone: .gold)
                }

                if let calculation = plan.calculation {
                    CalculationDisclosure(
                        title: "Planned volume",
                        result: Fmt.number(calculation.volumeLiters, decimals: 0),
                        resultUnit: "L",
                        steps: IrrigationCalculator.steps(for: calculation,
                                                          areaUnit: field.areaUnit,
                                                          depthUnit: plan.depthUnit,
                                                          volumeUnit: .liter),
                        assumptions: calculation.assumptions
                    )

                    if !calculation.blockers.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(calculation.blockers, id: \.self) { blocker in
                                Label(blocker, systemImage: "exclamationmark.circle")
                                    .font(.system(size: 11)).foregroundStyle(Palette.amber)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                Divider().overlay(Palette.hairline)

                HStack(spacing: Spacing.xl) {
                    ValueColumn(label: "Planned run",
                                value: Fmt.duration(minutes: plan.calculation?.estimatedMinutes),
                                unit: nil)
                    ValueColumn(label: "Recorded water",
                                value: Fmt.number(plan.totalActualLiters(), decimals: 0), unit: "L")
                    ValueColumn(label: "Runs", value: "\(plan.runs.count)", unit: nil)
                }

                if !plan.runs.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Actual runs (kept separate from the plan)")
                            .stampLabel(Palette.textSecondary)
                        ForEach(plan.runs.sorted { $0.startedAt > $1.startedAt }) { run in
                            HStack {
                                Text(Fmt.dateTime(run.startedAt) ?? "")
                                    .font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                                Spacer()
                                Text(Fmt.quantity(run.actualVolumeValue, run.volumeUnit.symbol)
                                     ?? "volume not recorded")
                                    .font(TypeScale.mono(12)).foregroundStyle(Palette.cream)
                            }
                        }
                    }
                }

                if let restrictions = plan.restrictions, !restrictions.isEmpty {
                    Label(restrictions, systemImage: "exclamationmark.shield")
                        .font(.system(size: 11)).foregroundStyle(Palette.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: Spacing.s) {
                    ChipButton(title: "Edit assumptions", systemImage: "slider.horizontal.3",
                               action: onEdit)
                    ChipButton(title: "Record actual water", systemImage: "drop.fill") {
                        showRunEditor = true
                    }
                }
            }
            .padding(Spacing.l)
        }
        .sheet(isPresented: $showRunEditor) {
            IrrigationRunEditor(plan: plan)
        }
    }
}

// MARK: - Plan editor

struct IrrigationPlanEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    var field: FarmField
    var plan: IrrigationPlan?

    @State private var zone = ""
    @State private var cropStage = ""
    @State private var method: IrrigationMethod?
    @State private var flowText = ""
    @State private var flowUnit: FlowUnit = .litersPerMinute
    @State private var targetText = ""
    @State private var depthUnit: DepthUnit = .millimeter
    @State private var rainText = ""
    @State private var rainSource = ""
    @State private var startWindow: Date?
    @State private var waterSource = ""
    @State private var restrictions = ""
    @State private var isSaving = false
    @State private var saveError: String?

    private var preview: IrrigationCalculation {
        IrrigationCalculator.calculate(
            areaSquareMeters: field.areaSquareMeters,
            targetDepth: Double(targetText.replacingOccurrences(of: ",", with: ".")),
            depthUnit: depthUnit,
            rainAdjustmentMM: Double(rainText.replacingOccurrences(of: ",", with: ".")),
            rainAdjustmentSource: rainSource.isEmpty ? nil : rainSource,
            flow: Double(flowText.replacingOccurrences(of: ",", with: ".")),
            flowUnit: flowUnit
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    if let saveError {
                        ErrorBanner(title: "Could not save", message: saveError,
                                    onRetry: { save() }, onDismiss: { self.saveError = nil })
                    }

                    CardShell {
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            PlateTextField(label: "Zone", placeholder: "Optional — whole field if blank",
                                           text: $zone)
                            PlateTextField(label: "Crop stage", placeholder: "Optional", text: $cropStage)
                            PlateField(label: "Method") {
                                Picker("", selection: $method) {
                                    Text("Not set").tag(IrrigationMethod?.none)
                                    ForEach(IrrigationMethod.allCases) {
                                        Text($0.rawValue).tag(IrrigationMethod?.some($0))
                                    }
                                }
                                .pickerStyle(.menu).tint(Palette.gold)
                            }
                        }
                    }

                    CardShell {
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            SectionHeader(title: "Your target",
                                          subtitle: "The app has no crop water model. This depth is yours.")
                            HStack(alignment: .top, spacing: Spacing.m) {
                                PlateTextField(label: "Target depth", placeholder: "0",
                                               text: $targetText, keyboard: .decimalPad)
                                PlateField(label: "Unit") {
                                    Picker("", selection: $depthUnit) {
                                        ForEach(DepthUnit.allCases) { Text($0.symbol).tag($0) }
                                    }
                                    .pickerStyle(.menu).tint(Palette.gold)
                                }
                                .frame(width: 100)
                            }
                            HStack(alignment: .top, spacing: Spacing.m) {
                                PlateTextField(label: "Rain credit (mm)", placeholder: "Optional",
                                               text: $rainText, keyboard: .decimalPad)
                                PlateTextField(label: "Rain source", placeholder: "e.g. forecast",
                                               text: $rainSource)
                            }
                            Text("Leaving rain blank means no credit is applied. It is not read as “zero rainfall”.")
                                .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    CardShell {
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            SectionHeader(title: "System")
                            HStack(alignment: .top, spacing: Spacing.m) {
                                PlateTextField(label: "Available flow", placeholder: "Optional",
                                               text: $flowText, keyboard: .decimalPad)
                                PlateField(label: "Unit") {
                                    Picker("", selection: $flowUnit) {
                                        ForEach(FlowUnit.allCases) { Text($0.symbol).tag($0) }
                                    }
                                    .pickerStyle(.menu).tint(Palette.gold)
                                }
                                .frame(width: 118)
                            }
                            OptionalDateRow(label: "Start window", date: $startWindow)
                            PlateTextField(label: "Water source", placeholder: "Optional",
                                           text: $waterSource)
                            PlateTextField(label: "Restrictions",
                                           placeholder: "e.g. abstraction limit, local rules",
                                           text: $restrictions, axis: .vertical)
                        }
                    }

                    CardShell {
                        CalculationDisclosure(
                            title: "Preview volume",
                            result: Fmt.number(preview.volumeLiters, decimals: 0),
                            resultUnit: "L",
                            steps: IrrigationCalculator.steps(for: preview,
                                                              areaUnit: field.areaUnit,
                                                              depthUnit: depthUnit,
                                                              volumeUnit: .liter),
                            assumptions: preview.assumptions
                        )
                    }

                    if !preview.blockers.isEmpty {
                        CardShell {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(preview.blockers, id: \.self) { blocker in
                                    Label(blocker, systemImage: "exclamationmark.circle")
                                        .font(.system(size: 11)).foregroundStyle(Palette.amber)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }

                    AmberButton(title: plan == nil ? "Save plan" : "Save changes",
                                systemImage: "checkmark", isBusy: isSaving) { save() }

                    Text("Saving records a plan. It does not start equipment — the app has no controller integration unless you connect one and confirm what it can do.")
                        .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Spacing.l)
            }
            .farmBackground()
            .navigationTitle(plan == nil ? "Build plan" : "Edit plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.textSecondary)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let plan else {
            method = field.irrigationMethod
            return
        }
        zone = plan.zone ?? ""
        cropStage = plan.cropStage ?? ""
        method = plan.method
        flowText = plan.availableFlowValue.map { String($0) } ?? ""
        flowUnit = plan.flowUnit
        targetText = plan.targetDepthValue.map { String($0) } ?? ""
        depthUnit = plan.depthUnit
        rainText = plan.rainAdjustmentMM.map { String($0) } ?? ""
        rainSource = plan.rainAdjustmentSource ?? ""
        startWindow = plan.startWindow
        waterSource = plan.waterSource ?? ""
        restrictions = plan.restrictions ?? ""
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        saveError = nil

        let target = plan ?? IrrigationPlan(field: field)
        let isNew = plan == nil

        target.zone = zone.trimmingCharacters(in: .whitespaces).isEmpty ? nil : zone
        target.cropStage = cropStage.trimmingCharacters(in: .whitespaces).isEmpty ? nil : cropStage
        target.method = method
        target.availableFlowValue = Double(flowText.replacingOccurrences(of: ",", with: "."))
        target.flowUnit = flowUnit
        target.targetDepthValue = Double(targetText.replacingOccurrences(of: ",", with: "."))
        target.depthUnit = depthUnit
        target.rainAdjustmentMM = Double(rainText.replacingOccurrences(of: ",", with: "."))
        target.rainAdjustmentSource = rainSource.isEmpty ? nil : rainSource
        target.startWindow = startWindow
        target.waterSource = waterSource.isEmpty ? nil : waterSource
        target.restrictions = restrictions.isEmpty ? nil : restrictions
        target.calculation = preview
        target.plannedDurationMinutes = preview.estimatedMinutes
        target.seasonID = field.currentSeason?.id
        target.fieldNameSnapshot = field.name
        target.statusRaw = startWindow == nil ? "draft" : "scheduled"
        target.updatedAt = Date()

        if isNew {
            target.field = field
            context.insert(target)
            field.irrigationPlans.append(target)
        }

        AuditService.log(action: isNew ? "Created" : "Updated", entityType: "Irrigation plan",
                         entityID: target.id,
                         summary: "\(isNew ? "Built" : "Updated") irrigation plan for \(field.name)",
                         details: Fmt.number(preview.volumeLiters, decimals: 0).map { "\($0) L planned" }
                            ?? "volume not calculable",
                         context: context)

        do {
            try context.save()
            appState.confirm(isNew ? "Plan saved" : "Plan updated",
                             detail: Fmt.number(preview.volumeLiters, decimals: 0)
                                .map { "\($0) L planned" } ?? "Volume could not be calculated")
            isSaving = false
            dismiss()
        } catch {
            isSaving = false
            saveError = error.localizedDescription
        }
    }
}

// MARK: - Run editor

struct IrrigationRunEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    var plan: IrrigationPlan

    @State private var startedAt = Date()
    @State private var endedAt: Date?
    @State private var volumeText = ""
    @State private var volumeUnit: VolumeUnit = .liter
    @State private var meterStart = ""
    @State private var meterEnd = ""
    @State private var notes = ""
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    CardShell {
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            SectionHeader(title: "Actual water",
                                          subtitle: "Stored separately from the plan; it never overwrites it.")
                            PlateField(label: "Started", isRequired: true) {
                                DatePicker("", selection: $startedAt).labelsHidden().tint(Palette.gold)
                            }
                            OptionalDateRow(label: "Ended", date: $endedAt)
                            HStack(alignment: .top, spacing: Spacing.m) {
                                PlateTextField(label: "Volume", placeholder: "Optional",
                                               text: $volumeText, keyboard: .decimalPad,
                                               error: error)
                                PlateField(label: "Unit") {
                                    Picker("", selection: $volumeUnit) {
                                        ForEach(VolumeUnit.allCases) { Text($0.symbol).tag($0) }
                                    }
                                    .pickerStyle(.menu).tint(Palette.gold)
                                }
                                .frame(width: 100)
                            }
                            HStack(spacing: Spacing.m) {
                                PlateTextField(label: "Meter start", placeholder: "Optional",
                                               text: $meterStart, keyboard: .decimalPad)
                                PlateTextField(label: "Meter end", placeholder: "Optional",
                                               text: $meterEnd, keyboard: .decimalPad)
                            }
                            PlateTextField(label: "Notes", placeholder: "Optional",
                                           text: $notes, axis: .vertical)
                        }
                    }

                    AmberButton(title: "Record run", systemImage: "checkmark", isBusy: isSaving) {
                        save()
                    }
                }
                .padding(Spacing.l)
            }
            .farmBackground()
            .navigationTitle("Record water")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.textSecondary)
                }
            }
        }
    }

    private func save() {
        guard !isSaving else { return }
        error = nil
        if let end = endedAt, end < startedAt {
            error = "The run cannot end before it starts."
            return
        }
        if !volumeText.isEmpty,
           Double(volumeText.replacingOccurrences(of: ",", with: ".")) == nil {
            error = "Enter a valid number, or leave blank."
            return
        }

        isSaving = true
        let run = IrrigationRun(startedAt: startedAt, plan: plan)
        run.endedAt = endedAt
        run.actualVolumeValue = Double(volumeText.replacingOccurrences(of: ",", with: "."))
        run.volumeUnit = volumeUnit
        run.meterReadingStart = Double(meterStart.replacingOccurrences(of: ",", with: "."))
        run.meterReadingEnd = Double(meterEnd.replacingOccurrences(of: ",", with: "."))
        run.notes = notes.isEmpty ? nil : notes
        context.insert(run)
        plan.runs.append(run)

        AuditService.log(action: "Recorded", entityType: "Irrigation run", entityID: run.id,
                         summary: "Water recorded for \(plan.fieldNameSnapshot)",
                         details: Fmt.quantity(run.actualVolumeValue, volumeUnit.symbol),
                         context: context)

        do {
            try context.save()
            appState.confirm("Run recorded",
                             detail: Fmt.quantity(run.actualVolumeValue, volumeUnit.symbol)
                                ?? "No volume entered")
            isSaving = false
            dismiss()
        } catch {
            isSaving = false
            self.error = error.localizedDescription
        }
    }
}
