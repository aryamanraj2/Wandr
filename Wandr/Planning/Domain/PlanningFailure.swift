//
//  PlanningFailure.swift
//  Wandr
//
//  Every way planning can stop, with a sentence the host can actually read.
//
//  There is no generic error string anywhere in the planning core. A failure is
//  a category plus a computed message plus the retry the UI should offer — so a
//  dead end is impossible by construction.
//
//  Privacy: a failure payload never carries raw request text. Venue IDs and slot
//  IDs are dataset-owned and safe; the host's words are not.
//

import Foundation

/// What the UI should offer the host after a failure.
nonisolated enum PlanningRetryAction: String, Sendable, Equatable, Hashable, CaseIterable {
    /// Nothing to retry — the run simply ended.
    case none
    /// Send the same request again.
    case retrySameRequest
    /// Let the host reword or add detail, then resubmit.
    case editRequest
    /// Point the host at Settings (Apple Intelligence).
    case openSettings
    /// Wait for on-device assets, then retry.
    case waitAndRetry
    /// Back to a clean capture screen.
    case startOver
}

/// A recoverable planning failure with a structured reason.
nonisolated struct PlanningFailure: Error, Sendable, Equatable, Hashable {

    nonisolated enum Category: Sendable, Equatable, Hashable {
        /// The request was empty or whitespace-only. Extraction never started.
        case inputEmpty
        /// This device cannot run Apple Intelligence.
        case deviceIneligible
        /// Apple Intelligence is off in Settings.
        case intelligenceDisabled
        /// On-device model assets are still downloading.
        case modelAssetsNotReady
        /// The model declined to answer.
        case guardrailRefusal
        /// The request exceeded the model's context.
        case contextTooLarge
        /// Structured output could not be decoded into the typed brief.
        case structuredOutputDecodingFailed
        /// Not enough grounded candidates to fill the required slots.
        case insufficientEvidence(details: [InsufficientEvidenceDetail])
        /// The curation violated one or more deterministic rules.
        case validationFailed(violations: [FeasibilityViolation])
        /// The host cancelled, or left.
        case cancelled
    }

    /// Why a slot could not be filled from grounded evidence.
    nonisolated struct InsufficientEvidenceDetail: Sendable, Equatable, Hashable {
        let category: SlotCategory
        let required: Int
        let found: Int

        init(category: SlotCategory, required: Int, found: Int) {
            self.category = category
            self.required = required
            self.found = found
        }
    }

    let category: Category

    init(_ category: Category) {
        self.category = category
    }

    /// A sentence the host reads. Never a raw error description, never their own words.
    var userMessage: String {
        switch category {
        case .inputEmpty:
            return "Tell us what you're planning first — a line or two is plenty."

        case .deviceIneligible:
            return "This iPhone can't run on-device planning. Wandr needs an Apple Intelligence device."

        case .intelligenceDisabled:
            return "Turn on Apple Intelligence in Settings and Wandr can plan this on-device."

        case .modelAssetsNotReady:
            return "Apple Intelligence is still setting up on this iPhone. Try again in a few minutes."

        case .guardrailRefusal:
            return "Wandr couldn't plan that one. Try describing the outing a different way."

        case .contextTooLarge:
            return "That's a lot to take in at once. Try a shorter version of the plan."

        case .structuredOutputDecodingFailed:
            return "Wandr couldn't make sense of that request. Try rewording it."

        case .insufficientEvidence(let details):
            guard let worst = details.min(by: { $0.found < $1.found }) else {
                return "We couldn't find enough real places for this plan yet."
            }
            return "We only found \(worst.found) \(worst.category.rawValue) options nearby — not enough to choose from. Try widening the area or budget."

        case .validationFailed(let violations):
            guard let first = violations.first else {
                return "That plan didn't hold up when we checked it. Let's try again."
            }
            return first.message

        case .cancelled:
            return "Planning stopped."
        }
    }

    /// What the UI offers next. No failure dead-ends.
    var retryAction: PlanningRetryAction {
        switch category {
        case .inputEmpty:                    return .editRequest
        case .deviceIneligible:              return .none
        case .intelligenceDisabled:          return .openSettings
        case .modelAssetsNotReady:           return .waitAndRetry
        case .guardrailRefusal:              return .editRequest
        case .contextTooLarge:               return .editRequest
        case .structuredOutputDecodingFailed: return .retrySameRequest
        case .insufficientEvidence:          return .editRequest
        case .validationFailed:              return .retrySameRequest
        case .cancelled:                     return .startOver
        }
    }

    /// Whether the run can be restarted at all.
    var isRecoverable: Bool { retryAction != .none }
}

// MARK: - Convenience

extension PlanningFailure {
    static let inputEmpty = PlanningFailure(.inputEmpty)
    static let cancelled = PlanningFailure(.cancelled)

    static func validationFailed(_ violations: [FeasibilityViolation]) -> PlanningFailure {
        PlanningFailure(.validationFailed(violations: violations))
    }

    static func insufficientEvidence(_ details: [InsufficientEvidenceDetail]) -> PlanningFailure {
        PlanningFailure(.insufficientEvidence(details: details))
    }
}
