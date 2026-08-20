//
//  ObservationListView.swift
//  GoldenAcres
//
//  Observation index and detail. The stored photo, the machine suggestion and
//  the user's confirmed category are shown as three separate things.
//

import SwiftUI
import SwiftData

struct ObservationListView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appState: AppState
    var field: FarmField

    @State private var showEditor = false
    @State private var filter: ObservationType?

    private var observations: [FieldObservation] {
        field.observations
            .filter { filter == nil || $0.observationType == filter }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                if !field.observations.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.s) {
                            FilterChip(title: "All", isOn: filter == nil) { filter = nil }
                            ForEach(usedTypes, id: \.self) { type in
                                FilterChip(title: type.rawValue, isOn: filter == type) {
                                    filter = filter == type ? nil : type
                                }
                            }
                        }
                    }
                }

                if observations.isEmpty {
                    HonestEmptyState(
                        icon: "eye",
                        title: field.observations.isEmpty ? "No observations yet" : "Nothing matches this filter",
                        message: field.observations.isEmpty
                            ? "A note or a photo is enough. Observations stay linked to this field and to the season running when you recorded them."
                            : "Clear the filter to see the rest.",
                        actionTitle: field.observations.isEmpty ? "Record observation" : nil,
                        action: field.observations.isEmpty ? { showEditor = true } : nil
                    )
                    .padding(.top, Spacing.xl)
                } else {
                    ForEach(observations) { obs in
                        NavigationLink { ObservationDetailView(observation: obs) } label: {
                            ObservationRowCard(observation: obs)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(Spacing.l)
        }
        .farmBackground()
        .navigationTitle("Observations")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showEditor = true } label: {
                    Image(systemName: "plus").foregroundStyle(Palette.gold)
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            if let farm = field.farm {
                ObservationEditorView(farm: farm, field: field, observation: nil)
            }
        }
    }

    private var usedTypes: [ObservationType] {
        Array(Set(field.observations.map(\.observationType))).sorted { $0.rawValue < $1.rawValue }
    }
}

struct FilterChip: View {
    var title: String
    var isOn: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(TypeScale.stamp(11)).tracking(0.5)
                .foregroundStyle(isOn ? Palette.graphite : Palette.textSecondary)
                .padding(.vertical, 6).padding(.horizontal, Spacing.m)
                .background(
                    Capsule().fill(isOn ? AnyShapeStyle(Plating.amberAction)
                                        : AnyShapeStyle(Palette.surfaceRaised))
                )
        }
        .buttonStyle(.plain)
    }
}

struct ObservationRowCard: View {
    var observation: FieldObservation

    var body: some View {
        CardShell {
            HStack(alignment: .top, spacing: Spacing.m) {
                if let first = observation.photoFilenames.first,
                   let image = PhotoStore.load(first) {
                    Image(uiImage: image)
                        .resizable().scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.small))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: Radius.small)
                            .fill(Palette.surfaceRaised)
                            .frame(width: 56, height: 56)
                        Image(systemName: observation.observationType.icon)
                            .foregroundStyle(Palette.gold)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(observation.confirmedCategory ?? observation.observationType.rawValue)
                            .font(TypeScale.headline(14)).foregroundStyle(Palette.cream)
                        Spacer()
                        if let severity = observation.severity {
                            StatusPill(text: severity.rawValue, tone: severity.tone)
                        }
                    }
                    Text(observation.summaryLine)
                        .font(TypeScale.body(12)).foregroundStyle(Palette.textSecondary)
                        .lineLimit(2).multilineTextAlignment(.leading)
                    HStack(spacing: Spacing.s) {
                        Text(Fmt.dateTime(observation.date) ?? "")
                            .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                        if observation.reviewRequested {
                            StatusPill(text: "review", tone: .warning)
                        }
                        if observation.isDetached {
                            StatusPill(text: "detached", tone: .neutral)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Detail

struct ObservationDetailView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appState: AppState
    var observation: FieldObservation

    @State private var showEditor = false
    @State private var showDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                if !observation.photoFilenames.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.s) {
                            ForEach(observation.photoFilenames, id: \.self) { name in
                                if let image = PhotoStore.load(name) {
                                    Image(uiImage: image)
                                        .resizable().scaledToFill()
                                        .frame(width: 200, height: 150)
                                        .clipShape(RoundedRectangle(cornerRadius: Radius.medium))
                                } else {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: Radius.medium)
                                            .fill(Palette.surfaceRaised)
                                            .frame(width: 200, height: 150)
                                        VStack(spacing: Spacing.xs) {
                                            Image(systemName: "photo.badge.exclamationmark")
                                                .foregroundStyle(Palette.amber)
                                            Text("Photo file missing")
                                                .font(.system(size: 11))
                                                .foregroundStyle(Palette.textSecondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                CardShell {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        SectionHeader(title: "Record")
                        ValueRow(label: "Field",
                                 value: observation.field?.name
                                    ?? (observation.fieldNameSnapshot.isEmpty ? nil : "\(observation.fieldNameSnapshot) (detached)"))
                        ValueRow(label: "Date", value: Fmt.dateTime(observation.date))
                        ValueRow(label: "Type", value: observation.observationType.rawValue)
                        ValueRow(label: "Severity", value: observation.severity?.rawValue,
                                 unknownHint: "Not rated")
                        ValueRow(label: "Confirmed category", value: observation.confirmedCategory,
                                 unknownHint: "Not set")
                        ValueRow(label: "Affected area",
                                 value: Fmt.number(observation.affectedAreaValue, decimals: 2),
                                 unit: observation.affectedAreaUnit.symbol)
                        ValueRow(label: "Crop stage", value: observation.relatedCropStage)
                        if let notes = observation.notes {
                            Divider().overlay(Palette.hairline)
                            Text(notes).font(TypeScale.body(14)).foregroundStyle(Palette.cream)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if let suggestion = observation.imageSuggestion {
                    CardShell {
                        VStack(alignment: .leading, spacing: Spacing.s) {
                            SectionHeader(title: "Image suggestion (unconfirmed)")
                            if let category = suggestion.suggestedCategory {
                                HStack {
                                    Text(category).font(TypeScale.headline(14))
                                        .foregroundStyle(Palette.cream)
                                    Spacer()
                                    Text("\(Int((suggestion.confidence ?? 0) * 100))%")
                                        .font(TypeScale.mono(13)).foregroundStyle(Palette.amber)
                                }
                            } else {
                                Text(suggestion.message ?? "Unable to identify reliably.")
                                    .font(TypeScale.body(13)).foregroundStyle(Palette.amber)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            ProvenanceBadge(source: suggestion.provenance.source,
                                            lastUpdated: suggestion.provenance.retrievedAt)
                            Text("Stored separately from your confirmed category. Not a diagnosis.")
                                .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                        }
                    }
                }
            }
            .padding(Spacing.l)
        }
        .farmBackground()
        .navigationTitle("Observation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showEditor = true } label: { Label("Edit", systemImage: "pencil") }
                    Button {
                        observation.isArchived.toggle()
                        try? context.save()
                        appState.confirm(observation.isArchived ? "Observation archived" : "Observation restored")
                    } label: {
                        Label(observation.isArchived ? "Restore" : "Archive",
                              systemImage: observation.isArchived ? "arrow.uturn.backward" : "archivebox")
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
        .sheet(isPresented: $showEditor) {
            if let farm = observation.field?.farm {
                ObservationEditorView(farm: farm, field: observation.field, observation: observation)
            }
        }
        .sheet(isPresented: $showDelete) {
            ConsequenceSheet(
                title: "Delete this observation?",
                entityName: "observation",
                consequences: consequences,
                canDelete: true,
                deleteBlockedReason: nil,
                onArchive: {
                    observation.isArchived = true
                    try? context.save()
                    showDelete = false
                    appState.confirm("Observation archived")
                },
                onDetach: nil,
                onDelete: { performDelete() },
                onCancel: { showDelete = false }
            )
        }
    }

    private var consequences: [String] {
        var out: [String] = []
        if !observation.photoFilenames.isEmpty {
            out.append("\(observation.photoFilenames.count) stored photo(s) will be deleted from the device.")
        }
        if observation.linkedTaskID != nil {
            out.append("A task links to this observation; the link will be removed but the task stays.")
        }
        if observation.seasonID != nil {
            out.append("It will no longer appear in that season's report or traceability trail.")
        }
        return out
    }

    private func performDelete() {
        for name in observation.photoFilenames { PhotoStore.delete(name) }
        AuditService.log(action: "Deleted", entityType: "Observation", entityID: observation.id,
                         summary: "Observation on \(observation.fieldNameSnapshot) deleted",
                         context: context)
        observation.field?.observations.removeAll { $0.id == observation.id }
        context.delete(observation)
        try? context.save()
        showDelete = false
        appState.confirm("Observation deleted")
    }
}
