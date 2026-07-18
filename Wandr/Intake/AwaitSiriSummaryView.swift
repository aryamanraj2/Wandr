//
//  AwaitSiriSummaryView.swift
//  Wandr
//
//  The resting state (Docs `awaitingSiriSummary`). Explains the one supported command
//  and the chat-access boundary, and waits for a summary to arrive through the intent.
//  Nothing here reads a chat or starts any work.
//

import SwiftUI
import AppIntents

struct AwaitSiriSummaryView: View {
    let inbox: IntakeInbox

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                boundaryCard

                howItWorks

                SiriTipView(intent: PlanOutingFromSiriSummaryIntent())
                    .siriTipViewStyle(.automatic)

                Color.clear.frame(height: 12)
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 12)
        }
        .background(Wandr.pageBackground)
        .safeAreaBar(edge: .bottom) {
            Button {
                inbox.openShortcutSetup()
            } label: {
                Label("Set up chat import", systemImage: "square.and.arrow.down.on.square")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.glass)
            .tint(Wandr.ink)
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 8)
        }
        .tint(Wandr.ink)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Wandr.accent(for: .nightlife))

            Text("Ready when the\ngroup chat is")
                .font(.wandrDisplay(38))
                .foregroundStyle(Wandr.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text("Ask Siri, or run the Wandr shortcut, to send a summary of your group chat here. Wandr plans the night from the summary — and only the summary.")
                .font(.body)
                .foregroundStyle(Wandr.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var boundaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The boundary")
                .wandrLabelStyle(Wandr.accent(for: .sights))

            Label("Wandr never reads your chats, contacts, or mic.", systemImage: "hand.raised.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Wandr.primaryText)

            Label("Siri does the listening; you approve what comes through.", systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Wandr.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(WandrCardBackground())
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Say to Siri")
                .wandrLabelStyle()

            ForEach(Self.phrases, id: \.self) { phrase in
                HStack(spacing: 10) {
                    Image(systemName: "quote.opening")
                        .font(.caption)
                        .foregroundStyle(Wandr.secondaryText)
                    Text(phrase)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Wandr.primaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static let phrases = [
        "“Plan this group outing in Wandr”",
        "“Use Wandr to plan this outing”"
    ]
}

#Preview {
    AwaitSiriSummaryView(inbox: IntakeInbox())
}
