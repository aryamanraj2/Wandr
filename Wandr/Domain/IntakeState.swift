//
//  IntakeState.swift
//  Wandr
//
//  The trimmed, intake-only slice of the Docs `PlanningRun` state machine
//  (`Docs/AI-Orchestration-Flow.md`). This covers only the doorway: onboarding →
//  awaiting a Siri/Shortcut summary → host review → confirm/recover. The full
//  12-state coordinator (researching, validating, curating, …) is a later milestone.
//

import Foundation

/// Why the app landed on the recovery screen. Drives the copy shown to the host.
enum RecoveryReason: Sendable, Equatable {
    /// The summary text was empty or whitespace only.
    case emptySummary
    /// The handoff itself couldn't supply content (unsupported/unavailable).
    case handoffUnavailable

    var message: String {
        switch self {
        case .emptySummary:
            return "That summary came through empty. Ask Siri to send the summary to Wandr again."
        case .handoffUnavailable:
            return "Wandr didn't receive a summary. Ask Siri to send the summary to Wandr again."
        }
    }
}

/// The single source of truth for the intake surface. `IntakeInbox` owns and mutates it;
/// SwiftUI renders it.
enum IntakeState: Sendable, Equatable {
    /// First launch, before the host has set up the chat-import Shortcut.
    case onboarding
    /// Resting state: waiting for a summary to arrive through the intent.
    case awaitingSummary
    /// A summary arrived. Shown to the host for review before anything else happens.
    /// `payload` is present when the text decoded into the structured schema; `rawText`
    /// is always the exact volatile content, held only for this screen.
    case hostReview(payload: ChatSummaryPayload?, rawText: String)
    /// Nothing usable arrived. Host is invited to try the handoff again.
    case recovery(RecoveryReason)
    /// Host confirmed the summary. The structured brief is handed downstream to planning.
    case confirmed(ChatSummaryPayload)
}
