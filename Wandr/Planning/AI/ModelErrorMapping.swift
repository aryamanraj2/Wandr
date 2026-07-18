//
//  ModelErrorMapping.swift
//  Wandr
//
//  One function. Every model-layer error becomes a `PlanningFailure` category
//  Step 1 already reserved — and nothing else escapes the adapters.
//
//  The deployment floor is 27, so the deprecated `LanguageModelSession.GenerationError`
//  is deliberately not referenced: the 27 surface splits across three types
//  (`LanguageModelError`, `SystemLanguageModel.Error`, `LanguageModelSession.Error`)
//  plus `GeneratedContent.ParsingError`, and a rename-only migration would silently
//  drop the three cases that left the enum.
//
//  Privacy rule this file exists to enforce: **no failure message ever interpolates
//  the underlying error's description.** `PlanningFailure.userMessage` is a fixed
//  sentence per category. A model error's `debugDescription` can quote the prompt,
//  and the prompt is the host's own words.
//

import Foundation
import FoundationModels

/// Any error thrown beneath a planning adapter → the `PlanningFailure` the host reads.
///
/// This is the **only** place these framework error types are caught. Both adapters
/// funnel through it, which is what makes §9.4's table a single reviewable list
/// rather than a rule scattered across two files.
nonisolated enum ModelErrorMapping {

    static func planningFailure(for error: any Error) -> PlanningFailure {
        PlanningFailure(category(for: error))
    }

    static func category(for error: any Error) -> PlanningFailure.Category {

        // Our own failures pass through untouched. The gate throws these before a
        // session exists, and re-mapping them here would turn a precise
        // "turn on Apple Intelligence" into a generic decoding failure.
        if let failure = error as? PlanningFailure {
            return failure.category
        }

        // Cancellation is the host's own doing, not a model fault.
        if error is CancellationError {
            return .cancelled
        }

        if let modelError = error as? LanguageModelError {
            return category(for: modelError)
        }

        // Left the old enum in 27: assets absent is an availability problem, so it
        // lands where the gate's `.modelNotReady` lands — `.waitAndRetry`.
        if let systemError = error as? SystemLanguageModel.Error {
            switch systemError {
            case .assetsUnavailable:
                return .modelAssetsNotReady
            @unknown default:
                assertionFailure("Unhandled SystemLanguageModel.Error case")
                return .modelAssetsNotReady
            }
        }

        // Also left the old enum. Both cases should be unreachable — every session
        // in this app is created inside one call and dies with it, and no transcript
        // is mutated — but mapped rather than crashed.
        if let sessionError = error as? LanguageModelSession.Error {
            switch sessionError {
            case .concurrentRequests, .transcriptMutationWhileResponding:
                return .modelAssetsNotReady
            @unknown default:
                assertionFailure("Unhandled LanguageModelSession.Error case")
                return .modelAssetsNotReady
            }
        }

        // A tool threw. The dataset is bundled so this should not happen, but a
        // decode regression would surface here rather than as an empty-but-
        // successful tool result.
        if let toolError = error as? LanguageModelSession.ToolCallError {
            return category(for: toolError.underlyingError)
        }

        // Structured output that wouldn't decode into the typed DTO. A struct in 27,
        // not an enum case — `is` rather than a pattern match.
        if error is GeneratedContent.ParsingError {
            return .structuredOutputDecodingFailed
        }

        // Anything else, including our own DTO-mapping failures.
        return .structuredOutputDecodingFailed
    }

    // MARK: - The unified inference error

    private static func category(for error: LanguageModelError) -> PlanningFailure.Category {
        switch error {

        // Who said no differs — Apple's classifier vs the model itself — but the
        // honest sentence for the host is the same, and so is the retry action.
        // Note we never read `Refusal.explanation`: it is an `async throws` property
        // that *runs another generation*, and its output is model prose we would
        // have no right to show as a failure reason.
        case .guardrailViolation, .refusal:
            return .guardrailRefusal

        case .contextSizeExceeded:
            return .contextTooLarge

        // §9.4: the existing message already says "try describing it differently",
        // which is the correct coaching here. A dedicated category is not worth a
        // Step 1 domain edit.
        case .unsupportedLanguageOrLocale:
            return .guardrailRefusal

        // Both are "wait, then try the same request again" — which is exactly the
        // `.waitAndRetry` action `.modelAssetsNotReady` carries. We deliberately do
        // not read `.rateLimited`'s `resetDate`: the UI has no countdown affordance
        // in this step, and inventing one is the bridge step's call.
        case .rateLimited, .timeout:
            return .modelAssetsNotReady

        // Schema-level programmer errors. Not recoverable at runtime by the host —
        // the fix is a code change — so they get the decoding category, and the
        // assertion makes them loud during development.
        case .unsupportedGenerationGuide, .unsupportedCapability, .unsupportedTranscriptContent:
            assertionFailure("Schema/capability error is a wiring bug: \(error)")
            return .structuredOutputDecodingFailed

        @unknown default:
            // A case the 27 SDK didn't have when this was written. Loud in debug,
            // honest in release.
            assertionFailure("Unhandled LanguageModelError case")
            return .structuredOutputDecodingFailed
        }
    }
}
