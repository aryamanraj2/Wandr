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
nonisolated enum OutingType: String, Codable, Sendable, CaseIterable {
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
/// - Note: `nonisolated` throughout. It is a pure value type decoded off the main
///   actor by `ChatSummaryBriefExtractor` and read by the planning core, and a
///   main-actor-isolated `init(from:)` would not satisfy `Decodable` under Swift 6.
nonisolated struct ChatSummaryPayload: Codable, Sendable, Equatable {
    var outingType: OutingType?
    var dateOrDay: String?
    var time: String?
    var area: String?
    var groupSize: Int?
    /// The money the host named, in their own words — "₹2000", "2k each".
    ///
    /// Free text on purpose: the *basis* lives in the wording, and dropping it into
    /// a bare number is what let Wandr read an unqualified "2000" as per head.
    var budget: String?
    var dietary: String?
    var accessibility: String?
    var vibe: String?
    var indoorOutdoor: String?
    /// What the group wants to *do* — "lunch", "drinks after", "a walk somewhere".
    ///
    /// Added because "lunch" previously had nowhere to go. The schema had a slot for
    /// when, where, how many and what mood, but none for the kind of stop, so the
    /// extractor dropped the one word that decides whether the plan contains a
    /// restaurant at all.
    var plannedStops: String?
    /// The same request as `plannedStops`, in Wandr's own closed vocabulary.
    ///
    /// Raw tokens on purpose — validation against `SlotBand` happens once, in
    /// `ChatSummaryBriefMapper`, so an unrecognised word is dropped in exactly one
    /// place rather than trusted here and rejected later.
    var stops: [String]?
    var otherNotes: String?

    /// `true` when the model returned a well-formed object but settled no fields at all.
    /// Treated as "no usable summary" by the inbox.
    var isEmpty: Bool {
        outingType == nil
            && dateOrDay.isNilOrBlank
            && time.isNilOrBlank
            && area.isNilOrBlank
            && groupSize == nil
            && budget.isNilOrBlank
            && dietary.isNilOrBlank
            && accessibility.isNilOrBlank
            && vibe.isNilOrBlank
            && indoorOutdoor.isNilOrBlank
            && plannedStops.isNilOrBlank
            && (stops?.isEmpty ?? true)
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
        add("Plan", plannedStops)
        add("Date / day", dateOrDay)
        add("Time", time)
        add("Area", area)
        if let groupSize { rows.append(("Group size", "\(groupSize)")) }
        add("Budget", budget)
        add("Dietary", dietary)
        add("Accessibility", accessibility)
        add("Vibe", vibe)
        add("Indoor / outdoor", indoorOutdoor)
        add("Other notes", otherNotes)
        return rows
    }
}

// MARK: - Coding

nonisolated extension ChatSummaryPayload {

    enum CodingKeys: String, CodingKey {
        case outingType, dateOrDay, time, area, groupSize, budget
        case dietary, accessibility, vibe, indoorOutdoor, plannedStops, stops, otherNotes
        /// The key this field shipped under before the per-head/total distinction
        /// existed. Shortcuts already installed on a host's phone still emit it, and
        /// they update on Apple's schedule rather than ours, so it is read forever.
        case legacyBudgetPerHead = "budgetPerHead"
    }

    /// Hand-written so the retired `budgetPerHead` key still decodes. Everything else
    /// is `decodeIfPresent`, matching the lenient contract in this file's header: a
    /// missing key, a null, or an unexpected extra key must never fail the payload.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            outingType: try container.decodeIfPresent(OutingType.self, forKey: .outingType),
            dateOrDay: try container.decodeIfPresent(String.self, forKey: .dateOrDay),
            time: try container.decodeIfPresent(String.self, forKey: .time),
            area: try container.decodeIfPresent(String.self, forKey: .area),
            groupSize: try container.decodeIfPresent(Int.self, forKey: .groupSize),
            budget: try container.decodeIfPresent(String.self, forKey: .budget)
                ?? container.decodeIfPresent(String.self, forKey: .legacyBudgetPerHead),
            dietary: try container.decodeIfPresent(String.self, forKey: .dietary),
            accessibility: try container.decodeIfPresent(String.self, forKey: .accessibility),
            vibe: try container.decodeIfPresent(String.self, forKey: .vibe),
            indoorOutdoor: try container.decodeIfPresent(String.self, forKey: .indoorOutdoor),
            plannedStops: try container.decodeIfPresent(String.self, forKey: .plannedStops),
            stops: try container.decodeIfPresent([String].self, forKey: .stops),
            otherNotes: try container.decodeIfPresent(String.self, forKey: .otherNotes)
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(outingType, forKey: .outingType)
        try container.encodeIfPresent(dateOrDay, forKey: .dateOrDay)
        try container.encodeIfPresent(time, forKey: .time)
        try container.encodeIfPresent(area, forKey: .area)
        try container.encodeIfPresent(groupSize, forKey: .groupSize)
        try container.encodeIfPresent(budget, forKey: .budget)
        try container.encodeIfPresent(dietary, forKey: .dietary)
        try container.encodeIfPresent(accessibility, forKey: .accessibility)
        try container.encodeIfPresent(vibe, forKey: .vibe)
        try container.encodeIfPresent(indoorOutdoor, forKey: .indoorOutdoor)
        try container.encodeIfPresent(plannedStops, forKey: .plannedStops)
        try container.encodeIfPresent(stops, forKey: .stops)
        try container.encodeIfPresent(otherNotes, forKey: .otherNotes)
    }
}

// MARK: - Decoding

nonisolated extension ChatSummaryPayload {

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

nonisolated private extension Optional where Wrapped == String {
    var isNilOrBlank: Bool {
        switch self {
        case .none: return true
        case .some(let value): return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}
