// WandrDrift.swift Wandr The page's own weather. Wide, slow blooms of light moving behind a screen that is working, so the two-thirds of a wait screen carrying no content are still part of what the app is doing.

import SwiftUI

/// A slow light field drifting behind a screen's content.
///
/// The wait screen already had four moving things on it and still read as frozen. Each one was
/// honest and each one was too small to see: a 7pt band, a glint inside a word, four 9pt dots
/// breathing by two points, a blurred gradient on the border. Under all of them sat most of a page
/// of flat `haze` that never changed at all — and a screen whose large areas hold still reads as
/// stopped no matter what its small ones are doing. Adding a fifth small animation would not have
/// fixed that; the field itself had to move.
///
/// Three blooms, on periods that do not divide into one another. That is the whole trick. Two lights
/// on a shared clock make an arrangement the eye learns inside a cycle and then stops seeing — which
/// is also why the band's two comets, half a period apart on the same 2.4s, stopped registering
/// after the first few seconds. Nineteen, twenty-six and thirty-one seconds never present the same
/// picture twice in any wait a person will actually sit through.
///
/// Nothing here has an edge or a silhouette, and nothing moves fast enough to pull the eye off the
/// type. It should be noticeable only if you go looking for it, and missed immediately if it stops.
private struct WandrDriftModifier: ViewModifier {

    var active: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.background {
            if active {
                Group {
                    if reduceMotion {
                        // Held, not removed. The blooms still give the page depth and keep the
                        // bottom of the screen from reading as a cut-off; they simply stop
                        // travelling.
                        field(at: 0)
                    } else {
                        TimelineView(.animation) { timeline in
                            field(at: timeline.date.timeIntervalSinceReferenceDate)
                        }
                    }
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }

    // MARK: Composition

    private func field(at time: Double) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                ForEach(Array(Self.blooms.enumerated()), id: \.offset) { _, bloom in
                    let radius = size.width * bloom.radius
                    // Two different rates on the two axes, so a bloom traces a slow open figure
                    // rather than a circle returning to its start. A circular path is a loop, and a
                    // loop is the thing this exists to avoid.
                    let angle = (time / bloom.period + bloom.phase) * 2 * .pi
                    let x = size.width * (bloom.centre.x + bloom.travel.width * sin(angle))
                    let y = size.height * (bloom.centre.y + bloom.travel.height * cos(angle * 0.61))

                    Circle()
                        .fill(gradient(for: bloom, radius: radius))
                        .frame(width: radius * 2, height: radius * 2)
                        .position(x: x, y: y)
                }
            }
        }
    }

    /// Three stops rather than two. A straight ramp from tint to clear has a visible middle — the
    /// bloom reads as a disc with soft edges instead of as light — so it falls away fast near the
    /// centre and then trails, which is the same head-and-tail shape the band and the border use.
    private func gradient(for bloom: Bloom, radius: CGFloat) -> RadialGradient {
        RadialGradient(
            stops: [
                .init(color: bloom.tint.opacity(bloom.strength), location: 0.00),
                .init(color: bloom.tint.opacity(bloom.strength * 0.45), location: 0.42),
                .init(color: bloom.tint.opacity(0), location: 1.00)
            ],
            center: .center,
            startRadius: 0,
            endRadius: radius
        )
    }

    // MARK: The blooms

    private struct Bloom {
        /// Fraction of the page's width.
        let radius: CGFloat
        /// Resting centre, in unit page coordinates.
        let centre: UnitPoint
        /// How far it wanders from that centre, as a fraction of the page.
        let travel: CGSize
        let period: Double
        let phase: Double
        let tint: Color
        let strength: Double
    }

    /// Two cool blooms and one deeper one, all inside the family the rest of the app draws from.
    /// The largest sits low, because the bottom of this screen is the emptiest part of it and a
    /// wait that fades toward its own footer reads as a page with somewhere to go.
    private static let blooms: [Bloom] = [
        Bloom(radius: 0.78, centre: UnitPoint(x: 0.16, y: 0.26), travel: CGSize(width: 0.20, height: 0.11),
              period: 19, phase: 0.00, tint: Wandr.cyan.mix(with: Wandr.indigo, by: 0.20), strength: 0.30),
        Bloom(radius: 0.62, centre: UnitPoint(x: 0.88, y: 0.62), travel: CGSize(width: 0.13, height: 0.12),
              period: 26, phase: 0.35, tint: Wandr.indigo, strength: 0.09),
        Bloom(radius: 0.98, centre: UnitPoint(x: 0.52, y: 0.99), travel: CGSize(width: 0.26, height: 0.09),
              period: 31, phase: 0.68, tint: Wandr.cyan, strength: 0.38)
    ]
}

extension View {

    /// Puts a slow drifting light field behind this view.
    ///
    /// Apply *inside* the page background — `.wandrDrift()` then `.background(Wandr.pageBackground)`
    /// — so the field sits on the page rather than over the content. Applied the other way round the
    /// page colour covers it, and applied as an overlay it washes the type.
    ///
    /// For screens where the app is working or waiting. On a screen that is merely sitting there it
    /// would be decoration, which is the one thing this palette does not do.
    func wandrDrift(_ active: Bool = true) -> some View {
        modifier(WandrDriftModifier(active: active))
    }
}

#Preview {
    VStack(alignment: .leading) {
        Text("Planning")
            .font(.wandrPoster(52))
            .tracking(Metrics.posterTracking)
            .foregroundStyle(Wandr.primaryText)
        Text("Finding places nearby")
            .font(.body)
            .foregroundStyle(Wandr.secondaryText)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .padding(.horizontal, Metrics.gutter)
    .wandrDrift()
    .background(Wandr.pageBackground)
}
