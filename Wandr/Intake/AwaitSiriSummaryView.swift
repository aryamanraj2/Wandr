// AwaitSiriSummaryView.swift Wandr The resting state (Docs `awaitingSiriSummary`). Explains the one supported command and the chat-access boundary, and waits for a summary to arrive through the intent. Nothing here reads a chat or starts any work.

import SwiftUI
import AppIntents

struct AwaitSiriSummaryView: View {
    let inbox: IntakeInbox

    /// Three blocks, in the order a host needs them: what this screen is, the one thing to say, and
    /// — only if they ask — what Wandr is and is not allowed to see. The screen used to run seven
    /// blocks deep, with the Siri phrase written out three separate times (two quoted lines plus the
    /// tip that renders it again), which is what made a short page read as a dense one.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero

                command

                boundary
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
        .background(Wandr.pageBackground)
        .safeAreaBar(edge: .bottom) {
            actions
        }
        .tint(Wandr.brand)
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            // The mark sits in its own chip rather than floating as a loose glyph above the title.
            // A bare symbol at the top-left of a page reads as an unfinished icon slot; contained,
            // it reads as a mark.
            Image(systemName: "sparkles")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Wandr.brand)
                .frame(width: 42, height: 42)
                .background {
                    Circle().fill(Wandr.brand.opacity(0.10))
                }

            Text("Ready when the\ngroup chat is")
                .font(.wandrDisplay(36))
                // Display sizes need their leading pulled in or the two lines read as two headings.
                .lineSpacing(-2)
                .foregroundStyle(Wandr.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text("Ask Siri to send a summary of your group chat here. Wandr plans the night from that summary — and only that summary.")
                .font(.body)
                .foregroundStyle(Wandr.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // A little air under the hero so the headline owns the top of the page rather than being
        // one item in an evenly spaced stack.
        .padding(.bottom, 4)
    }

    // MARK: The one command

    /// `SiriTipView` is the canonical rendering of the phrase — it is the artefact a host can
    /// actually tap. So it is the only place the phrase appears at full weight; the alternate
    /// wording rides underneath as a caption instead of getting a section of its own.
    private var command: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Say to Siri")
                .wandrLabelStyle()

            SiriTipView(intent: PlanOutingFromSiriSummaryIntent())
                .siriTipViewStyle(.automatic)

            Text("“Use Wandr to plan this outing” works too.")
                .font(.footnote)
                .foregroundStyle(Wandr.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Boundary

    /// The privacy promise, kept accurate now that there is a second doorway. This card used to read
    /// "Wandr never reads your chats, contacts, or mic." That was true when Siri was the only way
    /// in. It stopped being true the moment this screen grew a microphone button, and a privacy
    /// claim that is quietly false is worse than one that is merely narrow — so it now says exactly
    /// what holds: chats and contacts are still never read, and the mic is only ever on when the
    /// host presses it themselves. Folded rather than deleted: the headline claim stays visible on
    /// the page, the three clauses behind it are one tap away.
    private var boundary: some View {
        WandrFoldout(title: "Wandr never reads your chats", systemImage: "hand.raised.fill") {
            VStack(alignment: .leading, spacing: 12) {
                WandrPoint(systemImage: "person.2.slash",
                           text: "Your chats and contacts are never read by Wandr.")
                WandrPoint(systemImage: "mic.slash.fill",
                           text: "The mic only listens when you tap it, and stops when you're done.")
                WandrPoint(systemImage: "checkmark.seal.fill",
                           text: "Siri does the listening; you approve what comes through.")
            }
        }
    }

    // MARK: Actions

    /// One primary route and one plain link, not two full-width slabs. Two equally weighted buttons
    /// stacked at the bottom of a page make the host choose before they know what either does; this
    /// says "start here" and leaves setup as the quieter option it actually is.
    private var actions: some View {
        VStack(spacing: 6) {
            // A host with no group chat to summarise still has an outing to plan, and this is the
            // only route that does not require a Shortcut, Siri, or a chat to exist at all.
            Button {
                inbox.beginCapture()
            } label: {
                Label("Tell Wandr yourself", systemImage: "mic.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(Wandr.brand)

            Button("Set up chat import") {
                inbox.openShortcutSetup()
            }
            .font(.subheadline.weight(.medium))
            .buttonStyle(.plain)
            .foregroundStyle(Wandr.brand)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.bottom, 4)
    }
}

#Preview {
    AwaitSiriSummaryView(inbox: IntakeInbox())
}
