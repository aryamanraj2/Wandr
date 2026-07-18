//
//  ModelAvailabilityGate.swift
//  Wandr
//
//  The one place that reads `SystemLanguageModel.default.availability`.
//
//  No `LanguageModelSession` is constructed anywhere in this app without passing
//  this gate first, **at call time**. Availability changes when the host toggles
//  Apple Intelligence in Settings mid-session, so a check cached at app launch is
//  a stale check — which is why the gate takes no state and is called from inside
//  each adapter's entry method rather than at construction.
//
//  Every `.unavailable` reason maps to the `PlanningFailure` category Step 1
//  already reserved for it, so unavailability is not a special case anywhere
//  downstream: it is just another `PlanningFailure` landing the run in `.failed`
//  with a retry action the UI already understands.
//

import Foundation
import FoundationModels

/// Availability → `PlanningFailure`. Stateless by design; see the file header.
nonisolated enum ModelAvailabilityGate {

    /// Throws the mapped `PlanningFailure` unless the model is ready right now.
    ///
    /// - Parameter model: injected so tests can pass a non-default model. Production
    ///   always uses `.default`.
    static func check(_ model: SystemLanguageModel = .default) throws {
        try check(availability: model.availability)
    }

    /// The pure half, split out so the deterministic tier can exercise every
    /// branch without a model on the host.
    static func check(availability: SystemLanguageModel.Availability) throws {
        switch availability {
        case .available:
            return
        case .unavailable(let reason):
            throw PlanningFailure(failureCategory(for: reason))
        @unknown default:
            // A new availability state is not something the host can act on, and
            // it is certainly not "available" — refuse rather than guess.
            assertionFailure("Unhandled SystemLanguageModel.Availability case")
            throw PlanningFailure(.modelAssetsNotReady)
        }
    }

    /// The §9.4 mapping for the three reasons the framework defines.
    ///
    /// Each one was given a `PlanningFailure` category in Step 1 specifically so
    /// this function would exist without a domain edit.
    static func failureCategory(
        for reason: SystemLanguageModel.Availability.UnavailableReason
    ) -> PlanningFailure.Category {
        switch reason {
        case .deviceNotEligible:
            // Retry action `.none` — there is nothing the host can do.
            return .deviceIneligible
        case .appleIntelligenceNotEnabled:
            // Retry action `.openSettings`.
            return .intelligenceDisabled
        case .modelNotReady:
            // Retry action `.waitAndRetry` — assets are still downloading.
            return .modelAssetsNotReady
        @unknown default:
            assertionFailure("Unhandled SystemLanguageModel.Availability.UnavailableReason")
            return .modelAssetsNotReady
        }
    }
}
