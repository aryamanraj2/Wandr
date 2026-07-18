//
//  GenerableCuration.swift
//  Wandr
//
//  The `@Generable` curation DTO, and its resolution against the evidence snapshot.
//
//  The model proposes venue IDs as strings; this file turns those strings back into
//  `CurationSlot`s the validator can check. The resolution is where grounding is
//  enforced on the way out: an ID the snapshot doesn't contain is dropped, never
//  rebuilt into a fake venue, and the validator's Rule 1 stands behind that as a
//  second gate.
//
//  Like `GenerableBriefDraft`, this DTO exists only because `@Generable` needs
//  FoundationModels and `Domain/` is framework-free. Do not unify it with
//  `CurationSlot`.
//

import Foundation
import FoundationModels

// MARK: - DTO

/// What the curation session emits: up to four ranked slots of venue-ID picks.
@Generable
nonisolated struct GenerableCuration: Equatable {
    @Guide(description: "Up to four slots, one per kind of stop in the outing. Order them the way the evening should flow.", .maximumCount(4))
    var slots: [GenerableCurationSlot]

    init(slots: [GenerableCurationSlot] = []) {
        self.slots = slots
    }
}

@Generable
nonisolated struct GenerableCurationSlot: Equatable {
    @Guide(description: "Which kind of stop this slot is. Exactly one of: food, sights, nightlife, discover.")
    var category: String

    @Guide(description: "Between three and five venue picks for this slot, best first. Each ID must be one the search tool returned.", .maximumCount(5))
    var candidates: [GenerableCandidate]

    init(category: String = "", candidates: [GenerableCandidate] = []) {
        self.category = category
        self.candidates = candidates
    }
}

@Generable
nonisolated struct GenerableCandidate: Equatable {
    @Guide(description: "The exact venue ID from the search tool results. Never invent one.")
    var venueID: String

    @Guide(description: "One short line on why this venue fits the brief. Never a price, an opening hour, or an availability claim — those belong to the evidence, not to you.")
    var rationale: String

    init(venueID: String = "", rationale: String = "") {
        self.venueID = venueID
        self.rationale = rationale
    }
}

// MARK: - Resolution against evidence

/// The outcome of turning model IDs into grounded slots.
///
/// `droppedIDs` records every ID string the model proposed that the snapshot could
/// not confirm. It exists for the deterministic tier and for honest bookkeeping —
/// see the note in `FoundationModelsItineraryCurator` about why it cannot become a
/// run-level `PlanningEvent` under the frozen `ItineraryCurating` protocol.
nonisolated struct CurationResolution: Sendable, Equatable {
    let slots: [CurationSlot]
    let droppedIDs: [String]

    /// Whether any proposed ID failed to resolve against the evidence snapshot.
    var hadUnresolvableIDs: Bool { !droppedIDs.isEmpty }
}

extension GenerableCuration {

    /// Resolves model IDs against the evidence snapshot into validator-ready slots.
    ///
    /// Deterministic and non-throwing by design:
    /// - A candidate whose ID is not in the snapshot is dropped and recorded.
    /// - A duplicate ID within one slot is dropped (the validator would reject it
    ///   anyway; dropping keeps the deck honest without inventing a violation).
    /// - Rank is the 1-based surviving position, so a dropped ID doesn't leave a gap.
    /// - Slot titles reuse the fake's category→title mapping, so the downstream UI
    ///   expectation is unchanged.
    /// - An empty or under-filled slot is left as-is; the validator turns it into the
    ///   `.insufficientCandidates` path §6 relies on. Padding is never an option.
    func resolved(against evidence: [GroundedVenue]) -> CurationResolution {
        let known = Set(evidence.map(\.venueID.rawValue))

        var slots: [CurationSlot] = []
        var dropped: [String] = []

        for generableSlot in orderedSlots {
            guard let category = SlotCategory(rawValue: generableSlot.category.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                // An unrecognised category has no home in the domain. Every candidate
                // under it is effectively unverifiable, so record and skip the slot.
                dropped.append(contentsOf: generableSlot.candidates.map(\.venueID))
                continue
            }

            var seen: Set<String> = []
            var candidates: [CuratedCandidate] = []

            for candidate in generableSlot.candidates {
                let id = candidate.venueID.trimmingCharacters(in: .whitespacesAndNewlines)

                guard known.contains(id) else {
                    dropped.append(candidate.venueID)
                    continue
                }
                guard seen.insert(id).inserted else {
                    // Same ID twice in one slot: keep the first, drop the repeat.
                    dropped.append(candidate.venueID)
                    continue
                }

                candidates.append(
                    CuratedCandidate(
                        venueID: VenueID(id),
                        rank: candidates.count + 1,
                        rationale: Self.cleanedRationale(candidate.rationale)
                    )
                )
            }

            // A slot that resolved to nothing is omitted entirely — an empty deck is
            // not a deck. If that thins the plan below the floor, the validator says so.
            guard !candidates.isEmpty else { continue }

            slots.append(
                CurationSlot(
                    slotID: SlotID(category.rawValue),
                    category: category,
                    title: Self.title(for: category),
                    candidates: candidates
                )
            )
        }

        return CurationResolution(slots: slots, droppedIDs: dropped)
    }

    /// The model's slot order, with duplicate categories collapsed onto the first
    /// occurrence so a category can't accidentally fill two decks.
    private var orderedSlots: [GenerableCurationSlot] {
        var seenCategories: Set<String> = []
        return slots.filter { seenCategories.insert($0.category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()).inserted }
    }

    /// Rationale is model prose: trimmed, capped, and never allowed to be empty-noise.
    /// It is shown as "why we picked this" copy and never parsed as fact.
    private static func cleanedRationale(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(200))
    }

    /// Slot names matching the decks the current curation UI already shows — the
    /// same mapping `FakeItineraryCurator` uses, so nothing downstream drifts.
    private static func title(for category: SlotCategory) -> String {
        switch category {
        case .food: return "Dinner"
        case .sights: return "Afternoon"
        case .nightlife: return "Late"
        case .discover: return "Something new"
        }
    }
}
