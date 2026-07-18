//
//  IntakeInbox.swift
//  Wandr
//
//  The single handoff point between the foreground App Intent and the SwiftUI shell.
//  Because `PlanOutingFromSiriSummaryIntent` runs in the app's own process (foreground
//  mode), the intent can hand its summary straight to this MainActor singleton, and
//  `RootView` — observing the same instance — reacts.
//
//  Privacy contract (Docs/AI-Integration-Blueprint.md): the raw handed-in text is held
//  only for Host Review and is discarded the moment the host confirms or cancels. It is
//  never written to disk.
//

import Foundation
import Observation

@MainActor
@Observable
final class IntakeInbox {

    /// Shared instance the intent writes to and the UI reads from.
    static let shared = IntakeInbox()

    /// The current intake state. `RootView` renders this.
    private(set) var state: IntakeState

    /// Whether the host has finished first-launch Shortcut setup. Persisted across launches.
    /// Kept here (rather than an `@AppStorage` in the view) so the intent can move past
    /// onboarding when a summary arrives before setup was ever completed.
    var hasCompletedShortcutSetup: Bool {
        didSet {
            guard oldValue != hasCompletedShortcutSetup else { return }
            UserDefaults.standard.set(hasCompletedShortcutSetup, forKey: Self.setupKey)
        }
    }

    private static let setupKey = "hasCompletedShortcutSetup"

    init() {
        let completedSetup = UserDefaults.standard.bool(forKey: Self.setupKey)
        self.hasCompletedShortcutSetup = completedSetup
        self.state = completedSetup ? .awaitingSummary : .onboarding
    }

    // MARK: - Intent entry point

    /// Called by the App Intent when a Siri/Shortcut summary arrives. Decodes the volatile
    /// text and routes to Host Review (structured or raw) or the recovery state.
    func receive(rawText: String) {
        switch ChatSummaryPayload.decode(from: rawText) {
        case .structured(let payload):
            state = .hostReview(payload: payload, rawText: rawText)
        case .unstructured(let text):
            state = .hostReview(payload: nil, rawText: text)
        case .empty:
            state = .recovery(.emptySummary)
        }
    }

    // MARK: - Host actions

    /// Host confirms the reviewed summary. Discards the raw text and hands the structured
    /// brief downstream. When only unstructured text was received there is no brief to pass,
    /// so an empty payload is forwarded — the downstream constraint chips are where the host
    /// fills the gaps in a later milestone.
    func confirm() {
        guard case .hostReview(let payload, _) = state else { return }
        state = .confirmed(payload ?? ChatSummaryPayload())
    }

    /// Host rejects the summary. Discards the raw text and returns to the resting state.
    func cancel() {
        state = .awaitingSummary
    }

    /// Host dismisses the recovery screen, back to waiting for another handoff.
    func returnToAwaiting() {
        state = .awaitingSummary
    }

    /// Marks first-launch setup complete and moves off the onboarding screen.
    func completeShortcutSetup() {
        hasCompletedShortcutSetup = true
        if case .onboarding = state {
            state = .awaitingSummary
        }
    }

    /// Re-opens onboarding from the resting state (the "Set up chat import" affordance).
    func openShortcutSetup() {
        state = .onboarding
    }
}
