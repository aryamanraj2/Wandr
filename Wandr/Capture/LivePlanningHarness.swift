//
//  LivePlanningHarness.swift
//  Wandr
//
//  The interim doorway (§12.1): the smallest thing that turns the capture screen's
//  text/voice output into a real run through `PlanningAssembly`'s live pipeline, so
//  voice/text → extraction → research → curation → validation → schedule is testable
//  on device before the Siri doorway lands.
//
//  Deliberately observation-poor: no event timeline, no streaming, no `.needsDetails`
//  screen. It holds a status the capture screen can render and the run's ID so the
//  run can be cancelled — nothing more.
//
//  Privacy (§12.1): the submitted text goes into `PlanningInput` and NOWHERE else.
//  It is never assigned to a stored property, never logged. That is why "retry the
//  same request" here means "let the host re-submit" rather than replaying retained
//  text — retaining it would be exactly the leak the whole pipeline is built to
//  prevent.
//

import Foundation
import Observation

@MainActor
@Observable
final class LivePlanningHarness {

    /// What the capture screen shows. No raw input, no model prose — a phase and, on
    /// failure, an already-authored `PlanningFailure` sentence.
    enum Status: Equatable {
        case idle
        case running
        /// A plan is ready. It is *held* (below), not rendered — the curation screen
        /// keeps showing `DemoPlan` until the bridge step.
        case ready
        case failed(message: String, retry: PlanningRetryAction)
    }

    private(set) var status: Status = .idle

    /// The finished plan, held for the "plan ready" acknowledgment. Never rendered in
    /// this step; the bridge step is what draws it. Cleared on reset.
    private(set) var readyPlan: WandrPlan?

    // Built once, lazily, and reused across submissions.
    private var service: TravelPlanningService?
    private var runID: PlanningRunID?
    private var task: Task<Void, Never>?

    /// Starts a live run from freshly submitted text.
    ///
    /// `text` is used to build one `PlanningInput` and is then out of scope — it is
    /// never stored on `self`.
    func start(text: String) {
        cancel(resettingStatus: false)

        let runID = PlanningRunID()
        self.runID = runID
        status = .running
        readyPlan = nil

        task = Task { [weak self] in
            guard let self else { return }
            do {
                let service = try self.liveService()
                let run = try await service.plan(
                    PlanningInput(text: text, source: .directCapture),
                    runID: runID
                )
                self.absorb(run)
            } catch let failure as PlanningFailure {
                // `plan(_:)` throws only `.inputEmpty`; everything else lands on the run.
                self.status = .failed(message: failure.userMessage, retry: failure.retryAction)
            } catch {
                // A construction fault (e.g. the dataset can't be read). Not host-
                // actionable, but never a dead end.
                let fallback = PlanningFailure(.modelAssetsNotReady)
                self.status = .failed(message: fallback.userMessage, retry: fallback.retryAction)
            }
        }
    }

    /// Cancels an in-flight run and returns to idle.
    func cancel() { cancel(resettingStatus: true) }

    /// Dismisses a terminal status (used by the failure "try again" affordance).
    func reset() {
        guard case .running = status else {
            status = .idle
            readyPlan = nil
            return
        }
    }

    // MARK: - Internals

    private func liveService() throws -> TravelPlanningService {
        if let service { return service }
        let built = try PlanningAssembly.liveService()
        service = built
        return built
    }

    private func absorb(_ run: PlanningRun) {
        switch run.state {
        case .ready:
            readyPlan = run.plan
            status = .ready
        case .failed:
            let failure = run.failure ?? PlanningFailure(.structuredOutputDecodingFailed)
            status = .failed(message: failure.userMessage, retry: failure.retryAction)
        case .cancelled:
            status = .idle
        default:
            // No live configuration lands here (`.needsDetails` has no UI in this
            // step), but never leave the host staring at a spinner.
            status = .idle
        }
    }

    private func cancel(resettingStatus: Bool) {
        if let runID, let service {
            Task { await service.requestCancellation(of: runID) }
        }
        task?.cancel()
        task = nil
        runID = nil
        if resettingStatus {
            status = .idle
            readyPlan = nil
        }
    }
}
