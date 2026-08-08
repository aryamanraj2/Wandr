// AwaitSiriSummaryView.swift Wandr The resting state (Docs `awaitingSiriSummary`). Explains the one supported command and the chat-access boundary, and waits for a summary to arrive through the intent. Nothing here reads a chat or starts any work.

import SwiftUI
import AppIntents

struct AwaitSiriSummaryView: View {
    let inbox: IntakeInbox

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var arrived = false

    /// Two blocks, in the order a host needs them: the one thing to say, and — only if they ask —
    /// what Wandr is and is not allowed to see.
    ///
    /// The screen used to open with a `sparkles` glyph in a tinted circle. It was the only mark of
    /// its kind in the app, it stood for nothing in particular, and a decorative badge above a title
    /// is the exact thing a page does when it has not decided what it is about. The title is the
    /// mark now.
    var body: some View {
        Group {
            // Everything here fits on a phone at normal text sizes, and a `ScrollView` that never
            // scrolls costs the layout its ability to *place* things — every spacer collapses and
            // the content stacks at the top, which is how this screen ended up with its whole bottom
            // half empty. It only becomes scrollable at the sizes where it genuinely has to.
            if typeSize.isAccessibilitySize {
                // Without dropping the `maxHeight: .infinity` below, the content would be pinned to
                // the viewport's height inside the scroll view and could never grow past it — which
                // is the one thing it has to do here.
                ScrollView { content(fills: false) }
            } else {
                content(fills: true)
            }
        }
        .background(Wandr.pageBackground)
        // This screen's entire job is waiting for something to arrive from outside the app. A slow
        // breath at the border is that state, stated — and it is the same signal the capture screen
        // uses when it is listening, one step quieter.
        .wandrEdgeGlow(.resting)
        .onAppear { arrived = true }
        .safeAreaBar(edge: .bottom) {
            actions
        }
        .tint(Wandr.brand)
    }

    private func content(fills: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            WandrMasthead(
                title: "Ready when the group chat is",
                // "Wandr plans the night from that summary" was the old line. It does not know that
                // it is a night — the same summary might be a lunch or an afternoon — and the claim
                // this sentence exists to make is about the *boundary*, which does not depend on
                // what time of day it is.
                deck: "Ask Siri to send a summary of your group chat here. Wandr plans from that summary — and only that summary."
            )
            .entrance(arrived, index: 0, reduceMotion: reduceMotion)

            // One flexible gap, low down. The command and the boundary belong together just above
            // the buttons that act on them; the air belongs under the masthead, where it reads as
            // room rather than as a page that ran out of content.
            Spacer(minLength: 40)

            command
                .entrance(arrived, index: 1, reduceMotion: reduceMotion)

            boundary
                .padding(.top, 22)
                .entrance(arrived, index: 2, reduceMotion: reduceMotion)

            // A fixed counterweight rather than a second flexible spacer. Two spacers would split
            // the slack evenly and drop the block back toward the middle; this lifts it a fixed
            // distance clear of the action bar, so the boundary card and the button under it stop
            // reading as one stack of three controls.
            Color.clear.frame(height: 44)
        }
        .frame(maxWidth: .infinity, maxHeight: fills ? .infinity : nil, alignment: .top)
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 8)
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
        WandrFoldout(title: "Wandr never reads your chats", image: .wandrShieldCheck) {
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
                    .wandrActionLabel()
            }
            .wandrPrimaryAction()

            Button {
                inbox.openShortcutSetup()
            } label: {
                Label { Text("Set up chat import") } icon: { Image(.wandrChats) }
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
