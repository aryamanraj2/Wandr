//
//  CurationModels.swift
//  Wandr
//
//  UI-layer view models for the curation and schedule surfaces.
//  Hardcoded for the design pass — these mirror the shapes WandrKit's
//  DistrictVenue / GroundedOption / WandrPlan will hand over later.
//

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

    /// "Paisa Vasool" — savings against list price. Pure arithmetic, no inference.
    var savings: Int? {
        guard let listPrice, listPrice > perHead else { return nil }
        return listPrice - perHead
    }
}

// MARK: - Deck

/// A time slot in the plan plus the candidates competing for it.
///
/// The host does not pick a winner here — they shortlist. A right swipe adds a
/// candidate to the slate the squad will vote on, and the deck keeps going.
/// Narrowing many options down to one is the squad's job, not the host's.
struct Deck: Identifiable {
    let id: UUID = UUID()
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

    static func blocks(for day: PlanDay) -> [ScheduleBlock] {
        [
            ScheduleBlock(title: "Humayun's Tomb", category: .sights,
                          startMinute: 10 * 60, durationMinutes: 90, dayID: day.id),
            ScheduleBlock(title: "Lunch — Diggin", category: .food,
                          startMinute: 12 * 60 + 30, durationMinutes: 75, dayID: day.id),
            ScheduleBlock(title: "Sunder Nursery", category: .sights,
                          startMinute: 14 * 60 + 30, durationMinutes: 90, dayID: day.id),
            ScheduleBlock(title: "Piano Man", category: .nightlife,
                          startMinute: 20 * 60, durationMinutes: 120, dayID: day.id)
        ]
    }

    static let decks: [Deck] = [
        Deck(category: .food, slotName: "Dinner", window: "8:00 – 10:00 pm", candidates: [
            Candidate(name: "Diggin", area: "Anand Lok",
                      tagline: "Courtyard café under a rain tree. Continental, unhurried.",
                      category: .food, perHead: 1_100, listPrice: 1_400,
                      offer: "1+1 on cocktails", offerWindow: "till 9:30 pm",
                      openWindow: "Open till 11:30 pm", travelNote: "14 min by cab from Hauz Khas",
                      imageSeed: 1),
            Candidate(name: "Olive Bistro", area: "Mehrauli",
                      tagline: "Whitewashed Mediterranean courtyard beside the Qutub.",
                      category: .food, perHead: 1_800, listPrice: 2_200,
                      offer: "Complimentary dessert", offerWindow: "all evening",
                      openWindow: "Open till midnight", travelNote: "22 min by cab",
                      imageSeed: 2),
            Candidate(name: "Comorin", area: "Gurugram",
                      tagline: "Regional Indian small plates, long bar, loud room.",
                      category: .food, perHead: 1_500, listPrice: nil,
                      offer: nil, offerWindow: nil,
                      openWindow: "Open till 1:00 am", travelNote: "38 min by cab — outside the buffer",
                      imageSeed: 3),
            Candidate(name: "Dhaba by Claridges", area: "Connaught Place",
                      tagline: "Truck-art kitsch, butter chicken that earns the queue.",
                      category: .food, perHead: 1_200, listPrice: 1_500,
                      offer: "15% off pre-9 pm", offerWindow: "till 9:00 pm",
                      openWindow: "Open till 11:00 pm", travelNote: "18 min by metro",
                      imageSeed: 4),
            Candidate(name: "Andaz Delhi", area: "Aerocity",
                      tagline: "AnnaMaya food hall — everyone orders something different.",
                      category: .food, perHead: 1_600, listPrice: 1_900,
                      offer: "Squad platter for 6", offerWindow: "till 10:00 pm",
                      openWindow: "Open till 11:30 pm", travelNote: "31 min by cab",
                      imageSeed: 5)
        ]),

        Deck(category: .sights, slotName: "Afternoon", window: "2:30 – 5:00 pm", candidates: [
            Candidate(name: "Sunder Nursery", area: "Nizamuddin",
                      tagline: "90 acres of Mughal garden. Golden hour is the whole point.",
                      category: .sights, perHead: 200, listPrice: nil,
                      offer: nil, offerWindow: nil,
                      openWindow: "Gates close 7:00 pm", travelNote: "9 min walk from Humayun's Tomb",
                      imageSeed: 6),
            Candidate(name: "Hauz Khas Fort", area: "Hauz Khas",
                      tagline: "Ruins over a reservoir, deer park behind. Free entry.",
                      category: .sights, perHead: 0, listPrice: nil,
                      offer: nil, offerWindow: nil,
                      openWindow: "Open till 6:00 pm", travelNote: "12 min by cab",
                      imageSeed: 7),
            Candidate(name: "Lodhi Art District", area: "Lodhi Colony",
                      tagline: "India's first open-air public art district. Entirely walkable.",
                      category: .sights, perHead: 0, listPrice: nil,
                      offer: nil, offerWindow: nil,
                      openWindow: "Always open", travelNote: "7 min by cab",
                      imageSeed: 8),
            Candidate(name: "Agrasen ki Baoli", area: "Connaught Place",
                      tagline: "108 steps down into a 14th-century stepwell. Cool, echoey.",
                      category: .sights, perHead: 0, listPrice: nil,
                      offer: nil, offerWindow: nil,
                      openWindow: "Open till 6:00 pm", travelNote: "16 min by metro",
                      imageSeed: 9)
        ]),

        Deck(category: .nightlife, slotName: "Late", window: "10:00 pm – late", candidates: [
            Candidate(name: "Piano Man", area: "Safdarjung Enclave",
                      tagline: "Live jazz, low ceiling, no talking through the set.",
                      category: .nightlife, perHead: 1_400, listPrice: 1_800,
                      offer: "Cover waived before 9", offerWindow: "till 9:00 pm",
                      openWindow: "Sets at 9:00 & 11:00 pm", travelNote: "11 min by cab",
                      imageSeed: 10),
            Candidate(name: "Summer House Café", area: "Hauz Khas Village",
                      tagline: "Rooftop, resident DJs, the reliable default.",
                      category: .nightlife, perHead: 1_600, listPrice: 2_000,
                      offer: "1+1 till 10 pm", offerWindow: "till 10:00 pm",
                      openWindow: "Open till 1:00 am", travelNote: "4 min walk",
                      imageSeed: 11),
            Candidate(name: "Ghost Street", area: "Cyber Hub",
                      tagline: "Asian street-food bar. Loud, cheap, always full.",
                      category: .nightlife, perHead: 1_100, listPrice: 1_300,
                      offer: "Squad shots round", offerWindow: "till 11:00 pm",
                      openWindow: "Open till 1:00 am", travelNote: "41 min by cab — flagged",
                      imageSeed: 12)
        ]),

        Deck(category: .discover, slotName: "Something new", window: "flexible", candidates: [
            Candidate(name: "Smaaash Go-Karting", area: "Cyber Hub",
                      tagline: "Indoor karting, 12 laps. Someone will get competitive.",
                      category: .discover, perHead: 900, listPrice: 1_200,
                      offer: "Group of 6 — 2 free laps", offerWindow: "weekdays",
                      openWindow: "Open till 11:00 pm", travelNote: "36 min by cab",
                      imageSeed: 13),
            Candidate(name: "Kiran Nadar Museum", area: "Saket",
                      tagline: "Modern Indian art, currently showing a Gaitonde retrospective.",
                      category: .discover, perHead: 0, listPrice: nil,
                      offer: nil, offerWindow: nil,
                      openWindow: "Open till 6:30 pm", travelNote: "13 min by cab",
                      imageSeed: 14),
            Candidate(name: "Depot48 — Open Mic", area: "Safdarjung",
                      tagline: "Thursday open mic. Free entry, two-drink minimum.",
                      category: .discover, perHead: 800, listPrice: nil,
                      offer: nil, offerWindow: nil,
                      openWindow: "Doors 8:30 pm", travelNote: "9 min by cab",
                      imageSeed: 15),
            Candidate(name: "Adventure Island", area: "Rohini",
                      tagline: "Amusement park. Unserious, and that's the appeal.",
                      category: .discover, perHead: 1_500, listPrice: 1_800,
                      offer: "Group pass — 6 for 5", offerWindow: "all day",
                      openWindow: "Open till 8:00 pm", travelNote: "52 min by cab — flagged",
                      imageSeed: 16)
        ])
    ]
}
