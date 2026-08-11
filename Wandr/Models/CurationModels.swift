// CurationModels.swift Wandr UI-layer view models for the curation and schedule surfaces. Hardcoded for the design pass — these mirror the shapes WandrKit's DistrictVenue / GroundedOption / WandrPlan will hand over later.

import Foundation

// MARK: - Category

enum StopCategory: String, CaseIterable, Identifiable, Hashable {
    case food
    case sights
    case nightlife
    case discover

    var id: String { rawValue }

    var title: String {
        switch self {
        case .food:      return "Food"
        case .sights:    return "Sights"
        case .nightlife: return "Nightlife"
        case .discover:  return "Discover"
        }
    }

    var symbol: String {
        switch self {
        case .food:      return "fork.knife"
        case .sights:    return "building.columns"
        case .nightlife: return "music.quarternote.3"
        case .discover:  return "sparkles"
        }
    }
}

// MARK: - Setting

/// Where a stop actually happens. A UI-layer mirror of the planning domain's `VenueSetting` so the
/// curation models stay independent of it — and deliberately without an `unknown` case, because an
/// unsurveyed venue is expressed as `nil` here rather than as a fourth thing to render.
enum StopSetting: String, Hashable, CaseIterable {
    case indoor
    case outdoor
    case mixed

    var label: String {
        switch self {
        case .indoor:  return "Indoors"
        case .outdoor: return "Outdoors"
        case .mixed:   return "Indoors and out"
        }
    }
}

// MARK: - Candidate

/// One swipeable option inside a deck.
struct Candidate: Identifiable, Hashable {
    let id: UUID = UUID()
    let name: String
    let area: String
    let tagline: String
    let category: StopCategory

    /// Deterministic commerce metadata — computed by the app, never by the model.
    let perHead: Int
    let listPrice: Int?
    let offer: String?
    let offerWindow: String?

    let openWindow: String
    let travelNote: String

    /// Backdrop gradient seed, standing in for venue photography.
    let imageSeed: Int

    /// The model's one-line reason for this pick. Prose, never a source of facts — `nil` for the hardcoded demo deck, set for model-curated candidates.
    var rationale: String? = nil

    /// The dataset had no price. The card must show that honestly rather than rendering `perHead == 0` as "Free".
    var costUnknown: Bool = false

    /// Deterministic validator caveats to surface on the card (unknown hours, unverified dietary, provider limitations). Never model-authored.
    var warnings: [String] = []

    // MARK: Expanded-card content
    // None of the following appears in the deck. A card in the stack is a snap judgement — name, look, price, one line — and anything more competes with the swipe. These are the second look, revealed only once a card is opened.

    /// A short paragraph of colour: what the place actually feels like.
    var story: String? = nil

    /// Three or four short specifics — the things worth knowing before voting.
    var highlights: [String] = []

    /// The one thing a local would tell you that the listing never does.
    var insiderTip: String? = nil

    /// The provider's atmosphere words — "loud", "candlelit", "sit-down". Dataset fact, never model
    /// prose, and never a sentence: these are the handful of words that tell you what kind of room
    /// you are walking into, which is precisely the thing a photograph and a price cannot say.
    var vibeTags: [String] = []

    /// Indoors, outdoors, or both. `nil` when the provider never established it.
    var setting: StopSetting? = nil

    /// Dietary provisions, already in display form. `nil` and `[]` mean different things and the
    /// expanded card renders them differently: `nil` is "we never surveyed this place", `[]` is "we
    /// surveyed it and it has none". Collapsing the two would turn an unchecked venue into a
    /// confident negative, which is the one thing this app's data rules exist to prevent.
    var dietary: [String]? = nil

    /// Step-free entry and the rest, same three-state rule as `dietary`.
    var access: [String]? = nil

    /// "Paisa Vasool" — savings against list price. Pure arithmetic, no inference.
    var savings: Int? {
        guard !costUnknown, let listPrice, listPrice > perHead else { return nil }
        return listPrice - perHead
    }
}

// MARK: - Deck

/// A time slot in the plan plus the candidates competing for it. The host does not pick a winner here — they shortlist. A right swipe adds a candidate to the slate the squad will vote on, and the deck keeps going. Narrowing many options down to one is the squad's job, not the host's.
struct Deck: Identifiable {
    let id: UUID = UUID()

    /// Stable identity for this stop, carried through from the plan's `SlotID`. Distinct from `category`, which is *not* unique across a plan: a host who asks for lunch and dinner gets two `.food` decks. Keying anything by category silently merged them — the squad poll built one ballot for both, so voting on lunch also voted on dinner.
    let slotID: String
    let category: StopCategory
    /// e.g. "Dinner", "Late evening" — the human name for this slot.
    let slotName: String
    let window: String
    var candidates: [Candidate]

    /// Index of the top card. Advances on every swipe, either direction.
    var cursor: Int = 0
    /// Candidates the host swiped right on, in the order they were added.
    var shortlist: [Candidate.ID] = []

    var topCandidate: Candidate? {
        guard cursor < candidates.count else { return nil }
        return candidates[cursor]
    }

    /// Shortlisted candidates, resolved and in shortlist order.
    var shortlisted: [Candidate] {
        shortlist.compactMap { id in candidates.first { $0.id == id } }
    }

    /// Every card seen, nothing kept — this slot has no slate to vote on.
    var isExhausted: Bool { cursor >= candidates.count && shortlist.isEmpty }

    /// Deck fully reviewed with at least one option kept.
    var isReviewed: Bool { cursor >= candidates.count && !shortlist.isEmpty }

    /// The next two cards behind the top one, for the stacked peek.
    var backdrop: [Candidate] {
        guard cursor < candidates.count else { return [] }
        return Array(candidates[(cursor + 1)..<min(cursor + 3, candidates.count)])
    }

    var remaining: Int { max(0, candidates.count - cursor) }

    mutating func shortlistTop() {
        guard let top = topCandidate else { return }
        if !shortlist.contains(top.id) { shortlist.append(top.id) }
        cursor += 1
    }

    mutating func passTop() {
        guard cursor < candidates.count else { return }
        cursor += 1
    }

    mutating func restart() {
        cursor = 0
        shortlist.removeAll()
    }
}

// MARK: - Schedule

struct PlanDay: Identifiable, Hashable {
    let id: UUID = UUID()
    let date: Date

    var weekday: String {
        Calendar.current.isDateInToday(date)
            ? "Today"
            : date.formatted(.dateTime.weekday(.abbreviated))
    }

    var dayNumber: String {
        date.formatted(.dateTime.day())
    }
}

/// A scheduled block on the timeline. Draggable once lifted.
struct ScheduleBlock: Identifiable, Hashable {
    let id: UUID = UUID()
    let title: String
    let category: StopCategory
    /// Minutes from midnight. Mutated by the reschedule drag.
    var startMinute: Int
    var durationMinutes: Int
    let dayID: PlanDay.ID

    /// The venue's photography key, so a scheduled stop can show the picture the card that
    /// won it was showing. Defaults to `VenuePhoto.noPhoto` — a block is only a title and a
    /// time, and the demo fixtures build them from neither a `Candidate` nor a dataset row.
    var imageSeed: Int = 0

    var endMinute: Int { startMinute + durationMinutes }

    var startLabel: String { Self.clock(startMinute) }
    var endLabel: String { Self.clock(endMinute) }

    static func clock(_ minute: Int) -> String {
        let h24 = (minute / 60) % 24
        let m = minute % 60
        let suffix = h24 < 12 ? "am" : "pm"
        var h = h24 % 12
        if h == 0 { h = 12 }
        return m == 0 ? "\(h):00 \(suffix)" : String(format: "%d:%02d %@", h, m, suffix)
    }
}

// MARK: - Demo fixtures

enum DemoPlan {

    static let days: [PlanDay] = {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // The date bar only shows the days the itinerary actually spans.
        return (0..<3).compactMap { offset in
            cal.date(byAdding: .day, value: offset, to: today).map(PlanDay.init(date:))
        }
    }()

    /// The Khan Market night, already decided — the fixture the schedule and summary screens open
    /// against. Mirrors `decks`, so a block on the timeline is a place the squad could actually have
    /// voted for, photograph and all.
    static func blocks(for day: PlanDay) -> [ScheduleBlock] {
        [
            ScheduleBlock(title: "Big Chill Cafe", category: .food,
                          startMinute: 20 * 60, durationMinutes: 90, dayID: day.id, imageSeed: 186),
            ScheduleBlock(title: "Middle Lane Listening Bar", category: .nightlife,
                          startMinute: 22 * 60, durationMinutes: 120, dayID: day.id, imageSeed: 362)
        ]
    }

    /// Two slots in Khan Market, as the brief asks for them: dinner and somewhere to drink after.
    /// Every venue here is a real row from `district-venues-delhi.json` — same names, prices, hours
    /// and `imageSeed`s — so the demo deck shows the same photographs the grounded pipeline would.
    ///
    /// `travelNote` is the one field the dataset does not carry. Khan Market is a single market
    /// block, so every one of these is a walk, and that is what the notes say.
    static let decks: [Deck] = [
        Deck(slotID: "dinner", category: .food, slotName: "Dinner", window: "8:00 – 10:00 pm", candidates: [
            Candidate(name: "Big Chill Cafe", area: "Khan Market",
                      tagline: "Enormous pastas and taller cakes, unchanged for decades.",
                      category: .food, perHead: 1_100, listPrice: nil,
                      offer: nil, offerWindow: nil,
                      openWindow: "Open till 11:30 pm", travelNote: "In the market — 2 min walk",
                      imageSeed: 186,
                      warnings: ["No reservations; 30-45 min waits on weekends."],
                      story: "The Khan Market institution, and it has not changed its mind about anything in thirty years. Pastas arrive in bowls built for two, the cake counter is the actual reason half the room is there, and the walls are still covered in film posters. It is loud, it is cramped, and nobody has ever left hungry.",
                      highlights: [
                        "Portions are genuinely enormous — order fewer dishes than you think",
                        "The cake counter is the draw; the tiramisu goes first",
                        "Vegetarian half of the menu is as long as the rest",
                        "No reservations, so expect a wait on a Friday"
                      ],
                      insiderTip: "Put your name down downstairs and shop the market while you wait — they will call you.",
                      vibeTags: ["lively", "classic"],
                      setting: .indoor,
                      dietary: ["Vegetarian"],
                      access: nil),
            Candidate(name: "Khan Market Morning Counter", area: "Khan Market",
                      tagline: "Standing counter for coffee and parathas before nine.",
                      category: .food, perHead: 350, listPrice: nil,
                      offer: nil, offerWindow: nil,
                      openWindow: "7:00 am – 12:00 pm", travelNote: "In the market — 1 min walk",
                      imageSeed: 366,
                      warnings: ["Closes at noon — outside this slot's window."],
                      story: "A standing counter rather than a restaurant: coffee, parathas, and a queue of people who work in the market. Cheapest thing on the slate by a wide margin, and the only one that would leave the budget intact — but it shuts at noon, which is the whole problem with it as a dinner.",
                      highlights: [
                        "₹350 a head — a third of anything else in this slot",
                        "Standing room only; nobody lingers",
                        "Closes at noon, so it cannot serve this slot",
                        "Dietary provisions were never surveyed"
                      ],
                      insiderTip: "It is on the slate because it fits the budget, not because it fits the hour.",
                      vibeTags: ["quick", "quiet"],
                      setting: .indoor,
                      dietary: nil,
                      access: nil),
            Candidate(name: "Mamagoto", area: "Khan Market",
                      tagline: "Loud pan-Asian plates under comic-book walls.",
                      category: .food, perHead: 1_600, listPrice: nil,
                      offer: "15% off weekday lunch", offerWindow: "Mon–Fri before 4:00 pm",
                      openWindow: "Open till 11:00 pm", travelNote: "In the market — 3 min walk",
                      imageSeed: 187,
                      story: "Comic-book murals, primary colours, and a room pitched deliberately loud. The menu runs pan-Asian and shares well — bao, khao suey, a chilli basil that regulars order without looking. It is the most fun room on this slate and the least suited to a conversation.",
                      highlights: [
                        "Everything is built to share; order across the table",
                        "Khao suey and the bao are what the kitchen is known for",
                        "Vegan options are marked, not improvised",
                        "The weekday lunch discount does not apply on a Friday night"
                      ],
                      insiderTip: "Ask for the upstairs room — same menu, and you can hear each other.",
                      vibeTags: ["loud", "fun", "colourful"],
                      setting: .indoor,
                      dietary: ["Vegetarian", "Vegan"],
                      access: nil)
        ]),

        Deck(slotID: "late", category: .nightlife, slotName: "Late", window: "10:00 pm – late", candidates: [
            Candidate(name: "Middle Lane Listening Bar", area: "Khan Market",
                      tagline: "Vinyl only, low light, no one shouts.",
                      category: .nightlife, perHead: 1_700, listPrice: nil,
                      offer: nil, offerWindow: nil,
                      openWindow: "6:00 pm – 1:00 am", travelNote: "In the market — 2 min walk",
                      imageSeed: 362,
                      warnings: ["Dietary provisions unverified."],
                      story: "A listening bar in the proper sense: vinyl only, a system built for it, and a room lit low enough that people drop their voices without being asked. Records are chosen by whoever is behind the counter and the selection is not up for negotiation. The closest thing Khan Market has to a room that expects you to sit still.",
                      highlights: [
                        "Vinyl only — no requests, no playlist",
                        "Low light and low volume; the room polices itself",
                        "Opens at six and runs to one",
                        "Nobody has surveyed the dietary provisions here"
                      ],
                      insiderTip: "Go after eleven. The early crowd talks; the late one listens.",
                      vibeTags: ["music", "intimate"],
                      setting: .indoor,
                      dietary: nil,
                      access: nil),
            Candidate(name: "Perch Wine & Coffee Bar", area: "Khan Market",
                      tagline: "Wine by the glass and a room that stays conversational.",
                      category: .nightlife, perHead: 1_800, listPrice: nil,
                      offer: nil, offerWindow: nil,
                      openWindow: "8:00 am – 1:00 am", travelNote: "In the market — 2 min walk",
                      imageSeed: 189,
                      warnings: ["Small room; groups over six rarely seat together."],
                      story: "Wine by the glass at a range of prices that does not punish curiosity, coffee that is taken as seriously as the wine, and a room small enough that it never gets loud. It runs from breakfast to one in the morning, which makes it the most flexible thing on this slate and the easiest to end a night in.",
                      highlights: [
                        "Wide by-the-glass list — you are not committed to a bottle",
                        "Open from eight in the morning until one at night",
                        "Small room; a group of three seats easily, six does not",
                        "The quietest option in this slot"
                      ],
                      insiderTip: "The window seats go first and they are the only ones with a view of the market.",
                      vibeTags: ["relaxed", "intimate"],
                      setting: .indoor,
                      dietary: ["Vegetarian"],
                      access: nil),
            Candidate(name: "Amour Bistro", area: "Khan Market",
                      tagline: "Fairy-lit rooftop, long cocktail list.",
                      category: .nightlife, perHead: 1_900, listPrice: nil,
                      offer: nil, offerWindow: nil,
                      openWindow: "Open till 1:00 am", travelNote: "In the market — 3 min walk",
                      imageSeed: 191,
                      story: "A rooftop strung with fairy lights, above the market and just far enough from it. The cocktail list is long and the kitchen keeps going late. It is the prettiest room on the slate and the most expensive, and on a Friday it will be full of people who booked.",
                      highlights: [
                        "Rooftop, so it lives and dies by the weather",
                        "Longest cocktail list of the three",
                        "Kitchen runs late — food is still coming at midnight",
                        "Book ahead on a Friday or expect to stand"
                      ],
                      insiderTip: "The far end of the terrace is a step down and always emptier than the bar side.",
                      vibeTags: ["romantic", "view"],
                      setting: .outdoor,
                      dietary: ["Vegetarian"],
                      access: nil)
        ])
    ]
}
