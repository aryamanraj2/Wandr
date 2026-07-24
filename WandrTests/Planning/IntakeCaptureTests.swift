//
//  IntakeCaptureTests.swift
//  WandrTests
//
//  The second doorway: a host with no group chat describes the outing themselves.
//
//  The rule these defend is that the manual route **rejoins the Siri route at Host
//  Review** and is identical from there on. Anything that lands the host somewhere
//  else — a failure screen, a dead end, or worse, a confirmed-but-empty payload that
//  silently plans a generic night — is the bug.
//

import Foundation
import Testing
@testable import Wandr

@MainActor
@Suite("Direct capture intake")
struct IntakeCaptureTests {

    /// Stands in for the on-device model so these run without Apple Intelligence.
    private struct StubExtractor {
        static func payload(area: String) -> ChatSummaryPayload {
            var payload = ChatSummaryPayload()
            payload.area = area
            payload.groupSize = 6
            return payload
        }
    }

    // MARK: - Routing

    @Test("Beginning capture opens the speak-or-type screen")
    func beginCaptureEntersCapturing() {
        let inbox = IntakeInbox()
        inbox.beginCapture()

        #expect(inbox.state == .capturing)
    }

    @Test("Cancelling capture returns to the resting state once setup is done")
    func cancelReturnsToAwaiting() {
        let inbox = IntakeInbox()
        inbox.completeShortcutSetup()
        inbox.beginCapture()
        inbox.cancelCapture()

        #expect(inbox.state == .awaitingSummary)
    }

    @Test("Cancelling capture before setup returns to onboarding, not a dead end")
    func cancelBeforeSetupReturnsToOnboarding() {
        let inbox = IntakeInbox()
        inbox.hasCompletedShortcutSetup = false
        inbox.beginCapture()
        inbox.cancelCapture()

        #expect(inbox.state == .onboarding)
    }

    @Test("Empty or whitespace-only capture routes to recovery, never to planning")
    func blankCaptureRoutesToRecovery() async {
        for text in ["", "   ", "\n\t "] {
            let inbox = IntakeInbox()
            await inbox.captureFreeText(text)

            guard case .recovery = inbox.state else {
                Issue.record("Blank input should reach recovery, got \(inbox.state)")
                return
            }
        }
    }

    // MARK: - The contract with Host Review

    @Test("A confirmed capture carries the payload downstream, not an empty one")
    func confirmedCaptureCarriesThePayload() {
        // The bug this guards: `confirm()` forwards `payload ?? ChatSummaryPayload()`,
        // so a manual capture that reached Host Review with `payload: nil` would plan
        // a generic night while looking completely normal.
        let inbox = IntakeInbox()
        let extracted = StubExtractor.payload(area: "Khan Market")

        inbox.receive(rawText: Self.json(extracted))
        inbox.confirm()

        guard case .confirmed(let payload) = inbox.state else {
            Issue.record("Expected .confirmed, got \(inbox.state)")
            return
        }
        #expect(payload.area == "Khan Market")
        #expect(payload.groupSize == 6)
        #expect(!payload.isEmpty)
    }

    @Test("Text that carries no schema still reaches Host Review rather than failing")
    func unstructuredTextStillReachesReview() {
        let inbox = IntakeInbox()
        inbox.receive(rawText: "eight of us, Khan Market, Saturday, around 1500 each")

        guard case .hostReview(let payload, let rawText) = inbox.state else {
            Issue.record("Expected .hostReview, got \(inbox.state)")
            return
        }
        #expect(payload == nil, "Prose is not the JSON schema")
        #expect(rawText.contains("Khan Market"), "The host's own words survive to the review screen")
    }

    // MARK: - Helpers

    private static func json(_ payload: ChatSummaryPayload) -> String {
        guard let data = try? JSONEncoder().encode(payload),
              let string = String(data: data, encoding: .utf8)
        else { return "{}" }
        return string
    }
}
