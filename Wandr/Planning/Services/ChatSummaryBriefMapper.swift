//
//  ChatSummaryBriefMapper.swift
//  Wandr
//
//  Deterministic bridge: the group-booking summary (`ChatSummaryPayload`) → the
//  planning core's uncertain draft (`OutingBriefDraft`).
//
//  The group booking already arrives structured, so turning it into a brief needs
//  no model — this is pure parsing. It is the JSON-first replacement for the
//  free-text `FakeBriefExtractor`: loose strings ("₹1,500", "vegetarian", "free
//  only 8–9pm") become typed fields the pipeline can reason about.
//
//  Foundation only. Every value it emits is a *suggestion* — `BriefNormalizer`
//  still decides what is `.host` vs `.safeDefault`, and the host still reviews it.
//  Prompt-like text in any field is data: it is copied into the draft, never acted on.
//

import Foundation

/// Turns a settled `ChatSummaryPayload` into an `OutingBriefDraft`.
nonisolated struct ChatSummaryBriefMapper: Sendable {

    init() {}

    func draft(from payload: ChatSummaryPayload) -> OutingBriefDraft {
        OutingBriefDraft(
            occasion: payload.outingType?.display,
            timeWindow: Self.timeWindow(day: payload.dateOrDay, time: payload.time),
            area: payload.area?.trimmed.nonEmpty,
            groupSize: payload.groupSize,
            budgetPerHeadRupees: Self.rupees(from: payload.budgetPerHead),
            vibeTags: Self.vibeTags(from: payload.vibe),
            dietary: Self.dietary(from: payload.dietary),
            accessibility: Self.accessibility(from: payload.accessibility),
            setting: Self.setting(from: payload.indoorOutdoor),
            notes: payload.otherNotes?.trimmed.nonEmpty.map { [$0] } ?? []
        )
    }

    // MARK: - Budget

    /// First monetary figure in the string. Tolerates "₹", commas, "per head", and a
    /// trailing "k" (1.5k → 1500). Absent or unparseable → `nil` (normalizer defaults it).
    static func rupees(from raw: String?) -> Int? {
        guard let raw else { return nil }
        let scalars = Array(raw.lowercased().replacingOccurrences(of: ",", with: ""))

        var i = 0
        while i < scalars.count {
            guard scalars[i].isNumber else { i += 1; continue }

            var numberText = ""
            while i < scalars.count, scalars[i].isNumber || scalars[i] == "." {
                numberText.append(scalars[i]); i += 1
            }
            // Skip a single space before a "k" suffix ("1.5 k").
            var j = i
            while j < scalars.count, scalars[j] == " " { j += 1 }
            let hasK = j < scalars.count && scalars[j] == "k"

            guard let value = Double(numberText) else { return nil }
            return Int((hasK ? value * 1_000 : value).rounded())
        }
        return nil
    }

    // MARK: - Vibe

    /// Splits a vibe phrase into soft tags. "loud and fun" → ["loud", "fun"].
    static func vibeTags(from raw: String?) -> [String] {
        guard let raw = raw?.trimmed.nonEmpty else { return [] }
        let separators = CharacterSet(charactersIn: ",/&")
        return raw
            .lowercased()
            .components(separatedBy: separators)
            .flatMap { $0.components(separatedBy: " and ") }
            .map { $0.trimmed }
            .filter { !$0.isEmpty && $0 != "and" }
    }

    // MARK: - Dietary

    static func dietary(from raw: String?) -> DietaryNeeds {
        constraint(from: raw) { text in
            var found: Set<DietaryRequirement> = []
            if text.contains("vegan") { found.insert(.vegan) }
            // "vegetarian"/"veg", but not the "veg" inside "vegan".
            if text.contains("vegetarian") || text.matchesWord("veg") { found.insert(.vegetarian) }
            if text.contains("jain") { found.insert(.jain) }
            if text.contains("halal") { found.insert(.halal) }
            if text.contains("gluten") { found.insert(.glutenFree) }
            return found
        }
    }

    // MARK: - Accessibility

    static func accessibility(from raw: String?) -> AccessibilityNeeds {
        constraint(from: raw) { text in
            var found: Set<AccessibilityRequirement> = []
            if text.contains("step-free") || text.contains("step free")
                || text.contains("stepfree") || text.contains("wheelchair")
                || text.contains("ramp") { found.insert(.stepFreeEntry) }
            if text.contains("elevator") || text.contains("lift") { found.insert(.elevatorAccess) }
            if text.contains("restroom") || text.contains("washroom")
                || text.contains("toilet") || text.contains("accessible bathroom") {
                found.insert(.accessibleRestroom)
            }
            return found
        }
    }

    /// Shared shape for both hard-constraint fields: absent/blank → `.unknown`,
    /// an explicit "none"/"no restrictions" → `.noneStated`, matched keywords →
    /// `.required`, and a present-but-unrecognised value → `.unknown` (never invented).
    private static func constraint<R: Sendable & Hashable & Comparable>(
        from raw: String?,
        match: (String) -> Set<R>
    ) -> ConstraintNeed<R> {
        guard let text = raw?.trimmed.nonEmpty?.lowercased() else { return .unknown }
        if text.contains("none") || text.contains("no restriction")
            || text.contains("no requirement") || text == "na" || text == "n/a"
            || text.contains("anything") || text.contains("no preference") {
            return .noneStated
        }
        let found = match(text)
        return found.isEmpty ? .unknown : .required(found)
    }

    // MARK: - Setting

    static func setting(from raw: String?) -> SettingPreference {
        guard let text = raw?.trimmed.nonEmpty?.lowercased() else { return .noPreference }
        let indoor = text.contains("indoor")
        let outdoor = text.contains("outdoor") || text.contains("open air") || text.contains("open-air")
        switch (indoor, outdoor) {
        case (true, true):   return .mixed
        case (true, false):  return .indoor
        case (false, true):  return .outdoor
        case (false, false): return text.contains("mixed") || text.contains("both") ? .mixed : .noPreference
        }
    }

    // MARK: - Time window

    /// Parses a day label plus a loose time phrase into an `OutingTimeWindow`.
    ///
    /// Understands ranges ("8–9pm", "8 to 9"), lower bounds ("after 8", "from 8pm"),
    /// upper bounds ("finish by 9", "till 9", "before 9pm"), and durations ("3 hours",
    /// "a couple of hours", "90 mins"). Meridiem is inferred: a stated am/pm on any
    /// token applies to the others, and an unqualified evening hour defaults to pm.
    ///
    /// - Important: durations are consumed *first* and cut out of the phrase before
    ///   any clock token is read. "3 hours" shares its digits with "3 o'clock", and
    ///   leaving them in is what used to turn "we've only got 3 hours" into a 3 pm
    ///   start with no end — a window that constrained nothing and planned a full day.
    static func timeWindow(day: String?, time: String?) -> OutingTimeWindow {
        let dayLabel = day?.trimmed.nonEmpty
        guard let raw = time?.trimmed.nonEmpty?.lowercased() else {
            return OutingTimeWindow(dayLabel: dayLabel)
        }

        let (duration, phrase) = extractDuration(from: raw)

        let times = clockTokens(in: phrase)
        guard !times.isEmpty else {
            return OutingTimeWindow(maximumDurationMinutes: duration, dayLabel: dayLabel)
        }

        let hasLowerKeyword = ["after", "from", "not before", "starting", "start"].contains { phrase.contains($0) }
        let hasUpperKeyword = ["by", "before", "till", "until", "finish", "end", "wrap", "done"].contains { phrase.contains($0) }
        let isRange = times.count >= 2 || phrase.contains("-") || phrase.contains("–")
            || phrase.contains(" to ") || phrase.contains("between")

        var earliest: Int?
        var latest: Int?

        if isRange, times.count >= 2 {
            earliest = times[0]
            latest = times[1]
        } else if hasUpperKeyword && !hasLowerKeyword {
            latest = times.last
        } else if hasLowerKeyword {
            earliest = times.first
        } else {
            // A bare time is read as a start.
            earliest = times.first
        }

        return OutingTimeWindow(
            earliestStartMinute: earliest,
            latestEndMinute: latest,
            maximumDurationMinutes: duration,
            dayLabel: dayLabel
        )
    }

    // MARK: - Duration

    /// The longest outing the phrase allows, plus the phrase with that text removed.
    ///
    /// Returns `(nil, phrase)` unchanged when no duration is stated, so a pure clock
    /// phrase takes exactly the path it always did.
    static func extractDuration(from phrase: String) -> (minutes: Int?, remainder: String) {
        var remainder = phrase
        var minutes: Int?

        /// Cuts the first match out of `remainder` so its digits cannot be re-read
        /// as a clock time, and records the duration if this is the first one found.
        func take(_ range: Range<String.Index>, _ value: Int) {
            if minutes == nil { minutes = value }
            remainder.replaceSubrange(range, with: " ")
        }

        // Worded amounts first: they carry no digits, so a later numeric scan would
        // miss them entirely ("a couple of hours" has nothing for `clockTokens`).
        for (words, value) in wordedDurations {
            if let range = remainder.range(of: words) { take(range, value) }
        }

        // Then "<number> <unit>", left to right. The unit decides the scale, so
        // "90 mins" and "1.5 hours" both land on the same axis. Every match is cut,
        // not just the first — a second duration's digits would otherwise be read
        // as a clock time by the scan that follows.
        while let match = numericDuration(in: remainder) {
            take(match.range, match.minutes)
        }

        guard let found = minutes else { return (nil, phrase) }
        // A duration longer than a full day is a misread, not a plan.
        return (min(max(found, minimumDurationMinutes), maximumDurationMinutes), remainder)
    }

    /// Shortest duration worth honouring — below one stop, a cap says nothing useful.
    private static let minimumDurationMinutes = 30
    private static let maximumDurationMinutes = 18 * 60

    /// Phrasings with no digits to scan. Longest first, so "half an hour" is not
    /// matched as the "an hour" inside it.
    private static let wordedDurations: [(String, Int)] = [
        ("hour and a half", 90),
        ("couple of hours", 120),
        ("couple hours", 120),
        ("few hours", 180),
        ("half an hour", 30),
        ("half hour", 30),
        ("an hour", 60),
        ("one hour", 60),
        ("two hours", 120),
        ("three hours", 180),
        ("four hours", 240),
        ("five hours", 300),
        ("six hours", 360)
    ]

    /// The first "<number> <unit>" in `text`, as minutes plus the range it occupied.
    /// `nil` when the text holds no numeric duration.
    ///
    /// The caller cuts the returned range out before asking again, which is what
    /// makes repeated calls terminate.
    private static func numericDuration(
        in text: String
    ) -> (minutes: Int, range: Range<String.Index>)? {

        var index = text.startIndex
        while index < text.endIndex {
            guard text[index].isNumber else {
                index = text.index(after: index)
                continue
            }

            let numberStart = index
            var numberText = ""
            while index < text.endIndex, text[index].isNumber || text[index] == "." {
                numberText.append(text[index])
                index = text.index(after: index)
            }

            // Optional space, then the unit word.
            var unitStart = index
            while unitStart < text.endIndex, text[unitStart] == " " {
                unitStart = text.index(after: unitStart)
            }
            let tail = text[unitStart...]

            guard let value = Double(numberText) else { continue }

            // "hrs"/"hours"/"h" before "m", so "1h" is not read as a minute unit.
            for (unit, isHours) in [("hour", true), ("hrs", true), ("hr", true),
                                    ("minute", false), ("mins", false), ("min", false),
                                    ("h", true), ("m", false)] {
                guard tail.hasPrefix(unit) else { continue }

                var after = text.index(unitStart, offsetBy: unit.count)
                // A bare unit letter must not be the head of a longer word: "3 monday"
                // is a day, not three minutes.
                if unit.count == 1, after < text.endIndex, text[after].isLetter { break }
                // Swallow the rest of the word ("hour" → "hours") so no stray letters
                // survive into the clock scan.
                while after < text.endIndex, text[after].isLetter {
                    after = text.index(after: after)
                }

                let minutes = Int((isHours ? value * 60 : value).rounded())
                return (minutes, numberStart..<after)
            }
        }
        return nil
    }

    /// Every "h", "h:mm", "hpm", "h:mm am" token in the phrase, resolved to minutes
    /// from midnight in reading order. Meridiem stated on any token is applied to
    /// the ones without it.
    private static func clockTokens(in phrase: String) -> [Int] {
        struct Raw { let hour: Int; let minute: Int; var meridiem: Meridiem? }
        enum Meridiem { case am, pm }

        let chars = Array(phrase)
        var raws: [Raw] = []
        var i = 0

        while i < chars.count {
            guard chars[i].isNumber else { i += 1; continue }

            var hourText = ""
            while i < chars.count, chars[i].isNumber, hourText.count < 2 { hourText.append(chars[i]); i += 1 }
            guard let hour = Int(hourText), (0...23).contains(hour) else { continue }

            var minute = 0
            if i < chars.count, chars[i] == ":" {
                i += 1
                var minuteText = ""
                while i < chars.count, chars[i].isNumber, minuteText.count < 2 { minuteText.append(chars[i]); i += 1 }
                minute = Int(minuteText) ?? 0
            }

            var j = i
            while j < chars.count, chars[j] == " " { j += 1 }
            var meridiem: Meridiem?
            if j + 1 < chars.count, chars[j] == "a" || chars[j] == "p", chars[j + 1] == "m" {
                meridiem = chars[j] == "a" ? .am : .pm
                i = j + 2
            }

            raws.append(Raw(hour: hour, minute: minute, meridiem: meridiem))
        }

        // Apply any stated meridiem to the tokens that lacked one.
        if let stated = raws.compactMap(\.meridiem).last {
            for k in raws.indices where raws[k].meridiem == nil { raws[k].meridiem = stated }
        }

        return raws.map { raw in
            var h = raw.hour
            switch raw.meridiem {
            case .pm: if h < 12 { h += 12 }
            case .am: if h == 12 { h = 0 }
            case .none: if h >= 1 && h <= 11 { h += 12 } // unqualified → evening default
            }
            return h * 60 + raw.minute
        }
    }
}

// MARK: - Small string helpers

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nonEmpty: String? { isEmpty ? nil : self }

    /// Whole-word containment, so "veg" doesn't match inside "vegan"/"vegetables".
    func matchesWord(_ word: String) -> Bool {
        components(separatedBy: CharacterSet.alphanumerics.inverted).contains(word)
    }
}
