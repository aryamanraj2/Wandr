// CandidateCardView.swift Wandr One card in a deck. Full-bleed backdrop, no frame; the caption rides on a frosted panel that the backdrop still shows through, so the venue imagery and the copy read as one surface rather than two stacked ones. The face is split out from the card because the expanded view rebuilds the identical composition as its hero. Two hand-matched copies would drift by a point or two and the zoom transition would show the seam — sharing the view makes the growth read as the same object rather than a cross-fade.

import SwiftUI

// MARK: - Card

struct CandidateCardView: View {
    let candidate: Candidate
    /// -1 … 1 — how far the card has been dragged, for the verdict overlay.
    var dragProgress: CGFloat = 0

    var body: some View {
        CandidateCardFace(candidate: candidate)
            .overlay { verdictOverlay }
            // No frame, no stroke, no shadow — the edge is the clip itself. The stack reads as depth through scale and offset in DeckView, so the card needs nothing bleeding out past its own bounds.
            .clipShape(ConcentricRectangle(corners: .concentric(minimum: .fixed(Metrics.cardCorner))))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(candidate.name), \(candidate.area)")
            .accessibilityValue(accessibilityDetail)
    }

    // MARK: Verdict overlay

    /// Confirms the destination of the drag before release — the trajectory should reveal the outcome, not surprise on `onEnded`.
    private var verdictOverlay: some View {
        let keeping = dragProgress > 0
        let strength = min(abs(dragProgress), 1)

        return ZStack {
            (keeping ? Wandr.accent(for: candidate.category) : Wandr.charcoal)
                .opacity(strength * 0.32)

            Image(systemName: keeping ? "checkmark" : "arrow.uturn.forward")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Wandr.cream)
                .padding(22)
                .background(Circle().fill(.ultraThinMaterial.opacity(0.8)))
                .scaleEffect(0.7 + strength * 0.3)
                .opacity(strength)
        }
        .opacity(strength > 0.02 ? 1 : 0)
        .allowsHitTesting(false)
    }

    private var accessibilityDetail: String {
        var parts = [candidate.tagline]
        if let rationale = candidate.rationale { parts.append(rationale) }
        parts.append(candidate.openWindow)
        if !candidate.travelNote.isEmpty { parts.append(candidate.travelNote) }
        parts.append(
            candidate.costUnknown
                ? "Price not listed"
                : (candidate.perHead == 0 ? "Free" : "₹\(candidate.perHead) per head")
        )
        if let offer = candidate.offer { parts.append(offer) }
        if let warning = candidate.warnings.first { parts.append(warning) }
        return parts.joined(separator: ". ")
    }
}

// MARK: - Face

/// The card's visible composition, minus the clip, the gesture affordances and the verdict wash. Shared by the deck card and the expanded hero.
struct CandidateCardFace: View {
    let candidate: Candidate

    /// How far the caption panel takes to arrive out of the photograph, in points rather than as a
    /// fraction of the panel. The panel's height swings by ~80pt with how much copy a candidate
    /// carries — a rationale and a warning, or neither — and a proportional ramp put the title on
    /// solid paper for a wordy card and halfway inside the ramp for a terse one. A fixed distance
    /// makes the dissolve identical on every card and lets the copy's top padding be derived from
    /// it rather than guessed against it.
    private static let captionFeather: CGFloat = 40

    /// The expanded hero drops the deck-only marginalia — the model's rationale and the validator warning both get their own proper section down the page, and repeating them in the hero would read as a stutter.
    var isHero: Bool = false

    var body: some View {
        ZStack(alignment: .bottom) {
            CandidateBackdrop(candidate: candidate)
            areaTag
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(14)
            caption
        }
    }

    // MARK: Caption

    private var caption: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(candidate.name)
                .font(.wandrTitle(isHero ? 32 : 27))
                .foregroundStyle(Wandr.charcoal)
                .lineLimit(isHero ? 2 : 1)
                .minimumScaleFactor(0.7)

            Text(candidate.tagline)
                .font(.subheadline)
                .lineHeight(.tight)
                .foregroundStyle(Wandr.charcoal.opacity(0.66))
                .lineLimit(isHero ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)

            if !isHero {
                // The model's reason for the pick — the one piece of model prose on the card, styled as a quiet aside so it never reads as a hard fact.
                if let rationale = candidate.rationale {
                    Text(rationale)
                        .font(.footnote.italic())
                        .foregroundStyle(Wandr.accent(for: candidate.category))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }

                // The validator's caveats, if any — an honest flag, never hidden.
                if let warning = candidate.warnings.first {
                    Label(warning, systemImage: "exclamationmark.circle")
                        .font(.caption2)
                        .foregroundStyle(Wandr.charcoal.opacity(0.5))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 1)
                }
            }

            if let offer = candidate.offer {
                offerLine(offer)
                    .padding(.top, 1)
            }

            footer
                .padding(.top, 9)
        }
        .padding(.horizontal, 20)
        // Clears the ramp with a little air to spare, so the first line of type always begins on
        // solid panel. Type that starts inside the feather is the whole legibility problem: charcoal
        // at 27pt over a half-transparent panel over a lit photograph has no reliable contrast.
        .padding(.top, Self.captionFeather + 8)
        .padding(.bottom, isHero ? 22 : 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(frost)
    }

    /// The panel the copy sits on. The dissolve lives entirely in the top `captionFeather` points;
    /// below that the panel is paper and the type is simply legible.
    ///
    /// It used to be translucent all the way down — 0.82 paper over a material — on the argument
    /// that a backdrop travelling under the copy is what stops the panel reading as a pasted-on box.
    /// The argument holds; the placement was wrong. Over a warm photograph (a wood-lit bar, a
    /// lamplit counter) the panel took the picture's cast and the whole caption sat on a muddy
    /// red-brown wash, which is both illegible and the one hue this palette exists to avoid. The
    /// edge is what has to dissolve, not the text's background — so the transparency was moved into
    /// the ramp, where it does the same job against a scrimmed part of the photograph.
    ///
    /// Cool, not creamy. The warm tone was tried here and it fails on the food accent specifically: a clay backdrop dissolving into a cream panel muddies into beige across the whole lower half of the card, and food is the deck the user sees first. A near-white panel stays neutral under all four accents, and it matches the schedule's cards, so a stop looks like the same object before and after it is picked.
    private var frost: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(Wandr.paper.opacity(0.96))
            .mask(alignment: .top) {
                VStack(spacing: 0) {
                    // Eased rather than a straight two-stop ramp. A linear fade of a near-white over
                    // a photograph bands visibly across 40 points; the extra stops bend the curve so
                    // the panel appears to condense out of the image instead of wiping over it.
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0), location: 0),
                            .init(color: .white.opacity(0.10), location: 0.26),
                            .init(color: .white.opacity(0.38), location: 0.50),
                            .init(color: .white.opacity(0.76), location: 0.74),
                            .init(color: .white.opacity(0.95), location: 0.90),
                            .init(color: .white, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: Self.captionFeather)

                    Rectangle().fill(.white)
                }
            }
    }

    private func offerLine(_ offer: String) -> some View {
        Label {
            Text(offer)
                + Text(candidate.offerWindow.map { " · \($0)" } ?? "")
                .foregroundStyle(Wandr.charcoal.opacity(0.45))
        } icon: {
            Image(systemName: "tag.fill")
        }
        .font(.caption)
        .foregroundStyle(Wandr.accent(for: candidate.category))
        .lineLimit(1)
    }

    /// Quiet facts on the left, the number that decides the swipe on the right — the same weighting the eye already expects from a card's action row.
    private var footer: some View {
        HStack(alignment: .center, spacing: 14) {
            detail("clock", candidate.openWindow)
            // Travel time is a deferred rule — show the walk line only when we have one.
            if !candidate.travelNote.isEmpty {
                detail("figure.walk", candidate.travelNote)
            }

            Spacer(minLength: 8)

            pricePill
        }
    }

    /// Unknown cost renders as "₹ ?" — never as ₹0/"Free", which would be a false fact.
    private var priceHeadline: String {
        if candidate.costUnknown { return "₹ ?" }
        return candidate.perHead == 0 ? "Free" : "₹\(candidate.perHead)"
    }

    private var pricePill: some View {
        HStack(spacing: 5) {
            Text(priceHeadline)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Wandr.charcoal)

            if !candidate.costUnknown && candidate.perHead > 0 {
                Text("/head")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Wandr.charcoal.opacity(0.45))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        // The price is the figure the swipe turns on, so it gets the one tonal break on the caption
        // panel — a soft cyan chip, which reads without competing with the accent savings badge.
        .background(Capsule().fill(Wandr.haze))
        .overlay(alignment: .topTrailing) {
            if let savings = candidate.savings {
                Text("−₹\(savings)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Wandr.cream)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Wandr.accent(for: candidate.category)))
                    .offset(x: 6, y: -9)
            }
        }
        .fixedSize()
    }

    private func detail(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 11.5))
            .foregroundStyle(Wandr.charcoal.opacity(0.52))
            .lineLimit(1)
    }

    /// Sits on the image, so it takes its own glass rather than the panel's.
    private var areaTag: some View {
        Text(candidate.area)
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.7)
            .textCase(.uppercase)
            .foregroundStyle(Wandr.cream)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Capsule().fill(.ultraThinMaterial.opacity(0.55)))
            .background(Capsule().fill(Wandr.charcoal.opacity(0.22)))
    }
}

// MARK: - Backdrop

/// The card's image surface: the venue's photograph where one has been shot, and a
/// deterministic per-venue gradient everywhere else. The fallback is not a placeholder for
/// a failure — most of the dataset has never been photographed, and a coloured card that
/// keeps its identity across launches is a better answer there than an empty frame.
///
/// Both branches paint the identical surface for the deck card and for the expanded hero,
/// which is what lets `.navigationTransition(.zoom)` read as one object growing. See
/// `VenuePhoto` for why the lookup is synchronous.
struct CandidateBackdrop: View {
    let candidate: Candidate

    var body: some View {
        if let photo = VenuePhoto.image(seed: candidate.imageSeed) {
            photograph(photo)
        } else {
            gradient
        }
    }

    // MARK: Photograph

    /// Masters are square, because the two surfaces that draw this disagree about shape:
    /// the deck card is portrait (~0.90) and the hero is landscape (~1.12). A square fill
    /// crops symmetrically off the top and bottom on one and off the sides on the other,
    /// so a single asset sits correctly in both. A portrait or landscape master would be
    /// right in one place and wrong in the other.
    private func photograph(_ photo: Image) -> some View {
        // `scaledToFill` needs something to fill against. `Color.clear` hands it the card's
        // own bounds without the photo's intrinsic size getting a vote on the layout.
        Color.clear
            .overlay {
                photo
                    .resizable()
                    .scaledToFill()
                    // One grade over every photograph. The set is assembled from mixed
                    // sources and reads as a ransom note without it; a shared treatment is
                    // what makes twenty photographers look like one deck.
                    .saturation(0.94)
            }
            .clipped()
            .overlay { Wandr.charcoal.opacity(0.08) }
            .overlay(alignment: .top) { topScrim }
            .overlay { bottomScrim }
    }

    /// What the caption's feather emerges from. The panel's ramp is transparent by design, so for
    /// those 40 points the photograph is still the background — and an unscrimmed one arrives at
    /// full colour and full contrast right where the panel is at its weakest. Charcoal is the cool
    /// end of the palette, so it knocks a warm frame's saturation down as it darkens it, and the
    /// panel condenses out of a neutral rather than out of a red.
    ///
    /// Tall and shallow rather than short and strong: a hard scrim under a light panel shows up as
    /// a grey band across the card, which is a second seam in place of the one being removed.
    private var bottomScrim: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.24),
                .init(color: Wandr.charcoal.opacity(0.22), location: 0.52),
                .init(color: Wandr.charcoal.opacity(0.50), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }

    /// The area tag is cream on a thin material — legible over the gradient, and gone over
    /// a bright sky. This buys it back at the top without darkening the whole frame, which
    /// would cost the photograph the thing it was added for.
    private var topScrim: some View {
        LinearGradient(
            colors: [Wandr.charcoal.opacity(0.38), .clear],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 96)
    }

    // MARK: Gradient

    /// Deterministic per-venue hue so an unphotographed card keeps the same identity across
    /// launches — and so the expanded hero paints the exact same gradient the deck card was
    /// showing a frame earlier.
    private var gradient: some View {
        let base = Wandr.accent(for: candidate.category)
        let angle = Double(candidate.imageSeed % 7) * 24

        return LinearGradient(
            colors: [
                // Opaque at the top: at 0.95 the page tint bled through and washed the hue
                // out, which read as a faded swatch rather than a photograph.
                base,
                base.mix(with: Wandr.charcoal, by: 0.55, in: .perceptual),
                Wandr.charcoal
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            // Soft light break, so the surface reads as a photograph rather than a swatch.
            EllipticalGradient(
                colors: [Color.white.opacity(0.28), .clear],
                center: .init(x: 0.3, y: 0.18),
                startRadiusFraction: 0,
                endRadiusFraction: 0.75
            )
            .rotationEffect(.degrees(angle))
        }
    }
}

#Preview("Card") {
    ZStack {
        Wandr.pageBackground.ignoresSafeArea()
        CandidateCardView(candidate: DemoPlan.decks[0].candidates[0])
            .frame(height: 460)
            .padding(28)
    }
}
