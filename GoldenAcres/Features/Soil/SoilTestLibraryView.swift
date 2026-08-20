//
//  SoilTestLibraryView.swift
//  GoldenAcres
//
//  Screen 6. An uploaded report becomes a draft with per-value confidence and
//  page location. Only confirmed values enter comparisons, and values in
//  different units are never combined.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SoilTestLibraryView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appState: AppState
    var field: FarmField

    @State private var showEditor = false
    @State private var showImporter = false
    @State private var parsingTest: SoilTest?
    @State private var compareSelection: Set<UUID> = []
    @State private var showComparison = false
    @State private var importError: String?

    private var tests: [SoilTest] {
        field.soilTests.sorted { $0.sampleDate > $1.sampleDate }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                if let importError {
                    ErrorBanner(title: "Could not read file", message: importError,
                                onRetry: nil, onDismiss: { self.importError = nil })
                }

                if tests.isEmpty {
                    HonestEmptyState(
                        icon: "testtube.2",
                        title: "No soil tests yet",
                        message: "Upload a lab report or enter values by hand. Parsed values arrive as a draft you confirm — nothing goes into comparisons until you do.",
                        actionTitle: "Add manually",
                        action: { showEditor = true },
                        secondaryTitle: "Upload a report",
                        secondaryAction: { showImporter = true }
                    )
                    .padding(.top, Spacing.xl)
                } else {
                    HStack(spacing: Spacing.s) {
                        ChipButton(title: "Upload report", systemImage: "doc.badge.plus") {
                            showImporter = true
                        }
                        ChipButton(title: "Add manually", systemImage: "plus") { showEditor = true }
                        if compareSelection.count >= 2 {
                            ChipButton(title: "Compare \(compareSelection.count)",
                                       systemImage: "arrow.left.arrow.right") {
                                showComparison = true
                            }
                        }
                    }

                    ForEach(tests) { test in
                        SoilTestCard(
                            test: test,
                            isSelected: compareSelection.contains(test.id),
                            onToggleCompare: {
                                if compareSelection.contains(test.id) {
                                    compareSelection.remove(test.id)
                                } else {
                                    compareSelection.insert(test.id)
                                }
                            }
                        )
                    }
                }
            }
            .padding(Spacing.l)
            .padding(.bottom, Spacing.xxl)
        }
        .farmBackground()
        .navigationTitle("Soil tests")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showEditor = true } label: {
                    Image(systemName: "plus").foregroundStyle(Palette.gold)
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            SoilTestEditorView(field: field, test: nil, parseResult: nil)
        }
        .sheet(item: $parsingTest) { test in
            SoilTestEditorView(field: field, test: test, parseResult: nil)
        }
        .sheet(isPresented: $showComparison) {
            SoilComparisonView(tests: tests.filter { compareSelection.contains($0.id) })
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.pdf, .image],
                      allowsMultipleSelection: false) { result in
            handleImport(result)
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

            guard let data = try? Data(contentsOf: url) else {
                importError = "The file could not be opened."
                return
            }
            let ext = url.pathExtension.isEmpty ? "pdf" : url.pathExtension
            guard let storedName = PhotoStore.saveFile(data: data, extension: ext) else {
                importError = "The file could not be saved locally."
                return
            }

            // The file is kept regardless of whether parsing succeeds.
            let test = SoilTest(sampleDate: Date(), field: field)
            test.originalFileName = storedName
            context.insert(test)
            field.soilTests.append(test)
            try? context.save()

            Task {
                let parsed = await SoilReportParser.parse(fileURL: PhotoStore.url(for: storedName))
                await MainActor.run {
                    test.parsedSuggestions = parsed.suggestions
                    test.parseProvenance = parsed.provenance
                    test.parseFailedReason = parsed.failureReason
                    try? context.save()
                    parsingTest = test
                    appState.confirm(
                        parsed.isUsable ? "Report read — review the draft" : "File saved",
                        detail: parsed.isUsable
                            ? "\(parsed.suggestions.count) value(s) found, none confirmed yet"
                            : parsed.failureReason
                    )
                }
            }
        }
    }
}

// MARK: - Card

struct SoilTestCard: View {
    var test: SoilTest
    var isSelected: Bool
    var onToggleCompare: () -> Void

    var body: some View {
        NavigationLink { SoilTestDetailView(test: test) } label: {
            GoldPlate(accent: test.isConfirmed ? Palette.positive : Palette.amber) {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(test.laboratory ?? "Laboratory not recorded")
                                .font(TypeScale.headline(15)).foregroundStyle(Palette.cream)
                            Text("Sampled \(Fmt.date(test.sampleDate) ?? "")")
                                .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                        }
                        Spacer()
                        StatusPill(text: test.isConfirmed ? "confirmed" : "draft",
                                   tone: test.isConfirmed ? .positive : .warning)
                    }

                    HStack(spacing: Spacing.l) {
                        ValueColumn(label: "pH", value: Fmt.number(test.ph, decimals: 1), unit: nil)
                        ValueColumn(label: "Organic matter",
                                    value: Fmt.number(test.organicMatterPercent, decimals: 1), unit: "%")
                        ValueColumn(label: "Values", value: "\(test.recordedValueCount)", unit: nil)
                    }

                    if !test.isConfirmed {
                        Text("Draft — excluded from every comparison until confirmed.")
                            .font(.system(size: 11)).foregroundStyle(Palette.amber)
                    }
                    if !test.valuesMissingUnits.isEmpty {
                        Label("Missing units: \(test.valuesMissingUnits.joined(separator: ", "))",
                              systemImage: "exclamationmark.triangle")
                            .font(.system(size: 11)).foregroundStyle(Palette.amber)
                    }

                    if test.isConfirmed {
                        Button(action: onToggleCompare) {
                            HStack(spacing: 4) {
                                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                Text("Compare").font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(isSelected ? Palette.gold : Palette.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Spacing.l)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Detail

struct SoilTestDetailView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appState: AppState
    var test: SoilTest

    @State private var showEditor = false
    @State private var showDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                if !test.isConfirmed {
                    CardShell {
                        VStack(alignment: .leading, spacing: Spacing.s) {
                            Label("Draft", systemImage: "exclamationmark.circle")
                                .font(TypeScale.headline(14)).foregroundStyle(Palette.amber)
                            Text(test.parseFailedReason
                                 ?? "Review each value against the original report, then confirm. Draft values never appear in comparisons or season reviews.")
                                .font(TypeScale.body(12)).foregroundStyle(Palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            AmberButton(title: "Review and confirm", systemImage: "checkmark.seal") {
                                showEditor = true
                            }
                        }
                    }
                }

                CardShell {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        SectionHeader(title: "Sample")
                        ValueRow(label: "Laboratory", value: test.laboratory)
                        ValueRow(label: "Sample date", value: Fmt.date(test.sampleDate))
                        ValueRow(label: "Zone", value: test.zone)
                        ValueRow(label: "Depth", value: Fmt.number(test.depthValue, decimals: 1),
                                 unit: test.depthUnit.symbol)
                        ValueRow(label: "Field",
                                 value: test.field?.name
                                    ?? (test.fieldNameSnapshot.isEmpty ? nil : "\(test.fieldNameSnapshot) (detached)"))
                    }
                }

                CardShell {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        SectionHeader(title: "Results")
                        ValueRow(label: "pH", value: Fmt.number(test.ph, decimals: 2))
                        ValueRow(label: "Organic matter",
                                 value: Fmt.number(test.organicMatterPercent, decimals: 2), unit: "%")
                        ValueRow(label: "Nitrogen", value: Fmt.number(test.nitrogenValue, decimals: 2),
                                 unit: test.nitrogenUnit?.symbol ?? "unit missing")
                        ValueRow(label: "Phosphorus", value: Fmt.number(test.phosphorusValue, decimals: 2),
                                 unit: test.phosphorusUnit?.symbol ?? "unit missing")
                        ValueRow(label: "Potassium", value: Fmt.number(test.potassiumValue, decimals: 2),
                                 unit: test.potassiumUnit?.symbol ?? "unit missing")
                        ValueRow(label: "Salinity", value: Fmt.number(test.salinityValue, decimals: 2),
                                 unit: test.salinityUnit?.symbol ?? "unit missing")
                        ForEach(test.micronutrients) { nutrient in
                            ValueRow(label: nutrient.name,
                                     value: Fmt.number(nutrient.value, decimals: 2),
                                     unit: nutrient.unit?.symbol ?? "unit missing")
                        }
                    }
                }

                if !test.parsedSuggestions.isEmpty {
                    CardShell {
                        VStack(alignment: .leading, spacing: Spacing.s) {
                            SectionHeader(title: "Extracted from the file")
                            if let provenance = test.parseProvenance {
                                ProvenanceBadge(source: provenance.source,
                                                lastUpdated: provenance.retrievedAt)
                            }
                            ForEach(test.parsedSuggestions) { suggestion in
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(suggestion.fieldKey)
                                            .font(TypeScale.body(13)).foregroundStyle(Palette.cream)
                                        Text("“\(suggestion.rawText)” · \(suggestion.sourceLocation ?? "location unknown")")
                                            .font(.system(size: 10))
                                            .foregroundStyle(Palette.textTertiary)
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 1) {
                                        Text("\(Fmt.number(suggestion.numericValue, decimals: 2) ?? "—") \(suggestion.unitText ?? "")")
                                            .font(TypeScale.mono(12)).foregroundStyle(Palette.gold)
                                        Text("\(Int(suggestion.confidence * 100))% confidence")
                                            .font(.system(size: 9)).foregroundStyle(Palette.textTertiary)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }

                if let file = test.originalFileName {
                    CardShell {
                        HStack {
                            Image(systemName: "doc.text").foregroundStyle(Palette.gold)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Original file kept")
                                    .font(TypeScale.body(13)).foregroundStyle(Palette.cream)
                                Text(PhotoStore.exists(file) ? file : "\(file) — file missing on device")
                                    .font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                    }
                }
            }
            .padding(Spacing.l)
        }
        .farmBackground()
        .navigationTitle("Soil test")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showEditor = true } label: { Label("Edit", systemImage: "pencil") }
                    Button(role: .destructive) { showDelete = true } label: {
                        Label("Delete…", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundStyle(Palette.gold)
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            if let field = test.field {
                SoilTestEditorView(field: field, test: test, parseResult: nil)
            }
        }
        .sheet(isPresented: $showDelete) {
            ConsequenceSheet(
                title: "Delete this soil test?",
                entityName: "soil test",
                consequences: [
                    test.isConfirmed
                        ? "It will be removed from any comparison that used it."
                        : "It is a draft, so nothing downstream depends on it.",
                    test.originalFileName != nil
                        ? "The stored original file will be deleted from the device."
                        : "No file is attached."
                ],
                canDelete: true,
                deleteBlockedReason: nil,
                onArchive: nil,
                onDetach: nil,
                onDelete: {
                    if let file = test.originalFileName { PhotoStore.delete(file) }
                    AuditService.log(action: "Deleted", entityType: "Soil test", entityID: test.id,
                                     summary: "Soil test deleted", context: context)
                    test.field?.soilTests.removeAll { $0.id == test.id }
                    context.delete(test)
                    try? context.save()
                    showDelete = false
                    appState.confirm("Soil test deleted")
                },
                onCancel: { showDelete = false }
            )
        }
    }
}

// MARK: - Comparison

struct SoilComparisonView: View {
    @Environment(\.dismiss) private var dismiss
    var tests: [SoilTest]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    let blockers = comparisonBlockers()
                    if !blockers.isEmpty {
                        CardShell {
                            VStack(alignment: .leading, spacing: Spacing.s) {
                                Label("Some values cannot be compared", systemImage: "exclamationmark.triangle")
                                    .font(TypeScale.headline(14)).foregroundStyle(Palette.amber)
                                ForEach(blockers, id: \.self) { blocker in
                                    Text("— \(blocker)").font(.system(size: 12))
                                        .foregroundStyle(Palette.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }

                    CardShell {
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            ForEach(rows(), id: \.label) { row in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(row.label).stampLabel(Palette.textSecondary)
                                    HStack(spacing: Spacing.l) {
                                        ForEach(Array(row.values.enumerated()), id: \.offset) { _, value in
                                            Text(value ?? "—")
                                                .font(TypeScale.mono(13))
                                                .foregroundStyle(value == nil ? Palette.textTertiary : Palette.cream)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                }
                                Divider().overlay(Palette.hairline)
                            }
                        }
                    }
                }
                .padding(Spacing.l)
            }
            .farmBackground()
            .navigationTitle("Compare tests")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(Palette.gold)
                }
            }
        }
    }

    private struct Row { var label: String; var values: [String?] }

    private func rows() -> [Row] {
        var out: [Row] = []
        out.append(Row(label: "Sample date", values: tests.map { Fmt.date($0.sampleDate) }))
        out.append(Row(label: "Laboratory", values: tests.map { $0.laboratory }))
        out.append(Row(label: "pH", values: tests.map { Fmt.number($0.ph, decimals: 2) }))
        out.append(Row(label: "Organic matter %",
                       values: tests.map { Fmt.number($0.organicMatterPercent, decimals: 2) }))

        // Nutrients are only shown side by side when the units agree.
        out.append(nutrientRow("Nitrogen", { $0.nitrogenValue }, { $0.nitrogenUnit }))
        out.append(nutrientRow("Phosphorus", { $0.phosphorusValue }, { $0.phosphorusUnit }))
        out.append(nutrientRow("Potassium", { $0.potassiumValue }, { $0.potassiumUnit }))
        out.append(nutrientRow("Salinity", { $0.salinityValue }, { $0.salinityUnit }))
        return out
    }

    private func nutrientRow(_ label: String,
                             _ value: (SoilTest) -> Double?,
                             _ unit: (SoilTest) -> ConcentrationUnit?) -> Row {
        let units = tests.compactMap(unit)
        let comparable = units.count == tests.count
            && units.allSatisfy { $0.isComparable(with: units[0]) }
        if !comparable {
            return Row(label: "\(label) (units differ — not compared)",
                       values: tests.map { test in
                           guard let v = value(test) else { return nil }
                           return "\(Fmt.number(v, decimals: 2) ?? "") \(unit(test)?.symbol ?? "?")"
                       })
        }
        return Row(label: "\(label) (\(units[0].symbol))",
                   values: tests.map { Fmt.number(value($0), decimals: 2) })
    }

    private func comparisonBlockers() -> [String] {
        var out: [String] = []
        func check(_ label: String, _ unit: (SoilTest) -> ConcentrationUnit?, _ value: (SoilTest) -> Double?) {
            let withValues = tests.filter { value($0) != nil }
            guard !withValues.isEmpty else { return }
            let units = withValues.compactMap(unit)
            if units.count < withValues.count {
                out.append("\(label): at least one value has no unit, so it cannot be compared numerically.")
            } else if let first = units.first, !units.allSatisfy({ $0.isComparable(with: first) }) {
                let names = Set(units.map(\.symbol)).sorted().joined(separator: ", ")
                out.append("\(label): values use \(names), which are not interchangeable without lab context.")
            }
        }
        check("Nitrogen", { $0.nitrogenUnit }, { $0.nitrogenValue })
        check("Phosphorus", { $0.phosphorusUnit }, { $0.phosphorusValue })
        check("Potassium", { $0.potassiumUnit }, { $0.potassiumValue })
        check("Salinity", { $0.salinityUnit }, { $0.salinityValue })
        return out
    }
}
