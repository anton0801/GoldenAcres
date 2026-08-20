//
//  FieldListView.swift
//  GoldenAcres
//
//  Field index and the per-field hub that links seasons, observations,
//  weather, soil and irrigation together.
//

import SwiftUI
import SwiftData

struct FieldListView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appState: AppState
    @Query(sort: \Farm.createdAt) private var farms: [Farm]

    @State private var showFieldEditor = false
    @State private var showFarmSetup = false
    @State private var showArchived = false

    private var farm: Farm? { farms.first(where: { !$0.isArchived }) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                if let farm {
                    let fields = showArchived ? farm.fields : farm.activeFields

                    if fields.isEmpty {
                        HonestEmptyState(
                            icon: "square.dashed",
                            title: showArchived ? "No archived fields" : "No fields yet",
                            message: showArchived
                                ? "Fields you archive keep their history and appear here."
                                : "Add your first field. Everything else — seasons, observations, irrigation — hangs off a field.",
                            actionTitle: showArchived ? nil : "Add field",
                            action: showArchived ? nil : { showFieldEditor = true }
                        )
                        .padding(.top, Spacing.xl)
                    } else {
                        ForEach(fields.sorted(by: { $0.name < $1.name })) { field in
                            NavigationLink { FieldDetailView(field: field) } label: {
                                FieldPlateCard(field: field)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if farm.fields.contains(where: \.isArchived) {
                        Button(showArchived ? "Hide archived" : "Show archived") {
                            withAnimation { showArchived.toggle() }
                        }
                        .font(TypeScale.body(13))
                        .foregroundStyle(Palette.gold)
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    HonestEmptyState(
                        icon: "house",
                        title: "No farm yet",
                        message: "Create a farm first — fields belong to it.",
                        actionTitle: "Create farm",
                        action: { showFarmSetup = true }
                    )
                    .padding(.top, Spacing.xxl)
                }
            }
            .padding(Spacing.l)
        }
        .farmBackground()
        .navigationTitle("Fields")
        .toolbar {
            if farm != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showFieldEditor = true } label: {
                        Image(systemName: "plus").foregroundStyle(Palette.gold)
                    }
                }
            }
        }
        .sheet(isPresented: $showFieldEditor) {
            if let farm { FieldEditorView(farm: farm, field: nil) }
        }
        .sheet(isPresented: $showFarmSetup) { FarmSetupView() }
    }
}

// MARK: - Field card

struct FieldPlateCard: View {
    var field: FarmField

    var body: some View {
        GoldPlate {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(field.name)
                            .font(TypeScale.title(19))
                            .foregroundStyle(Palette.cream)
                        if let season = field.currentSeason {
                            Text(season.displayTitle)
                                .font(TypeScale.body(13))
                                .foregroundStyle(Palette.gold)
                        } else {
                            Text("No active season")
                                .font(TypeScale.body(13))
                                .foregroundStyle(Palette.textTertiary)
                        }
                    }
                    Spacer()
                    if field.isArchived {
                        StatusPill(text: "archived", tone: .neutral)
                    } else if field.currentSeason != nil {
                        StatusPill(text: "active", tone: .positive)
                    }
                }

                Divider().overlay(Palette.hairline)

                HStack(spacing: Spacing.xl) {
                    ValueColumn(label: "Area",
                                value: Fmt.number(field.areaValue, decimals: 2),
                                unit: field.areaUnit.symbol)
                    ValueColumn(label: "Observations",
                                value: "\(field.observations.count)", unit: nil)
                    ValueColumn(label: "Soil tests",
                                value: "\(field.soilTests.filter(\.isConfirmed).count)", unit: nil)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Palette.gold.opacity(0.7))
                }

                if field.areaValue == nil || field.resolvedCoordinate == nil {
                    HStack(spacing: Spacing.s) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 10))
                        Text(missingSummary)
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(Palette.amber)
                }
            }
            .padding(Spacing.l)
        }
    }

    private var missingSummary: String {
        var missing: [String] = []
        if field.areaValue == nil { missing.append("area") }
        if field.resolvedCoordinate == nil { missing.append("location") }
        return "Missing \(missing.joined(separator: " and ")) — some calculations stay unavailable"
    }
}

// MARK: - Field detail

struct FieldDetailView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appState: AppState
    var field: FarmField

    @State private var showEditor = false
    @State private var showSeasonEditor = false
    @State private var showObservation = false
    @State private var showDeleteSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                summaryCard
                sectionLinks
                seasonsSection
                observationsSection
            }
            .padding(Spacing.l)
            .padding(.bottom, Spacing.xxl)
        }
        .farmBackground()
        .navigationTitle(field.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showEditor = true } label: { Label("Edit field", systemImage: "pencil") }
                    Button {
                        field.isArchived.toggle()
                        try? context.save()
                        appState.confirm(field.isArchived ? "Field archived" : "Field restored",
                                         detail: field.name)
                    } label: {
                        Label(field.isArchived ? "Restore field" : "Archive field",
                              systemImage: field.isArchived ? "arrow.uturn.backward" : "archivebox")
                    }
                    Divider()
                    Button(role: .destructive) { showDeleteSheet = true } label: {
                        Label("Delete field…", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundStyle(Palette.gold)
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            if let farm = field.farm { FieldEditorView(farm: farm, field: field) }
        }
        .sheet(isPresented: $showSeasonEditor) {
            if let farm = field.farm {
                SeasonEditorView(farm: farm, field: field, season: nil)
            }
        }
        .sheet(isPresented: $showObservation) {
            if let farm = field.farm {
                ObservationEditorView(farm: farm, field: field, observation: nil)
            }
        }
        .sheet(isPresented: $showDeleteSheet) { deleteSheet }
    }

    private var summaryCard: some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader(title: "Field record")
                ValueRow(label: "Area",
                         value: Fmt.number(field.areaValue, decimals: 3),
                         unit: field.areaUnit.symbol,
                         onFill: { showEditor = true })
                ValueRow(label: "Boundary", value: field.boundary.kind == .none ? nil : field.boundary.kind.label,
                         unknownHint: "Not set", onFill: { showEditor = true })
                ValueRow(label: "Soil type", value: field.soilType, onFill: { showEditor = true })
                ValueRow(label: "Irrigation method", value: field.irrigationMethod?.rawValue,
                         onFill: { showEditor = true })
                ValueRow(label: "Coordinates",
                         value: field.resolvedCoordinate.map {
                             "\(String(format: "%.4f", $0.lat)), \(String(format: "%.4f", $0.lon))"
                         },
                         unknownHint: "Not set", onFill: { showEditor = true })
                if let notes = field.notes, !notes.isEmpty {
                    Divider().overlay(Palette.hairline)
                    Text(notes).font(TypeScale.body(13)).foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var sectionLinks: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeader(title: "Work with this field")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.m) {
                NavLinkCard(title: "Weather & windows", icon: "cloud.sun") {
                    WeatherWindowsView(field: field)
                }
                NavLinkCard(title: "Soil tests", icon: "testtube.2") {
                    SoilTestLibraryView(field: field)
                }
                NavLinkCard(title: "Irrigation", icon: "drop") {
                    IrrigationPlannerView(field: field)
                }
                NavLinkCard(title: "Observations", icon: "eye") {
                    ObservationListView(field: field)
                }
            }
        }
    }

    private var seasonsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeader(title: "Crop seasons", actionTitle: "Start",
                          action: { showSeasonEditor = true })
            if field.seasons.isEmpty {
                CardShell {
                    Text("No seasons on this field yet. A season is what links tasks, inputs, irrigation and harvest together.")
                        .font(TypeScale.body(13)).foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                CardShell {
                    VStack(spacing: 0) {
                        let sorted = field.seasons.sorted { $0.createdAt > $1.createdAt }
                        ForEach(sorted) { season in
                            DrillRow(title: season.displayTitle,
                                     subtitle: "\(season.status.label) · \(season.tasks.count) task(s)",
                                     trailing: Fmt.date(season.actualPlantingDate)) {
                                SeasonDetailView(season: season)
                            }
                            if season.id != sorted.last?.id { Divider().overlay(Palette.hairline) }
                        }
                    }
                }
            }
        }
    }

    private var observationsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeader(title: "Recent observations", actionTitle: "Record",
                          action: { showObservation = true })
            let recent = field.observations.sorted { $0.date > $1.date }.prefix(3)
            if recent.isEmpty {
                CardShell {
                    Text("Nothing recorded yet. A note or a photo is enough to create an observation.")
                        .font(TypeScale.body(13)).foregroundStyle(Palette.textSecondary)
                }
            } else {
                CardShell {
                    VStack(spacing: 0) {
                        ForEach(recent) { obs in
                            DrillRow(title: obs.confirmedCategory ?? obs.observationType.rawValue,
                                     subtitle: obs.summaryLine,
                                     trailing: Fmt.date(obs.date)) {
                                ObservationDetailView(observation: obs)
                            }
                            if obs.id != recent.last?.id { Divider().overlay(Palette.hairline) }
                        }
                    }
                }
            }
        }
    }

    // MARK: Delete

    private var deleteSheet: some View {
        let consequences = deleteConsequences()
        return ConsequenceSheet(
            title: "Delete field “\(field.name)”?",
            entityName: field.name,
            consequences: consequences,
            canDelete: true,
            deleteBlockedReason: nil,
            onArchive: {
                field.isArchived = true
                try? context.save()
                showDeleteSheet = false
                appState.confirm("Field archived", detail: "History kept. You can restore it any time.")
            },
            onDetach: nil,
            onDelete: {
                performDelete()
            },
            onCancel: { showDeleteSheet = false }
        )
    }

    private func deleteConsequences() -> [String] {
        var out: [String] = []
        if !field.seasons.isEmpty {
            out.append("\(field.seasons.count) crop season(s) and their tasks will be deleted with the field.")
        }
        if !field.observations.isEmpty {
            out.append("\(field.observations.count) observation(s) will be kept but detached — they will show as “field deleted”.")
        }
        if !field.soilTests.isEmpty {
            out.append("\(field.soilTests.count) soil test(s) will be kept but detached.")
        }
        if !field.irrigationPlans.isEmpty {
            out.append("\(field.irrigationPlans.count) irrigation plan(s) will be kept but detached.")
        }
        let batches = field.seasons.flatMap(\.harvestBatches)
        if !batches.isEmpty {
            out.append("\(batches.count) harvest batch(es) stay in Records with a note that the field is gone.")
        }
        let applications = field.seasons.flatMap(\.applications)
        if !applications.isEmpty {
            out.append("\(applications.count) application record(s) remain — they are legal records and are never removed.")
        }
        return out
    }

    private func performDelete() {
        let name = field.name
        AuditService.log(action: "Deleted", entityType: "Field", entityID: field.id,
                         summary: "Field “\(name)” deleted",
                         details: deleteConsequences().joined(separator: " "),
                         context: context)
        field.farm?.fields.removeAll { $0.id == field.id }
        context.delete(field)
        try? context.save()
        showDeleteSheet = false
        appState.confirm("Field deleted", detail: "Linked records were kept and marked as detached.")
    }
}

// MARK: - Small nav card

struct NavLinkCard<Destination: View>: View {
    var title: String
    var icon: String
    @ViewBuilder var destination: Destination

    var body: some View {
        NavigationLink { destination } label: {
            HStack(spacing: Spacing.s) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.gold)
                Text(title)
                    .font(TypeScale.headline(13))
                    .foregroundStyle(Palette.cream)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .padding(.horizontal, Spacing.m)
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
