//
//  Components.swift
//  GoldenAcres
//
//  Reusable metallic UI parts. Nothing here invents data: every component that
//  can render an absent value renders it as "Unknown", never as zero.
//

import SwiftUI

// MARK: - Gold plate card

/// A layered, embossed gold plate. The default (`raised: false`) face is dark
/// with a gold sheen so text stays readable; `raised: true` is the bright
/// struck-metal treatment for hero surfaces.
struct GoldPlate<Content: View>: View {
    var raised: Bool = false
    var accent: Color = Palette.gold
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                        .fill(raised ? AnyShapeStyle(Plating.plate) : AnyShapeStyle(Plating.plateDark))

                    // Embossed top-edge specular line.
                    RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                        .strokeBorder(Plating.edgeHighlight, lineWidth: 1)

                    RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                        .strokeBorder(accent.opacity(raised ? 0.0 : 0.22), lineWidth: 1)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .shadow(color: .black.opacity(0.55), radius: 14, x: 0, y: 8)
            .shadow(color: accent.opacity(raised ? 0.30 : 0.08), radius: 18, x: 0, y: 2)
    }
}

// MARK: - Medallion

/// Circular polished medallion used for ratio readouts. `value` is optional —
/// an unknown ratio renders an empty ring and a dash, not a zeroed ring.
struct Medallion: View {
    var value: Double?
    var caption: String
    var detail: String?
    var diameter: CGFloat = 96
    var tint: Color = Palette.gold

    private var clamped: Double? {
        guard let value else { return nil }
        return min(max(value, 0), 1)
    }

    var body: some View {
        VStack(spacing: Spacing.s) {
            ZStack {
                Circle()
                    .fill(Plating.plateDark)
                    .overlay(Circle().strokeBorder(Palette.hairline, lineWidth: 1))

                Circle()
                    .stroke(Palette.cream.opacity(0.08), lineWidth: 9)
                    .padding(8)

                if let clamped {
                    Circle()
                        .trim(from: 0, to: clamped)
                        .stroke(
                            AngularGradient(
                                colors: [tint, Palette.amber, tint],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 9, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .padding(8)
                        .shadow(color: tint.opacity(0.5), radius: 6)
                }

                VStack(spacing: 0) {
                    if let clamped {
                        Text("\(Int((clamped * 100).rounded()))%")
                            .font(TypeScale.mono(19))
                            .foregroundStyle(Palette.cream)
                    } else {
                        Text("—")
                            .font(TypeScale.mono(19))
                            .foregroundStyle(Palette.textTertiary)
                    }
                    if let detail {
                        Text(detail)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
            }
            .frame(width: diameter, height: diameter)

            Text(caption)
                .stampLabel(Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Buttons

struct AmberButton: View {
    var title: String
    var systemImage: String?
    var isBusy: Bool = false
    var isEnabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s) {
                if isBusy {
                    ProgressView()
                        .tint(Palette.graphite)
                        .scaleEffect(0.8)
                } else if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 14, weight: .bold))
                }
                Text(title)
                    .font(TypeScale.headline(15))
            }
            .foregroundStyle(Palette.graphite)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .fill(Plating.amberAction)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                            .blendMode(.plusLighter)
                    )
            }
            .shadow(color: Palette.amber.opacity(0.45), radius: 16, x: 0, y: 8)
            .shadow(color: .black.opacity(0.5), radius: 6, x: 0, y: 4)
            .opacity(isEnabled && !isBusy ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isBusy)
    }
}

struct GhostButton: View {
    var title: String
    var systemImage: String?
    var tint: Color = Palette.gold
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 13, weight: .semibold))
                }
                Text(title).font(TypeScale.headline(14))
            }
            .foregroundStyle(tint)
            .padding(.vertical, 11)
            .padding(.horizontal, Spacing.l)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .fill(Palette.surfaceRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                            .strokeBorder(tint.opacity(0.4), lineWidth: 1)
                    )
            }
        }
        .buttonStyle(.plain)
    }
}

/// Compact action used inside card headers.
struct ChipButton: View {
    var title: String
    var systemImage: String?
    var tint: Color = Palette.gold
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 11, weight: .bold))
                }
                Text(title).font(TypeScale.stamp(11)).tracking(0.6)
            }
            .foregroundStyle(tint)
            .padding(.vertical, 7)
            .padding(.horizontal, Spacing.m)
            .background(
                Capsule().fill(tint.opacity(0.12))
                    .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Status pills

enum PillTone {
    case neutral, positive, warning, risk, gold

    var color: Color {
        switch self {
        case .neutral: return Palette.textSecondary
        case .positive: return Palette.positive
        case .warning: return Palette.amber
        case .risk: return Palette.burgundy
        case .gold: return Palette.gold
        }
    }
}

struct StatusPill: View {
    var text: String
    var tone: PillTone = .neutral
    var systemImage: String?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 9, weight: .bold))
            }
            Text(text).font(TypeScale.stamp(10)).tracking(0.8).textCase(.uppercase)
        }
        .foregroundStyle(tone == .risk ? Palette.cream : tone.color)
        .padding(.vertical, 4)
        .padding(.horizontal, Spacing.s)
        .background(
            Capsule()
                .fill(tone == .risk ? Palette.burgundy.opacity(0.85) : tone.color.opacity(0.14))
                .overlay(Capsule().strokeBorder(tone.color.opacity(0.45), lineWidth: 1))
        )
    }
}

// MARK: - Provenance

/// Shows where an external value came from and when it was refreshed.
/// Stale snapshots are explicitly marked so cached data never reads as live.
struct ProvenanceBadge: View {
    var source: String
    var lastUpdated: Date?
    var isStale: Bool = false
    var onTap: (() -> Void)?

    var body: some View {
        let content = HStack(spacing: 5) {
            Image(systemName: isStale ? "clock.badge.exclamationmark" : "dot.radiowaves.up.forward")
                .font(.system(size: 9, weight: .bold))
            Text(labelText)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(isStale ? Palette.amber : Palette.textTertiary)
        .padding(.vertical, 3)
        .padding(.horizontal, Spacing.s)
        .background(
            Capsule().fill(Palette.graphite.opacity(0.6))
                .overlay(Capsule().strokeBorder(
                    (isStale ? Palette.amber : Palette.hairline).opacity(0.5), lineWidth: 1))
        )

        if let onTap {
            Button(action: onTap) { content }.buttonStyle(.plain)
        } else {
            content
        }
    }

    private var labelText: String {
        guard let lastUpdated else { return "\(source) · never updated" }
        return "\(source) · \(RelativeTime.string(from: lastUpdated))"
    }
}

enum RelativeTime {
    static func string(from date: Date, now: Date = Date()) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: now)
    }
}

// MARK: - Value rows (unknown-aware)

/// A label/value row. A nil value renders as "Unknown", tappable to fill in.
struct ValueRow: View {
    var label: String
    var value: String?
    var unit: String?
    var tone: Color = Palette.cream
    var unknownHint: String = "Unknown"
    var onFill: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(TypeScale.body(13))
                .foregroundStyle(Palette.textSecondary)
            Spacer(minLength: Spacing.m)
            if let value {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value).font(TypeScale.mono(14)).foregroundStyle(tone)
                    if let unit {
                        Text(unit).font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
            } else if let onFill {
                Button(action: onFill) {
                    HStack(spacing: 3) {
                        Text(unknownHint).font(TypeScale.body(12))
                        Image(systemName: "plus.circle.fill").font(.system(size: 10))
                    }
                    .foregroundStyle(Palette.amber)
                }
                .buttonStyle(.plain)
            } else {
                Text(unknownHint)
                    .font(TypeScale.body(12))
                    .foregroundStyle(Palette.textTertiary)
                    .italic()
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Section header

struct SectionHeader: View {
    var title: String
    var subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).stampLabel()
                if let subtitle {
                    Text(subtitle)
                        .font(TypeScale.body(12))
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            Spacer()
            if let actionTitle, let action {
                ChipButton(title: actionTitle, action: action)
            }
        }
    }
}

// MARK: - Honest states

/// Empty state that explains the situation and offers the single next action.
struct HonestEmptyState: View {
    var icon: String
    var title: String
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?
    var secondaryTitle: String?
    var secondaryAction: (() -> Void)?

    var body: some View {
        VStack(spacing: Spacing.m) {
            ZStack {
                Circle().fill(Palette.surfaceRaised).frame(width: 74, height: 74)
                Circle().strokeBorder(Palette.gold.opacity(0.3), lineWidth: 1).frame(width: 74, height: 74)
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Palette.gold)
            }
            Text(title)
                .font(TypeScale.title(18))
                .foregroundStyle(Palette.cream)
                .multilineTextAlignment(.center)
            Text(message)
                .font(TypeScale.body(14))
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                AmberButton(title: actionTitle, systemImage: "plus", action: action)
                    .padding(.top, Spacing.xs)
                    .frame(maxWidth: 280)
            }
            if let secondaryTitle, let secondaryAction {
                Button(secondaryTitle, action: secondaryAction)
                    .font(TypeScale.body(13))
                    .foregroundStyle(Palette.gold)
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity)
    }
}

/// Skeleton loader. Deliberately renders placeholder bars — never duplicates
/// real rows — so a loading screen can't be mistaken for content.
struct LoadingBlock: View {
    var lines: Int = 3
    @State private var shimmer = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            ForEach(0..<lines, id: \.self) { i in
                RoundedRectangle(cornerRadius: 6)
                    .fill(Palette.surfaceRaised)
                    .frame(height: 14)
                    .frame(maxWidth: i == lines - 1 ? 160 : .infinity, alignment: .leading)
                    .opacity(shimmer ? 0.45 : 0.9)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                shimmer = true
            }
        }
        .accessibilityLabel("Loading")
    }
}

/// Error state that always offers Retry and never discards entered form data.
struct ErrorBanner: View {
    var title: String
    var message: String
    var retryTitle: String = "Retry"
    var onRetry: (() -> Void)?
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Palette.cream)
                .font(.system(size: 16))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(TypeScale.headline(14)).foregroundStyle(Palette.cream)
                Text(message)
                    .font(TypeScale.body(13))
                    .foregroundStyle(Palette.cream.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Spacing.l) {
                    if let onRetry {
                        Button(retryTitle, action: onRetry)
                            .font(TypeScale.headline(13))
                            .foregroundStyle(Palette.gold)
                    }
                    if let onDismiss {
                        Button("Dismiss", action: onDismiss)
                            .font(TypeScale.body(13))
                            .foregroundStyle(Palette.cream.opacity(0.7))
                    }
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .fill(Palette.burgundy.opacity(0.9))
                .overlay(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .strokeBorder(Palette.burgundy, lineWidth: 1))
        )
    }
}

/// Offline / cached notice with the snapshot time always visible.
struct CachedNotice: View {
    var source: String
    var capturedAt: Date?

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "wifi.slash").font(.system(size: 12, weight: .semibold))
            VStack(alignment: .leading, spacing: 1) {
                Text("Offline — showing local snapshot")
                    .font(TypeScale.headline(12))
                if let capturedAt {
                    Text("\(source) · captured \(capturedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.cream.opacity(0.7))
                } else {
                    Text("\(source) · no snapshot stored yet")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.cream.opacity(0.7))
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Palette.amber)
        .padding(.vertical, Spacing.s)
        .padding(.horizontal, Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                .fill(Palette.amber.opacity(0.1))
                .overlay(RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .strokeBorder(Palette.amber.opacity(0.35), lineWidth: 1))
        )
    }
}

/// Transient success confirmation stating exactly what changed.
struct SuccessToast: View {
    var message: String
    var detail: String?

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(Palette.positive)
            VStack(alignment: .leading, spacing: 1) {
                Text(message).font(TypeScale.headline(13)).foregroundStyle(Palette.cream)
                if let detail {
                    Text(detail).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .fill(Palette.surfaceRaised)
                .overlay(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .strokeBorder(Palette.positive.opacity(0.5), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
    }
}

// MARK: - Form building blocks

struct FieldLabel: View {
    var text: String
    var isRequired: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            Text(text).stampLabel(Palette.textSecondary)
            if isRequired {
                Text("*").font(TypeScale.stamp()).foregroundStyle(Palette.amber)
            }
        }
    }
}

/// Text input with inline, adjacent validation messaging.
struct PlateTextField: View {
    var label: String
    var placeholder: String
    @Binding var text: String
    var isRequired: Bool = false
    var keyboard: UIKeyboardType = .default
    var error: String?
    var helper: String?
    var axis: Axis = .horizontal

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            FieldLabel(text: label, isRequired: isRequired)
            TextField(placeholder, text: $text, axis: axis)
                .font(TypeScale.body(15))
                .foregroundStyle(Palette.cream)
                .keyboardType(keyboard)
                .padding(.vertical, 11)
                .padding(.horizontal, Spacing.m)
                .background(
                    RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                        .fill(Palette.graphite.opacity(0.7))
                        .overlay(RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                            .strokeBorder(error == nil ? Palette.hairline : Palette.burgundy,
                                          lineWidth: error == nil ? 1 : 1.5))
                )
            if let error {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.burgundy)
            } else if let helper {
                Text(helper).font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
            }
        }
    }
}

/// Wraps arbitrary controls with the same label/error treatment.
struct PlateField<Content: View>: View {
    var label: String
    var isRequired: Bool = false
    var error: String?
    var helper: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            FieldLabel(text: label, isRequired: isRequired)
            content
                .padding(.vertical, 8)
                .padding(.horizontal, Spacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                        .fill(Palette.graphite.opacity(0.7))
                        .overlay(RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                            .strokeBorder(error == nil ? Palette.hairline : Palette.burgundy,
                                          lineWidth: error == nil ? 1 : 1.5))
                )
            if let error {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.burgundy)
            } else if let helper {
                Text(helper).font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
            }
        }
    }
}

// MARK: - Calculation disclosure

/// Renders a computed figure together with its inputs, units and assumptions.
struct CalculationDisclosure: View {
    var title: String
    var result: String?
    var resultUnit: String?
    var steps: [CalculationStep]
    var assumptions: [String]
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).stampLabel(Palette.textSecondary)
                Spacer()
                if let result {
                    Text(result).font(TypeScale.mono(17)).foregroundStyle(Palette.gold)
                    if let resultUnit {
                        Text(resultUnit).font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                    }
                } else {
                    Text("Cannot compute").font(TypeScale.body(13)).foregroundStyle(Palette.amber)
                }
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                    Text(expanded ? "Hide calculation" : "Show calculation, units and assumptions")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Palette.gold)
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    ForEach(steps) { step in
                        HStack(alignment: .top, spacing: Spacing.s) {
                            Text("•").foregroundStyle(Palette.gold.opacity(0.7))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(step.label)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Palette.textSecondary)
                                Text(step.expression)
                                    .font(TypeScale.mono(12))
                                    .foregroundStyle(step.isMissing ? Palette.amber : Palette.cream)
                                if let note = step.note {
                                    Text(note).font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                                }
                            }
                        }
                    }
                    if !assumptions.isEmpty {
                        Divider().overlay(Palette.hairline)
                        Text("Assumptions").stampLabel(Palette.amber)
                        ForEach(assumptions, id: \.self) { a in
                            Text("— \(a)")
                                .font(.system(size: 11))
                                .foregroundStyle(Palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(Spacing.m)
                .background(
                    RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                        .fill(Palette.graphite.opacity(0.55))
                )
            }
        }
    }
}

struct CalculationStep: Identifiable {
    let id = UUID()
    var label: String
    var expression: String
    var note: String? = nil
    var isMissing: Bool = false
}

// MARK: - Destructive confirmation

/// Lists the consequences of a delete and offers safer alternatives.
struct ConsequenceSheet: View {
    var title: String
    var entityName: String
    var consequences: [String]
    var canDelete: Bool
    var deleteBlockedReason: String?
    var onArchive: (() -> Void)?
    var onDetach: (() -> Void)?
    var onDelete: (() -> Void)?
    var onCancel: () -> Void

    @State private var typedConfirmation = ""

    private var confirmationMatches: Bool {
        typedConfirmation.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(entityName) == .orderedSame
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                Text(title).font(TypeScale.title(20)).foregroundStyle(Palette.cream)

                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("What this affects").stampLabel(Palette.amber)
                    if consequences.isEmpty {
                        Text("No other records reference this item.")
                            .font(TypeScale.body(13))
                            .foregroundStyle(Palette.textSecondary)
                    } else {
                        ForEach(consequences, id: \.self) { c in
                            HStack(alignment: .top, spacing: Spacing.s) {
                                Image(systemName: "link").font(.system(size: 10))
                                    .foregroundStyle(Palette.amber)
                                    .padding(.top, 3)
                                Text(c).font(TypeScale.body(13)).foregroundStyle(Palette.cream)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(Spacing.m)
                .background(RoundedRectangle(cornerRadius: Radius.medium)
                    .fill(Palette.surfaceRaised))

                VStack(spacing: Spacing.s) {
                    if let onArchive {
                        GhostButton(title: "Archive instead (keeps history)",
                                    systemImage: "archivebox", action: onArchive)
                    }
                    if let onDetach {
                        GhostButton(title: "Unlink related records only",
                                    systemImage: "link.badge.plus", action: onDetach)
                    }
                }

                if let reason = deleteBlockedReason {
                    ErrorBanner(title: "Delete not available", message: reason, onRetry: nil, onDismiss: nil)
                } else if canDelete, let onDelete {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Text("Permanent delete").stampLabel(Palette.burgundy)
                        Text("Type “\(entityName)” to confirm. This cannot be undone.")
                            .font(TypeScale.body(12)).foregroundStyle(Palette.textSecondary)
                        TextField("", text: $typedConfirmation)
                            .font(TypeScale.mono(14))
                            .foregroundStyle(Palette.cream)
                            .padding(.vertical, 10).padding(.horizontal, Spacing.m)
                            .background(RoundedRectangle(cornerRadius: Radius.small)
                                .fill(Palette.graphite)
                                .overlay(RoundedRectangle(cornerRadius: Radius.small)
                                    .strokeBorder(Palette.burgundy.opacity(0.6), lineWidth: 1)))
                        Button(action: onDelete) {
                            Text("Delete permanently")
                                .font(TypeScale.headline(14))
                                .foregroundStyle(Palette.cream)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(RoundedRectangle(cornerRadius: Radius.medium)
                                    .fill(Palette.burgundy))
                                .opacity(confirmationMatches ? 1 : 0.4)
                        }
                        .buttonStyle(.plain)
                        .disabled(!confirmationMatches)
                    }
                }

                Button("Cancel", action: onCancel)
                    .font(TypeScale.headline(14))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.s)
            }
            .padding(Spacing.l)
        }
        .farmBackground()
    }
}

// MARK: - Small helpers

struct KeyStat: View {
    var value: String?
    var unit: String?
    var label: String
    var tone: Color = Palette.gold

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value ?? "—")
                    .font(TypeScale.mono(20))
                    .foregroundStyle(value == nil ? Palette.textTertiary : tone)
                if let unit, value != nil {
                    Text(unit).font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            Text(label).stampLabel(Palette.textSecondary)
        }
    }
}

/// Row that navigates to the underlying records behind a figure.
struct DrillRow<Destination: View>: View {
    var title: String
    var subtitle: String?
    var trailing: String?
    var tone: Color = Palette.cream
    @ViewBuilder var destination: Destination

    var body: some View {
        NavigationLink {
            destination
        } label: {
            HStack(spacing: Spacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(TypeScale.headline(14)).foregroundStyle(tone)
                    if let subtitle {
                        Text(subtitle).font(TypeScale.body(12)).foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: Spacing.s)
                if let trailing {
                    Text(trailing).font(TypeScale.mono(13)).foregroundStyle(Palette.gold)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.textTertiary)
            }
            .padding(.vertical, Spacing.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
