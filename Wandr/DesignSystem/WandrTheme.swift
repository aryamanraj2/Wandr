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

    /// Poster masthead. One per screen, and it owns the top of the page — everything under it
    /// drops to supporting weight rather than competing. Black rather than the display ramp's bold
    /// because at this size weight is what lets the line stay this large without reading as
    /// shouting: the letters close ranks instead of spreading. Pair with `Metrics.posterTracking`
    /// and `Metrics.posterLeading`, which are what actually make it a masthead rather than big text.
    static func wandrPoster(_ size: CGFloat = 46) -> Font {
        .system(size: size, weight: .black)
    }

    /// Venue and stop names.
    static func wandrTitle(_ size: CGFloat = 24) -> Font {
        .system(size: size, weight: .semibold)
    }

    /// Small all-caps metadata: category, day-of-week, offer window.
    static let wandrLabel = Font.system(size: 11, weight: .semibold, design: .default)

    /// The one place a second typeface is allowed, and only for a specific kind of content:
    /// machine state read at a glance rather than prose — a phase counter, a percentage, the
    /// pipeline's own step names. Monospacing is doing a job there that SF Pro cannot: a readout
    /// that changes while you are looking at it must not reflow, and a list of step names is easier
    /// to scan when the glyphs sit on a grid.
    ///
    /// It is not a display face and never carries a sentence. Two screens already reached for
    /// `design: .monospaced` inline for raw text payloads; this names the decision so the next one
    /// does not have to guess a size.
    static func wandrMono(_ size: CGFloat = 12, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

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

    /// One object changing posture — the capture orb collapsing into a text field and back. Slower
    /// than `wandrTransition` because the eye is tracking a single silhouette the whole way and a
    /// brisk spring reads as a cut; damped just under 1 so it arrives with weight rather than
    /// bouncing, which on a 236pt body would look like jelly.
    static let wandrMorph = Animation.spring(response: 0.52, dampingFraction: 0.86)

    /// Entrance for an occasional, information-dense screen: the blocks arrive in reading order
    /// with a small stagger applied by the caller. Deliberately gentle and never used on anything
    /// a person taps repeatedly.
    static func wandrEnter(_ index: Int) -> Animation {
        .spring(response: 0.5, dampingFraction: 0.92).delay(0.06 * Double(index))
    }

    /// Whole-screen handoff, outgoing half. Leaves briskly and on its own — a screen that lingers while the next arrives reads as two screens.
    static let wandrStageOut = Animation.easeOut(duration: 0.24)

    /// Whole-screen handoff, incoming half. Held back just past the outgoing screen's midpoint so the two never share the frame at full strength.
    static let wandrStageIn = Animation.easeInOut(duration: 0.32).delay(0.14)
}

// MARK: - Transitions

extension AnyTransition {

    /// One whole screen handing over to the next.
    ///
    /// Plain `.opacity` was doing this, and a crossfade has no direction: two screens dissolve
    /// through each other and nothing about the change says which way the flow went. The arriving
    /// screen rises a little and settles at full size; the leaving one recedes very slightly as it
    /// goes. The distances are small on purpose — this fires on every step of intake, and anything
    /// larger would turn a five-step flow into five animations to sit through.
    static var wandrStage: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.985))
                .combined(with: .offset(y: 14)),
            removal: .opacity.combined(with: .scale(scale: 1.012))
        )
    }
}

// MARK: - Metrics

enum Metrics {
    /// Display type closes up as it grows. Applied at poster sizes only — the same value on body
    /// copy would tighten it past legibility, which is why this is a named constant rather than the
    /// app's tracking.
    static let posterTracking: CGFloat = -1.6

    /// Poster lines sit closer than SwiftUI's default leading, or a two-line masthead reads as two
    /// separate headings rather than one statement.
    static let posterLeading: CGFloat = -4

    static let cardCorner: CGFloat = 26
    static let blockCorner: CGFloat = 18
    static let gutter: CGFloat = 20

    /// A hard rule — a line meant to be seen as structure rather than as a seam. Distinct from the
    /// 1pt hairline that separates two near-white surfaces and from `WandrDashedRule`'s 3pt dashes,
    /// both of which exist to be quiet.
    static let rule: CGFloat = 2

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

/// A card whose detail is folded away until asked for. The intake screens have to state a privacy
/// boundary and hand over a wall of prompt text, and both are things a host reads once and then
/// needs to stop seeing — left open they turn every screen into a document. Built on
/// `DisclosureGroup` rather than a hand-rolled chevron so expansion state, keyboard activation, and
/// the VoiceOver "expanded/collapsed" announcement come from the system.
struct WandrFoldout<Content: View>: View {
    let title: String
    /// An `Image` rather than a symbol name, so the app's own generated symbols and SF Symbols are
    /// equally welcome here. `Tools/PhosphorSymbols` produces the former as real symbol assets, and
    /// the whole point of doing it that way is that a caller should not have to care which is which.
    let icon: Image
    @ViewBuilder var content: Content

    @State private var isExpanded = false

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = Image(systemName: systemImage)
        self.content = content()
    }

    init(title: String, image: ImageResource, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = Image(image)
        self.content = content()
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 14)
        } label: {
            Label {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Wandr.primaryText)
                    .multilineTextAlignment(.leading)
            } icon: {
                icon.foregroundStyle(Wandr.brand)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .tint(Wandr.secondaryText)
        .padding(16)
        .background(WandrCardBackground())
        .animation(.wandrTransition, value: isExpanded)
    }
}

/// One line of a folded-out list: a symbol in the accent column, a sentence beside it. Kept here
/// rather than in each screen so the boundary card and the setup steps share a single rhythm.
struct WandrPoint: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Wandr.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .font(.footnote)
                .foregroundStyle(Wandr.brand.opacity(0.75))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Actions

/// One filled action per screen, and everything else quiet. Five screens each re-rolled
/// `.glassProminent` + `.buttonBorderShape` + `.controlSize` + `.tint` by hand, which is how
/// `ShortcutSetupView` ended up with four full-width indigo slabs stacked down a page — no single
/// place said which of them was the one to press. Naming the two roles makes that a decision rather
/// than an accident: `wandrPrimaryAction` is the screen's answer, `wandrQuietAction` is everything
/// that merely helps you get there.
extension View {

    /// The screen's single filled action. If a second one appears, one of them is wrong.
    func wandrPrimaryAction() -> some View {
        buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(Wandr.brand)
    }

    /// Every other button on the screen. Same geometry, no fill — so the page reads as one
    /// destination with steps rather than a column of equally urgent slabs.
    func wandrQuietAction() -> some View {
        buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(Wandr.brand)
    }

    /// Geometry for a full-bleed action's label. Lives on the label rather than the button because
    /// the glass styles size their capsule to what they are given.
    func wandrActionLabel(_ font: Font = .headline) -> some View {
        self.font(font)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
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

// MARK: - Entrance

extension View {

    /// A block arriving in reading order, for a screen seen occasionally.
    ///
    /// Modest scale plus opacity, never from zero: a block that grows out of nothing has no physical
    /// form to read on the way in. Reduce Motion gets the arrival with no travel. Lives here rather
    /// than privately on the setup screen — where it started — because the three intake screens are
    /// one flow and had no business arriving in three different ways.
    ///
    /// Never use this on something a person taps repeatedly. It costs time on every appearance, and
    /// the only reason it is affordable here is that each of these screens is seen once per outing.
    func entrance(_ arrived: Bool, index: Int, reduceMotion: Bool) -> some View {
        opacity(arrived ? 1 : 0)
            .scaleEffect(arrived || reduceMotion ? 1 : 0.97, anchor: .leading)
            .offset(y: arrived || reduceMotion ? 0 : 10)
            .animation(reduceMotion ? .easeOut(duration: 0.2) : .wandrEnter(index), value: arrived)
    }

    /// A card being *put down*, for a page whose content is a pile of them.
    ///
    /// Same licence and the same spring as `entrance`, but the anchor and the travel are a card's
    /// rather than a paragraph's. A block of copy settles where it already was, so 10pt and a
    /// leading anchor are enough to say "arrived"; a card is a large object with a visible bottom
    /// edge, and at 10pt it reads as a wobble rather than as landing. Rising further and scaling
    /// from `.bottom` puts the growth where the eye is already looking — the edge nearest the
    /// bottom of the screen — so the card reads as coming up onto the stack.
    ///
    /// Scale still starts at 0.94, not 0: an entrance from nothing has no physical form to read on
    /// the way in. Reduce Motion keeps the arrival and drops the travel entirely.
    func dealIn(_ arrived: Bool, order: Int, reduceMotion: Bool) -> some View {
        opacity(arrived ? 1 : 0)
            .scaleEffect(arrived || reduceMotion ? 1 : 0.94, anchor: .bottom)
            .offset(y: arrived || reduceMotion ? 0 : 52)
            .animation(reduceMotion ? .easeOut(duration: 0.2) : .wandrEnter(order), value: arrived)
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
