// CandidateDetailView.swift Wandr The expanded card. A long press on a card in the deck grows it into this — same photograph, same caption, same shape, just larger and with everything the deck deliberately withholds. The deck is a snap judgement: name, look, price, one line. Everything here is the second look. The hero is literally `CandidateCardFace`, the same view the card was drawing a frame earlier, so the zoom reads as one object growing rather than one view dissolving into another.
//
// The page is `paper`, not the app's usual `haze`. Everywhere else a card is paper lifted off a haze
// page; here the card *is* the page — it grew into the whole screen — so the hero's caption panel and
// the copy beneath it have to be one continuous sheet. On a haze page they were not: the panel ends
// in near-white and the page resumed twenty tone-steps darker, which drew a hard rule straight across
// the screen at the exact point the eye leaves the photograph. Inverting the two makes the join
// invisible and gives the quiet blocks below something to be quiet *against*.

import SwiftUI

struct CandidateDetailView: View {
    let candidate: Candidate
    var onKeep: () -> Void
    var onPass: () -> Void

    @Environment(\.dismiss) private var dismiss
    /// The spec table is a two-column grid, and a fixed label column cannot survive an accessibility
    /// text size. At those sizes it becomes stacked rows instead of being squeezed into a sliver.
    @Environment(\.dynamicTypeSize) private var typeSize

    private var accent: Color { Wandr.accent(for: candidate.category) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                body_
            }
        }
        .background(Wandr.paper)
        .scrollEdgeEffectStyle(.soft, for: .top)
        // The action bar floats over the copy; without this the last spec row runs under the glass
        // with a hard edge instead of falling away beneath it.
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .overlay(alignment: .topTrailing) { closeButton }
        .safeAreaBar(edge: .bottom) { actionBar }
    }

    // MARK: Hero

    /// Sized to the same share of the screen the deck card occupied, so the growth is a scale rather than a reshape — the caption lands where the eye left it instead of jumping up the page.
    private var hero: some View {
        CandidateCardFace(candidate: candidate, isHero: true)
            .containerRelativeFrame(.vertical) { height, _ in
                min(max(height * 0.5, 320), 480)
            }
            .clipped()
    }

    // MARK: Body

    /// Reading order, and it is deliberate: why we picked it, what kind of room it is, what it is
    /// like, what to watch out for, and only then the numbers. The numbers come last because the
    /// hero already stated them — down here they are reference, not news.
    private var body_: some View {
        VStack(alignment: .leading, spacing: 30) {
            if let rationale = candidate.rationale {
                reason(rationale)
            }

            if !atmosphere.isEmpty {
                WandrWrap(spacing: 8, lineSpacing: 8) {
                    ForEach(atmosphere, id: \.self, content: chip)
                }
            }

            if let story = candidate.story {
                section("The place") {
                    Text(story)
                        .font(.callout)
                        .lineHeight(.loose)
                        .foregroundStyle(Wandr.primaryText.opacity(0.86))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !candidate.highlights.isEmpty {
                section("What you get") { highlightList }
            }

            if let tip = candidate.insiderTip {
                insiderTip(tip)
            }

            if !candidate.warnings.isEmpty {
                section("Worth knowing") { caveats }
            }

            section("The details") { specSheet }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Why

    /// Model prose, clearly attributed and clearly quoted. On the card this is a two-line aside that
    /// the eye skips; here it is the first thing on the page, because it is the one line explaining
    /// why this venue is in front of you at all.
    ///
    /// Set in charcoal rather than the accent. The accent italic at this size — a full-width block of
    /// terracotta type — read as an error message rather than as a considered opinion, which is the
    /// opposite of what it is. The colour moves to the rule and the label, where it attributes the
    /// quote without shouting it.
    private func reason(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Capsule()
                .fill(accent.opacity(0.5))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 9) {
                Text("Why Wandr picked this")
                    .wandrLabelStyle(accent)

                Text(text)
                    .font(.system(size: 17).italic())
                    .lineHeight(.loose)
                    .foregroundStyle(Wandr.primaryText.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Atmosphere

    /// The provider's own words for the room, plus whether it has a roof. Three or four short chips
    /// are the only thing on this page that says what *kind* of evening this is, and they say it
    /// faster than any sentence — which is why they sit directly under the reason rather than being
    /// buried as two more rows in the spec table.
    private var atmosphere: [String] {
        var words = candidate.vibeTags.map { $0.prefix(1).uppercased() + $0.dropFirst() }
        if let setting = candidate.setting { words.append(setting.label) }
        return words
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Wandr.slate)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(Capsule().fill(Wandr.haze))
    }

    // MARK: Prose blocks

    private var highlightList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(candidate.highlights, id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Circle()
                        .fill(accent)
                        .frame(width: 5, height: 5)
                        // Baseline-aligned text puts a bare circle slightly high; this drops it onto the x-height where it reads as a bullet.
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

    /// The one block that earns a surface of its own — it is the piece of the expanded card a reader would actually screenshot.
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
        .background(quietSurface)
    }

    /// The validator's caveats. Grouped onto one surface rather than floated as loose lines: a
    /// warning that shares the page's background reads as body copy, and these are the sentences a
    /// host most needs to notice before adding a place to the slate. Slate rather than red — every
    /// one of these is a fact about the listing, not a failure.
    private var caveats: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(candidate.warnings, id: \.self) { warning in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Wandr.slate.opacity(0.65))

                    Text(warning)
                        .font(.subheadline)
                        .lineHeight(.tight)
                        .foregroundStyle(Wandr.primaryText.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(quietSurface)
    }

    /// A block set into the paper rather than raised off it. On a paper page a raised card has
    /// nowhere to go — it would need a stroke to exist at all, and a page of stroked boxes is what
    /// this screen looked like before.
    private var quietSurface: some View {
        ConcentricRectangle(corners: .concentric(minimum: .fixed(18)))
            .fill(Wandr.haze)
    }

    // MARK: Details

    /// Every stated fact about the venue, as a spec table.
    ///
    /// This replaces a card that repeated the hero verbatim — hours, price and offer were on screen
    /// twice, forty points apart, and the second copy was the largest object on the page. Ruled rows
    /// let the same reference material sit quietly at the foot of the page, and leave room for the
    /// things the hero has no space for: what the provider actually surveyed.
    private var specSheet: some View {
        VStack(spacing: 0) {
            ForEach(Array(specs.enumerated()), id: \.element.id) { index, spec in
                if index > 0 {
                    Divider().overlay(Wandr.hairline)
                }
                specRow(spec)
            }
        }
    }

    private struct Spec: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    private var specs: [Spec] {
        var rows = [Spec(label: "Hours", value: candidate.openWindow)]

        if !candidate.travelNote.isEmpty {
            rows.append(Spec(label: "Getting there", value: candidate.travelNote))
        }

        rows.append(Spec(label: "Per head", value: priceDetail))

        if let offer = candidate.offer {
            rows.append(
                Spec(label: "Offer",
                     value: offer + (candidate.offerWindow.map { " · \($0)" } ?? ""))
            )
        }

        rows.append(Spec(label: "Dietary", value: provision(candidate.dietary)))
        rows.append(Spec(label: "Access", value: provision(candidate.access)))
        return rows
    }

    /// Mirrors the card's honesty rule: an absent price is "not listed", never ₹0.
    private var priceDetail: String {
        if candidate.costUnknown { return "Not listed" }
        if candidate.perHead == 0 { return "Free" }
        var line = "₹\(candidate.perHead)"
        if let savings = candidate.savings { line += " · ₹\(savings) under list" }
        return line
    }

    /// The same three-state rule the evidence layer keeps: a venue nobody surveyed is *unverified*,
    /// which is not the same as a venue surveyed and found to have nothing. Saying "None listed" for
    /// an unchecked kitchen would be the app inventing a fact in the one place it must not.
    private func provision(_ names: [String]?) -> String {
        guard let names else { return "Not verified" }
        return names.isEmpty ? "None listed" : names.joined(separator: ", ")
    }

    @ViewBuilder
    private func specRow(_ spec: Spec) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                Text(spec.label).wandrLabelStyle()
                specValue(spec.value)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 13)
        } else {
            HStack(alignment: .top, spacing: 16) {
                Text(spec.label)
                    .wandrLabelStyle()
                    // Optically aligns the small caps with the first line of the value beside it.
                    .padding(.top, 3)
                    // Wide enough for the longest label to hold one line: a table where a single
                    // row's label wraps and the rest do not stops reading as a table.
                    .frame(width: 106, alignment: .leading)

                specValue(spec.value)
            }
            .padding(.vertical, 13)
        }
    }

    private func specValue(_ value: String) -> some View {
        Text(value)
            .font(.subheadline)
            .lineHeight(.tight)
            .foregroundStyle(Wandr.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func section(
        _ title: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .wandrLabelStyle()
            content()
        }
    }

    // MARK: Chrome

    /// Takes the same surface as the area tag at the other corner of the photograph — a dark wash
    /// under thin glass — rather than the system's light glass. Light glass on a lit photograph is
    /// where the button was disappearing: a pale glyph on a pale blur with nothing behind it to push
    /// against.
    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Wandr.cream)
                .frame(width: 34, height: 34)
                .background(Circle().fill(.ultraThinMaterial.opacity(0.55)))
                .background(Circle().fill(Wandr.charcoal.opacity(0.34)))
                // Buys the 44pt target back around a 34pt circle.
                .padding(6)
                .contentShape(Circle())
        }
        .buttonStyle(WandrPressStyle())
        .padding(.trailing, 10)
        .padding(.top, 4)
        .accessibilityLabel("Close")
    }

    /// The same two outcomes the swipe offers, named — opening a card should never be a dead end you can only back out of.
    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                onPass()
                dismiss()
            } label: {
                actionLabel("Pass", systemImage: "arrow.uturn.forward")
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .tint(Wandr.brand)

            Button {
                onKeep()
                dismiss()
            } label: {
                actionLabel("Add to slate", systemImage: "checkmark")
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            // The card's own accent rather than the app's indigo: this button *is* the card, and the
            // deck already promised that colour on the swipe-right wash.
            .tint(accent)
        }
        .padding(.horizontal, Metrics.gutter)
        // Deep enough that the wash is already opaque where the buttons begin. A shallower bar puts
        // the top of the capsules inside the fade, which is where the ghost of a passing spec row
        // shows through them.
        .padding(.top, 30)
        .padding(.bottom, 8)
        .background(alignment: .bottom) { barBackdrop }
    }

    /// A verb, and a glyph when there is room for one.
    ///
    /// At an accessibility text size the icon is as large as the words and takes half the capsule,
    /// which leaves "Add to slate" truncating to "Add to…" — the button loses the noun it is named
    /// for. The glyph is decoration on a labelled button, so it is the part that goes.
    @ViewBuilder
    private func actionLabel(_ title: String, systemImage: String) -> some View {
        Group {
            if typeSize.isAccessibilitySize {
                Text(title)
            } else {
                Label(title, systemImage: systemImage)
            }
        }
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
    }

    /// The floor the bar stands on.
    ///
    /// Two buttons alone over a scrolling page is not a bar — the copy travels between them and
    /// through the glass one, and a half-legible spec row sliding behind a button reads as a
    /// rendering fault rather than as content passing underneath. The scroll edge effect feathers
    /// that, but it feathers it into whatever is behind, and here that is the same near-white the
    /// type sits on, so there is nothing for the fade to resolve into.
    ///
    /// Haze rather than paper: it is the app's own page tone, it gives the glass Pass button
    /// something to be glass *against* — a near-white capsule on a near-white page is invisible —
    /// and it lands the bar as a distinct surface without a rule drawn across the screen to say so.
    private var barBackdrop: some View {
        LinearGradient(
            stops: [
                .init(color: Wandr.haze.opacity(0), location: 0),
                .init(color: Wandr.haze.opacity(0.62), location: 0.13),
                .init(color: Wandr.haze, location: 0.25),
                .init(color: Wandr.haze, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea(edges: .bottom)
    }
}

#Preview("Expanded") {
    CandidateDetailView(
        candidate: DemoPlan.decks[0].candidates[0],
        onKeep: {},
        onPass: {}
    )
}

#if DEBUG
#Preview("Curated — facts only") {
    CandidateDetailView(
        candidate: DebugScreen.curatedCandidate,
        onKeep: {},
        onPass: {}
    )
}
#endif
