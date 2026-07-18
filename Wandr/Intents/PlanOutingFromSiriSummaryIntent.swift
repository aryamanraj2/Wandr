//
//  PlanOutingFromSiriSummaryIntent.swift
//  Wandr
//
//  The one and only doorway into Wandr (Docs/plan.md §6.1). A Siri phrase or the
//  Wandr chat-import Shortcut supplies a summary of a group conversation; the intent
//  foregrounds the app and hands that summary to Host Review. Wandr never reads the
//  chat itself — only the summary the host explicitly asked to send.
//
//  Both intake channels (the Wandr Shortcut's `Use Model` JSON, and a plain
//  conversational Siri request) converge on this single `summary` parameter; the
//  intent cannot tell them apart and does not need to.
//

import AppIntents
import Foundation

struct PlanOutingFromSiriSummaryIntent: AppIntent {

    static var title: LocalizedStringResource = "Plan Outing from Summary"

    static var description = IntentDescription(
        "Hands a summary of your group chat to Wandr, which plans the outing. Wandr never reads the chat itself.",
        categoryName: "Planning"
    )

    /// Appears in the Shortcuts app and Spotlight.
    static var isDiscoverable: Bool = true

    /// Foreground: the host must review the summary before anything runs (Docs state machine).
    static var supportedModes: IntentModes = .foreground(.immediate)

    /// The summary is untrusted personal-context content; gate the handoff on authentication.
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    /// The single doorway parameter. `AttributedString` preserves rich text from the
    /// Shortcuts `Use Model` action; the Wandr Shortcut's JSON output coerces into it as
    /// text, which Host Review decodes into the structured brief.
    @Parameter(title: "Summary", description: "A summary of the group conversation to plan from.")
    var summary: AttributedString

    static var parameterSummary: some ParameterSummary {
        Summary("Plan an outing in \(\.$summary)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        // No model call, no persistence — just route the volatile text to Host Review.
        IntakeInbox.shared.receive(rawText: String(summary.characters))
        return .result()
    }
}
