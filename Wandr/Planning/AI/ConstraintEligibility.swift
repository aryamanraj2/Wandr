//
//  ConstraintEligibility.swift
//  Wandr
//
//  The one hard-constraint filter both curators share.
//
//  Surveyed-and-contradicted is dropped; never-surveyed is kept. That asymmetry is
//  the whole point: a venue the evidence *proves* incompatible with a hard
//  requirement (vegetarian menu it doesn't have, a step it can't avoid) must not
//  reach the deck, but a venue that was simply never surveyed is unverified — not
//  contradicted — and the validator turns it into a warning, not a removal.
//
//  It lives here so `FakeItineraryCurator` (tests) and `FoundationModelsCurator`
//  (production) apply exactly the same rule — otherwise a test could pass against a
//  filter the real curator doesn't use. Foundation only.
//

import Foundation

/// Shared pre-curation hard-constraint filter.
nonisolated enum ConstraintEligibility {

    /// Whether `venue` may be offered for `brief`, given only what the evidence proves.
    static func isEligible(_ venue: GroundedVenue, for brief: OutingBrief) -> Bool {
        if brief.dietary.isHardConstraint,
           let missing = venue.dietaryTags.unsatisfied(by: brief.dietary.requirements),
           !missing.isEmpty {
            return false
        }

        if brief.accessibility.isHardConstraint,
           let missing = venue.accessibilityTags.unsatisfied(by: brief.accessibility.requirements),
           !missing.isEmpty {
            return false
        }

        if brief.setting.isHardConstraint, venue.setting.satisfies(brief.setting) == false {
            return false
        }

        return true
    }
}
