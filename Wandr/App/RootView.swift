// RootView.swift Wandr Outings-only shell (D3 — no Trips tab in v1); switches on IntakeInbox's state machine from onboarding through host review to confirm/recover, then hands off to curation.

import SwiftUI

struct RootView: View {
    @State private var inbox = IntakeInbox.shared

    /// The other way into the app. Someone who was handed a code never ran intake — no Shortcut, no summary, no curation — so for them the room *is* the app, and it takes the whole screen.
    @State private var room = SquadRoom.shared
    @State private var showJoin = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var curating: Bool {
        if case .confirmed = inbox.state { return true }
        return false
    }

    /// Only once the room has actually answered. Between the tap and the first snapshot the join screen owns the moment, and yanking it away mid-connect would leave nothing to report a bad code against.
    private var joined: Bool {
        room.role == .joiner && room.snapshot != nil
    }

    /// The door is only worth showing where a code is the *only* thing that could happen next: the two resting states before intake begins. Anywhere further in, the host is mid-plan and a join would throw it away.
    private var canJoin: Bool {
        switch inbox.state {
        case .onboarding, .awaitingSummary: return true
        default: return false
        }
    }

    var body: some View {
        Group {
            if joined {
                SquadFlowView(room: room)
                    .transition(.opacity)
            } else {
                shell
            }
        }
        .animation(.wandrTransition, value: joined)
        .sheet(isPresented: $showJoin) {
            JoinCodeView(room: room)
        }
    }

    private var shell: some View {
        Group {
            switch inbox.state {
            case .onboarding:
                ShortcutSetupView(inbox: inbox)
                    .transition(.wandrStage)
            case .awaitingSummary:
                AwaitSiriSummaryView(inbox: inbox)
                    .transition(.wandrStage)
            case .capturing:
                // The speak-or-type doorway: PlanCaptureView hands back raw words, extracted on-device, rejoining the Siri path at Host Review.
                PlanCaptureView(
                    onCommit: { text in
                        Task { await inbox.captureFreeText(text) }
                    },
                    onCancel: { inbox.cancelCapture() }
                )
                .transition(.wandrStage)
            case .extracting:
                ExtractingSummaryView()
                    .transition(.wandrStage)
            case .hostReview(let payload, let rawText):
                HostReviewView(inbox: inbox, payload: payload, rawText: rawText)
                    .transition(.wandrStage)
            case .recovery(let reason):
                RecoveryView(inbox: inbox, reason: reason)
                    .transition(.wandrStage)
            case .confirmed(let payload):
                // The confirmed summary seeds the grounded pipeline; PlanningFlowView owns that async lifecycle and its states.
                PlanningFlowView(payload: payload, inbox: inbox)
                    // Settling the last hair of scale rather than sliding in: the plan was already on its way, this is it arriving.
                    .scaleEffect(reduceMotion ? 1 : (curating ? 1 : 1.015))
                    .transition(.wandrStage)
            }
        }
        .animation(stateAnimation, value: stateID)
        // A bar, not an overlay. As an overlay this floated over whatever the screen underneath put
        // at its top, which on the setup screen was the title — the pill sat across the words "chat
        // import". A bar *reserves* the space, so no screen can collide with it and none of them has
        // to leave a gap on the chance that it might.
        .safeAreaBar(edge: .top) {
            if canJoin { joinDoor }
        }
        .animation(.wandrResponse, value: canJoin)
    }

    /// Small, glass, and out of the way — the host's own path is the one this screen is really for. But without it a joiner has no way in at all, because the state machine below never starts for them.
    private var joinDoor: some View {
        Button {
            showJoin = true
        } label: {
            Label("Have a code?", systemImage: "person.2.wave.2")
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .tint(Wandr.brand)
        // Trailing rather than centred: it now has a row of its own, and a lone pill floating in the
        // middle of one reads as a title. Hard against the edge it reads as what it is — a way in
        // that is not this screen's business.
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, Metrics.gutter)
    }

    /// Arriving screen waits for the other to clear, leaving screen goes immediately — a one-directional handoff, not a symmetric crossfade.
    private var stateAnimation: Animation {
        curating ? .wandrStageIn : .wandrStageOut
    }

    /// A cheap identity for the state so the container animates transitions without `IntakeState` needing to be `Hashable`.
    private var stateID: Int {
        switch inbox.state {
        case .onboarding:      return 0
        case .awaitingSummary: return 1
        case .capturing:       return 5
        case .extracting:      return 6
        case .hostReview:      return 2
        case .recovery:        return 3
        case .confirmed:       return 4
        }
    }
}

// MARK: - Extraction

/// The wait while the on-device model turns what the host said into the same structured summary the Shortcut would produce.
///
/// No stage is passed, and that is the honest answer rather than an omission: this is one
/// `FreeTextSummaryExtractor` call with no phases inside it to report. `WandrThinkingView` leaves
/// its track empty in that case, so the screen shows activity without claiming a position.
private struct ExtractingSummaryView: View {
    var body: some View {
        WandrThinkingView(
            title: "Reading\nthat back",
            caption: "Pulling out the details you gave"
        )
    }
}

#Preview("Onboarding") {
    RootView_PreviewHost { $0.openShortcutSetup() }
}

#Preview("Awaiting") {
    RootView_PreviewHost { $0.completeShortcutSetup() }
}

#Preview("Host review") {
    RootView_PreviewHost {
        $0.receive(rawText: #"{"outingType":"birthday","area":"CP","groupSize":8,"budgetPerHead":"₹1500","vibe":"loud and fun"}"#)
    }
}

#Preview("Recovery") {
    RootView_PreviewHost { $0.receive(rawText: "   ") }
}

#Preview("Curation") {
    CurationView()
}

// MARK: - Planning flow

/// Owns one planning run: kicks off the grounded pipeline and renders its three outcomes (working, decks ready, recoverable failure); separated from `RootView` for a stable async lifecycle identity.
private struct PlanningFlowView: View {
    let payload: ChatSummaryPayload
    let inbox: IntakeInbox

    @State private var coordinator = PlanningCoordinator()

    var body: some View {
        Group {
            switch coordinator.phase {
            case .idle, .planning:
                PlanningProgressView(stage: coordinator.stage)
                    .transition(.wandrStage)
            case .ready(let output, let groupSize):
                CurationView(
                    decks: output.decks,
                    groupSize: groupSize,
                    banner: output.banner,
                    slotWindows: output.slotWindows
                )
                .transition(.wandrStage)
            case .failed(let failure):
                PlanningFailureView(
                    failure: failure,
                    onRetry: { Task { await coordinator.run(payload: payload) } },
                    onStartOver: { inbox.cancel() }
                )
                .transition(.wandrStage)
            }
        }
        // This switch was a hard cut, and it was the one cut in the app that mattered most: the
        // longest wait in the flow ended by the wait screen vanishing between two frames and the
        // plan being there instead. Every other step of intake hands over with `.wandrStage`; the
        // payoff was the only one that did not, which made the arrival read as a glitch rather than
        // as the thing the host had been waiting through.
        .animation(phaseAnimation, value: phaseID)
        .task {
            // Run once when the confirmed summary first appears.
            if case .idle = coordinator.phase {
                await coordinator.run(payload: payload)
            }
        }
    }

    /// The same one-directional handoff `RootView` uses: the plan arriving is worth holding back
    /// until the wait has cleared, a failure is not — it should replace what it corrects promptly.
    private var phaseAnimation: Animation {
        if case .ready = coordinator.phase { return .wandrStageIn }
        return .wandrStageOut
    }

    /// A cheap identity for the phase, so the container can animate on it without `Phase` needing to
    /// be `Equatable` — its payloads are decks and failures, neither of which has any business
    /// conforming for a transition's sake.
    private var phaseID: Int {
        switch coordinator.phase {
        case .idle, .planning: return 0
        case .ready:           return 1
        case .failed:          return 2
        }
    }
}

/// The wait while the dataset is researched and the on-device model picks places.
///
/// The masthead used to read "Planning your night". It does not any more, because the pipeline does
/// not know that: the same run plans a lunch, an afternoon walk, and a birthday, and which one it is
/// lives in the brief this screen has not seen. One word it can stand behind beats three it cannot.
private struct PlanningProgressView: View {
    let stage: PlanningState

    var body: some View {
        WandrThinkingView(title: "Planning", stage: stage)
    }
}

/// A recoverable planning failure, with the structured message and the next step.
///
/// Same masthead and same left margin as the wait it replaces, so a run that fails reads as the
/// screen the host was already on changing its mind, not as an error page arriving from somewhere
/// else. The warning triangle is gone: the sentence under the title already says what happened, and
/// a 40pt glyph above it only makes a recoverable stall look like a crash.
private struct PlanningFailureView: View {
    let failure: PlanningFailure
    let onRetry: () -> Void
    let onStartOver: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            WandrMasthead(title: "No plan yet", deck: failure.userMessage, size: 44)

            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, Metrics.gutter)
        .background(Wandr.pageBackground)
        .safeAreaBar(edge: .bottom) {
            VStack(spacing: 6) {
                if failure.isRecoverable {
                    Button(action: onRetry) {
                        Text("Try again").wandrActionLabel()
                    }
                    .wandrPrimaryAction()
                }

                Button("Start over", action: onStartOver)
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
}

/// Preview-only shell that drives the intake screens from a freshly configured inbox rather than the shared singleton, so each preview shows a distinct state.
private struct RootView_PreviewHost: View {
    @State private var inbox: IntakeInbox

    init(configure: (IntakeInbox) -> Void) {
        let inbox = IntakeInbox()
        configure(inbox)
        _inbox = State(initialValue: inbox)
    }

    var body: some View {
        Group {
            switch inbox.state {
            case .onboarding:
                ShortcutSetupView(inbox: inbox)
                    .transition(.wandrStage)
            case .awaitingSummary:
                AwaitSiriSummaryView(inbox: inbox)
                    .transition(.wandrStage)
            case .capturing:
                PlanCaptureView(
                    onCommit: { text in
                        Task { await inbox.captureFreeText(text) }
                    },
                    onCancel: { inbox.cancelCapture() }
                )
            case .extracting:
                ExtractingSummaryView()
            case .hostReview(let payload, let rawText):
                HostReviewView(inbox: inbox, payload: payload, rawText: rawText)
            case .recovery(let reason):
                RecoveryView(inbox: inbox, reason: reason)
            case .confirmed:
                CurationView()
            }
        }
    }
}
