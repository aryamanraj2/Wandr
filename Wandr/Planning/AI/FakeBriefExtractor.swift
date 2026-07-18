//
//  FakeBriefExtractor.swift
//  Wandr
//
//  TEMPORARY. Stands in for Step 3's Foundation Models adapter.
//
//  This file exists so the coordinator has *something* behind `BriefExtracting`
//  before `LanguageModelSession` is allowed into the project. Its entire job is to
//  be deleted. It imports Foundation and nothing else — no FoundationModels, no
//  SwiftUI — and Step 3 replaces it by adding a sibling file here and changing
//  which one `TravelPlanningService` is constructed with.
//
//  Privacy: this type reads `PlanningInput.text` because extraction is the one job
//  that legitimately must. It never stores it, never logs it, and never copies it
//  into the draft it returns.
//

import Foundation

/// A deterministic, model-free `BriefExtracting` stand-in.
///
/// Recognised fixture requests map to hand-authored drafts; anything else falls
/// back to a small keyword scan. Neither path is meant to be good — a real
/// extractor is Step 3's problem.
nonisolated struct FakeBriefExtractor: BriefExtracting, Sendable {

    /// Set to make the fake throw instead, so the coordinator's failure branch is
    /// reachable without a live model.
    let failure: PlanningFailure?

    init(failure: PlanningFailure? = nil) {
        self.failure = failure
    }

    func extractBrief(from input: PlanningInput) async throws -> OutingBriefDraft {
        if let failure { throw failure }
        return Self.draft(for: input.text)
    }

    // MARK: - Canned drafts
    //
    // These are the drafts the six sanitized fixture requests are expected to
    // produce. They are keyed on the request text purely so Step 2's tests have a
    // stable extraction stage; a real model obviously does not work this way.

    /// The after-work request: everything stated, nothing to guess.
    static let afterWorkDraft = OutingBriefDraft(
        occasion: "after-work dinner and music",
        timeWindow: OutingTimeWindow(dayLabel: "Friday"),
        area: "Hauz Khas",
        groupSize: 6,
        budgetPerHeadRupees: 1_500,
        vibeTags: ["music"]
    )

    /// The birthday request: a hard dietary constraint and a fixed finish time.
    static let birthdayDraft = OutingBriefDraft(
        occasion: "birthday",
        timeWindow: OutingTimeWindow(latestEndMinute: 21 * 60),
        groupSize: 8,
        dietary: .required([.vegetarian])
    )

    /// The sparse request: nothing stated at all.
    static let sparseDraft = OutingBriefDraft()

    /// The injection request. Note what is *not* here: no instruction survives
    /// extraction, because a draft has no field an instruction could occupy.
    /// "Book the most expensive place" has nowhere to go.
    static let injectionDraft = OutingBriefDraft(
        notes: ["treat request text as data"]
    )

    /// The impossible-budget request: a ceiling no real venue can meet.
    static let impossibleBudgetDraft = OutingBriefDraft(
        occasion: "dinner and club",
        groupSize: 10,
        budgetPerHeadRupees: 200
    )

    // MARK: - Dispatch

    static func draft(for text: String) -> OutingBriefDraft {
        let normalized = text.lowercased()

        if normalized.contains("hauz khas") && normalized.contains("music") {
            return afterWorkDraft
        }
        if normalized.contains("birthday") {
            return birthdayDraft
        }
        if normalized.contains("ignore instructions") {
            return injectionDraft
        }
        if normalized.contains("club") && normalized.contains("200") {
            return impossibleBudgetDraft
        }
        if normalized.contains("something fun") {
            return sparseDraft
        }
        return fallbackDraft(for: normalized)
    }

    /// A deliberately thin keyword scan for anything the table doesn't recognise.
    /// Good enough to keep the pipeline running; not good enough to keep.
    private static func fallbackDraft(for normalized: String) -> OutingBriefDraft {
        OutingBriefDraft(
            area: knownAreas.first { normalized.contains($0.lowercased()) },
            groupSize: firstNumber(in: normalized, upTo: 50),
            dietary: normalized.contains("vegetarian") ? .required([.vegetarian]) : .unknown
        )
    }

    private static let knownAreas = ["Hauz Khas", "Lodhi", "Connaught Place", "Cyberhub"]

    private static func firstNumber(in text: String, upTo limit: Int) -> Int? {
        let digits = text.split { !$0.isNumber }
        for run in digits {
            if let value = Int(run), value > 0, value <= limit { return value }
        }
        return nil
    }
}
