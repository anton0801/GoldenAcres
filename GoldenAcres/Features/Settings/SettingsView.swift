//
//  SettingsView.swift
//  GoldenAcres
//
//  Screen 14. Units, roles, connections, sync state, export and deletion.
//  Integrations state exactly what they can do; deleting a farm lists every
//  linked record and requires the name typed out.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var auth: AuthStore

    @Query(sort: \Farm.createdAt) private var farms: [Farm]
    @Query private var connections: [DataConnection]
    @Query private var events: [AuditEvent]

    @State private var showFarmEditor = false
    @State private var showDeleteFarm = false
    @State private var showMemberSheet = false
    @State private var memberName = ""
    @State private var memberRole: TeamRole = .worker

    private var farm: Farm? { farms.first(where: { !$0.isArchived }) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                accountLinkCard

                if let farm {
                    farmCard(farm)
                    unitsCard(farm)
                    accessCard(farm)
                    connectionsCard(farm)
                    syncCard(farm)
                    dataCard(farm)
                    dangerCard(farm)
                } else {
                    HonestEmptyState(icon: "gearshape", title: "No farm yet",
                                     message: "Settings apply to a farm. Create one first.")
                        .padding(.top, Spacing.xxl)
                }
            }
            .padding(Spacing.l)
            .padding(.bottom, Spacing.xxl)
        }
        .farmBackground()
        .navigationTitle("Data & access")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showFarmEditor) {
            FarmSetupView(existingFarm: farm)
        }
        .sheet(isPresented: $showDeleteFarm) {
            if let farm { deleteSheet(farm) }
        }
        .alert("Add team member", isPresented: $showMemberSheet) {
            TextField("Name", text: $memberName)
            Button("Cancel", role: .cancel) { memberName = "" }
            Button("Add") { addMember() }
        } message: {
            Text("Roles limit what someone can do. This is a local record — the app does not send invitations.")
        }
    }

    // MARK: - Cards

    /// Entry point to the account. Shown whether or not anyone is signed in,
    /// because the app is fully usable without an account.
    private var accountLinkCard: some View {
        NavigationLink { ProfileView() } label: {
            GoldPlate {
                HStack(spacing: Spacing.m) {
                    ZStack {
                        Circle()
                            .fill(auth.isSignedIn ? AnyShapeStyle(Plating.plate)
                                                  : AnyShapeStyle(Palette.surfaceRaised))
                            .frame(width: 44, height: 44)
                        Image(systemName: auth.isSignedIn ? "person.fill" : "person")
                            .font(.system(size: 18))
                            .foregroundStyle(auth.isSignedIn ? Palette.graphite : Palette.gold)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(auth.profile?.displayName ?? auth.profile?.email ?? "Account")
                            .font(TypeScale.headline(15)).foregroundStyle(Palette.cream)
                        Text(auth.isSignedIn
                             ? "Signed in · sync, devices, password, deletion"
                             : "Not signed in · this device only")
                            .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Palette.gold)
                }
                .padding(Spacing.l)
            }
        }
        .buttonStyle(.plain)
    }

    private func farmCard(_ farm: Farm) -> some View {
        GoldPlate {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(farm.name).font(TypeScale.title(19)).foregroundStyle(Palette.cream)
                        Text("Created \(Fmt.date(farm.createdAt) ?? "")")
                            .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                    }
                    Spacer()
                    ChipButton(title: "Edit", systemImage: "pencil") { showFarmEditor = true }
                }
                HStack(spacing: Spacing.xl) {
                    ValueColumn(label: "Fields", value: "\(farm.fields.count)", unit: nil)
                    ValueColumn(label: "Seasons",
                                value: "\(farm.fields.flatMap(\.seasons).count)", unit: nil)
                    ValueColumn(label: "Lots", value: "\(farm.inventoryLots.count)", unit: nil)
                }
            }
            .padding(Spacing.l)
        }
    }

    private func unitsCard(_ farm: Farm) -> some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader(title: "Units & currency")
                ValueRow(label: "Default units", value: farm.unitSystem.label)
                ValueRow(label: "Currency", value: farm.currencyCode)
                ValueRow(label: "Time zone", value: farm.timeZoneIdentifier)
                Text("Changing the default affects new entries only. Existing records keep the unit they were saved with, so nothing is silently reinterpreted.")
                    .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func accessCard(_ farm: Farm) -> some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader(title: "Team roles", actionTitle: "Add",
                              action: { showMemberSheet = true })
                if farm.teamMembers.isEmpty {
                    Text("No team members recorded. You have full access as the owner of this local data.")
                        .font(TypeScale.body(13)).foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(farm.teamMembers) { member in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(member.name)
                                    .font(TypeScale.headline(14)).foregroundStyle(Palette.cream)
                                Spacer()
                                StatusPill(text: member.role.rawValue, tone: .gold)
                            }
                            Text(member.role.summary)
                                .font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 3)
                    }
                }
                Divider().overlay(Palette.hairline)
                Text("Roles are recorded here for your own planning. Without sync enabled, this device holds a single local copy and no invitations are sent.")
                    .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func connectionsCard(_ farm: Farm) -> some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.m) {
                SectionHeader(title: "Connected data sources")

                VStack(alignment: .leading, spacing: Spacing.s) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Open-Meteo forecast")
                                .font(TypeScale.headline(14)).foregroundStyle(Palette.cream)
                            Text("Public weather API · no account required")
                                .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                        }
                        Spacer()
                        StatusPill(text: appState.isOnline ? "reachable" : "offline",
                                   tone: appState.isOnline ? .positive : .warning)
                    }
                    Text("Can do: fetch hourly forecast and sunrise/sunset for a coordinate you provide.")
                        .font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Cannot do: control equipment, read your records, or send anything from this device.")
                        .font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider().overlay(Palette.hairline)

                VStack(alignment: .leading, spacing: Spacing.s) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("On-device text & image recognition")
                                .font(TypeScale.headline(14)).foregroundStyle(Palette.cream)
                            Text("Apple Vision · runs locally")
                                .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                        }
                        Spacer()
                        StatusPill(text: "available", tone: .positive)
                    }
                    Text("Can do: read text from a report or label, and suggest a generic image label with a confidence figure.")
                        .font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Cannot do: identify a disease, recommend a treatment, or judge whether a product is approved.")
                        .font(.system(size: 11)).foregroundStyle(Palette.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider().overlay(Palette.hairline)

                VStack(alignment: .leading, spacing: Spacing.s) {
                    HStack {
                        Text("Irrigation controller")
                            .font(TypeScale.headline(14)).foregroundStyle(Palette.cream)
                        Spacer()
                        StatusPill(text: "not connected", tone: .neutral)
                    }
                    Text("No controller integration exists in this build. The app never starts or stops equipment.")
                        .font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func syncCard(_ farm: Farm) -> some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader(title: "Sync")
                HStack {
                    Text("Status").font(TypeScale.body(13)).foregroundStyle(Palette.textSecondary)
                    Spacer()
                    StatusPill(text: appState.connectivityUnknown ? "checking"
                                    : (appState.isOnline ? "online" : "offline"),
                               tone: appState.isOnline ? .positive : .warning)
                }
                ValueRow(label: "Last sync", value: Fmt.dateTime(farm.lastSyncAt),
                         unknownHint: "Never — data is local only")
                Text("This build stores everything on this device. No account is required, and nothing is uploaded. Because there is one copy, there are no sync conflicts to resolve.")
                    .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func dataCard(_ farm: Farm) -> some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.m) {
                SectionHeader(title: "Your data")
                ValueRow(label: "Recorded changes", value: "\(events.count)")
                ValueRow(label: "Retention",
                         value: farm.retentionMonths.map { "\($0) months" },
                         unknownHint: "Kept indefinitely")

                NavigationLink {
                    ExportPreviewView(document: ExportService.fullExport(farm: farm))
                } label: {
                    ChipActionLabel(title: "Export all data", icon: "square.and.arrow.up")
                }
                .buttonStyle(.plain)

                NavigationLink { AuditLogView() } label: {
                    ChipActionLabel(title: "View change history", icon: "clock.arrow.circlepath")
                }
                .buttonStyle(.plain)

                NavigationLink { ArchivedItemsView(farm: farm) } label: {
                    ChipActionLabel(title: "Archived items", icon: "archivebox")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func dangerCard(_ farm: Farm) -> some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionHeader(title: "Delete farm")
                Text("Removes the farm and everything structurally under it. You will see the full list before anything happens.")
                    .font(TypeScale.body(12)).foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    showDeleteFarm = true
                } label: {
                    Text("Delete farm…")
                        .font(TypeScale.headline(14)).foregroundStyle(Palette.cream)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: Radius.medium)
                            .fill(Palette.burgundy.opacity(0.85)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func deleteSheet(_ farm: Farm) -> some View {
        var consequences: [String] = []
        consequences.append("\(farm.fields.count) field(s) will be deleted.")
        let seasons = farm.fields.flatMap(\.seasons)
        if !seasons.isEmpty {
            consequences.append("\(seasons.count) crop season(s) and their task plans will be deleted.")
        }
        let observations = farm.fields.flatMap(\.observations)
        if !observations.isEmpty {
            consequences.append("\(observations.count) observation(s) and their stored photos will be deleted.")
        }
        let tests = farm.fields.flatMap(\.soilTests)
        if !tests.isEmpty {
            consequences.append("\(tests.count) soil test(s) and any uploaded reports will be deleted.")
        }
        if !farm.inventoryLots.isEmpty {
            consequences.append("\(farm.inventoryLots.count) inventory lot(s) and their full movement ledger will be deleted.")
        }
        let batches = seasons.flatMap(\.harvestBatches)
        if !batches.isEmpty {
            consequences.append("\(batches.count) harvest batch(es) will lose their link and remain as orphaned records.")
        }
        let applications = seasons.flatMap(\.applications)
        if !applications.isEmpty {
            consequences.append("\(applications.count) application record(s) will remain — they are never deleted.")
        }
        consequences.append("The change history stays, so the deletion itself is recorded.")

        return ConsequenceSheet(
            title: "Delete “\(farm.name)”?",
            entityName: farm.name,
            consequences: consequences,
            canDelete: true,
            deleteBlockedReason: nil,
            onArchive: {
                farm.isArchived = true
                try? context.save()
                showDeleteFarm = false
                appState.confirm("Farm archived", detail: "Nothing was deleted.")
            },
            onDetach: nil,
            onDelete: { performDelete(farm) },
            onCancel: { showDeleteFarm = false }
        )
    }

    private func performDelete(_ farm: Farm) {
        for observation in farm.fields.flatMap(\.observations) {
            for name in observation.photoFilenames { PhotoStore.delete(name) }
        }
        for test in farm.fields.flatMap(\.soilTests) {
            if let file = test.originalFileName { PhotoStore.delete(file) }
        }
        AuditService.log(action: "Deleted", entityType: "Farm", entityID: farm.id,
                         summary: "Farm “\(farm.name)” deleted with all structural records",
                         context: context)
        context.delete(farm)
        try? context.save()
        showDeleteFarm = false
        appState.confirm("Farm deleted", detail: "The change history was kept.")
    }

    private func addMember() {
        guard let farm, !memberName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let member = TeamMember(name: memberName.trimmingCharacters(in: .whitespaces),
                                role: memberRole)
        member.farm = farm
        context.insert(member)
        farm.teamMembers.append(member)
        AuditService.log(action: "Added", entityType: "Team member", entityID: member.id,
                         summary: "\(member.name) added as \(member.role.rawValue)",
                         context: context)
        try? context.save()
        memberName = ""
        appState.confirm("Team member added", detail: member.role.rawValue)
    }
}

// MARK: - Archived items

struct ArchivedItemsView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appState: AppState
    var farm: Farm

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                let archivedFields = farm.fields.filter(\.isArchived)
                let archivedLots = farm.inventoryLots.filter(\.isArchived)
                let archivedSeasons = farm.fields.flatMap(\.seasons).filter { $0.status == .archived }

                if archivedFields.isEmpty && archivedLots.isEmpty && archivedSeasons.isEmpty {
                    HonestEmptyState(icon: "archivebox", title: "Nothing archived",
                                     message: "Archived items keep their history and can be restored.")
                        .padding(.top, Spacing.xl)
                } else {
                    if !archivedFields.isEmpty {
                        SectionHeader(title: "Fields")
                        ForEach(archivedFields) { field in
                            CardShell {
                                HStack {
                                    Text(field.name)
                                        .font(TypeScale.body(14)).foregroundStyle(Palette.cream)
                                    Spacer()
                                    Button("Restore") {
                                        field.isArchived = false
                                        try? context.save()
                                        appState.confirm("Field restored", detail: field.name)
                                    }
                                    .font(TypeScale.body(13)).foregroundStyle(Palette.gold)
                                }
                            }
                        }
                    }
                    if !archivedSeasons.isEmpty {
                        SectionHeader(title: "Seasons")
                        ForEach(archivedSeasons) { season in
                            CardShell {
                                HStack {
                                    Text(season.displayTitle)
                                        .font(TypeScale.body(14)).foregroundStyle(Palette.cream)
                                    Spacer()
                                    Button("Restore") {
                                        season.status = .draft
                                        try? context.save()
                                        appState.confirm("Season restored as draft")
                                    }
                                    .font(TypeScale.body(13)).foregroundStyle(Palette.gold)
                                }
                            }
                        }
                    }
                    if !archivedLots.isEmpty {
                        SectionHeader(title: "Inventory lots")
                        ForEach(archivedLots) { lot in
                            CardShell {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(lot.displayLabel)
                                            .font(TypeScale.body(14)).foregroundStyle(Palette.cream)
                                        Text("\(lot.movements.count) ledger entries kept")
                                            .font(.system(size: 10))
                                            .foregroundStyle(Palette.textTertiary)
                                    }
                                    Spacer()
                                    Button("Restore") {
                                        InventoryService.restore(lot: lot, context: context)
                                        try? context.save()
                                        appState.confirm("Lot restored")
                                    }
                                    .font(TypeScale.body(13)).foregroundStyle(Palette.gold)
                                }
                            }
                        }
                    }
                }
            }
            .padding(Spacing.l)
        }
        .farmBackground()
        .navigationTitle("Archived")
        .navigationBarTitleDisplayMode(.inline)
    }
}
