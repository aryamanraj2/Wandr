//
//  CandidateDetailView.swift
//  Wandr
//
//  The expanded card. A long press on a card in the deck grows it into this —
//  same gradient, same caption, same shape, just larger and with the copy the
//  deck deliberately withholds.
//
//  The deck is a snap judgement: name, look, price, one line. Everything here
//  is the second look. The hero is literally `CandidateCardFace`, the same view
//  the card was drawing a frame earlier, so the zoom reads as one object
//  growing rather than one view dissolving into another.
//

import SwiftUI

struct CandidateDetailView: View {
    let candidate: Candidate
    var onKeep: () -> Void
    var onPass: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var accent: Color { Wandr.accent(for: candidate.category) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                body_
            }
        }
        .background(Wandr.pageBackground)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .overlay(alignment: .topTrailing) { closeButton }
        .safeAreaBar(edge: .bottom) { actionBar }
    }

    // MARK: Hero

    /// Sized to the same share of the screen the deck card occupied, so the
    /// growth is a scale rather than a reshape — the caption lands where the
    /// eye left it instead of jumping up the page.
    private var hero: some View {
        CandidateCardFace(candidate: candidate, isHero: true)
            .containerRelativeFrame(.vertical) { height, _ in
                min(max(height * 0.5, 320), 480)
            }
            .clipped()
    }

    // MARK: Body

    private var body_: some View {
        VStack(alignment: .leading, spacing: 26) {
            if let story = candidate.story {
                Text(story)
                    .font(.callout)
                    .lineHeight(.loose)
                    .foregroundStyle(Wandr.primaryText.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !candidate.highlights.isEmpty {
                highlightList
            }

            if let tip = candidate.insiderTip {
                insiderTip(tip)
            }

            // Model prose, clearly attributed. On the card this is a two-line
            // aside; here it gets room and a label, because at this size an
            // unattributed italic line would start to read as a fact.
            if let rationale = candidate.rationale {
                section("Why Wandr picked this") {
                    Text(rationale)
                        .font(.callout.italic())
                        .lineHeight(.loose)
                        .foregroundStyle(accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !candidate.warnings.isEmpty {
                section("Worth knowing") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(candidate.warnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.circle")
                                .font(.footnote)
                                .foregroundStyle(Wandr.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            factSheet
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 36)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var highlightList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(candidate.highlights, id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Circle()
                        .fill(accent)
                        .frame(width: 5, height: 5)
                        // Baseline-aligned text puts a bare circle slightly high;
                        // this drops it onto the x-height where it reads as a bullet.
                        .offset(y: -1)

                    Text(line)
                        .font(.subheadline)
                        .lineHeight(.tight)
                        .foregroundStyle(Wandr.primaryText.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// The one block that earns a surface of its own — it is the piece of the
    /// expanded card a reader would actually screenshot.
    private func insiderTip(_ tip: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb.max")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(accent)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 5) {
                Text("On the ground")
                    .wandrLabelStyle(accent)

                Text(tip)
                    .font(.subheadline)
                    .lineHeight(.tight)
                    .foregroundStyle(Wandr.primaryText.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WandrCardBackground(fill: Wandr.sand.opacity(0.3), corner: 18))
    }

    private var factSheet: some View {
        VStack(spacing: 0) {
            factRow("clock", "Hours", candidate.openWindow)

            if !candidate.travelNote.isEmpty {
                Divider().overlay(Wandr.hairline)
                factRow("figure.walk", "Getting there", candidate.travelNote)
            }

            Divider().overlay(Wandr.hairline)
            factRow("indianrupeesign.circle", "Per head", priceDetail)

            if let offer = candidate.offer {
                Divider().overlay(Wandr.hairline)
                factRow("tag.fill", "Offer",
                        offer + (candidate.offerWindow.map { " · \($0)" } ?? ""))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(WandrCardBackground(fill: Wandr.cardSurface, corner: 20))
    }

    /// Mirrors the card's honesty rule: an absent price is "not listed", never ₹0.
    private var priceDetail: String {
        if candidate.costUnknown { return "Not listed" }
        if candidate.perHead == 0 { return "Free" }
        var line = "₹\(candidate.perHead)"
        if let savings = candidate.savings { line += " · ₹\(savings) under list" }
        return line
    }

    private func factRow(_ symbol: String, _ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(Wandr.secondaryText)
                .frame(width: 20, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .wandrLabelStyle()

                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(Wandr.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
    }

    private func section(
        _ title: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .wandrLabelStyle()
            content()
        }
    }

    // MARK: Chrome

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .tint(Wandr.cream)
        .padding(.trailing, 16)
        .padding(.top, 8)
        .accessibilityLabel("Close")
    }

    /// The same two outcomes the swipe offers, named — opening a card should
    /// never be a dead end you can only back out of.
    private var actionBar: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    onPass()
                    dismiss()
                } label: {
                    Label("Pass", systemImage: "arrow.uturn.forward")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glass)
                .tint(Wandr.ink)

                Button {
                    onKeep()
                    dismiss()
                } label: {
                    Label("Add to slate", systemImage: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
                .tint(accent)
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 8)
        }
    }
}

#Preview("Expanded") {
    CandidateDetailView(
        candidate: DemoPlan.decks[0].candidates[0],
        onKeep: {},
        onPass: {}
    )
}
