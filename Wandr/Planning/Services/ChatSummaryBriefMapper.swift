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
            budget: Self.budget(from: payload.budget),
            vibeTags: Self.vibeTags(from: payload.vibe),
            dietary: Self.dietary(from: payload.dietary),
            accessibility: Self.accessibility(from: payload.accessibility),
            setting: Self.setting(from: payload.indoorOutdoor),
            requestedStops: Self.requestedStops(from: payload),
            stopsAreExclusive: Self.stopsAreExclusive(from: payload),
            // No fallback reading of the words here, deliberately. Every other field on
            // this mapper has a keyword scan behind it because the model drops fields;
            // an occasion cannot have one, because the whole point of these four values
            // is that they describe nights nobody enumerated. A missing profile is an
            // unspecified one, and an unspecified one still plans.
            occasionProfile: payload.occasionProfile ?? .unspecified,
            notes: payload.otherNotes?.trimmed.nonEmpty.map { [$0] } ?? []
        )
    }

    /// Whether the host said these are the *only* stops they want.
    ///
    /// The model's own answer when it gave one, or the deterministic scan — the same
    /// "either source is enough" rule `stops(classified:inText:)` runs under, and for
    /// the same reason: a flag the model dropped must not silently become `false`.
    static func stopsAreExclusive(from payload: ChatSummaryPayload) -> Bool {
        payload.onlyTheseStops == true || statesExclusiveStops(inText: haystack(of: payload))
    }

    // MARK: - Requested stops

    /// The stops the host asked for.
    static func requestedStops(from payload: ChatSummaryPayload) -> Set<SlotBand> {
        stops(classified: payload.stops, inText: haystack(of: payload))
    }

    /// The stops a request names, from the model's classification *and* the words
    /// themselves.
    ///
    /// Three sources, and the order between the first two is the fix for the reported
    /// bug:
    ///
    /// 1. **The model's classification**, validated against `SlotBand` so an invented
    ///    token is dropped rather than trusted. This is the path that handles
    ///    "something to eat before the movie" — a phrase no keyword list will contain.
    /// 2. **Band words the host actually typed**, *unioned* with (1), not used as a
    ///    fallback for it. A host who writes "dinner" has already told us the stop in
    ///    Wandr's own vocabulary; treating that as a mere backup meant a run where the
    ///    model dropped the field lost the word entirely, and the same sentence planned
    ///    a different night depending on how the generation went. Deterministic
    ///    evidence should never lose to a probabilistic one that says nothing.
    /// 3. **Category words** — "eat", "drinks" — but only for a *kind of stop nothing
    ///    above already covers*. "Dinner then drinks" needs the nightlife half or it
    ///    plans one stop instead of two; "dinner" with a vibe of "loves coffee" must
    ///    not gain a second meal from that word. Coverage by category is what
    ///    separates the two, and it is why these are neither unioned outright nor
    ///    demoted to a plain fallback.
    ///
    /// - Parameters:
    ///   - classified: the model's own tokens, if it produced any.
    ///   - text: what the host wrote — their raw words on the capture path, the
    ///     settled summary fields on the Siri one.
    static func stops(classified: [String]?, inText text: String) -> Set<SlotBand> {
        let fromModel = Set((classified ?? []).compactMap(band(named:)))
        let named = fromModel.union(bandsNamed(inText: text))

        let covered = Set(named.map(\.category))
        let byKind = categoriesNamed(inText: text).filter { !covered.contains($0.category) }

        return named.union(byKind)
    }

    /// Whether the host said these are the *only* stops they want.
    ///
    /// Proximity, not mere presence: "just" and "only" are among the commonest words
    /// in a sentence about plans, and `"just 2 of us for dinner"` is not a request for
    /// a one-stop night. The word has to sit beside a stop word to mean exclusivity.
    ///
    /// Two tokens either side, which is tight on purpose. Three caught `"only 1500
    /// each, dinner somewhere"` — an exclusivity word doing its job on the *budget*,
    /// three tokens away from a stop it had nothing to do with — and reading that as
    /// "dinner and nothing else" would have thrown away most of their night. Two still
    /// covers "just dinner", "just the breakfast plan", "only doing lunch", "we just
    /// want lunch", and "dinner and nothing else".
    static func statesExclusiveStops(inText raw: String) -> Bool {
        let tokens = raw.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        for (index, token) in tokens.enumerated() where exclusivityWords.contains(token) {
            let lower = max(0, index - 2)
            let upper = min(tokens.count - 1, index + 2)
            for neighbour in lower...upper
            where neighbour != index && allStopWords.contains(tokens[neighbour]) {
                return true
            }
        }
        return false
    }

    private static let exclusivityWords: Set<String> = [
        "just", "only", "nothing", "solely", "merely", "simply"
    ]

    /// Every word that names a stop, of either kind. Used only by the exclusivity
    /// scan, which cares that a stop was mentioned, not which one.
    private static let allStopWords: Set<String> = Set(
        bandKeywords.values.flatMap { $0 } + categoryKeywords.values.flatMap { $0 }
    )

    /// One model-emitted token resolved to a band, or `nil` if it is not one of ours.
    ///
    /// Case- and whitespace-tolerant, because a model told to answer "somethingNew"
    /// will sometimes answer "Something New" and that is not a different request.
    static func band(named raw: String) -> SlotBand? {
        let squashed = raw.lowercased().filter(\.isLetter)
        return SlotBand.allCases.first { $0.rawValue.lowercased() == squashed }
    }

    /// The fields a stop word could have landed in, joined for scanning.
    ///
    /// Deliberately several fields rather than only `plannedStops`: the word that
    /// matters ("lunch", "drinks") lands wherever the extractor decided to put it, and
    /// missing it costs the host the one stop they actually asked for. Area is
    /// excluded — half the neighbourhoods in Delhi have "Market" in the name.
    ///
    /// This is the Siri path's substitute for the host's raw words, which are gone by
    /// the time a summary reaches the mapper. The capture path passes the real text.
    static func haystack(of payload: ChatSummaryPayload) -> String {
        [
            payload.plannedStops,
            payload.otherNotes,
            payload.time,
            payload.vibe,
            payload.outingType?.rawValue
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")
    }

    /// Stops named outright — words that fix the kind of stop *and* when it happens.
    ///
    /// Whole-word matched, and every entry is a noun that names a stop, never a mood
    /// or an adjective: this set seeds the plan's shape, so a false positive here
    /// invents a stop the host never asked for.
    static func bandsNamed(inText raw: String) -> Set<SlotBand> {
        guard !raw.isEmpty else { return [] }
        let haystack = raw.lowercased()
        return Set(
            bandKeywords
                .filter { _, words in words.contains { haystack.matchesWord($0) } }
                .keys
        )
    }

    /// Stops named only by kind — "somewhere to eat", "drinks".
    ///
    /// Offers every band the category can occupy and lets the window pin it down: an
    /// open evening makes "somewhere to eat" dinner, a midday one makes it lunch.
    /// Naming the meal outright is what fixes it to one.
    static func categoriesNamed(inText raw: String) -> Set<SlotBand> {
        guard !raw.isEmpty else { return [] }
        let haystack = raw.lowercased()

        var found: Set<SlotBand> = []
        for (category, words) in categoryKeywords
        where words.contains(where: { haystack.matchesWord($0) }) {
            found.formUnion(SlotBand.all(in: category))
        }
        return found
    }

    /// Words that name a stop *and* when it happens. Whole-word matched.
    ///
    /// `breakfast` has its own band now. It used to be listed under `.lunch`, because
    /// the band table began at noon and there was nowhere else to put it — which meant
    /// a host asking for breakfast was scheduled a 12 o'clock meal.
    private static let bandKeywords: [SlotBand: [String]] = [
        .breakfast: ["breakfast", "brekkie"],
        // Brunch sits across both bands; lunch is the safer of the two, and a stated
        // morning window still moves it since the band has to fit the window anyway.
        .lunch: ["lunch", "brunch"],
        .dinner: ["dinner", "supper"]
    ]

    /// Words that name a kind of stop but not a time of day. Whole-word matched, so
    /// "bar" does not fire on "barbecue" and "walk" does not fire on "walkable".
    private static let categoryKeywords: [SlotCategory: [String]] = [
        .food: ["eat", "eating", "food", "meal", "meals", "restaurant", "restaurants",
                "cafe", "café", "coffee", "bite", "biryani", "pizza", "thali",
                "dessert", "snacks"],
        .nightlife: ["drink", "drinks", "bar", "bars", "pub", "pubs", "club", "clubbing",
                     "party", "cocktail", "cocktails", "beer", "wine", "nightcap",
                     "nightlife", "dancing"],
        .sights: ["sightseeing", "sights", "monument", "monuments", "park", "walk",
                  "garden", "gardens", "museum", "gallery", "temple", "fort", "tomb",
                  "view", "views", "stroll", "heritage"],
        .discover: ["shopping", "shop", "shops", "bookstore", "bookshop", "books",
                    "browse", "browsing", "activity", "arcade", "workshop", "gaming",
                    "bowling", "karaoke"]
    ]

    // MARK: - Group size

    /// How many people are going, read straight out of what the host wrote.
    ///
    /// A headcount is a small number sitting next to a word that says it counts
    /// people — something Swift reads exactly and a twelve-field generation cannot be
    /// relied on to. It is the same argument as `stops(classified:inText:)`: a fact the
    /// host stated plainly should not depend on which fields a particular run happened
    /// to get right.
    ///
    /// Deliberately narrow, because a sentence about an outing is full of numbers that
    /// are not people. It fires only on a value in `GroupSize.supportedRange` that is
    /// *marked* as a headcount — by a following noun ("4 people", "6 of us") or a
    /// preceding preposition ("for 2", "table of 8") — and never when the next word
    /// makes it a time or an amount: "only 3 hours" is not a party of three, and
    /// "2000 each" is out of range before the question is even asked.
    static func groupSize(inText raw: String) -> Int? {
        let tokens = raw.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        for (index, token) in tokens.enumerated() {
            guard let value = Int(token) ?? wordedNumbers[token],
                  GroupSize.supportedRange.contains(value)
            else { continue }

            let next = index + 1 < tokens.count ? tokens[index + 1] : nil

            // The number is counting hours, rupees or o'clock, not people.
            if let next, nonHeadcountUnits.contains(next) { continue }

            let followedByNoun = next.map(headcountNouns.contains) ?? false
            // "6 of us", "just the two of them".
            let followedByOfUs = next == "of" && index + 2 < tokens.count
                && ["us", "them"].contains(tokens[index + 2])
            let precededByMarker = index > 0 && headcountMarkers.contains(tokens[index - 1])

            if followedByNoun || followedByOfUs || precededByMarker { return value }
        }
        return nil
    }

    /// Nouns that make the number in front of them a headcount.
    private static let headcountNouns: Set<String> = [
        "people", "person", "persons", "pax", "adults", "friends", "guys", "folks", "heads"
    ]

    /// Words that make the number *after* them a headcount — "for 2", "party of 8".
    private static let headcountMarkers: Set<String> = ["for", "of"]

    /// Units that prove the number counts something other than people. Without these,
    /// "we've only got 3 hours" reads as a group of three.
    private static let nonHeadcountUnits: Set<String> = [
        "hour", "hours", "hr", "hrs", "minute", "minutes", "min", "mins",
        "am", "pm", "oclock", "k", "rs", "rupees", "inr", "each", "pp", "ph"
    ]

    /// "Just the two of us" is the commonest way to say a group of two and carries no
    /// digit at all.
    private static let wordedNumbers: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
        "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12
    ]

    // MARK: - Budget

    /// The ceiling the host named, in the basis they named it in.
    ///
    /// The basis is read from their own words and never assumed. An unqualified
    /// "2000" is the group's *total*, because that is the weaker of the two
    /// readings and the only one they actually said — reading it as ₹2000 each
    /// invents a budget four times larger for a group of four, and then compares
    /// it against a per-head venue price. That mismatch is what told two people
    /// with ₹2000 between them that an ordinary dinner was over their limit.
    static func budget(from raw: String?) -> Budget? {
        guard let raw, let rupees = rupees(from: raw) else { return nil }
        return .clamping(rupees: rupees, perHead: statesPerHead(raw))
    }

    /// Whether the phrase says the number is *each*.
    ///
    /// Whole-word matched where the token is a word, so "app" does not read as "pp".
    static func statesPerHead(_ raw: String) -> Bool {
        let text = raw.lowercased()
        if ["per head", "a head", "per person", "a person", "each", "/head", "/person",
             "per pax", "a pax", "apiece"].contains(where: text.contains) {
            return true
        }
        // "pp" and "pax" only as standalone words — "2k pp", not "shopping".
        return ["pp", "pax", "ph"].contains { text.matchesWord($0) }
    }

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

            // "8:30" and "8.30" are the same time. A dot counts only when a digit
            // follows it, which is what separates a minute separator from a sentence
            // ending in an hour ("we're free from 8. Anywhere is fine").
            //
            // Without this, "12.00" split into *two* tokens — hour 12, then hour 00 —
            // and the second inherited the phrase's trailing meridiem to become a
            // second 12:00 pm. In a range that made the finish equal the start.
            // Durations are cut out of the phrase before this runs, so "1.5 hours"
            // never reaches here and cannot be misread as 1:05.
            var minute = 0
            let separatesMinutes = i < chars.count
                && (chars[i] == ":" || (chars[i] == "." && i + 1 < chars.count && chars[i + 1].isNumber))
            if separatesMinutes {
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

nonisolated private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nonEmpty: String? { isEmpty ? nil : self }

    /// Whole-word containment, so "veg" doesn't match inside "vegan"/"vegetables".
    func matchesWord(_ word: String) -> Bool {
        components(separatedBy: CharacterSet.alphanumerics.inverted).contains(word)
    }
}
