//
//  TaskDetailView.swift
//  GoldenAcres
//
//  Task lifecycle. Completing twice is a no-op. Rescheduling a task only
//  *offers* to move its dependents — it never moves them silently.
//

import SwiftUI
import SwiftData

struct TaskDetailView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appState: AppState
    @Query private var allTasks: [FarmTask]
    @Query private var lots: [InventoryLot]

    var task: FarmTask

    @State private var showEditor = false
    @State private var showBlockSheet = false
    @State private var blockReason = ""
    @State private var showReschedule = false
    @State private var showDelete = false
    @State private var actualDurationText = ""
    @State private var showCompleteSheet = false

    private var dependents: [FarmTask] {
        allTasks.filter { $0.dependencyIDs.contains(task.id) }
    }

    private var dependencies: [FarmTask] {
        allTasks.filter { task.dependencyIDs.contains($0.id) }
    }

    private var unmetDependencies: [FarmTask] {
        dependencies.filter { $0.status != .completed }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                headerCard
                if task.weatherReviewNeeded { weatherReviewCard }
                if !unmetDependencies.isEmpty { dependencyWarning }
                detailsCard
                if !task.requiredInputs.isEmpty { inputsCard }
                actionsCard
            }
            .padding(Spacing.l)
            .padding(.bottom, Spacing.xxl)
        }
        .farmBackground()
        .navigationTitle("Task")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showEditor = true } label: { Label("Edit", systemImage: "pencil") }
                    Button { showReschedule = true } label: {
                        Label("Reschedule", systemImage: "calendar")
                    }
                    Divider()
                    Button(role: .destructive) { showDelete = true } label: {
                        Label("Delete…", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundStyle(Palette.gold)
                }
            }
        }
        .sheet(isPresented: $showEditor) { TaskEditorView(season: task.season, task: task) }
        .sheet(isPresented: $showReschedule) { RescheduleView(task: task, dependents: dependents) }
        .sheet(isPresented: $showCompleteSheet) { completeSheet }
        .alert("Mark as blocked", isPresented: $showBlockSheet) {
            TextField("Reason", text: $blockReason)
            Button("Cancel", role: .cancel) { }
            Button("Mark blocked") { markBlocked() }
        } message: {
            Text("A reason keeps the plan explainable to whoever picks this up next.")
        }
        .sheet(isPresented: $showDelete) { deleteSheet }
    }

    // MARK: - Cards

    private var headerCard: some View {
        GoldPlate(accent: task.isOverdue ? Palette.burgundy : Palette.gold) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.title)
                            .font(TypeScale.title(19)).foregroundStyle(Palette.cream)
                        Text(task.fieldNameSnapshot.isEmpty ? "No field" : task.fieldNameSnapshot)
                            .font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
                    }
                    Spacer()
                    StatusPill(text: task.status.rawValue, tone: task.status.tone)
                }
                if let detail = task.detail {
                    Text(detail).font(TypeScale.body(13)).foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Spacing.l)
        }
    }

    private var weatherReviewCard: some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Label("Weather changed since this was planned", systemImage: "cloud.sun.bolt")
                    .font(TypeScale.headline(14)).foregroundStyle(Palette.amber)
                if let note = task.weatherReviewNote {
                    Text(note).font(TypeScale.body(12)).foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("The task has not been moved. Review it and decide yourself.")
                    .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                HStack(spacing: Spacing.s) {
                    ChipButton(title: "Reschedule", systemImage: "calendar") { showReschedule = true }
                    ChipButton(title: "Dismiss flag", systemImage: "checkmark",
                               tint: Palette.textSecondary) {
                        task.weatherReviewNeeded = false
                        task.weatherReviewNote = nil
                        try? context.save()
                        appState.confirm("Weather flag cleared")
                    }
                }
            }
        }
    }

    private var dependencyWarning: some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Label("Waiting on \(unmetDependencies.count) task(s)", systemImage: "arrow.triangle.branch")
                    .font(TypeScale.headline(13)).foregroundStyle(Palette.amber)
                ForEach(unmetDependencies) { dependency in
                    Text("— \(dependency.title) (\(dependency.status.rawValue))")
                        .font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                }
                Text("You can still start this task; the app only points out the order you recorded.")
                    .font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var detailsCard: some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader(title: "Details")
                ValueRow(label: "Season", value: task.season?.displayTitle)
                ValueRow(label: "Due", value: task.dueDisplay)
                ValueRow(label: "Priority", value: task.priority.rawValue)
                ValueRow(label: "Assignee", value: task.assignee)
                ValueRow(label: "Equipment", value: task.equipment)
                ValueRow(label: "Estimated",
                         value: Fmt.duration(minutes: task.estimatedDurationMinutes))
                ValueRow(label: "Started", value: Fmt.dateTime(task.startedAt))
                ValueRow(label: "Completed", value: Fmt.dateTime(task.completedAt))
                ValueRow(label: "Actual time",
                         value: Fmt.duration(minutes: task.actualDurationMinutes))
                if let source = task.sourceWindowDescription {
                    Divider().overlay(Palette.hairline)
                    Text("Source").stampLabel(Palette.textSecondary)
                    Text(source).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let reason = task.blockedReason, task.status == .blocked {
                    Divider().overlay(Palette.hairline)
                    Label(reason, systemImage: "hand.raised")
                        .font(TypeScale.body(12)).foregroundStyle(Palette.burgundy)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var inputsCard: some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader(title: "Required inputs")
                ForEach(task.requiredInputs) { input in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(input.itemName)
                                .font(TypeScale.body(13)).foregroundStyle(Palette.cream)
                            if input.reservationID != nil {
                                Text("Reserved from stock")
                                    .font(.system(size: 10)).foregroundStyle(Palette.positive)
                            } else if input.lotID == nil {
                                Text("Noted only — not held in inventory")
                                    .font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                            }
                        }
                        Spacer()
                        Text(Fmt.quantity(input.quantity, input.unit?.symbol) ?? "—")
                            .font(TypeScale.mono(12)).foregroundStyle(Palette.gold)
                    }
                }
                Text("Reservations are released when the task completes or is cancelled. Stock is deducted only by a confirmed application.")
                    .font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var actionsCard: some View {
        VStack(spacing: Spacing.s) {
            switch task.status {
            case .planned:
                AmberButton(title: "Start", systemImage: "play.fill") { start() }
                GhostButton(title: "Mark blocked", systemImage: "hand.raised",
                            tint: Palette.burgundy) { showBlockSheet = true }
            case .inProgress:
                AmberButton(title: "Complete", systemImage: "checkmark") { showCompleteSheet = true }
                GhostButton(title: "Mark blocked", systemImage: "hand.raised",
                            tint: Palette.burgundy) { showBlockSheet = true }
            case .blocked:
                AmberButton(title: "Unblock and start", systemImage: "play.fill") { start() }
            case .completed:
                CardShell {
                    Label("Completed \(Fmt.dateTime(task.completedAt) ?? "")",
                          systemImage: "checkmark.seal.fill")
                        .font(TypeScale.headline(14)).foregroundStyle(Palette.positive)
                }
                GhostButton(title: "Reopen task", systemImage: "arrow.uturn.backward") { reopen() }
            case .cancelled:
                GhostButton(title: "Restore to planned", systemImage: "arrow.uturn.backward") {
                    task.status = .planned
                    try? context.save()
                }
            }
        }
    }

    private var completeSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    CardShell {
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            SectionHeader(title: "Record completion")
                            PlateTextField(label: "Actual time (minutes)",
                                           placeholder: task.estimatedDurationMinutes
                                            .map { String(Int($0)) } ?? "Optional",
                                           text: $actualDurationText, keyboard: .numberPad,
                                           helper: "Leave blank if you did not time it — it will stay Unknown, not zero.")
                            if !task.requiredInputs.filter({ $0.reservationID != nil }).isEmpty {
                                Text("Reserved stock will be released back to available. It is deducted only when you record an application.")
                                    .font(.system(size: 11)).foregroundStyle(Palette.amber)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    AmberButton(title: "Complete task", systemImage: "checkmark") { complete() }
                }
                .padding(Spacing.l)
            }
            .farmBackground()
            .navigationTitle("Complete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { showCompleteSheet = false }
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }
    }

    private var deleteSheet: some View {
        var consequences: [String] = []
        if !dependents.isEmpty {
            consequences.append("\(dependents.count) task(s) depend on this one; the dependency will be removed from them.")
        }
        let reserved = task.requiredInputs.filter { $0.reservationID != nil }
        if !reserved.isEmpty {
            consequences.append("\(reserved.count) stock reservation(s) will be released back to available.")
        }
        if task.status == .completed {
            consequences.append("This task is completed and forms part of the season record.")
        }

        return ConsequenceSheet(
            title: "Delete “\(task.title)”?",
            entityName: task.title,
            consequences: consequences,
            canDelete: task.status != .completed,
            deleteBlockedReason: task.status == .completed
                ? "A completed task is part of the season history. Reopen it first if you really need to remove it."
                : nil,
            onArchive: nil,
            onDetach: dependents.isEmpty ? nil : {
                for dependent in dependents {
                    dependent.dependencyIDs.removeAll { $0 == task.id }
                }
                try? context.save()
                showDelete = false
                appState.confirm("Dependencies removed", detail: "\(dependents.count) task(s) updated")
            },
            onDelete: { performDelete() },
            onCancel: { showDelete = false }
        )
    }

    // MARK: - Actions

    private func start() {
        task.status = .inProgress
        task.blockedReason = nil
        if task.startedAt == nil { task.startedAt = Date() }
        task.updatedAt = Date()
        AuditService.log(action: "Started", entityType: "Task", entityID: task.id,
                         summary: "Task “\(task.title)” started", context: context)
        try? context.save()
        appState.confirm("Task started", detail: task.title)
    }

    private func markBlocked() {
        task.status = .blocked
        task.blockedReason = blockReason.isEmpty ? "No reason given" : blockReason
        task.updatedAt = Date()
        AuditService.log(action: "Blocked", entityType: "Task", entityID: task.id,
                         summary: "Task “\(task.title)” blocked",
                         details: task.blockedReason, context: context)
        try? context.save()
        blockReason = ""
        appState.confirm("Task marked blocked")
    }

    /// Guarded by `completionKey`: a repeated tap will not record twice.
    private func complete() {
        guard task.completionKey == nil else {
            showCompleteSheet = false
            appState.confirm("Already completed", detail: "This task was recorded once.")
            return
        }

        task.completionKey = UUID()
        task.status = .completed
        task.completedAt = Date()
        task.actualDurationMinutes = Double(actualDurationText)
        task.weatherReviewNeeded = false
        task.updatedAt = Date()

        // Release reservations; consumption belongs to an application record.
        var released = 0
        for input in task.requiredInputs where input.reservationID != nil {
            guard let lotID = input.lotID,
                  let lot = lots.first(where: { $0.id == lotID }),
                  let quantity = input.quantity, let unit = input.unit,
                  let converted = unit.convert(quantity, to: lot.unit) else { continue }
            InventoryService.releaseReservation(lot: lot, quantity: converted,
                                                forTask: task.id, taskLabel: task.title,
                                                context: context)
            released += 1
        }
        task.requiredInputs = task.requiredInputs.map { input in
            var copy = input
            copy.reservationID = nil
            return copy
        }

        AuditService.log(action: "Completed", entityType: "Task", entityID: task.id,
                         summary: "Task “\(task.title)” completed",
                         details: Fmt.duration(minutes: task.actualDurationMinutes),
                         context: context)
        try? context.save()
        showCompleteSheet = false
        appState.confirm("Task completed",
                         detail: released > 0 ? "\(released) reservation(s) released" : task.title)
    }

    private func reopen() {
        task.status = .inProgress
        task.completedAt = nil
        task.completionKey = nil
        task.updatedAt = Date()
        AuditService.log(action: "Reopened", entityType: "Task", entityID: task.id,
                         summary: "Task “\(task.title)” reopened", context: context)
        try? context.save()
        appState.confirm("Task reopened")
    }

    private func performDelete() {
        for input in task.requiredInputs where input.reservationID != nil {
            guard let lotID = input.lotID,
                  let lot = lots.first(where: { $0.id == lotID }),
                  let quantity = input.quantity, let unit = input.unit,
                  let converted = unit.convert(quantity, to: lot.unit) else { continue }
            InventoryService.releaseReservation(lot: lot, quantity: converted,
                                                forTask: task.id, taskLabel: task.title,
                                                context: context)
        }
        for dependent in dependents {
            dependent.dependencyIDs.removeAll { $0 == task.id }
        }
        AuditService.log(action: "Deleted", entityType: "Task", entityID: task.id,
                         summary: "Task “\(task.title)” deleted", context: context)
        task.season?.tasks.removeAll { $0.id == task.id }
        context.delete(task)
        try? context.save()
        showDelete = false
        appState.confirm("Task deleted")
    }
}

// MARK: - Reschedule

struct RescheduleView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    var task: FarmTask
    var dependents: [FarmTask]

    @State private var newStart: Date?
    @State private var newEnd: Date?
    @State private var shiftDependents = false
    @State private var error: String?

    private var shiftInterval: TimeInterval? {
        guard let newStart, let original = task.dueStart else { return nil }
        return newStart.timeIntervalSince(original)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    CardShell {
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            SectionHeader(title: "New due window")
                            OptionalDateRow(label: "Start", date: $newStart)
                            OptionalDateRow(label: "End", date: $newEnd)
                            if let error {
                                Label(error, systemImage: "exclamationmark.circle.fill")
                                    .font(.system(size: 11)).foregroundStyle(Palette.burgundy)
                            }
                        }
                    }

                    if !dependents.isEmpty {
                        CardShell {
                            VStack(alignment: .leading, spacing: Spacing.s) {
                                SectionHeader(title: "Dependent tasks")
                                Text("\(dependents.count) task(s) depend on this one. They are not moved unless you choose to.")
                                    .font(TypeScale.body(12)).foregroundStyle(Palette.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                ForEach(dependents) { dependent in
                                    HStack {
                                        Text(dependent.title)
                                            .font(TypeScale.body(13)).foregroundStyle(Palette.cream)
                                        Spacer()
                                        Text(dependent.dueDisplay ?? "no due date")
                                            .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                                    }
                                }
                                Toggle(isOn: $shiftDependents) {
                                    Text("Shift them by the same amount")
                                        .font(TypeScale.body(13)).foregroundStyle(Palette.cream)
                                }
                                .tint(Palette.amber)
                                .disabled(shiftInterval == nil)
                                if shiftInterval == nil {
                                    Text("A shift can only be offered when both the old and new start dates are set.")
                                        .font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                                }
                            }
                        }
                    }

                    AmberButton(title: "Apply", systemImage: "checkmark") { apply() }
                }
                .padding(Spacing.l)
            }
            .farmBackground()
            .navigationTitle("Reschedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Palette.textSecondary)
                }
            }
            .onAppear {
                newStart = task.dueStart
                newEnd = task.dueEnd
            }
        }
    }

    private func apply() {
        error = nil
        if let start = newStart, let end = newEnd, end < start {
            error = "The window ends before it starts."
            return
        }

        var movedCount = 0
        if shiftDependents, let interval = shiftInterval {
            for dependent in dependents {
                if let start = dependent.dueStart {
                    dependent.dueStart = start.addingTimeInterval(interval)
                }
                if let end = dependent.dueEnd {
                    dependent.dueEnd = end.addingTimeInterval(interval)
                }
                dependent.updatedAt = Date()
                movedCount += 1
            }
        }

        task.dueStart = newStart
        task.dueEnd = newEnd
        task.weatherReviewNeeded = false
        task.updatedAt = Date()

        AuditService.log(action: "Rescheduled", entityType: "Task", entityID: task.id,
                         summary: "Task “\(task.title)” rescheduled",
                         details: movedCount > 0 ? "\(movedCount) dependent task(s) shifted too" : nil,
                         context: context)
        try? context.save()
        appState.confirm("Task rescheduled",
                         detail: movedCount > 0 ? "\(movedCount) dependent task(s) also moved" : nil)
        dismiss()
    }
}
