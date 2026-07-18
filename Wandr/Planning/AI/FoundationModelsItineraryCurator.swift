//
//  FoundationModelsItineraryCurator.swift
//  Wandr
//
//  The real `ItineraryCurating`: a research/curation session whose only tool is
//  `SearchDistrictVenuesTool`, and whose output is rank order plus rationale — never
//  a display fact.
//
//  The boundaries it lives by (§5.3, §10):
//  - Gate at call time; no session past a failed gate.
//  - Exactly one tool. The model is instructed that venue facts come only from tool
//    results, that it must call the tool before proposing, and that it must never
//    claim a price, hour, or availability.
//  - The prompt carries the brief's constraints ONLY — never a serialized venue
//    list. Evidence enters the transcript only as bounded tool results, keeping the
//    exchange inside the on-device context window (read `contextSize`, don't assume).
//  - Output IDs are resolved against the evidence snapshot; unresolvable ones are
//    dropped (never rebuilt into fake venues). An under-filled slot flows into the
//    existing `.validationFailed(.insufficientCandidates)` path.
//  - Every model-layer error funnels through `ModelErrorMapping`.
//
//  A note on the dropped-ID limitation (§10.2). The plan asks for a fixed-string
//  `PlanningEvent` when an ID is dropped. The `ItineraryCurating` protocol returns
//  `[CurationSlot]` and carries no event channel, and modifying the protocol or the
//  coordinator is out of scope — so that transparency event has no seam to travel
//  through and is intentionally not emitted. The run-visible consequence the plan
//  actually depends on IS produced: dropping that thins a slug below the floor
//  becomes `.insufficientCandidates` at the validator. The drop is also surfaced as
//  a testable value (`CurationResolution.droppedIDs`) for the deterministic tier.
//

import Foundation
import FoundationModels

/// The on-device curator. A `Sendable` struct invoked from the
/// `TravelPlanningService` actor, same shape as the fake it replaces.
nonisolated struct FoundationModelsItineraryCurator: ItineraryCurating, Sendable {

    /// Injected so the availability path is exercisable with a non-default model.
    let model: SystemLanguageModel

    init(model: SystemLanguageModel = .default) {
        self.model = model
    }

    func curate(brief: OutingBrief, evidence: [GroundedVenue]) async throws -> [CurationSlot] {
        // Call-time gate. Throws a mapped `PlanningFailure` before any session exists.
        try ModelAvailabilityGate.check(model)

        do {
            // The tool wraps the evidence snapshot the coordinator handed us — the
            // model can only ever retrieve IDs that already exist here.
            let tool = SearchDistrictVenuesTool(venues: evidence)

            let session = LanguageModelSession(
                model: model,
                tools: [tool],
                instructions: Self.instructions
            )

            let response = try await session.respond(
                to: Self.prompt(for: brief),
                generating: GenerableCuration.self,
                options: GenerationOptions(samplingMode: .greedy)
            )

            // Grounding on the way out: resolve model IDs against the snapshot. The
            // validator re-checks everything this produces.
            return response.content.resolved(against: evidence).slots
        } catch {
            throw ModelErrorMapping.planningFailure(for: error)
        }
    }

    // MARK: - Instructions
    //
    // Fixed, versioned constant per §10.1: role, the grounding rule, the output
    // rule, the constraint rule. No venue names, no dataset facts — those come only
    // from the tool at call time.
    //
    // Token count (estimate, ~3 chars/token English; ~160 tokens): confirm on device
    // with `SystemLanguageModel.default.tokenCount(for: Instructions(instructionsText))`.
    // Version: 1.

    static let instructionsText = """
    You assemble an outing from real venues for a given brief.

    Every venue comes ONLY from the searchDistrictVenues tool. Call it before you \
    propose anything, and never name a venue you did not retrieve from it. Use only \
    the venue IDs the tool returned.

    Your output is a ranked list of venue IDs per kind of stop, each with one short \
    line on why it fits. Do NOT state prices, opening hours, or availability — those \
    facts belong to the evidence, not to you.

    Respect the brief's dietary, accessibility, and setting constraints when choosing \
    among retrieved venues. When a venue's compliance is unknown, prefer ones known \
    to comply, but never claim the unknown is safe.
    """

    static let instructions = Instructions(instructionsText)

    // MARK: - Prompt
    //
    // The brief's constraint summary only — never a serialized venue list (§10.3).
    // Fixed, coordinator-authored phrasing wrapping typed brief fields; it carries no
    // `PlanningInput.text`, because the curator never receives it (the protocol
    // signature makes that structurally impossible).

    static func prompt(for brief: OutingBrief) -> String {
        var lines: [String] = ["Plan an outing with these constraints:"]

        lines.append("- Occasion: \(brief.occasion.value)")
        lines.append("- Area: \(brief.area.value)")
        lines.append("- Group size: \(brief.groupSize.value.people)")

        if let limit = brief.budgetPerHead.value.limitRupees {
            lines.append("- Budget per person: up to ₹\(limit)")
        } else {
            lines.append("- Budget per person: no stated ceiling")
        }

        if brief.dietary.isHardConstraint {
            lines.append("- Dietary (required): \(brief.dietary.requirements.map(\.rawValue).joined(separator: ", "))")
        }
        if brief.accessibility.isHardConstraint {
            lines.append("- Accessibility (required): \(brief.accessibility.requirements.map(\.rawValue).joined(separator: ", "))")
        }
        if brief.setting.isHardConstraint {
            lines.append("- Setting (required): \(brief.setting.rawValue)")
        }
        if !brief.vibeTags.isEmpty {
            lines.append("- Vibe: \(brief.vibeTags.joined(separator: ", "))")
        }

        lines.append("Search for venues, then propose 3-5 ranked picks per relevant kind of stop.")
        return lines.joined(separator: "\n")
    }
}
