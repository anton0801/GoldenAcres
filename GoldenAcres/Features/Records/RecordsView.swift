//
//  RecordsView.swift
//  GoldenAcres
//
//  Screen 12. The records index plus the traceability walk and exports.
//  Reports are built only from stored records and always list their gaps.
//

import SwiftUI
import SwiftData

struct RecordsView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appState: AppState

    @Query(sort: \Farm.createdAt) private var farms: [Farm]
    @Query(sort: \HarvestBatch.startedAt, order: .reverse) private var batches: [HarvestBatch]
    @Query(sort: \AuditEvent.timestamp, order: .reverse) private var events: [AuditEvent]
    @Query private var applications: [InputApplication]

    private var farm: Farm? { farms.first(where: { !$0.isArchived }) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                if farm == nil {
                    HonestEmptyState(icon: "doc.text.magnifyingglass", title: "No records yet",
                                     message: "Records appear here as you create fields, seasons and harvests.")
                        .padding(.top, Spacing.xxl)
                } else {
                    traceSection
                    seasonsSection
                    applicationsSection
                    historySection
                    exportSection
                }
            }
            .padding(Spacing.l)
            .padding(.bottom, Spacing.xxl)
        }
        .farmBackground()
        .navigationTitle("Records")
    }

    private var traceSection: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeader(title: "Trace a harvest lot",
                          subtitle: "Walk a batch back to the field and seed it came from.")
            if batches.isEmpty {
                CardShell {
                    Text("No harvest batches yet. Once you record a harvest, its full path becomes traceable here.")
                        .font(TypeScale.body(13)).foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                CardShell {
                    VStack(spacing: 0) {
                        ForEach(batches.prefix(6)) { batch in
                            DrillRow(title: "Batch \(batch.batchCode)",
                                     subtitle: "\(batch.fieldNameSnapshot) · \(batch.status.rawValue)",
                                     trailing: Fmt.quantity(batch.totalGross,
                                                            batch.commonUnit?.symbol) ?? "mixed") {
                                TraceabilityView(batch: batch)
                            }
                            if batch.id != batches.prefix(6).last?.id {
                                Divider().overlay(Palette.hairline)
                            }
                        }
                    }
                }
            }
        }
    }

    private var seasonsSection: some View {
        let seasons = (farm?.fields ?? []).flatMap(\.seasons)
        let closed = seasons.filter { $0.status == .closed }
        return VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeader(title: "Seasons", subtitle: "\(closed.count) closed of \(seasons.count)")
            if seasons.isEmpty {
                CardShell {
                    Text("No seasons recorded yet.")
                        .font(TypeScale.body(13)).foregroundStyle(Palette.textSecondary)
                }
            } else {
                CardShell {
                    VStack(spacing: 0) {
                        let sorted = seasons.sorted { $0.createdAt > $1.createdAt }
                        ForEach(sorted.prefix(8)) { season in
                            DrillRow(title: season.displayTitle,
                                     subtitle: "\(season.field?.name ?? "Detached") · \(season.status.label)",
                                     trailing: Fmt.date(season.closedAt)) {
                                SeasonReviewView(season: season)
                            }
                            if season.id != sorted.prefix(8).last?.id {
                                Divider().overlay(Palette.hairline)
                            }
                        }
                    }
                }
            }
            if closed.count >= 2 {
                NavigationLink { SeasonComparisonView(seasons: closed) } label: {
                    ChipActionLabel(title: "Compare closed seasons", icon: "arrow.left.arrow.right")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var applicationsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeader(title: "Input applications",
                          subtitle: "Immutable records, including voided ones.")
            if applications.isEmpty {
                CardShell {
                    Text("No applications recorded.")
                        .font(TypeScale.body(13)).foregroundStyle(Palette.textSecondary)
                }
            } else {
                CardShell {
                    VStack(spacing: 0) {
                        let sorted = applications.sorted { $0.date > $1.date }
                        ForEach(sorted.prefix(6)) { application in
                            DrillRow(title: application.productName,
                                     subtitle: "\(Fmt.date(application.date) ?? "") · \(application.fieldNameSnapshot)\(application.isVoided ? " · VOIDED" : "")",
                                     trailing: Fmt.quantity(application.quantity,
                                                            application.quantityUnit.symbol),
                                     tone: application.isVoided ? Palette.textTertiary : Palette.cream) {
                                ApplicationDetailView(application: application)
                            }
                            if application.id != sorted.prefix(6).last?.id {
                                Divider().overlay(Palette.hairline)
                            }
                        }
                    }
                }
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeader(title: "Change history")
            if events.isEmpty {
                CardShell {
                    Text("No changes recorded yet.")
                        .font(TypeScale.body(13)).foregroundStyle(Palette.textSecondary)
                }
            } else {
                NavigationLink { AuditLogView() } label: {
                    CardShell {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(events.count) recorded change(s)")
                                    .font(TypeScale.headline(14)).foregroundStyle(Palette.cream)
                                Text("Most recent: \(events.first?.summary ?? "")")
                                    .font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Palette.gold)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeader(title: "Export")
            if let farm {
                CardShell {
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        Text("Exports carry generated_at, data_range and version, and list every gap found in the records they cover.")
                            .font(TypeScale.body(12)).foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        NavigationLink { ExportPreviewView(document: ExportService.fullExport(farm: farm)) } label: {
                            ChipActionLabel(title: "Export all farm data", icon: "square.and.arrow.up")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Audit log

struct AuditLogView: View {
    @Query(sort: \AuditEvent.timestamp, order: .reverse) private var events: [AuditEvent]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Every create, update, delete and stock movement, in order. This log is append-only.")
                    .font(TypeScale.body(12)).foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(events) { event in
                    CardShell {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(event.action).stampLabel(Palette.gold)
                                Spacer()
                                Text(Fmt.dateTime(event.timestamp) ?? "")
                                    .font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                            }
                            Text(event.summary)
                                .font(TypeScale.body(13)).foregroundStyle(Palette.cream)
                                .fixedSize(horizontal: false, vertical: true)
                            if let details = event.details {
                                Text(details).font(.system(size: 11))
                                    .foregroundStyle(Palette.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Text("\(event.entityType) · \(event.actor)")
                                .font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                        }
                    }
                }
            }
            .padding(Spacing.l)
        }
        .farmBackground()
        .navigationTitle("Change history")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Traceability

struct TraceabilityView: View {
    @Query private var lots: [InventoryLot]
    var batch: HarvestBatch

    @State private var result: TraceResult?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                if let result {
                    if result.hasGaps { gapsCard(result) }
                    timeline(result)
                    exportRow
                } else {
                    LoadingBlock(lines: 5).padding(Spacing.l)
                }
            }
            .padding(Spacing.l)
            .padding(.bottom, Spacing.xxl)
        }
        .farmBackground()
        .navigationTitle("Traceability")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            result = TraceabilityService.trace(batch: batch, allLots: lots)
        }
    }

    private func gapsCard(_ result: TraceResult) -> some View {
        CardShell {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Label("\(result.gaps.count) gap(s) in this trail", systemImage: "exclamationmark.triangle")
                    .font(TypeScale.headline(14)).foregroundStyle(Palette.amber)
                ForEach(result.gaps, id: \.self) { gap in
                    Text("— \(gap)")
                        .font(TypeScale.body(12)).foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Gaps are shown rather than hidden, so this trail is never mistaken for a complete one.")
                    .font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func timeline(_ result: TraceResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Field → season → seed → work → harvest")
                .padding(.bottom, Spacing.m)

            ForEach(Array(result.nodes.enumerated()), id: \.element.id) { index, node in
                HStack(alignment: .top, spacing: Spacing.m) {
                    VStack(spacing: 0) {
                        ZStack {
                            Circle()
                                .fill(node.isGap ? Palette.burgundy.opacity(0.25)
                                                 : Palette.surfaceRaised)
                                .frame(width: 34, height: 34)
                            Circle()
                                .strokeBorder(node.isGap ? Palette.burgundy : Palette.gold.opacity(0.5),
                                              lineWidth: 1)
                                .frame(width: 34, height: 34)
                            Image(systemName: node.kind.icon)
                                .font(.system(size: 13))
                                .foregroundStyle(node.isGap ? Palette.burgundy : Palette.gold)
                        }
                        if index < result.nodes.count - 1 {
                            Rectangle()
                                .fill(Palette.hairline)
                                .frame(width: 1)
                                .frame(minHeight: 30)
                        }
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(node.kind.rawValue).stampLabel(
                            node.isGap ? Palette.burgundy : Palette.textTertiary)
                        Text(node.title)
                            .font(TypeScale.headline(14)).foregroundStyle(Palette.cream)
                        if let subtitle = node.subtitle {
                            Text(subtitle)
                                .font(TypeScale.body(12)).foregroundStyle(Palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !node.detailLines.isEmpty {
                            VStack(alignment: .leading, spacing: 1) {
                                ForEach(node.detailLines, id: \.self) { line in
                                    Text(line).font(.system(size: 11))
                                        .foregroundStyle(Palette.textTertiary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(.top, 2)
                        }
                    }
                    .padding(.bottom, Spacing.l)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var exportRow: some View {
        VStack(spacing: Spacing.s) {
            if let season = batch.season {
                NavigationLink {
                    ExportPreviewView(document: ExportService.seasonReport(for: season, allLots: lots))
                } label: {
                    ChipActionLabel(title: "Export season report", icon: "doc.text")
                }
                .buttonStyle(.plain)
            }
            if let field = batch.season?.field {
                NavigationLink {
                    ExportPreviewView(document: ExportService.fieldLog(for: field))
                } label: {
                    ChipActionLabel(title: "Export field log", icon: "doc.plaintext")
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Export preview

struct ExportPreviewView: View {
    var document: ExportDocument

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                CardShell {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        SectionHeader(title: "Export metadata")
                        ValueRow(label: "Generated",
                                 value: Fmt.dateTime(document.metadata.generatedAt))
                        ValueRow(label: "Data range",
                                 value: Fmt.dateRange(document.metadata.dataRangeStart,
                                                      document.metadata.dataRangeEnd))
                        ValueRow(label: "Format version", value: document.metadata.version)
                        ValueRow(label: "Gaps listed", value: "\(document.metadata.gaps.count)",
                                 tone: document.metadata.gaps.isEmpty ? Palette.positive : Palette.amber)
                    }
                }

                if let url = document.writeToTemporaryFile() {
                    ShareLink(item: url) {
                        HStack(spacing: Spacing.s) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share \(document.filename)").font(TypeScale.headline(14))
                        }
                        .foregroundStyle(Palette.graphite)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: Radius.medium)
                            .fill(Plating.amberAction))
                    }
                }

                CardShell {
                    Text(document.text)
                        .font(TypeScale.mono(11))
                        .foregroundStyle(Palette.cream)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Spacing.l)
            .padding(.bottom, Spacing.xxl)
        }
        .farmBackground()
        .navigationTitle("Export")
        .navigationBarTitleDisplayMode(.inline)
    }
}
