//
//  Theme.swift
//  GoldenAcres
//
//  Metallic gold design system. Green is reserved exclusively for
//  positive/confirmed states; burgundy carries risk and destructive intent.
//

import SwiftUI

// MARK: - Palette

enum Palette {
    static let gold = Color(hex: 0xFFD21F)
    static let amber = Color(hex: 0xFF9418)
    static let graphite = Color(hex: 0x171717)
    static let burgundy = Color(hex: 0x8F1717)
    static let cream = Color(hex: 0xFFF2D0)
    static let positive = Color(hex: 0x45A94D)

    /// Surfaces lifted above the graphite base.
    static let surface = Color(hex: 0x1F1D1A)
    static let surfaceRaised = Color(hex: 0x2A2723)
    static let hairline = Color(hex: 0x3D372E)

    static var textPrimary: Color { cream }
    static var textSecondary: Color { cream.opacity(0.68) }
    static var textTertiary: Color { cream.opacity(0.42) }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Metallic gradients

enum Plating {
    /// Full-strength struck plate, used for medallions and primary emphasis.
    static let plate = LinearGradient(
        colors: [
            Color(hex: 0xFFE86A),
            Palette.gold,
            Color(hex: 0xE0A312),
            Palette.amber
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Dark card face with a warm gold sheen — readable, still metallic.
    static let plateDark = LinearGradient(
        colors: [
            Color(hex: 0x35301F),
            Color(hex: 0x241F17),
            Color(hex: 0x1C1813)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Specular highlight running along the top edge of a plate.
    static let edgeHighlight = LinearGradient(
        colors: [
            Palette.gold.opacity(0.85),
            Palette.gold.opacity(0.18),
            Color.clear
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let amberAction = LinearGradient(
        colors: [Palette.gold, Palette.amber],
        startPoint: .top,
        endPoint: .bottom
    )

    static let screenBackground = LinearGradient(
        colors: [Color(hex: 0x1A1714), Palette.graphite, Color(hex: 0x131110)],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - Spacing / Radius / Type

enum Spacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum Radius {
    static let small: CGFloat = 10
    static let medium: CGFloat = 16
    static let large: CGFloat = 22
    static let pill: CGFloat = 999
}

enum TypeScale {
    static func display(_ size: CGFloat = 30) -> Font {
        .system(size: size, weight: .heavy, design: .serif)
    }
    static func title(_ size: CGFloat = 20) -> Font {
        .system(size: size, weight: .bold, design: .serif)
    }
    static func headline(_ size: CGFloat = 16) -> Font {
        .system(size: size, weight: .semibold)
    }
    static func body(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .regular)
    }
    static func mono(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .semibold, design: .monospaced)
    }
    /// Stamped-metal label: small, bold, wide tracking, uppercase at call site.
    static func stamp(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .bold)
    }
}

// MARK: - Shared view modifiers

extension View {
    /// Screen-level background used by every root view.
    func farmBackground() -> some View {
        self.background(Plating.screenBackground.ignoresSafeArea())
    }

    /// Wide-tracking uppercase label, like a stamped brass tag.
    func stampLabel(_ color: Color = Palette.gold) -> some View {
        self.font(TypeScale.stamp())
            .textCase(.uppercase)
            .tracking(1.3)
            .foregroundStyle(color)
    }
}
