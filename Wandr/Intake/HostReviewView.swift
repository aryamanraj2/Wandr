// HostReviewView.swift Wandr Docs `hostReview`: the exact summary that came through, shown for approval before any planning starts. This is where the "final JSON summary" becomes visible — the structured brief the group settled on. The host confirms (planning begins) or cancels (the volatile summary is discarded). Nothing here reads a chat or runs a model.

import SwiftUI

struct HostReviewView: View {
    let inbox: IntakeInbox
    /// The structured summary, when the text decoded into Wandr's schema.
    let payload: ChatSummaryPayload?
    /// The exact volatile text that arrived — always available, held only for this screen.
    let rawText: String

    @State private var showingRaw = false

    /// The summary is the payoff of the whole Siri handoff — it arrives rather than being already
    /// there. Same staggered entrance the setup screen uses, so the two read as one flow.
    @State private var arrived = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                    .padding(.bottom, 10)
                    .entrance(arrived, index: 0, reduceMotion: reduceMotion)

                Group {
                    if let payload, !payload.displayFields.isEmpty {
                        structuredCard(payload)
                    } else {
                        unstructuredCard
                    }
                }
                .entrance(arrived, index: 1, reduceMotion: reduceMotion)

                rawDisclosure
                    .entrance(arrived, index: 2, reduceMotion: reduceMotion)

                Color.clear.frame(height: 12)
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 12)
        }
        .background(Wandr.pageBackground)
        .safeAreaBar(edge: .bottom) { actionBar }
        .tint(Wandr.brand)
        .onAppear { arrived = true }
    }

    // MARK: Header

    private var header: some View {
        WandrMasthead(
            title: "Here’s what came through",
            deck: "Only this summary crossed into Wandr — no chat, no contacts. Check it over before planning starts.",
            size: 42
        )
    }

    // MARK: Structured

    /// The group's own decisions, set as a plain two-column table.
    ///
    /// Two earlier attempts, both wrong in opposite directions. First a white card of label/value
    /// rows with a fixed label column and a divider between each — the layout iOS uses for
    /// *preferences*, which is not what these are. Then the same grid with a hairline drawn over
    /// every cell, which turned nine short facts into nine ruled boxes: more lines on the page than
    /// words on some rows, and an orphan rule hanging beside the empty half of the last one.
    ///
    /// So: no rules at all. Space does the separating. A small label over a large value is already
    /// an unambiguous pair, and nine of them in a column grid already reads as a table — drawing the
    /// table as well was saying the same thing twice.
    private func structuredCard(_ payload: ChatSummaryPayload) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 20, alignment: .topLeading),
                GridItem(.flexible(), spacing: 20, alignment: .topLeading)
            ],
            alignment: .leading,
            spacing: 28
        ) {
            ForEach(Array(payload.displayFields.enumerated()), id: \.offset) { _, field in
                VStack(alignment: .leading, spacing: 6) {
                    Text(field.label)
                        .wandrLabelStyle()

                    Text(field.value)
                        .font(.wandrTitle(19))
                        .foregroundStyle(Wandr.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: Unstructured

    private var unstructuredCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Unstructured summary", systemImage: "text.alignleft")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Wandr.primaryText)

            Text(rawText)
                .font(.callout)
                .foregroundStyle(Wandr.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            Text("This came through as plain text. Install the Wandr shortcut for a cleaner, structured summary next time.")
                .font(.caption)
                .foregroundStyle(Wandr.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(WandrCardBackground(corner: Metrics.blockCorner))
    }

    // MARK: Raw JSON disclosure

    @ViewBuilder
    private var rawDisclosure: some View {
        // Only meaningful when we actually parsed structured JSON — otherwise the card above already shows the raw text.
        if let payload, !payload.displayFields.isEmpty {
            // The page's one rule, and it earns it: it is the line between what the host reads and
            // what they almost certainly will not. Without it the disclosure read as a tenth field.
            Rectangle()
                .fill(Wandr.hairline)
                .frame(height: 1)
                .padding(.top, 10)

            DisclosureGroup(isExpanded: $showingRaw) {
                Text(rawText)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Wandr.secondaryText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
            } label: {
                Text("Raw JSON")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Wandr.primaryText)
            }
            .tint(Wandr.brand)
            .padding(.horizontal, 4)
        }
    }

    // MARK: Actions

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button(role: .cancel) {
                inbox.cancel()
            } label: {
                Text("Discard").wandrActionLabel(.subheadline.weight(.semibold))
            }
            .wandrQuietAction()

            Button {
                inbox.confirm()
            } label: {
                Label("Plan this", systemImage: "arrow.forward").wandrActionLabel()
            }
            .wandrPrimaryAction()
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.bottom, 8)
    }
}

#Preview("Structured") {
    HostReviewView(
        inbox: IntakeInbox(),
        payload: ChatSummaryPayload(
            outingType: .afterOffice,
            dateOrDay: "Friday",
            time: "8pm, finish by 11",
            area: "Hauz Khas",
            groupSize: 6,
            budget: "₹1200 each",
            dietary: "2 vegetarian",
            vibe: "Chill, live music",
            indoorOutdoor: "Indoor if it rains"
        ),
        rawText: "{ \"outingType\": \"after-office\" }"
    )
}

#Preview("Unstructured") {
    HostReviewView(
        inbox: IntakeInbox(),
        payload: nil,
        rawText: "Friday night, Hauz Khas, around 6 of us, keep it under 1200 a head."
    )
}
