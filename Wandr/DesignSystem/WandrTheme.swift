//
//  WandrTheme.swift
//  Wandr
//
//  The palette, type ramp, and motion vocabulary for the whole app.
//  Content layer carries the brand; the UI layer stays native.
//

import SwiftUI

// MARK: - Palette

enum Wandr {

    /// #253032 — deepest ink. Text, lifted timeline blocks, pass surfaces.
    static let ink = Color(hex: 0x253032)
    /// #7D898A — muted slate. Secondary text, category labels, grid lines.
    static let slate = Color(hex: 0x7D898A)
    /// #B8B6AD — warm sand. Selected chips, dividers, resting accents.
    static let sand = Color(hex: 0xB8B6AD)
    /// #E5E1D6 — linen. Page background.
    static let linen = Color(hex: 0xE5E1D6)
    /// #FFF3DD — cream. Raised cards sitting on linen.
    static let cream = Color(hex: 0xFFF3DD)

    // Derived, semantic roles — always reference these from views, never a raw hex.
    static let pageBackground = linen
    static let cardSurface = cream
    static let liftedSurface = ink
    static let primaryText = ink
    static let secondaryText = slate
    static let hairline = sand.opacity(0.55)
    /// Burnt umber, kept inside the family — the one color allowed to
    /// interrupt, and reserved for validator warnings. Nothing else may use it.
    static let caution = Color(hex: 0x9A5B28)

    /// Category accents stay inside the family — desaturated so no stop shouts.
    static func accent(for category: StopCategory) -> Color {
        switch category {
        case .food:      return Color(hex: 0x8A6F4E)
        case .sights:    return Color(hex: 0x4E6E7D)
        case .nightlife: return Color(hex: 0x6B5470)
        case .discover:  return Color(hex: 0x5C7A63)
        }
    }
}

// MARK: - Typography

extension Font {

    /// Display masthead. SF Pro throughout — hierarchy comes from weight,
    /// tracking, and placement rather than a second typeface.
    static func wandrDisplay(_ size: CGFloat = 44) -> Font {
        .system(size: size, weight: .bold)
    }

    /// Venue and stop names.
    static func wandrTitle(_ size: CGFloat = 24) -> Font {
        .system(size: size, weight: .semibold)
    }

    /// Small all-caps metadata: category, day-of-week, offer window.
    static let wandrLabel = Font.system(size: 11, weight: .semibold, design: .default)

    /// Clock readouts in the timeline.
    static func wandrClock(_ size: CGFloat = 20) -> Font {
        .system(size: size, weight: .medium)
    }
}

// MARK: - Motion

extension Animation {

    /// Default for user-driven, retargetable movement. Critically damped —
    /// no decorative overshoot on something a finger is holding.
    static let wandrInteractive = Animation.interactiveSpring(response: 0.32, dampingFraction: 1.0)

    /// Settling after a release that carried real momentum. Slight bounce is earned here.
    static let wandrSettle = Animation.spring(response: 0.38, dampingFraction: 0.82)

    /// Short state response: press, lift, chip selection.
    static let wandrResponse = Animation.easeOut(duration: 0.18)

    /// The grab. Loose enough to overshoot slightly, so a block being picked up
    /// reads as squeezed in the hand rather than merely resized.
    static let wandrLift = Animation.spring(response: 0.26, dampingFraction: 0.58)

    /// Occasional structural transitions: deck advance, sheet content swap.
    static let wandrTransition = Animation.spring(response: 0.45, dampingFraction: 0.9)

    /// Whole-screen handoff, outgoing half. Leaves briskly and on its own —
    /// a screen that lingers while the next one arrives reads as two screens.
    static let wandrStageOut = Animation.easeOut(duration: 0.24)

    /// Whole-screen handoff, incoming half. Held back just past the outgoing
    /// screen's midpoint so the two never share the frame at full strength;
    /// without the offset the chrome of both is briefly legible at once.
    static let wandrStageIn = Animation.easeInOut(duration: 0.32).delay(0.14)
}

// MARK: - Metrics

enum Metrics {
    static let cardCorner: CGFloat = 26
    static let blockCorner: CGFloat = 18
    static let gutter: CGFloat = 20

    /// Timeline scale. One minute of plan time = this many points.
    /// 1.15 keeps a 12-hour day readable without runaway scroll length.
    static let pointsPerMinute: CGFloat = 1.15

    /// Reschedule snaps to this grain.
    static let snapMinutes: Int = 15

    /// How far a page scrolls before its display header hands off to the
    /// short title in the navigation bar.
    static let headerCollapse: CGFloat = 44
}

// MARK: - Reusable surfaces

/// A raised content card. Uses `ConcentricRectangle` so corners resolve against
/// whatever container it lands in (sheet, glass container, plain page).
struct WandrCardBackground: View {
    var fill: Color = Wandr.cardSurface
    var corner: CGFloat = Metrics.cardCorner

    var body: some View {
        ConcentricRectangle(corners: .concentric(minimum: .fixed(corner)))
            .fill(fill)
    }
}

/// Separates one deck from the next. Weight does the work — a heavy stroke in
/// a low-contrast sand keeps it present without competing with the cards, which
/// a thin hairline at higher contrast would not manage.
struct WandrDashedRule: View {
    var body: some View {
        Rule()
            .stroke(Wandr.sand,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [5, 9]))
            .frame(height: 3)
            .accessibilityHidden(true)
    }

    /// A single horizontal line through the middle of whatever it's given.
    private struct Rule: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
    }
}

/// Immediate touch-down feedback for custom pressable content.
struct WandrPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.wandrResponse, value: configuration.isPressed)
    }
}

// MARK: - Helpers

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension View {
    /// Small-caps metadata treatment used on category and day labels.
    func wandrLabelStyle(_ color: Color = Wandr.secondaryText) -> some View {
        self.font(.wandrLabel)
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}
