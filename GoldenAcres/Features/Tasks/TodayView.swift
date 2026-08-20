//
//  TodayView.swift
//  GoldenAcres
//
//  Screen 9. The crew plan. Completion is idempotent, dependency shifts are
//  suggested rather than applied, and conflicts are explained.
//

import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appState: AppState

    @Query(sort: \Farm.createdAt) private var farms: [Farm]
    @Query private var allTasks: [FarmTask]

    @State private var showEditor = false
    @State private var filter: TaskFilter = .open
    @State private var showShareSheet = false
    @State private var shareText = ""

    enum TaskFilter: String, CaseIterable, Identifiable {
        case today = "Today"
        case open = "Open"
        case blocked = "Blocked"
        case all = "All"
        var id: String { rawValue }
    }

    private var farm: Farm? { farms.first(where: { !$0.isArchived }) }

    private var tasks: [FarmTask] {
        let base = allTasks.sorted { lhs, rhs in
            if lhs.priority.sortWeight != rhs.priority.sortWeight {
                return lhs.priority.sortWeight < rhs.priority.sortWeight
            }
            return (lhs.dueEnd ?? .distantFuture) < (rhs.dueEnd ?? .distantFuture)
        }
        switch filter {
        case .today:
            let calendar = Calendar.current
            return base.filter { task in
                guard task.status.isOpen else { return false }
                guard let due = task.dueStart ?? task.dueEnd else { return false }
                return calendar.isDateInToday(due) || task.isOverdue
            }
        case .open: return base.filter { $0.status.isOpen }
        case .blocked: return base.filter { $0.status == .blocked }
        case .all: return base
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                if farm == nil {
                    HonestEmptyState(
                        icon: "checklist",
                        title: "No farm yet",
                        message: "Tasks belong to a season on a field. Create your farm first."
                    )
                    .padding(.top, Spacing.xxl)
                } else {
                    summaryCard

                    Picker("", selection: $filter) {
                        ForEach(TaskFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if tasks.isEmpty {
                        HonestEmptyState(
                            icon: "checklist",
                            title: emptyTitle,
                            message: emptyMessage,
                            actionTitle: allTasks.isEmpty ? "Add task" : nil,
                            action: allTasks.isEmpty ? { showEditor = true } : nil
                        )
                        .padding(.top, Spacing.l)
                    } else {
                        ForEach(tasks) { task in
                            NavigationLink { TaskDetailView(task: task) } label: {
                                TaskCard(task: task)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !tasks.isEmpty {
                        GhostButton(title: "Share crew summary", systemImage: "square.and.arrow.up") {
                            shareText = buildCrewSummary()
                            showShareSheet = true
                        }
                    }
                }
            }
            .padding(Spacing.l)
            .padding(.bottom, Spacing.xxl)
        }
        .farmBackground()
        .navigationTitle("Today")
        .toolbar {
            if farm != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showEditor = true } label: {
                        Image(systemName: "plus").foregroundStyle(Palette.gold)
                    }
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            TaskEditorView(season: farm?.activeSeasons.first, task: nil)
        }
        .sheet(isPresented: $showShareSheet) {
            CrewSummaryView(text: shareText)
        }
    }

    private var emptyTitle: String {
        allTasks.isEmpty ? "No tasks yet" : "Nothing in this filter"
    }

    private var emptyMessage: String {
        if allTasks.isEmpty {
            return "Activating a season creates an empty plan. Add the work you actually intend to do, or turn a weather window into a task."
        }
        switch filter {
        case .today: return "Nothing is due today and nothing is overdue."
        case .blocked: return "No task is currently blocked."
        default: return "Change the filter to see other tasks."
        }
    }

    private var summaryCard: some View {
        let open = allTasks.filter { $0.status.isOpen }
        let overdue = allTasks.filter(\.isOverdue)
        let flagged = allTasks.filter(\.weatherReviewNeeded)
        return GoldPlate {
            HStack(spacing: Spacing.xl) {
                Medallion(value: completionRatio, caption: "Completed",
                          detail: allTasks.isEmpty ? "no tasks" : nil, diameter: 78)
                VStack(alignment: .leading, spacing: Spacing.s) {
                    KeyStat(value: "\(open.count)", unit: nil, label: "Open")
                    KeyStat(value: "\(overdue.count)", unit: nil, label: "Overdue",
                            tone: overdue.isEmpty ? Palette.gold : Palette.amber)
                    if !flagged.isEmpty {
                        KeyStat(value: "\(flagged.count)", unit: nil, label: "Need weather review",
                                tone: Palette.amber)
                    }
                }
                Spacer()
            }
            .padding(Spacing.l)
        }
    }

    private var completionRatio: Double? {
        guard !allTasks.isEmpty else { return nil }
        let done = allTasks.filter { $0.status == .completed }.count
        return Double(done) / Double(allTasks.count)
    }

    /// Builds text for sharing. It never claims the summary was delivered.
    private func buildCrewSummary() -> String {
        var lines: [String] = ["Crew plan — \(Date().formatted(date: .abbreviated, time: .omitted))", ""]
        for task in tasks {
            var line = "• \(task.title)"
            if !task.fieldNameSnapshot.isEmpty { line += " — \(task.fieldNameSnapshot)" }
            if let due = task.dueDisplay { line += " — due \(due)" }
            if let assignee = task.assignee { line += " — \(assignee)" }
            line += " [\(task.status.rawValue)]"
            lines.append(line)
            if task.weatherReviewNeeded {
                lines.append("   ⚠︎ weather changed since planning — review before starting")
            }
        }
        lines.append("")
        lines.append("Generated from GoldenAcres records on \(Date().formatted()). Sharing this text does not notify anyone automatically.")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Task card

struct TaskCard: View {
    var task: FarmTask

    var body: some View {
        GoldPlate(accent: task.isOverdue ? Palette.burgundy : Palette.gold) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title)
                            .font(TypeScale.headline(15)).foregroundStyle(Palette.cream)
                        Text(task.fieldNameSnapshot.isEmpty ? "No field" : task.fieldNameSnapshot)
                            .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                    }
                    Spacer()
                    StatusPill(text: task.status.rawValue, tone: task.status.tone)
                }

                HStack(spacing: Spacing.s) {
                    if task.priority != .normal {
                        StatusPill(text: task.priority.rawValue, tone: task.priority.tone)
                    }
                    if task.isOverdue { StatusPill(text: "overdue", tone: .risk) }
                    if task.weatherReviewNeeded {
                        StatusPill(text: "review weather", tone: .warning, systemImage: "cloud.sun")
                    }
                }

                HStack(spacing: Spacing.l) {
                    ValueColumn(label: "Due", value: task.dueDisplay, unit: nil)
                    ValueColumn(label: "Assignee", value: task.assignee, unit: nil)
                }

                if !task.requiredInputs.isEmpty {
                    Text("\(task.requiredInputs.count) input(s) required")
                        .font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                }
            }
            .padding(Spacing.l)
        }
    }
}

// MARK: - Crew summary

struct CrewSummaryView: View {
    @Environment(\.dismiss) private var dismiss
    var text: String

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    CardShell {
                        Text(text)
                            .font(TypeScale.mono(12))
                            .foregroundStyle(Palette.cream)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ShareLink(item: text) {
                        HStack(spacing: Spacing.s) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share this text").font(TypeScale.headline(15))
                        }
                        .foregroundStyle(Palette.graphite)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: Radius.medium)
                            .fill(Plating.amberAction))
                    }
                    Text("This copies text to whatever you choose. The app does not send it and will not report it as delivered.")
                        .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Spacing.l)
            }
            .farmBackground()
            .navigationTitle("Crew summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(Palette.gold)
                }
            }
        }
    }
}
