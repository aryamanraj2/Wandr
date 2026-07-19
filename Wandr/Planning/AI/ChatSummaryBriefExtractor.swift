//
//  ChatSummaryBriefExtractor.swift
//  Wandr
//
//  The live `BriefExtracting` for the JSON-first intake path.
//
//  The group booking hands Wandr a *structured* summary, not free prose, so
//  extraction here is deterministic decoding — no model. This is what actually
//  fills the `BriefExtracting` seam in production, replacing `FakeBriefExtractor`.
//  (The model in this app does curation, not extraction.)
//
//  It decodes the summary carried in `PlanningInput.text` back into a
//  `ChatSummaryPayload`, then maps it to a draft. Text that isn't our schema
//  yields an empty draft, which the normalizer fills with safe defaults — the run
//  still proceeds rather than dead-ending. Privacy: the text is a structured
//  summary at this point, never the raw chat; it is not stored or logged here.
//

import Foundation

/// Deterministic `BriefExtracting` over the group-booking JSON summary.
nonisolated struct ChatSummaryBriefExtractor: BriefExtracting, Sendable {

    private let mapper: ChatSummaryBriefMapper
    /// Set to make extraction throw, so the coordinator's failure branch is reachable
    /// without a live model. Nothing in the app sets it.
    private let failure: PlanningFailure?

    init(mapper: ChatSummaryBriefMapper = ChatSummaryBriefMapper(), failure: PlanningFailure? = nil) {
        self.mapper = mapper
        self.failure = failure
    }

    func extractBrief(from input: PlanningInput) async throws -> OutingBriefDraft {
        if let failure { throw failure }

        switch ChatSummaryPayload.decode(from: input.text) {
        case .structured(let payload):
            return mapper.draft(from: payload)
        case .unstructured, .empty:
            // Not our schema (or nothing settled): proceed on safe defaults rather
            // than fail — the normalizer marks every one as `.safeDefault`.
            return OutingBriefDraft()
        }
    }
}
