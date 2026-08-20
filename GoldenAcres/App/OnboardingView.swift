//
//  OnboardingView.swift
//  GoldenAcres
//
//  Four screens: the problem, how the sections connect, how external data is
//  labelled, and the creation of the user's first real field. No demo data is
//  seeded at any point.
//

import SwiftUI
import SwiftData

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var context
    @Query private var farms: [Farm]

    @State private var page = 0

    var body: some View {
        ZStack {
            Plating.screenBackground.ignoresSafeArea()
            GoldDustBackdrop()

            VStack(spacing: 0) {
                header

                TabView(selection: $page) {
                    OnboardingPanel(
                        icon: "square.grid.3x3.topleft.filled",
                        title: "Connect Every Field and Season",
                        message: "Field notes usually live in three places at once — a notebook, a phone gallery, and memory. GoldenAcres keeps fields, seasons, observations and harvests as one linked record.",
                        points: [
                            "A field holds its seasons; a season holds its work.",
                            "Nothing is filled in for you — the app starts empty.",
                            "Every figure can be opened back to the entry it came from."
                        ]
                    ).tag(0)

                    OnboardingPanel(
                        icon: "arrow.triangle.branch",
                        title: "Plan Work Around Real Conditions",
                        message: "You set the thresholds for each job. The app checks them against the forecast and shows which hours pass, which fail, and exactly why.",
                        points: [
                            "A work window is a planning hint, not a guarantee.",
                            "If the forecast changes, tasks are flagged for review — never moved silently.",
                            "Beyond the forecast horizon it says so instead of guessing."
                        ]
                    ).tag(1)

                    OnboardingPanel(
                        icon: "shippingbox.and.arrow.backward",
                        title: "Keep Inputs and Harvests Traceable",
                        message: "A confirmed application deducts a specific stock lot. A harvest creates a batch. Traceability walks the whole path back from a batch to the field and seed it came from.",
                        points: [
                            "Applications are immutable; corrections are recorded as revisions.",
                            "Unknown values stay Unknown — they are never counted as zero.",
                            "Reports list their gaps instead of looking complete."
                        ]
                    ).tag(2)

                    FirstFieldPanel(onCreated: finish).tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                footer
            }
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: Spacing.s) {
                WheatMark(size: 22)
                Text("GoldenAcres")
                    .font(TypeScale.title(17))
                    .foregroundStyle(Palette.cream)
            }
            Spacer()
            if page < 3 {
                Button("Skip intro") { withAnimation { page = 3 } }
                    .font(TypeScale.body(13))
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.top, Spacing.s)
    }

    private var footer: some View {
        VStack(spacing: Spacing.m) {
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? Palette.gold : Palette.cream.opacity(0.2))
                        .frame(width: index == page ? 22 : 7, height: 7)
                        .animation(.spring(response: 0.3), value: page)
                }
            }

            if page < 3 {
                AmberButton(title: page == 2 ? "Add your first field" : "Continue",
                            systemImage: "arrow.right") {
                    withAnimation { page += 1 }
                }
                .padding(.horizontal, Spacing.l)
            }
        }
        .padding(.bottom, Spacing.l)
    }

    private func finish() {
        appState.hasCompletedOnboarding = true
    }
}

// MARK: - Panels

private struct OnboardingPanel: View {
    var icon: String
    var title: String
    var message: String
    var points: [String]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                ZStack {
                    Circle()
                        .fill(Plating.plate)
                        .frame(width: 92, height: 92)
                        .shadow(color: Palette.amber.opacity(0.45), radius: 22, y: 8)
                    Image(systemName: icon)
                        .font(.system(size: 38, weight: .light))
                        .foregroundStyle(Palette.graphite)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, Spacing.xl)

                Text(title)
                    .font(TypeScale.display(28))
                    .foregroundStyle(Palette.cream)
                    .fixedSize(horizontal: false, vertical: true)

                Text(message)
                    .font(TypeScale.body(16))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: Spacing.m) {
                    ForEach(points, id: \.self) { point in
                        HStack(alignment: .top, spacing: Spacing.m) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(Palette.gold)
                                .padding(.top, 2)
                            Text(point)
                                .font(TypeScale.body(14))
                                .foregroundStyle(Palette.cream.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(Spacing.l)
                .background {
                    RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                        .fill(Plating.plateDark)
                        .overlay(RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                            .strokeBorder(Palette.gold.opacity(0.2), lineWidth: 1))
                }
            }
            .padding(.horizontal, Spacing.l)
            .padding(.bottom, Spacing.xl)
        }
    }
}

/// Step 4 creates a real farm and a real field — the app's first records.
private struct FirstFieldPanel: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appState: AppState
    @Query private var farms: [Farm]

    var onCreated: () -> Void

    @State private var farmName = ""
    @State private var fieldName = ""
    @State private var areaText = ""
    @State private var areaUnit: AreaUnit = .hectare
    @State private var unitSystem: UnitSystem = .metric
    @State private var errors: [String: String] = [:]
    @State private var isSaving = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                Text("Add Your First Field")
                    .font(TypeScale.display(28))
                    .foregroundStyle(Palette.cream)
                    .padding(.top, Spacing.xl)

                Text("This creates real records, not an example. You can rename or archive anything later.")
                    .font(TypeScale.body(15))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: Spacing.m) {
                    PlateTextField(label: "Farm name", placeholder: "e.g. Hillside Holding",
                                   text: $farmName, isRequired: true,
                                   error: errors["farm"])

                    PlateTextField(label: "Field name", placeholder: "e.g. North Paddock",
                                   text: $fieldName, isRequired: true,
                                   error: errors["field"])

                    HStack(alignment: .top, spacing: Spacing.m) {
                        PlateTextField(label: "Area", placeholder: "0.00", text: $areaText,
                                       isRequired: true, keyboard: .decimalPad,
                                       error: errors["area"])
                        PlateField(label: "Unit", isRequired: true) {
                            Picker("", selection: $areaUnit) {
                                ForEach(AreaUnit.allCases) { unit in
                                    Text(unit.symbol).tag(unit)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(Palette.gold)
                        }
                        .frame(width: 110)
                    }

                    PlateField(label: "Measurement system",
                               helper: "Used as the default for new records. Every value still shows its own unit.") {
                        Picker("", selection: $unitSystem) {
                            ForEach(UnitSystem.allCases) { system in
                                Text(system.label).tag(system)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .padding(Spacing.l)
                .background {
                    RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                        .fill(Plating.plateDark)
                        .overlay(RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                            .strokeBorder(Palette.gold.opacity(0.2), lineWidth: 1))
                }

                AmberButton(title: "Create farm and field",
                            systemImage: "checkmark", isBusy: isSaving) {
                    save()
                }

                Text("Prefer to look around first? You can create the farm later from the Farm tab.")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textTertiary)

                Button("Continue without creating anything") {
                    onCreated()
                }
                .font(TypeScale.body(14))
                .foregroundStyle(Palette.gold)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Spacing.l)
            .padding(.bottom, Spacing.xxl)
        }
    }

    private func save() {
        guard !isSaving else { return }
        errors = [:]

        if farmName.trimmingCharacters(in: .whitespaces).isEmpty {
            errors["farm"] = "Enter a farm name."
        }
        if fieldName.trimmingCharacters(in: .whitespaces).isEmpty {
            errors["field"] = "Enter a field name."
        }
        let normalized = areaText.replacingOccurrences(of: ",", with: ".")
        guard let area = Double(normalized), area > 0 else {
            errors["area"] = areaText.isEmpty ? "Enter the field area." : "Enter a number greater than zero."
            return
        }
        guard errors.isEmpty else { return }

        isSaving = true

        let farm = Farm(name: farmName.trimmingCharacters(in: .whitespaces),
                        unitSystem: unitSystem)
        let field = FarmField(name: fieldName.trimmingCharacters(in: .whitespaces),
                              areaValue: area, areaUnit: areaUnit)
        field.farm = farm
        farm.fields.append(field)

        context.insert(farm)
        context.insert(field)

        AuditService.log(action: "Created", entityType: "Farm", entityID: farm.id,
                         summary: "Farm “\(farm.name)” created during onboarding", context: context)
        AuditService.log(action: "Created", entityType: "Field", entityID: field.id,
                         summary: "Field “\(field.name)” created with area \(Fmt.quantity(area, areaUnit.symbol) ?? "")",
                         context: context)

        do {
            try context.save()
            appState.confirm("Farm and field created",
                             detail: "\(field.name) · \(Fmt.quantity(area, areaUnit.symbol) ?? "")")
            isSaving = false
            onCreated()
        } catch {
            isSaving = false
            errors["farm"] = "Could not save: \(error.localizedDescription)"
        }
    }
}

// MARK: - Decorative

/// Faint metallic flecks. Purely decorative and never conveys information.
struct GoldDustBackdrop: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<18, id: \.self) { index in
                    let seed = Double(index)
                    let x = (sin(seed * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1)
                    let y = (sin(seed * 78.233) * 43758.5453).truncatingRemainder(dividingBy: 1)
                    Circle()
                        .fill(Palette.gold.opacity(0.06))
                        .frame(width: 3 + abs(x) * 6, height: 3 + abs(x) * 6)
                        .position(x: abs(x) * geo.size.width,
                                  y: abs(y) * geo.size.height)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Small wheat-ear mark used as the app's glyph.
struct WheatMark: View {
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: "laurel.leading")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(Plating.plate)
            .overlay(
                Image(systemName: "laurel.trailing")
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(Plating.plate)
            )
    }
}
