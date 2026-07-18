//
//  ModelErrorMappingTests.swift
//  WandrTests
//
//  §13.1's deterministic tier for the gate and the error table. No model runs here,
//  so this suite is green on any Mac including a CI box with no Apple Intelligence.
//
//  What is deliberately *not* asserted: the `LanguageModelError` rows. Those cases
//  carry framework payload structs with no public initializer, so a test cannot
//  construct one — the compiler checking the exhaustive `switch` in
//  `ModelErrorMapping` (including its `@unknown default`) is the coverage that is
//  actually available, and the device-gated tier exercises the live paths. The rows
//  that *can* be built are all asserted below.
//

import Foundation
import FoundationModels
import Testing
@testable import Wandr

@Suite("Model availability gate")
struct ModelAvailabilityGateTests {

    @Test("An available model passes the gate without throwing")
    func availablePasses() throws {
        try ModelAvailabilityGate.check(availability: .available)
    }

    // §3.3: each reason must land on the category Step 1 reserved for it, *and* on
    // the retry action that category carries. Asserting the action too is the point —
    // a mapping that produced the right category with a dead-end retry would still
    // strand the host.

    @Test(
        "Every unavailable reason maps to its reserved category and retry action",
        arguments: [
            (SystemLanguageModel.Availability.UnavailableReason.deviceNotEligible,
             PlanningFailure.Category.deviceIneligible,
             PlanningRetryAction.none),
            (.appleIntelligenceNotEnabled, .intelligenceDisabled, .openSettings),
            (.modelNotReady, .modelAssetsNotReady, .waitAndRetry)
        ]
    )
    func unavailableReasonsMap(
        reason: SystemLanguageModel.Availability.UnavailableReason,
        expected: PlanningFailure.Category,
        retry: PlanningRetryAction
    ) throws {
        #expect(ModelAvailabilityGate.failureCategory(for: reason) == expected)

        #expect(throws: PlanningFailure(expected)) {
            try ModelAvailabilityGate.check(availability: .unavailable(reason))
        }

        #expect(PlanningFailure(expected).retryAction == retry)
    }

    @Test("A gate failure never carries a raw error description")
    func gateMessagesAreAuthored() {
        // Every category's sentence is authored in `PlanningFailure`. This asserts
        // the gate can't have smuggled framework text into one.
        for reason in [SystemLanguageModel.Availability.UnavailableReason.deviceNotEligible,
                       .appleIntelligenceNotEnabled,
                       .modelNotReady] {
            let message = PlanningFailure(ModelAvailabilityGate.failureCategory(for: reason)).userMessage
            #expect(!message.isEmpty)
            #expect(!message.contains("Error"))
            #expect(!message.contains("FoundationModels"))
        }
    }
}

@Suite("Model error mapping")
struct ModelErrorMappingTests {

    /// Stands in for "anything else" — a foreign error the table has no row for.
    private struct ForeignError: Error {}

    /// Stands in for a DTO-mapping failure raised by our own adapter code.
    private struct DTOMappingError: Error {
        let field: String
    }

    // MARK: - Pass-through

    @Test("A PlanningFailure passes through untouched")
    func planningFailurePassesThrough() {
        // The gate throws these *before* a session exists. Re-mapping one would turn
        // a precise "turn on Apple Intelligence" into a generic decoding failure —
        // the exact regression this branch exists to prevent.
        let categories: [PlanningFailure.Category] = [
            .deviceIneligible,
            .intelligenceDisabled,
            .modelAssetsNotReady,
            .guardrailRefusal,
            .contextTooLarge,
            .inputEmpty,
            .cancelled
        ]

        for category in categories {
            let mapped = ModelErrorMapping.planningFailure(for: PlanningFailure(category))
            #expect(mapped.category == category)
        }
    }

    @Test("Insufficient-evidence and validation payloads survive the mapping intact")
    func structuredCategoriesSurvive() {
        let violations = PlanningFailure.insufficientEvidence([
            .init(category: .food, required: 3, found: 1)
        ])
        #expect(ModelErrorMapping.planningFailure(for: violations) == violations)
    }

    // MARK: - Cancellation

    @Test("A CancellationError becomes the cancelled category, not a decoding failure")
    func cancellationMaps() {
        let mapped = ModelErrorMapping.planningFailure(for: CancellationError())
        #expect(mapped.category == .cancelled)
        #expect(mapped.retryAction == .startOver)
    }

    // MARK: - The fallback row

    @Test("An unrecognised error falls back to structuredOutputDecodingFailed")
    func foreignErrorFallsBack() {
        #expect(ModelErrorMapping.category(for: ForeignError()) == .structuredOutputDecodingFailed)
        #expect(ModelErrorMapping.category(for: DTOMappingError(field: "occasion")) == .structuredOutputDecodingFailed)
    }

    @Test("The fallback offers a retry rather than dead-ending")
    func fallbackIsRecoverable() {
        let mapped = ModelErrorMapping.planningFailure(for: ForeignError())
        #expect(mapped.retryAction == .retrySameRequest)
        #expect(mapped.isRecoverable)
    }

    // MARK: - Privacy

    @Test("No mapped failure interpolates the underlying error's description")
    func messagesNeverQuoteTheError() {
        // A model error's debugDescription can quote the prompt, and the prompt is
        // the host's own words. §9.4's rule, asserted rather than trusted.
        struct LoudError: Error, CustomStringConvertible {
            var description = "SECRET-REQUEST-TEXT-Hauz-Khas"
        }

        let mapped = ModelErrorMapping.planningFailure(for: LoudError())
        #expect(!mapped.userMessage.contains("SECRET"))
        #expect(!mapped.userMessage.contains("Hauz"))
    }

    @Test("Every category the mapping can produce has a non-empty authored message")
    func everyProducibleCategoryReads() {
        let producible: [PlanningFailure.Category] = [
            .deviceIneligible,
            .intelligenceDisabled,
            .modelAssetsNotReady,
            .guardrailRefusal,
            .contextTooLarge,
            .structuredOutputDecodingFailed,
            .cancelled
        ]

        for category in producible {
            let failure = PlanningFailure(category)
            #expect(!failure.userMessage.isEmpty)
            // No failure dead-ends except device ineligibility, which genuinely has
            // no action the host could take.
            if category != .deviceIneligible {
                #expect(failure.isRecoverable)
            }
        }
    }
}
