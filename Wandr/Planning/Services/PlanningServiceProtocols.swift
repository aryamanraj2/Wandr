//
//  PlanningServiceProtocols.swift
//  Wandr
//
//  Small seams, not one omniscient service.
//
//  `TravelPlanningService` will compose these. It must never be able to tell
//  whether a brief came from a live Foundation Models session or a fake fixture —
//  which is exactly why none of these protocols may import SwiftUI, MapKit,
//  FoundationModels, or SwiftData. Foundation only.
//

import Foundation

// MARK: - Extraction

/// Turns a volatile request into a constrained draft. One job, nothing else.
///
/// The live implementation gates on model availability and uses `@Generable`;
/// the test implementation returns a fixture. Neither detail belongs here.
nonisolated protocol BriefExtracting: Sendable {
    /// - Throws: `PlanningFailure` for every unavailability and decoding case.
    func extractBrief(from input: PlanningInput) async throws -> OutingBriefDraft
}

// MARK: - Normalization

/// Turns an uncertain draft into a canonical brief, or says what's missing.
///
/// Pure Swift. This is where safe defaults are applied and marked as such.
nonisolated protocol BriefNormalizing: Sendable {
    func normalize(_ draft: OutingBriefDraft) throws -> BriefNormalizationOutcome
}

// MARK: - Research

/// What a provider returns: evidence plus the transparency trail that produced it.
nonisolated struct VenueResearchResult: Sendable, Equatable {
    let venues: [GroundedVenue]
    let events: [PlanningEvent]

    init(venues: [GroundedVenue], events: [PlanningEvent] = []) {
        self.venues = venues
        self.events = events
    }
}

/// Collects grounded candidates for a brief.
///
/// The first implementation reads a bundled Delhi NCR dataset. Whatever comes
/// later — MapKit enrichment, live hours — must still return `GroundedVenue`
/// snapshots carrying a source and a retrieval timestamp.
nonisolated protocol VenueResearching: Sendable {
    func research(for brief: OutingBrief) async throws -> VenueResearchResult
}

// MARK: - Curation

/// Ranks known evidence IDs into slots.
///
/// The curator receives an immutable evidence snapshot and may only reference
/// venues by `VenueID` drawn from it. It produces rank order and rationale —
/// never a display fact, never a price, never an availability claim.
nonisolated protocol ItineraryCurating: Sendable {
    func curate(brief: OutingBrief, evidence: [GroundedVenue]) async throws -> [CurationSlot]
}

// MARK: - Validation

/// The deterministic gate between curation and the UI.
///
/// Synchronous and non-throwing-by-accident: it either returns a validated plan
/// or throws a `PlanningFailure` carrying every violation it found. No model,
/// network, file system, or UI framework may be reachable from here.
nonisolated protocol ItineraryValidating: Sendable {
    func validate(
        brief: OutingBrief,
        evidence: [GroundedVenue],
        slots: [CurationSlot],
        runID: PlanningRunID,
        now: Date
    ) throws -> WandrPlan
}

// MARK: - Scheduling

/// Derives timeline blocks from a validated plan. Pure Swift.
nonisolated protocol ScheduleDrafting: Sendable {
    func draftSchedule(for plan: WandrPlan, evidence: [GroundedVenue]) throws -> ScheduleDraft
}

// MARK: - Storage

/// Structured, finished data only — never raw input.
///
/// A no-op during this slice. SwiftData arrives much later, and nothing in the
/// planning core may depend on it existing.
nonisolated protocol PlanningRunStoring: Sendable {
    func store(_ plan: WandrPlan) async throws
}
