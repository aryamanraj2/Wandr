//
//  RootView.swift
//  Wandr
//
//  Outings-only shell (D3 — no Trips tab in v1). Switches on the intake state machine
//  (`IntakeInbox`): first-launch setup → awaiting a Siri/Shortcut summary → host review
//  → confirm/recover. On confirm it hands off to curation, the existing downstream surface.
//
//  Once `TravelPlanningService` lands, this view switches on `PlanningRun.state`
//  (awaitingSiriSummary → hostReview → … → curating → approving). For the design
//  pass it opens straight onto curation, which is where the plan becomes visible.
//

import SwiftUI

struct RootView: View {
    @State private var inbox = IntakeInbox.shared

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var curating: Bool {
        if case .confirmed = inbox.state { return true }
        return false
    }

    var body: some View {
        Group {
            switch inbox.state {
            case .onboarding:
                ShortcutSetupView(inbox: inbox)
            case .awaitingSummary:
                AwaitSiriSummaryView(inbox: inbox)
            case .hostReview(let payload, let rawText):
                HostReviewView(inbox: inbox, payload: payload, rawText: rawText)
            case .recovery(let reason):
                RecoveryView(inbox: inbox, reason: reason)
            case .confirmed(let payload):
                // The confirmed summary now seeds the grounded pipeline: research the
                // dataset, let the on-device model pick places, validate, and open the
                // decks. `PlanningFlowView` owns that async lifecycle and its states.
                PlanningFlowView(payload: payload, inbox: inbox)
                    // Settling the last hair of scale, rather than sliding in: the plan
                    // was already on its way, this is it arriving.
                    .scaleEffect(reduceMotion ? 1 : (curating ? 1 : 1.015))
                    .transition(.opacity)
            }
        }
        .animation(stateAnimation, value: stateID)
    }

    /// Whichever screen is arriving waits for the other to clear; whichever is
    /// leaving goes immediately. Reads as a handoff in one direction rather
    /// than a symmetric crossfade.
    private var stateAnimation: Animation {
        curating ? .wandrStageIn : .wandrStageOut
    }

    /// A cheap identity for the state, so the container animates on transitions between
    /// screens without needing `IntakeState` itself to be `Hashable`.
    private var stateID: Int {
        switch inbox.state {
        case .onboarding:      return 0
        case .awaitingSummary: return 1
        case .hostReview:      return 2
        case .recovery:        return 3
        case .confirmed:       return 4
        }
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

/// Owns one planning run: it kicks off the grounded pipeline for the confirmed
/// summary and renders its three outcomes — working, decks ready, or a recoverable
/// failure. Separated from `RootView` so the async lifecycle has a stable identity.
private struct PlanningFlowView: View {
    let payload: ChatSummaryPayload
    let inbox: IntakeInbox

    @State private var coordinator = PlanningCoordinator()

    var body: some View {
        Group {
            switch coordinator.phase {
            case .idle, .planning:
                PlanningProgressView()
            case .ready(let output, let groupSize):
                CurationView(
                    decks: output.decks,
                    groupSize: groupSize,
                    banner: output.banner,
                    slotWindows: output.slotWindows
                )
            case .failed(let failure):
                PlanningFailureView(
                    failure: failure,
                    onRetry: { Task { await coordinator.run(payload: payload) } },
                    onStartOver: { inbox.cancel() }
                )
            }
        }
        .task {
            // Run once when the confirmed summary first appears.
            if case .idle = coordinator.phase {
                await coordinator.run(payload: payload)
            }
        }
    }
}

/// The wait while the dataset is researched and the on-device model picks places.
private struct PlanningProgressView: View {
    var body: some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)
            VStack(spacing: 4) {
                Text("Planning your night")
                    .font(.headline)
                    .foregroundStyle(Wandr.primaryText)
                Text("Picking places for your group…")
                    .font(.subheadline)
                    .foregroundStyle(Wandr.primaryText.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Wandr.pageBackground)
    }
}

/// A recoverable planning failure, with the structured message and the next step.
private struct PlanningFailureView: View {
    let failure: PlanningFailure
    let onRetry: () -> Void
    let onStartOver: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Wandr.primaryText.opacity(0.7))

            Text(failure.userMessage)
                .font(.title3.weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(Wandr.primaryText)
                .padding(.horizontal, 32)

            VStack(spacing: 12) {
                if failure.isRecoverable {
                    Button(action: onRetry) {
                        Text("Try again")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Wandr.ink)
                }

                Button("Start over", action: onStartOver)
                    .font(.subheadline.weight(.medium))
                    .tint(Wandr.ink)
            }
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Wandr.pageBackground)
    }
}

/// Preview-only shell that drives the intake screens from a freshly configured inbox
/// rather than the shared singleton, so each preview shows a distinct state.
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
            case .awaitingSummary:
                AwaitSiriSummaryView(inbox: inbox)
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
