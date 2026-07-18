//
//  ChatSummaryPayload.swift
//  Wandr
//
//  The "final JSON summary" — the structured shape the Wandr chat-import Shortcut
//  emits from its `Use Model` (Apple Intelligence) step, and the one place that
//  shape is defined in Swift. The Shortcut's extraction prompt (chat-extraction-prompt.txt)
//  is hand-mirrored against this schema; keep the two in sync.
//
//  This value type is untrusted external content: it describes what a group *said*
//  they wanted, never an instruction to the app. It is shown on Host Review and
//  discarded on confirm/cancel — never persisted.
//

import Foundation

/// The outing categories the group can settle on. Mirrors the vocabulary in
/// `Docs/AI-Orchestration-Flow.md` ("after-office, birthday, get-together, full-day, or custom").
enum OutingType: String, Codable, Sendable, CaseIterable {
    case afterOffice = "after-office"
    case birthday
    case getTogether = "get-together"
    case fullDay = "full-day"
    case custom

    var display: String {
        switch self {
        case .afterOffice: return "After-office"
        case .birthday:    return "Birthday"
        case .getTogether: return "Get-together"
        case .fullDay:     return "Full-day"
        case .custom:      return "Custom"
        }
    }
}

/// The structured summary handed to Wandr through the single intent doorway.
///
/// Every field is optional: the model emits only what the group actually agreed on,
/// skipping anything left open (`Docs/plan.md` §6.1a). Decoding is deliberately lenient —
/// a missing key, a null, or an unexpected extra key must never fail the whole payload.
struct ChatSummaryPayload: Codable, Sendable, Equatable {
    var outingType: OutingType?
    var dateOrDay: String?
    var time: String?
    var area: String?
    var groupSize: Int?
    var budgetPerHead: String?
    var dietary: String?
    var accessibility: String?
    var vibe: String?
    var indoorOutdoor: String?
    var otherNotes: String?

    /// `true` when the model returned a well-formed object but settled no fields at all.
    /// Treated as "no usable summary" by the inbox.
    var isEmpty: Bool {
        outingType == nil
            && dateOrDay.isNilOrBlank
            && time.isNilOrBlank
            && area.isNilOrBlank
            && groupSize == nil
            && budgetPerHead.isNilOrBlank
            && dietary.isNilOrBlank
            && accessibility.isNilOrBlank
            && vibe.isNilOrBlank
            && indoorOutdoor.isNilOrBlank
            && otherNotes.isNilOrBlank
    }

    /// Labeled rows for Host Review, in a stable reading order, skipping unsettled fields.
    var displayFields: [(label: String, value: String)] {
        var rows: [(String, String)] = []
        func add(_ label: String, _ value: String?) {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty { rows.append((label, trimmed)) }
        }
        if let outingType { rows.append(("Outing", outingType.display)) }
        add("Date / day", dateOrDay)
        add("Time", time)
        add("Area", area)
        if let groupSize { rows.append(("Group size", "\(groupSize)")) }
        add("Budget / head", budgetPerHead)
        add("Dietary", dietary)
        add("Accessibility", accessibility)
        add("Vibe", vibe)
        add("Indoor / outdoor", indoorOutdoor)
        add("Other notes", otherNotes)
        return rows
    }
}

// MARK: - Decoding

extension ChatSummaryPayload {

    /// The result of trying to read raw handed-in text as a structured summary.
    enum DecodeResult: Sendable, Equatable {
        /// Valid JSON object carrying at least one settled field.
        case structured(ChatSummaryPayload)
        /// Non-empty text that isn't our JSON schema (e.g. conversational Siri prose,
        /// or a well-formed-but-empty object). Not a dead end — shown raw on Host Review.
        case unstructured(String)
        /// Nothing usable — empty or whitespace only. Routes to the recovery state.
        case empty
    }

    /// Decode raw intent text into a summary. Tolerant of the wrapping the Shortcuts
    /// runtime and Apple Intelligence sometimes add (leading/trailing prose, ```json fences).
    static func decode(from rawText: String) -> DecodeResult {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

        guard let jsonSlice = extractJSONObject(from: trimmed),
              let data = jsonSlice.data(using: .utf8),
              let payload = try? JSONDecoder().decode(ChatSummaryPayload.self, from: data)
        else {
            return .unstructured(trimmed)
        }

        return payload.isEmpty ? .unstructured(trimmed) : .structured(payload)
    }

    /// Pull the outermost `{ ... }` object out of a string, tolerating a code fence or
    /// a sentence of preamble around it. Returns `nil` when no braces are present.
    private static func extractJSONObject(from text: String) -> String? {
        guard let open = text.firstIndex(of: "{"),
              let close = text.lastIndex(of: "}"),
              open < close
        else { return nil }
        return String(text[open...close])
    }
}

// MARK: - Helpers

private extension Optional where Wrapped == String {
    var isNilOrBlank: Bool {
        switch self {
        case .none: return true
        case .some(let value): return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}
