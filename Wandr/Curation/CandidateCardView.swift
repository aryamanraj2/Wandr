//
//  CandidateCardView.swift
//  Wandr
//
//  One card in a deck. Full-bleed backdrop, no frame; the caption rides on a
//  frosted panel that the backdrop still shows through, so the venue imagery
//  and the copy read as one surface rather than two stacked ones.
//
//  The face is split out from the card because the expanded view rebuilds the
//  identical composition as its hero. Two hand-matched copies would drift by a
//  point or two and the zoom transition would show the seam — sharing the view
//  makes the growth read as the same object rather than a cross-fade.
//

import SwiftUI

// MARK: - Card

struct CandidateCardView: View {
    let candidate: Candidate
    /// -1 … 1 — how far the card has been dragged, for the verdict overlay.
    var dragProgress: CGFloat = 0

    var body: some View {
        CandidateCardFace(candidate: candidate)
            .overlay { verdictOverlay }
            // No frame, no stroke, no shadow — the edge is the clip itself. The
            // stack reads as depth through scale and offset in DeckView, so the
            // card needs nothing bleeding out past its own bounds.
            .clipShape(ConcentricRectangle(corners: .concentric(minimum: .fixed(Metrics.cardCorner))))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(candidate.name), \(candidate.area)")
            .accessibilityValue(accessibilityDetail)
    }

    // MARK: Verdict overlay

    /// Confirms the destination of the drag before release — the trajectory
    /// should reveal the outcome, not surprise on `onEnded`.
    private var verdictOverlay: some View {
        let keeping = dragProgress > 0
        let strength = min(abs(dragProgress), 1)

        return ZStack {
            (keeping ? Wandr.accent(for: candidate.category) : Wandr.ink)
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

/// The card's visible composition, minus the clip, the gesture affordances and
/// the verdict wash. Shared by the deck card and the expanded hero.
struct CandidateCardFace: View {
    let candidate: Candidate

    /// The expanded hero drops the deck-only marginalia — the model's rationale
    /// and the validator warning both get their own proper section down the page,
    /// and repeating them in the hero would read as a stutter.
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
                .foregroundStyle(Wandr.ink)
                .lineLimit(isHero ? 2 : 1)
                .minimumScaleFactor(0.7)

            Text(candidate.tagline)
                .font(.subheadline)
                .lineHeight(.tight)
                .foregroundStyle(Wandr.ink.opacity(0.66))
                .lineLimit(isHero ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)

            if !isHero {
                // The model's reason for the pick — the one piece of model prose on the
                // card, styled as a quiet aside so it never reads as a hard fact.
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
                        .foregroundStyle(Wandr.ink.opacity(0.5))
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
        .padding(.top, 34)
        .padding(.bottom, isHero ? 22 : 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(frost)
    }

    /// Translucent, not opaque: the backdrop keeps travelling under the copy and
    /// dissolves into it, which is what stops the panel reading as a pasted-on box.
    private var frost: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(Wandr.cream.opacity(0.62))
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white.opacity(0.55), location: 0.28),
                        .init(color: .white, location: 0.6)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
    }

    private func offerLine(_ offer: String) -> some View {
        Label {
            Text(offer)
                + Text(candidate.offerWindow.map { " · \($0)" } ?? "")
                .foregroundStyle(Wandr.ink.opacity(0.45))
        } icon: {
            Image(systemName: "tag.fill")
        }
        .font(.caption)
        .foregroundStyle(Wandr.accent(for: candidate.category))
        .lineLimit(1)
    }

    /// Quiet facts on the left, the number that decides the swipe on the right —
    /// the same weighting the eye already expects from a card's action row.
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
                .foregroundStyle(Wandr.ink)

            if !candidate.costUnknown && candidate.perHead > 0 {
                Text("/head")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Wandr.ink.opacity(0.45))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Capsule().fill(Wandr.cream.opacity(0.95)))
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
            .foregroundStyle(Wandr.ink.opacity(0.52))
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
            .background(Capsule().fill(Wandr.ink.opacity(0.22)))
    }
}

// MARK: - Backdrop

/// Stands in for venue photography. Deterministic per-venue hue so a card
/// keeps the same identity across launches — and so the expanded hero paints
/// the exact same gradient the deck card was showing a frame earlier.
struct CandidateBackdrop: View {
    let candidate: Candidate

    var body: some View {
        let base = Wandr.accent(for: candidate.category)
        let angle = Double(candidate.imageSeed % 7) * 24

        LinearGradient(
            colors: [
                base.opacity(0.95),
                base.mix(with: Wandr.ink, by: 0.55, in: .perceptual),
                Wandr.ink
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
