//
//  PlanningRun.swift
//  Wandr
//
//  The run, its phases, and the guard that makes an illegal phase change
//  impossible rather than merely discouraged.
//
//  Only `TravelPlanningService` mutates a run. A view cannot jump from capture
//  straight to curation merely because it has text — the transition table says so,
//  and `transition(to:)` throws when asked to break it.
//

import Foundation

// MARK: - State

/// The phases of one planning run.
///
/// Deliberately payload-free: the transition table is about phase identity alone,
/// which keeps the guard exhaustively testable. The brief, plan, and failure live
/// on `PlanningRun` beside the state.
nonisolated enum PlanningState: String, Sendable, Equatable, Hashable, CaseIterable {
    /// No active request. The capture screen is showing.
    case idle
    /// A request is becoming a structured brief.
    case extracting
    /// A hard constraint is missing or ambiguous.
    case needsDetails
    /// Grounded candidates are being collected.
    case researching
    /// Deterministic feasibility checks are running.
    case validating
    /// Grounded candidate IDs are being ranked.
    case curating
    /// An immutable validated result is ready for the decks and schedule.
    case ready
    /// A recoverable failure with a structured reason.
    case failed
    /// The host stopped the work, or left.
    case cancelled

    /// The states this one may legally advance to.
    ///
    /// Mirrors the transition table in `nonuistuff/plan.md` §6 exactly. Note there
    /// are no self-transitions: re-entering a phase is a bug, not a no-op.
    var legalNextStates: Set<PlanningState> {
        switch self {
        case .idle:         return [.extracting]
        case .extracting:   return [.needsDetails, .researching, .failed, .cancelled]
        case .needsDetails: return [.researching, .cancelled]
        case .researching:  return [.validating, .failed, .cancelled]
        case .validating:   return [.curating, .needsDetails, .failed, .cancelled]
        case .curating:     return [.ready, .failed, .cancelled]
        case .ready:        return [.idle, .researching]
        case .failed:       return [.idle, .extracting, .researching]
        case .cancelled:    return [.idle]
        }
    }

    func canTransition(to next: PlanningState) -> Bool {
        legalNextStates.contains(next)
    }

    /// Whether the run is doing work the host is waiting on.
    var isActive: Bool {
        switch self {
        case .extracting, .researching, .validating, .curating: return true
        case .idle, .needsDetails, .ready, .failed, .cancelled: return false
        }
    }

    /// Whether the run has stopped for good, absent an explicit restart.
    var isTerminal: Bool {
        switch self {
        case .ready, .failed, .cancelled: return true
        default: return false
        }
    }
}

/// Thrown when something tries to move a run along an edge the table forbids.
nonisolated struct IllegalPlanningTransition: Error, Sendable, Equatable, Hashable, CustomStringConvertible {
    let from: PlanningState
    let to: PlanningState

    var description: String {
        "Illegal planning transition: \(from.rawValue) → \(to.rawValue)"
    }
}

// MARK: - Events

/// One line of tool/status transparency.
///
/// Contains what Wandr *did*, never what the model thought and never what the
/// host typed. No chain-of-thought, no raw input, no transcript.
nonisolated struct PlanningEvent: Sendable, Equatable, Hashable, Identifiable {

    nonisolated enum Severity: String, Sendable, Equatable, Hashable, CaseIterable {
        case info
        case warning
        /// Something Wandr could not establish, stated plainly.
        case limitation
    }

    let id: UUID
    let timestamp: Date
    /// The phase the run was in when this happened.
    let phase: PlanningState
    let title: String
    let detail: String?
    let severity: Severity

    init(
        id: UUID = UUID(),
        timestamp: Date,
        phase: PlanningState,
        title: String,
        detail: String? = nil,
        severity: Severity = .info
    ) {
        self.id = id
        self.timestamp = timestamp
        self.phase = phase
        self.title = title
        self.detail = detail
        self.severity = severity
    }
}

// MARK: - Run

/// The single source of truth for one planning attempt.
///
/// Note what is *not* here: `PlanningInput.text`. The run keeps the input's ID and
/// channel for audit, and nothing else. Once the extractor has produced a draft,
/// the host's words have no home in this object — which is why they cannot leak
/// into events, failures, or storage.
nonisolated struct PlanningRun: Sendable, Equatable, Identifiable {

    let id: PlanningRunID
    /// Audit metadata only — the input's identity, not its content.
    let inputID: PlanningInput.ID
    let source: PlanningInputSource
    let startedAt: Date

    private(set) var state: PlanningState
    private(set) var brief: OutingBrief?
    private(set) var events: [PlanningEvent]
    private(set) var failure: PlanningFailure?
    private(set) var plan: WandrPlan?
    private(set) var missingConstraints: [MissingConstraint]
    /// Set the moment the host asks to stop. Checked between phases.
    private(set) var isCancellationRequested: Bool

    /// Starts a run from a validated input, keeping only its provenance.
    init(id: PlanningRunID = PlanningRunID(), input: PlanningInput, startedAt: Date) {
        self.id = id
        self.inputID = input.id
        self.source = input.source
        self.startedAt = startedAt
        self.state = .idle
        self.brief = nil
        self.events = []
        self.failure = nil
        self.plan = nil
        self.missingConstraints = []
        self.isCancellationRequested = false
    }

    // MARK: Transitions

    /// Moves the run to `next`, or throws if the table forbids the edge.
    mutating func transition(to next: PlanningState) throws {
        guard state.canTransition(to: next) else {
            throw IllegalPlanningTransition(from: state, to: next)
        }

        // Leaving a failure or a result behind means clearing it, so a stale
        // failure can never be rendered beside a fresh phase.
        if next == .idle || next == .extracting || next == .researching {
            failure = nil
        }
        if next == .idle {
            brief = nil
            plan = nil
            missingConstraints = []
        }

        state = next
    }

    /// Records the normalized brief. Only meaningful once extraction has succeeded.
    mutating func setBrief(_ brief: OutingBrief) {
        self.brief = brief
    }

    mutating func setMissingConstraints(_ missing: [MissingConstraint]) {
        self.missingConstraints = missing
    }

    /// Moves to `.failed` and attaches the structured reason.
    mutating func fail(_ failure: PlanningFailure) throws {
        try transition(to: .failed)
        self.failure = failure
    }

    /// Moves to `.ready` and attaches the immutable validated result.
    mutating func complete(with plan: WandrPlan) throws {
        try transition(to: .ready)
        self.plan = plan
    }

    /// Marks the run for cancellation. The coordinator checks this between phases.
    mutating func requestCancellation() {
        isCancellationRequested = true
    }

    /// Moves to `.cancelled` and discards everything but provenance.
    mutating func cancel() throws {
        try transition(to: .cancelled)
        isCancellationRequested = true
        brief = nil
        plan = nil
        missingConstraints = []
        failure = PlanningFailure(.cancelled)
    }

    // MARK: Events

    /// Appends one transparency event.
    ///
    /// Callers must pass a fixed, Wandr-authored `title`/`detail`. Never interpolate
    /// `PlanningInput.text` here — that is the one rule this type exists to protect.
    mutating func record(_ event: PlanningEvent) {
        events.append(event)
    }

    mutating func record(
        _ title: String,
        detail: String? = nil,
        severity: PlanningEvent.Severity = .info,
        at timestamp: Date
    ) {
        events.append(
            PlanningEvent(
                timestamp: timestamp,
                phase: state,
                title: title,
                detail: detail,
                severity: severity
            )
        )
    }
}
