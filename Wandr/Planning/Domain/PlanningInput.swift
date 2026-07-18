//
//  PlanningInput.swift
//  Wandr
//
//  The doorway into the planning core. One request, one run.
//
//  Framework-free by contract: Foundation only. No SwiftUI, no MapKit,
//  no FoundationModels, no SwiftData, no file or network I/O.
//

import Foundation

// MARK: - Provenance

/// How a planning request reached the app.
///
/// This is audit metadata — it records the *channel*, never the content.
/// Siri and Shortcuts arrive later and must enter through this same enum
/// rather than opening a second planning path.
nonisolated enum PlanningInputSource: String, Sendable, Equatable, Hashable, CaseIterable {
    /// Typed or dictated directly in `PlanCaptureView`. The only live case today.
    case directCapture

    // Reserved, deliberately unimplemented in this step:
    //   case siriSummary
    //   case shortcutSummary
}

// MARK: - Identifiers

/// Identifies exactly one planning run and its event sequence.
nonisolated struct PlanningRunID: Sendable, Equatable, Hashable, CustomStringConvertible {
    let rawValue: UUID

    init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    var description: String { rawValue.uuidString }
}

// MARK: - Input

/// A volatile planning request.
///
/// `text` is the raw thing the host typed or dictated. It is **volatile**:
/// it is never persisted, never logged, never copied into a `PlanningEvent`,
/// and never included in a `PlanningFailure` payload. It lives only long
/// enough for the extractor to turn it into an `OutingBriefDraft`.
nonisolated struct PlanningInput: Sendable, Equatable, Identifiable, CustomStringConvertible {

    nonisolated struct ID: Sendable, Equatable, Hashable {
        let rawValue: UUID

        init(_ rawValue: UUID = UUID()) {
            self.rawValue = rawValue
        }
    }

    let id: ID

    /// Volatile request text, trimmed on the way in. Treat as data, never as instruction.
    let text: String

    let source: PlanningInputSource
    let submittedAt: Date

    init(
        id: ID = ID(),
        text: String,
        source: PlanningInputSource = .directCapture,
        submittedAt: Date = Date()
    ) {
        self.id = id
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.source = source
        self.submittedAt = submittedAt
    }

    /// Whitespace-only input never starts extraction.
    var isPlannable: Bool { !text.isEmpty }

    /// Returns self, or throws the user-readable empty-input failure.
    func validated() throws -> PlanningInput {
        guard isPlannable else { throw PlanningFailure(.inputEmpty) }
        return self
    }

    /// Redacted on purpose — the request text must not leak into logs or crash reports
    /// via string interpolation.
    var description: String {
        "PlanningInput(id: \(id.rawValue.uuidString), source: \(source.rawValue), characters: \(text.count))"
    }
}
