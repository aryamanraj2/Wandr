// WandrTheme.swift Wandr The palette, type ramp, and motion vocabulary for the whole app; content layer carries the brand, UI layer stays native.

import SwiftUI

// MARK: - Palette

/// Four brand tones carry the app: charcoal reads, indigo acts, cyan structures, creamy warms.
/// The field is cool and near-neutral so the one warm tone lands as an event — creamy only ever
/// appears on something dark or something being spoken to, never as a page.
enum Wandr {

    // MARK: Brand tones

    /// #23282B — charcoal. The deepest tone: body copy, image gradients, shadows.
    static let charcoal = Color(hex: 0x23282B)
    /// #37426F — indigo. The only tone that means "act": controls, selection, a block in the air.
    static let indigo = Color(hex: 0x37426F)
    /// #A9D0D5 — cyan. The structural tone the whole light field is drawn from.
    static let cyan = Color(hex: 0xA9D0D5)
    /// #F5E1BC — creamy. The single warm tone, reserved for what sits on charcoal or indigo.
    static let cream = Color(hex: 0xF5E1BC)

    // MARK: Derived neutrals

    /// #E7F1F3 — cyan carried most of the way to white. The page.
    static let haze = Color(hex: 0xE7F1F3)
    /// #FBFDFD — a cool near-white that lifts off `haze` without going stark.
    static let paper = Color(hex: 0xFBFDFD)
    /// #9BC2C9 — cyan pulled a step deeper so a full-strength hairline or dash still registers.
    static let mist = Color(hex: 0x9BC2C9)
    /// #5A6485 — indigo desaturated toward slate. Passes AA on both `paper` and `haze`.
    static let slate = Color(hex: 0x5A6485)

    // Semantic roles — always reference these from views, never a raw tone.
    static let pageBackground = haze
    static let cardSurface = paper
    /// A block that has been picked up leaves the page's palette entirely — indigo, not a darker grey.
    static let liftedSurface = indigo
    static let primaryText = charcoal
    static let secondaryText = slate
    static let hairline = mist.opacity(0.55)
    /// Controls, selection, and anything the finger is meant to find.
    static let brand = indigo
    /// Copy and glyphs riding on `brand` or `charcoal`.
    static let onBrand = cream

    /// Category accents stay inside the family — three cool, one warm, all desaturated so no stop
    /// shouts. Dark enough to double as text on the creamy card caption, which is the tightest
    /// contrast pairing in the app.
    static func accent(for category: StopCategory) -> Color {
        switch category {
        // Terracotta rather than a browner clay: brown against the creamy tone reads as the beige
        // this palette exists to get away from, and food is the deck seen first.
        case .food:      return Color(hex: 0x9C4F3C)
        case .sights:    return Color(hex: 0x2F5C77)
        case .nightlife: return Color(hex: 0x574577)
        case .discover:  return Color(hex: 0x2F6A62)
        }
    }
}

// MARK: - Typography

extension Font {

    /// Display masthead. SF Pro throughout — hierarchy comes from weight, tracking, and placement, not a second typeface.
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

    /// Default for user-driven, retargetable movement. Critically damped — no decorative overshoot on something a finger is holding.
    static let wandrInteractive = Animation.interactiveSpring(response: 0.32, dampingFraction: 1.0)

    /// Settling after a release that carried real momentum. Slight bounce is earned here.
    static let wandrSettle = Animation.spring(response: 0.38, dampingFraction: 0.82)

    /// Short state response: press, lift, chip selection.
    static let wandrResponse = Animation.easeOut(duration: 0.18)

    /// The grab. Loose enough to overshoot slightly, so a block being picked up reads as squeezed in the hand rather than merely resized.
    static let wandrLift = Animation.spring(response: 0.26, dampingFraction: 0.58)

    /// Occasional structural transitions: deck advance, sheet content swap.
    static let wandrTransition = Animation.spring(response: 0.45, dampingFraction: 0.9)

    /// Whole-screen handoff, outgoing half. Leaves briskly and on its own — a screen that lingers while the next arrives reads as two screens.
    static let wandrStageOut = Animation.easeOut(duration: 0.24)

    /// Whole-screen handoff, incoming half. Held back just past the outgoing screen's midpoint so the two never share the frame at full strength.
    static let wandrStageIn = Animation.easeInOut(duration: 0.32).delay(0.14)
}

// MARK: - Metrics

enum Metrics {
    static let cardCorner: CGFloat = 26
    static let blockCorner: CGFloat = 18
    static let gutter: CGFloat = 20

    /// Timeline scale: one minute of plan time = this many points. 1.15 keeps a 12-hour day readable without runaway scroll length.
    static let pointsPerMinute: CGFloat = 1.15

    /// Reschedule snaps to this grain.
    static let snapMinutes: Int = 15

    /// How far a page scrolls before its display header hands off to the short title in the navigation bar.
    static let headerCollapse: CGFloat = 44
}

// MARK: - Reusable surfaces

/// A raised content card. Uses `ConcentricRectangle` so corners resolve against whatever container it lands in (sheet, glass container, plain page).
struct WandrCardBackground: View {
    var fill: Color = Wandr.cardSurface
    var corner: CGFloat = Metrics.cardCorner

    var body: some View {
        ConcentricRectangle(corners: .concentric(minimum: .fixed(corner)))
            .fill(fill)
            // A cool near-white card on a cool near-white page is separated by very little tone, so
            // the edge gets drawn rather than left to the fill difference alone.
            .overlay {
                ConcentricRectangle(corners: .concentric(minimum: .fixed(corner)))
                    .stroke(Wandr.mist.opacity(0.4), lineWidth: 1)
            }
    }
}

/// Separates one deck from the next. Weight does the work — a heavy stroke in low-contrast sand stays present without competing with the cards.
struct WandrDashedRule: View {
    var body: some View {
        Rule()
            .stroke(Wandr.mist,
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
