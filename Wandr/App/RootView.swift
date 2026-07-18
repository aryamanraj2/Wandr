//
//  RootView.swift
//  Wandr
//
//  Outings-only shell (D3 — no Trips tab in v1). Switches on the intake state machine
//  (`IntakeInbox`): first-launch setup → awaiting a Siri/Shortcut summary → host review
//  → confirm/recover. On confirm it hands off to curation, the existing downstream surface.
//
//  The full `PlanningRun` coordinator (researching, validating, curating, …) replaces
//  the `.confirmed` branch in a later milestone; today it opens the design-pass curation.
//

import SwiftUI

struct RootView: View {
    @State private var inbox = IntakeInbox.shared

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
                // Downstream planning/curation. The confirmed brief will seed the
                // coordinator here once it lands; for now it opens the curation surface.
                CurationView()
            }
        }
        .animation(.wandrTransition, value: stateID)
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
