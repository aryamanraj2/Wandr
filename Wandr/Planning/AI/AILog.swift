//
//  AILog.swift
//  Wandr
//
//  One place every on-device model call reports what it did.
//
//  Wandr has exactly two model calls — extraction (free text to a summary) and
//  curation (ranking venues) — and both are non-deterministic, both run off the main
//  actor, and both now *degrade* rather than fail. That last property is what makes
//  this file necessary: a curator that quietly falls back to deterministic ranking
//  looks identical, from the UI, to one whose model is working perfectly. Without a
//  log there is no way to tell "the model picked these five" from "the model timed
//  out twice and the provider's ranking picked these five".
//
//  ## Reading it
//
//      log stream --predicate 'subsystem == "com.wandr.ai"' --level debug
//
//  or in Console.app, filter on `com.wandr.ai`. Every line from one planning run
//  carries the same `run=` correlation ID, because slots interleave with retries and
//  the sequence is unreadable without it.
//
//  ## Privacy
//
//  Two levels, deliberately:
//
//  - **Public** — counts, categories, durations, token totals, error classifications,
//    indices. Everything needed to diagnose a failure. Safe in a shipped build.
//  - **Private** — the prompt, the host's words, extracted field *values*. OSLog
//    redacts these to `<private>` in a release build and reveals them when you are
//    attached with Console or a debugger, which is exactly when you want them.
//
//  Nothing is ever written to disk by this file, and no host text is interpolated
//  into a `.public` field. That boundary is the same one `TravelPlanningService`
//  draws for its planning events.
//

import Foundation
import OSLog

/// Structured logging and signposts for the AI path.
nonisolated struct AILog: Sendable {

    static let subsystem = "com.wandr.ai"

    /// Which model call is talking. Separate categories so one can be filtered out.
    nonisolated enum Stage: String, Sendable {
        case curation
        case extraction
    }

    private let logger: Logger
    private let signposter: OSSignposter
    private let stage: Stage

    /// Ties every line from one run together. Slots interleave with retries, so
    /// without this the sequence cannot be reconstructed from the log.
    private let runID: String

    init(stage: Stage, runID: String = String(UUID().uuidString.prefix(8))) {
        self.stage = stage
        self.runID = runID
        self.logger = Logger(subsystem: Self.subsystem, category: stage.rawValue)
        self.signposter = OSSignposter(subsystem: Self.subsystem, category: stage.rawValue)
    }

    // MARK: - Run lifecycle

    func runStarted(detail: String) {
        logger.notice("run=\(runID, privacy: .public) START \(detail, privacy: .public)")
    }

    func runFinished(detail: String, milliseconds: Int) {
        logger.notice("run=\(runID, privacy: .public) DONE \(detail, privacy: .public) elapsed=\(milliseconds, privacy: .public)ms")
    }

    /// The model's own readiness, logged verbatim. The single most common cause of
    /// "the AI does nothing" is that this is not `.available`.
    func availability(_ state: String, contextSize: Int?) {
        if let contextSize {
            logger.notice("run=\(runID, privacy: .public) AVAILABILITY state=\(state, privacy: .public) contextSize=\(contextSize, privacy: .public)")
        } else {
            logger.error("run=\(runID, privacy: .public) AVAILABILITY state=\(state, privacy: .public)")
        }
    }

    // MARK: - Intervals

    func measure<T>(_ name: StaticString, _ label: String, _ body: () async throws -> T) async rethrows -> T {
        let id = signposter.makeSignpostID()
        let state = signposter.beginInterval(name, id: id, "\(label, privacy: .public)")
        defer { signposter.endInterval(name, state) }
        return try await body()
    }

    // MARK: - Prompt

    /// Sizes are public because prompt length is the first thing to check when
    /// generation is slow or the context blows. The prompt itself is private.
    func prompt(label: String, characters: Int, itemCount: Int, text: String) {
        logger.info(
            "run=\(runID, privacy: .public) PROMPT \(label, privacy: .public) chars=\(characters, privacy: .public) items=\(itemCount, privacy: .public)"
        )
        logger.debug("run=\(runID, privacy: .public) PROMPT-BODY \(label, privacy: .public)\n\(text, privacy: .private)")
    }

    /// Token accounting from `LanguageModelSession.Usage`.
    ///
    /// `cached` answers "did prewarm land?" — a warm session reports a non-zero
    /// cached share of its input.
    func usage(label: String, input: Int, cached: Int, output: Int, milliseconds: Int) {
        logger.info(
            """
            run=\(runID, privacy: .public) USAGE \(label, privacy: .public) \
            input=\(input, privacy: .public) cached=\(cached, privacy: .public) \
            output=\(output, privacy: .public) elapsed=\(milliseconds, privacy: .public)ms
            """
        )
    }

    // MARK: - Outcomes

    /// A normal, successful step.
    func event(_ message: String) {
        logger.info("run=\(runID, privacy: .public) \(message, privacy: .public)")
    }

    /// Something worth noticing that is not a failure — a retry, a fallback, a
    /// backfilled deck. These are the lines that reveal a silently degrading model.
    func warning(_ message: String) {
        logger.warning("run=\(runID, privacy: .public) \(message, privacy: .public)")
    }

    /// A failure, with its classification public and its detail private.
    ///
    /// A model error's `description` can quote the prompt back, and the prompt
    /// carries the host's brief — so the classification is what ships, and the raw
    /// text is only visible to someone attached to the device.
    func failure(_ classification: String, detail: String? = nil) {
        logger.error("run=\(runID, privacy: .public) FAIL \(classification, privacy: .public)")
        if let detail {
            logger.debug("run=\(runID, privacy: .public) FAIL-DETAIL \(detail, privacy: .private)")
        }
    }

    /// A wiring bug rather than a runtime condition — something that should be
    /// impossible and means the code is wrong, not the model.
    func fault(_ message: String) {
        logger.fault("run=\(runID, privacy: .public) FAULT \(message, privacy: .public)")
    }
}
