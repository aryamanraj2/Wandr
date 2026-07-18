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

/// A time window that keeps "unknown" and "flexible" honest.
///
/// Minutes are measured from midnight, matching the schedule surface. Actual
/// date and time-zone resolution is a deferred rule — this step never invents one.
nonisolated struct OutingTimeWindow: Sendable, Equatable, Hashable {
    /// e.g. 20 * 60 for "not before 8pm". `nil` means the host didn't say.
    var earliestStartMinute: Int?
    /// e.g. 21 * 60 for "finish by 9". `nil` means the host didn't say.
    var latestEndMinute: Int?
    /// e.g. "Friday". A label only — never parsed into a `Date` at this layer.
    var dayLabel: String?

    init(earliestStartMinute: Int? = nil, latestEndMinute: Int? = nil, dayLabel: String? = nil) {
        self.earliestStartMinute = earliestStartMinute
        self.latestEndMinute = latestEndMinute
        self.dayLabel = dayLabel
    }

    /// Nothing was said about timing at all.
    static let unknown = OutingTimeWindow()

    var isUnknown: Bool {
        earliestStartMinute == nil && latestEndMinute == nil && dayLabel == nil
    }

    /// A hard finish time the host stated.
    var hasFixedEnd: Bool { latestEndMinute != nil }
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

/// Per-head budget in rupees.
///
/// Never a guessed precise price: either the host gave a ceiling, or there isn't one.
nonisolated enum BudgetPerHead: Sendable, Equatable, Hashable {
    static let supportedRange = 0...100_000

    /// No budget ceiling is known. Cost checks are skipped; unknown costs still warn.
    case unspecified
    /// A confirmed per-head ceiling in rupees.
    case upTo(rupees: Int)

    /// Clamps into the supported range rather than trusting model output.
    static func clamping(rupees: Int) -> BudgetPerHead {
        .upTo(rupees: min(max(rupees, supportedRange.lowerBound), supportedRange.upperBound))
    }

    var limitRupees: Int? {
        switch self {
        case .unspecified: return nil
        case .upTo(let rupees): return rupees
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
    var budgetPerHeadRupees: Int?
    var vibeTags: [String]
    var dietary: DietaryNeeds
    var accessibility: AccessibilityNeeds
    var setting: SettingPreference
    /// Remaining neutral constraints. Data, never executable instructions.
    var notes: [String]

    init(
        occasion: String? = nil,
        timeWindow: OutingTimeWindow = .unknown,
        area: String? = nil,
        groupSize: Int? = nil,
        budgetPerHeadRupees: Int? = nil,
        vibeTags: [String] = [],
        dietary: DietaryNeeds = .unknown,
        accessibility: AccessibilityNeeds = .unknown,
        setting: SettingPreference = .noPreference,
        notes: [String] = []
    ) {
        self.occasion = occasion
        self.timeWindow = timeWindow
        self.area = area
        self.groupSize = groupSize
        self.budgetPerHeadRupees = budgetPerHeadRupees
        self.vibeTags = vibeTags
        self.dietary = dietary
        self.accessibility = accessibility
        self.setting = setting
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
    let budgetPerHead: Sourced<BudgetPerHead>

    /// Soft preferences. These never gate evidence.
    let vibeTags: [String]

    let dietary: DietaryNeeds
    let accessibility: AccessibilityNeeds
    let setting: SettingPreference
    let notes: [String]

    init(
        occasion: Sourced<String> = .safeDefault(OutingBrief.defaultOccasion),
        timeWindow: Sourced<OutingTimeWindow> = .safeDefault(.unknown),
        area: Sourced<String> = .safeDefault(OutingBrief.defaultArea),
        groupSize: Sourced<GroupSize> = .safeDefault(OutingBrief.defaultGroupSize),
        budgetPerHead: Sourced<BudgetPerHead> = .safeDefault(.unspecified),
        vibeTags: [String] = [],
        dietary: DietaryNeeds = .unknown,
        accessibility: AccessibilityNeeds = .unknown,
        setting: SettingPreference = .noPreference,
        notes: [String] = []
    ) {
        self.occasion = occasion
        self.timeWindow = timeWindow
        self.area = area
        self.groupSize = groupSize
        self.budgetPerHead = budgetPerHead
        self.vibeTags = vibeTags
        self.dietary = dietary
        self.accessibility = accessibility
        self.setting = setting
        self.notes = notes
    }

    /// The values Wandr filled in on the host's behalf. Drives the demo's
    /// "here's what we assumed" affordance without a new service contract.
    var safeDefaults: [MissingConstraint] {
        var defaults: [MissingConstraint] = []
        if area.isSafeDefault { defaults.append(.area) }
        if timeWindow.isSafeDefault { defaults.append(.timeWindow) }
        if groupSize.isSafeDefault { defaults.append(.groupSize) }
        if budgetPerHead.isSafeDefault { defaults.append(.budgetPerHead) }
        return defaults
    }
}

// MARK: - Normalization outcome

/// A constraint that was missing or too ambiguous to settle from the request.
nonisolated enum MissingConstraint: String, Sendable, Equatable, Hashable, CaseIterable {
    case area
    case timeWindow
    case groupSize
    case budgetPerHead
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
