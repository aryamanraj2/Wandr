//
//  HostReviewView.swift
//  Wandr
//
//  Docs `hostReview`: the exact summary that came through, shown for approval before
//  any planning starts. This is where the "final JSON summary" becomes visible — the
//  structured brief the group settled on. The host confirms (planning begins) or
//  cancels (the volatile summary is discarded). Nothing here reads a chat or runs a model.
//

import SwiftUI

struct HostReviewView: View {
    let inbox: IntakeInbox
    /// The structured summary, when the text decoded into Wandr's schema.
    let payload: ChatSummaryPayload?
    /// The exact volatile text that arrived — always available, held only for this screen.
    let rawText: String

    @State private var showingRaw = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                if let payload, !payload.displayFields.isEmpty {
                    structuredCard(payload)
                } else {
                    unstructuredCard
                }

                rawDisclosure

                Color.clear.frame(height: 12)
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 12)
        }
        .background(Wandr.pageBackground)
        .safeAreaBar(edge: .bottom) { actionBar }
        .tint(Wandr.ink)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Here’s what came through")
                .font(.wandrDisplay(32))
                .foregroundStyle(Wandr.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text("Only this summary crossed into Wandr — no chat, no contacts. Check it over before planning starts.")
                .font(.subheadline)
                .foregroundStyle(Wandr.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Structured

    private func structuredCard(_ payload: ChatSummaryPayload) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(payload.displayFields.enumerated()), id: \.offset) { index, field in
                if index != 0 {
                    Divider().overlay(Wandr.hairline)
                }
                HStack(alignment: .top, spacing: 12) {
                    Text(field.label)
                        .wandrLabelStyle()
                        .frame(width: 108, alignment: .leading)
                    Text(field.value)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Wandr.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 12)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 4)
        .background(WandrCardBackground())
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
        .background(WandrCardBackground())
    }

    // MARK: Raw JSON disclosure

    @ViewBuilder
    private var rawDisclosure: some View {
        // Only meaningful when we actually parsed structured JSON — otherwise the card above
        // already shows the raw text.
        if let payload, !payload.displayFields.isEmpty {
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
            .tint(Wandr.ink)
            .padding(.horizontal, 4)
        }
    }

    // MARK: Actions

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button(role: .cancel) {
                inbox.cancel()
            } label: {
                Text("Discard")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.glass)

            Button {
                inbox.confirm()
            } label: {
                Label("Plan this", systemImage: "arrow.forward")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
        }
        .tint(Wandr.ink)
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
            budgetPerHead: "₹1200",
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
