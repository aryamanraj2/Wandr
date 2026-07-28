//
//  OutingBrief.swift
//  Wandr
//
//  The typed brief the whole pipeline consumes.
//
//  `OutingBriefDraft` is model-generated and always uncertain.
//  `OutingBrief` is the canonical, normalized object — every inferable value
//  carries a `ValueSource` marker so a future "review chips" screen can show
//  the host what Wandr guessed versus what they actually said.
//

import Foundation

// MARK: - Provenance of a single value

/// Where one brief value came from. Guessing is allowed; hiding the guess is not.
nonisolated enum ValueSource: String, Sendable, Equatable, Hashable, CaseIterable {
    /// The host said it.
    case host
    /// The model inferred it from the request.
    case modelSuggestion
    /// Wandr filled it in because nothing was said.
    case safeDefault
}

/// A brief value paired with the marker explaining how Wandr knows it.
nonisolated struct Sourced<Value: Sendable & Equatable>: Sendable, Equatable {
    let value: Value
    let source: ValueSource

    init(_ value: Value, from source: ValueSource) {
        self.value = value
        self.source = source
    }

    static func host(_ value: Value) -> Sourced { Sourced(value, from: .host) }
    static func modelSuggestion(_ value: Value) -> Sourced { Sourced(value, from: .modelSuggestion) }
    static func safeDefault(_ value: Value) -> Sourced { Sourced(value, from: .safeDefault) }

    var isSafeDefault: Bool { source == .safeDefault }
}

extension Sourced: Hashable where Value: Hashable {}

// MARK: - Time

/// Whether the night should build towards something or stay level.
///
/// A birthday ends somewhere bigger than it started; a Tuesday catch-up does not.
/// Read from what the host said, never inferred from the clock.
nonisolated enum OccasionArc: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    case flat
    case buildsToFinale
}

/// What kind of occasion this is, as four numbers the rest of the app can act on.
///
/// This is the whole of what the model contributes to a plan's *shape*, and it is
/// deliberately not a stop, a time, or a count. "A date", "five of us after work" and
/// "her birthday" are the same arithmetic over the same venues and three different
/// nights — the difference lives here, and nowhere in this type names a place, an
/// hour, or a number of stops.
///
/// Contrast with what came before: an occasion was a *string* (`"birthday"`) matched
/// against a list, so every new kind of night needed a new case somewhere. Nothing
/// here enumerates occasions. A photography walk and a first date produce different
/// values of these four fields without either being a case anyone wrote down.
nonisolated struct OccasionProfile: Sendable, Equatable, Hashable, Codable {
    /// How fast they want to move. Drives how many stops fill a gap — via division,
    /// in `SlotSchedule`, never by the model counting anything.
    var pace: SlotSchedule.Pace
    /// 0 = the outing is a meal, 1 = the outing is an activity and food is incidental.
    /// A ranking weight, not a filter: it can never empty a deck, so it never needs
    /// relaxing and stays off the constraint ladder.
    var activityBias: Double
    /// The group has to sit down together. A hard requirement when true.
    var groupSeating: Bool
    var arc: OccasionArc

    /// What Wandr assumes when the host described no occasion at all.
    ///
    /// Mid-scale on both axes deliberately: an unspecified outing should lean neither
    /// towards a tasting menu nor towards an escape room.
    static let unspecified = OccasionProfile(
        pace: .steady, activityBias: 0.5, groupSeating: false, arc: .flat
    )

    /// Clamped on the way in — `activityBias` is the one field a model can put out of
    /// range, and a bias of 4.0 would swamp every other ranking term.
    init(pace: SlotSchedule.Pace, activityBias: Double, groupSeating: Bool, arc: OccasionArc) {
        self.pace = pace
        self.activityBias = min(max(activityBias, 0), 1)
        self.groupSeating = groupSeating
        self.arc = arc
    }
}

/// A time window that keeps "unknown" and "flexible" honest.
///
/// Minutes are measured from midnight, matching the schedule surface. Actual
/// date and time-zone resolution is a deferred rule — this step never invents one.
nonisolated struct OutingTimeWindow: Sendable, Equatable, Hashable {
    /// e.g. 20 * 60 for "not before 8pm". `nil` means the host didn't say.
    var earliestStartMinute: Int?
    /// e.g. 21 * 60 for "finish by 9". `nil` means the host didn't say.
    var latestEndMinute: Int?
    /// How long the whole outing may run, e.g. 180 for "we've only got 3 hours".
    ///
    /// A separate axis from the two clock bounds, and the reason this field exists:
    /// a duration is not a time of day. Without it, "3 hours" had nowhere to go but
    /// the clock parser, which read the bare `3` as an evening hour and produced
    /// "starts at 3 pm" — a window that keeps *every* slot and plans a whole day for
    /// a group that said they had an afternoon's worth of time.
    var maximumDurationMinutes: Int?
    /// e.g. "Friday". A label only — never parsed into a `Date` at this layer.
    var dayLabel: String?

    /// - Important: a window that ends no later than it starts is **not
    ///   representable**. A finish at or before the start is never a real
    ///   constraint — it is a misread phrase — and the upper bound is dropped here
    ///   rather than defended against downstream.
    ///
    ///   This is enforced at construction because the alternative failed silently and
    ///   catastrophically. `"12.00 to 5:00 pm"` parsed the `.00` as a *second* clock
    ///   token, which then inherited the trailing `pm` and became a second 12:00 —
    ///   so the window read as 12:00 pm → 12:00 pm, no band could fit a
    ///   zero-minute span, and the host got a plan with **no stops in it at all**.
    ///   A bad parse should cost the constraint, never the day.
    ///
    ///   Normalising in the initializer makes the property hold for every window the
    ///   app can build, from any source, rather than at the one call site that was
    ///   known to be wrong.
    init(
        earliestStartMinute: Int? = nil,
        latestEndMinute: Int? = nil,
        maximumDurationMinutes: Int? = nil,
        dayLabel: String? = nil
    ) {
        let contradictory = if let latestEndMinute, let earliestStartMinute {
            latestEndMinute <= earliestStartMinute
        } else {
            false
        }

        self.earliestStartMinute = earliestStartMinute
        self.latestEndMinute = contradictory ? nil : latestEndMinute
        self.maximumDurationMinutes = maximumDurationMinutes
        self.dayLabel = dayLabel
        self.statedEndWasUnreadable = contradictory
    }

    /// Whether the phrase produced bounds that contradicted each other, so the finish
    /// time was dropped. Drives the host-facing disclosure — a constraint given up
    /// silently is the failure mode `PlanRelaxation` exists to prevent.
    ///
    /// Deliberately excluded from `isUnknown`: a window that carries only this flag
    /// still constrains nothing, and should not switch on the "you're only free 8–9"
    /// banner.
    private(set) var statedEndWasUnreadable: Bool = false

    /// Nothing was said about timing at all.
    static let unknown = OutingTimeWindow()

    var isUnknown: Bool {
        earliestStartMinute == nil && latestEndMinute == nil
            && maximumDurationMinutes == nil && dayLabel == nil
    }

    /// A hard finish time the host stated.
    var hasFixedEnd: Bool { latestEndMinute != nil }

    /// Whether the host capped how long they have, however they phrased it.
    var hasDurationCap: Bool { maximumDurationMinutes != nil }
}

// MARK: - Bounded numbers

/// Group size, bounded so a bad extraction can't produce a party of 40,000.
nonisolated struct GroupSize: Sendable, Equatable, Hashable {
    static let supportedRange = 1...50

    let people: Int

    /// Clamps into the supported range rather than trusting model output.
    init(clamping people: Int) {
        self.people = min(max(people, Self.supportedRange.lowerBound), Self.supportedRange.upperBound)
    }
}

/// A budget ceiling in rupees, carrying the basis the host actually stated.
///
/// The basis is the whole point of this type. It used to be a bare per-head number,
/// which meant a host who typed "2000" had that read as ₹2000 *each* — a constraint
/// they never stated — and then compared against a venue's per-head price. Two
/// people with ₹2000 between them were told a perfectly ordinary dinner was "over
/// your ₹2000 limit", and the run dead-ended on it.
///
/// Never a guessed precise price: either the host gave a ceiling, or there isn't one.
nonisolated enum Budget: Sendable, Equatable, Hashable {
    static let supportedRange = 0...1_000_000

    /// No budget ceiling is known. Cost checks are skipped; unknown costs still warn.
    case unspecified
    /// The host said this much *each* — "₹2000 a head", "2k pp".
    case perHead(rupees: Int)
    /// The host named a number without a basis, so it is the group's total.
    /// Assuming per head would invent the more permissive of the two readings.
    case total(rupees: Int)

    /// Clamps into the supported range rather than trusting model output.
    static func clamping(rupees: Int, perHead: Bool) -> Budget {
        let bounded = min(max(rupees, supportedRange.lowerBound), supportedRange.upperBound)
        return perHead ? .perHead(rupees: bounded) : .total(rupees: bounded)
    }

    /// The ceiling to compare a venue's price against.
    ///
    /// Venue costs in the dataset are always per head, so a group total has to be
    /// divided before it means anything. This is the one place that division
    /// happens — comparing a total against a per-head price is the bug this type
    /// exists to make unrepresentable.
    func ceilingPerHead(for groupSize: GroupSize) -> Int? {
        switch self {
        case .unspecified:          return nil
        case .perHead(let rupees):  return rupees
        case .total(let rupees):    return rupees / max(groupSize.people, 1)
        }
    }

    /// The number the host said, whatever it meant. For display and logging only —
    /// never compare this against a venue price.
    var statedRupees: Int? {
        switch self {
        case .unspecified:         return nil
        case .perHead(let rupees): return rupees
        case .total(let rupees):   return rupees
        }
    }

    /// How to describe the ceiling back to the host, in the terms they used.
    var basisLabel: String? {
        switch self {
        case .unspecified: return nil
        case .perHead:     return "per head"
        case .total:       return "for the group"
        }
    }
}

// MARK: - Hard constraints

nonisolated enum DietaryRequirement: String, Sendable, Equatable, Hashable, CaseIterable, Comparable {
    case vegetarian
    case vegan
    case jain
    case halal
    case glutenFree

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

nonisolated enum AccessibilityRequirement: String, Sendable, Equatable, Hashable, CaseIterable, Comparable {
    case stepFreeEntry
    case accessibleRestroom
    case elevatorAccess

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A constraint Wandr either knows, knows to be absent, or hasn't established.
///
/// The three states stay distinct all the way to the UI. "Unknown" is never
/// silently promoted to "none stated".
nonisolated enum ConstraintNeed<Requirement: Sendable & Hashable & Comparable>: Sendable, Equatable, Hashable {
    /// Nothing in the request settled this either way.
    case unknown
    /// The host explicitly has no requirement here.
    case noneStated
    /// A hard requirement the plan must satisfy.
    case required(Set<Requirement>)

    /// The requirements that must be satisfied, sorted for deterministic messages.
    var requirements: [Requirement] {
        switch self {
        case .unknown, .noneStated: return []
        case .required(let set): return set.sorted()
        }
    }

    var isHardConstraint: Bool {
        if case .required(let set) = self { return !set.isEmpty }
        return false
    }
}

typealias DietaryNeeds = ConstraintNeed<DietaryRequirement>
typealias AccessibilityNeeds = ConstraintNeed<AccessibilityRequirement>

/// Indoor/outdoor preference. A hard constraint only when the host was explicit.
nonisolated enum SettingPreference: String, Sendable, Equatable, Hashable, CaseIterable {
    case noPreference
    case indoor
    case outdoor
    case mixed

    /// Only `.indoor` and `.outdoor` gate evidence. `.mixed` and `.noPreference` are soft.
    var isHardConstraint: Bool { self == .indoor || self == .outdoor }
}

// MARK: - Draft (model-generated, never authoritative)

/// What the on-device extractor produces. Every field may be absent or wrong.
///
/// A draft is never consumed by research, curation, or validation. It must go
/// through `BriefNormalizing` first.
nonisolated struct OutingBriefDraft: Sendable, Equatable {
    var occasion: String?
    var timeWindow: OutingTimeWindow
    var area: String?
    var groupSize: Int?
    /// The ceiling the host named, with the basis they named it in.
    /// `nil` means they said nothing about money.
    var budget: Budget?
    var vibeTags: [String]
    var dietary: DietaryNeeds
    var accessibility: AccessibilityNeeds
    var setting: SettingPreference
    /// The stops the host asked for by name — "lunch", "drinks", "a walk".
    ///
    /// Empty means they didn't say, which is not the same as wanting nothing: an empty
    /// request keeps every stop the window allows. One named stop seeds a plan built
    /// around it; two or more describe the shape exactly. See `SlotSchedule.chooseBands`.
    var requestedStops: Set<SlotBand>
    /// The host said these are the *only* stops they want — "just dinner".
    ///
    /// Separate from `requestedStops` because one named stop cannot otherwise tell
    /// "an evening with dinner in it" apart from "dinner and nothing else", and those
    /// are different plans.
    var stopsAreExclusive: Bool

    /// What kind of night this is. `.unspecified` until the model reads one.
    var occasionProfile: OccasionProfile
    /// Remaining neutral constraints. Data, never executable instructions.
    var notes: [String]

    init(
        occasion: String? = nil,
        timeWindow: OutingTimeWindow = .unknown,
        area: String? = nil,
        groupSize: Int? = nil,
        budget: Budget? = nil,
        vibeTags: [String] = [],
        dietary: DietaryNeeds = .unknown,
        accessibility: AccessibilityNeeds = .unknown,
        setting: SettingPreference = .noPreference,
        requestedStops: Set<SlotBand> = [],
        stopsAreExclusive: Bool = false,
        occasionProfile: OccasionProfile = .unspecified,
        notes: [String] = []
    ) {
        self.occasionProfile = occasionProfile
        self.timeWindow = timeWindow
        self.area = area
        self.groupSize = groupSize
        self.budget = budget
        self.vibeTags = vibeTags
        self.dietary = dietary
        self.accessibility = accessibility
        self.setting = setting
        self.requestedStops = requestedStops
        self.stopsAreExclusive = stopsAreExclusive
        self.occasionProfile = occasionProfile
        self.notes = notes
    }
}

// MARK: - Brief (canonical)

/// The normalized brief the rest of the pipeline consumes.
nonisolated struct OutingBrief: Sendable, Equatable {

    /// Used when the host names no occasion.
    static let defaultOccasion = "group outing"
    /// Used only when the host names no area at all.
    static let defaultArea = "Delhi NCR"
    /// Used when the host names no group size.
    static let defaultGroupSize = GroupSize(clamping: 4)

    let occasion: Sourced<String>
    let timeWindow: Sourced<OutingTimeWindow>
    let area: Sourced<String>
    let groupSize: Sourced<GroupSize>
    let budget: Sourced<Budget>

    /// Soft preferences. These never gate evidence.
    let vibeTags: [String]

    let dietary: DietaryNeeds
    let accessibility: AccessibilityNeeds
    let setting: SettingPreference

    /// The stops the host named. One seeds a plan built around it; two or more
    /// describe it exactly — see `SlotSchedule.chooseBands`.
    let requestedStops: Set<SlotBand>

    /// The host said these are the only stops they want. See `OutingBriefDraft`.
    let stopsAreExclusive: Bool

    /// What kind of night this is. Drives how many stops fill a gap, and how venues
    /// are ranked inside each — never which stops exist.
    let occasionProfile: OccasionProfile

    let notes: [String]

    init(
        occasion: Sourced<String> = .safeDefault(OutingBrief.defaultOccasion),
        timeWindow: Sourced<OutingTimeWindow> = .safeDefault(.unknown),
        area: Sourced<String> = .safeDefault(OutingBrief.defaultArea),
        groupSize: Sourced<GroupSize> = .safeDefault(OutingBrief.defaultGroupSize),
        budget: Sourced<Budget> = .safeDefault(.unspecified),
        vibeTags: [String] = [],
        dietary: DietaryNeeds = .unknown,
        accessibility: AccessibilityNeeds = .unknown,
        setting: SettingPreference = .noPreference,
        requestedStops: Set<SlotBand> = [],
        stopsAreExclusive: Bool = false,
        occasionProfile: OccasionProfile = .unspecified,
        notes: [String] = []
    ) {
        self.occasionProfile = occasionProfile
        self.timeWindow = timeWindow
        self.area = area
        self.groupSize = groupSize
        self.budget = budget
        self.vibeTags = vibeTags
        self.dietary = dietary
        self.accessibility = accessibility
        self.setting = setting
        self.requestedStops = requestedStops
        self.stopsAreExclusive = stopsAreExclusive
        self.occasionProfile = occasionProfile
        self.notes = notes
    }

    /// The values Wandr filled in on the host's behalf. Drives the demo's
    /// "here's what we assumed" affordance without a new service contract.
    var safeDefaults: [MissingConstraint] {
        var defaults: [MissingConstraint] = []
        if area.isSafeDefault { defaults.append(.area) }
        if timeWindow.isSafeDefault { defaults.append(.timeWindow) }
        if groupSize.isSafeDefault { defaults.append(.groupSize) }
        if budget.isSafeDefault { defaults.append(.budget) }
        return defaults
    }
}

// MARK: - The plan's shape

nonisolated extension OutingBrief {

    /// The stops this brief's plan will contain, in time order.
    ///
    /// The *only* place `SlotSchedule.compute` is called from production code. Five
    /// separate call sites used to pass the brief's window and stops themselves —
    /// the curator, the fake curator, the evidence resolver, the schedule drafter and
    /// the poll builder — which meant a new input like `stopsAreExclusive` had to be
    /// threaded through five times to avoid the deck, the window label on the card,
    /// and the timeline quietly disagreeing about what the night is.
    ///
    /// Pure arithmetic over six bands, so recomputing it per caller costs nothing.
    var schedule: SlotSchedule {
        SlotSchedule.compute(
            for: timeWindow.value,
            requesting: requestedStops,
            exclusive: stopsAreExclusive,
            pace: occasionProfile.pace
        )
    }
}

// MARK: - Normalization outcome

/// A constraint that was missing or too ambiguous to settle from the request.
nonisolated enum MissingConstraint: String, Sendable, Equatable, Hashable, CaseIterable {
    case area
    case timeWindow
    case groupSize
    case budget
}

/// What `BriefNormalizing` returns: a usable brief, or the reason we need the host.
nonisolated enum BriefNormalizationOutcome: Sendable, Equatable {
    /// Ready for research.
    case normalized(OutingBrief)
    /// Usable but incomplete — drives the `needsDetails` state.
    case needsDetails(partial: OutingBrief, missing: [MissingConstraint])

    /// The brief either way, including the partial one.
    var brief: OutingBrief {
        switch self {
        case .normalized(let brief): return brief
        case .needsDetails(let brief, _): return brief
        }
    }
}
