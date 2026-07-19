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

    /// The model's one-line reason for this pick. Prose, never a source of facts —
    /// `nil` for the hardcoded demo deck, set for model-curated candidates.
    var rationale: String? = nil

    /// The dataset had no price. The card must show that honestly rather than
    /// rendering `perHead == 0` as "Free".
    var costUnknown: Bool = false

    /// Deterministic validator caveats to surface on the card (unknown hours,
    /// unverified dietary, provider limitations). Never model-authored.
    var warnings: [String] = []

    // MARK: Expanded-card content
    //
    // None of the following appears in the deck. A card in the stack is a snap
    // judgement — name, look, price, one line — and anything more competes with
    // the swipe. These are the second look, revealed only once a card is opened.

    /// A short paragraph of colour: what the place actually feels like.
    var story: String? = nil

    /// Three or four short specifics — the things worth knowing before voting.
    var highlights: [String] = []

    /// The one thing a local would tell you that the listing never does.
    var insiderTip: String? = nil

    /// "Paisa Vasool" — savings against list price. Pure arithmetic, no inference.
    var savings: Int? {
        guard !costUnknown, let listPrice, listPrice > perHead else { return nil }
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
                      imageSeed: 1,
                      story: "A converted bungalow where the whole room is really one courtyard, strung with fairy lights and built around a rain tree that predates the restaurant. Tables are wrought iron, spaced far enough apart to actually hear each other, and nobody will rush you off one. The kitchen is unfussy continental — thin-crust pizzas, a very good mushroom risotto, pastas that arrive hot — and the wine list is short in a way that reads as edited rather than thin.",
                      highlights: [
                        "Courtyard seating is the whole draw — ask for it, not the indoor annexe",
                        "Thin-crust pizzas and the mushroom risotto are what the kitchen is known for",
                        "Tables spaced for conversation; among the quieter rooms in this price band",
                        "Comfortably seats a group of six without a reservation on weeknights"
                      ],
                      insiderTip: "The far corner under the tree takes no bookings — walk in before 8 and it's usually free."),
            Candidate(name: "Olive Bistro", area: "Mehrauli",
                      tagline: "Whitewashed Mediterranean courtyard beside the Qutub.",
                      category: .food, perHead: 1_800, listPrice: 2_200,
                      offer: "Complimentary dessert", offerWindow: "all evening",
                      openWindow: "Open till midnight", travelNote: "22 min by cab",
                      imageSeed: 2,
                      story: "Bougainvillea over whitewashed walls, olive trees in terracotta, and the Qutub Minar lit up just past the far wall — this is the room Delhi books when it wants the evening to look like somewhere else. The Mediterranean menu plays it straight: wood-fired breads, grilled fish, a lamb dish that regulars order without reading. It is the most expensive option in this slot and it knows it.",
                      highlights: [
                        "Qutub Minar visible from the courtyard once the floodlights come on",
                        "Wood-fired breads and the grilled fish are the reliable orders",
                        "Dress code is loosely enforced but the room skews smart",
                        "Reservations strongly advised on Friday and Saturday"
                      ],
                      insiderTip: "Ask for a table on the upper terrace — same menu, and the minaret sits dead centre from up there."),
            Candidate(name: "Comorin", area: "Gurugram",
                      tagline: "Regional Indian small plates, long bar, loud room.",
                      category: .food, perHead: 1_500, listPrice: nil,
                      offer: nil, offerWindow: nil,
                      openWindow: "Open till 1:00 am", travelNote: "38 min by cab — outside the buffer",
                      imageSeed: 3,
                      story: "A serious bar that happens to serve some of the most interesting regional Indian food in the NCR — kebabs off a live grill, a rotating set of small plates pulled from a different state every few months, and a cocktail programme built on Indian botanicals rather than imported syrups. The room is loud and stays loud, which is either the point or the problem depending on your table.",
                      highlights: [
                        "Cocktail programme is the real draw — Indian botanicals, nothing imported",
                        "Small plates rotate by region every few months",
                        "Kitchen runs late; food service continues past midnight",
                        "Loud room — a bad fit if anyone wants a conversation"
                      ],
                      insiderTip: "It's the furthest option in this slot. Worth it only if the squad is already heading Gurugram-side."),
            Candidate(name: "Dhaba by Claridges", area: "Connaught Place",
                      tagline: "Truck-art kitsch, butter chicken that earns the queue.",
                      category: .food, perHead: 1_200, listPrice: 1_500,
                      offer: "15% off pre-9 pm", offerWindow: "till 9:00 pm",
                      openWindow: "Open till 11:00 pm", travelNote: "18 min by metro",
                      imageSeed: 4,
                      story: "Deliberate kitsch — truck art on every surface, hand-painted signage, tin plates — wrapped around a kitchen that takes North Indian food completely seriously. The butter chicken is the reason people queue and it does not disappoint; the dal makhani has been on a slow fire since morning. It is the most straightforwardly crowd-pleasing option here, and the only one within walking distance of a metro stop.",
                      highlights: [
                        "Butter chicken and the overnight dal makhani are non-negotiable orders",
                        "Rajiv Chowk metro is a seven-minute walk — no cab needed",
                        "Vegetarian half of the menu is as strong as the rest",
                        "No reservations after 8 pm; expect a twenty-minute wait on weekends"
                      ],
                      insiderTip: "The 15% pre-9 discount applies to the whole bill, not just food — worth arriving early for."),
            Candidate(name: "Andaz Delhi", area: "Aerocity",
                      tagline: "AnnaMaya food hall — everyone orders something different.",
                      category: .food, perHead: 1_600, listPrice: 1_900,
                      offer: "Squad platter for 6", offerWindow: "till 10:00 pm",
                      openWindow: "Open till 11:30 pm", travelNote: "31 min by cab",
                      imageSeed: 5,
                      story: "A European-style food hall inside a hotel, which sounds worse than it is: separate counters for bakery, charcuterie, a raw bar and a proper kitchen, all billed to one table. It solves the group problem better than anything else in this slot — the vegetarian, the person who only wants a salad, and whoever wants a full meal all get what they want without negotiating a shared menu.",
                      highlights: [
                        "Separate counters mean nobody compromises on what they eat",
                        "Bakery counter is genuinely good — not hotel-buffet filler",
                        "Squad platter for six is the cheapest way through the menu",
                        "Aerocity location makes sense only if someone has an early flight"
                      ],
                      insiderTip: "The platter has to be ordered before 10 — after that it comes off the menu entirely.")
        ]),

        Deck(category: .sights, slotName: "Afternoon", window: "2:30 – 5:00 pm", candidates: [
            Candidate(name: "Sunder Nursery", area: "Nizamuddin",
                      tagline: "90 acres of Mughal garden. Golden hour is the whole point.",
                      category: .sights, perHead: 200, listPrice: nil,
                      offer: nil, offerWindow: nil,
                      openWindow: "Gates close 7:00 pm", travelNote: "9 min walk from Humayun's Tomb",
                      imageSeed: 6,
                      story: "Ninety acres restored over a decade into what is now the closest thing Delhi has to a great public park — formal Mughal water channels, fifteen heritage monuments scattered through the grounds, and a micro-habitat zone at the far end that most visitors never reach. It is big enough that an hour only covers a third of it, and the light in the last hour before closing is the reason photographers keep coming back.",
                      highlights: [
                        "Fifteen heritage monuments inside the grounds, six of them UNESCO-listed",
                        "The lake and bonsai house sit at the far end — allow a full hour",
                        "Connects to Humayun's Tomb on foot; the two work as one afternoon",
                        "Wide paved paths throughout — the only step-free option in this slot"
                      ],
                      insiderTip: "Enter from the Nizamuddin gate rather than the main one — the amphitheatre lawns are right there and almost always empty."),
            Candidate(name: "Hauz Khas Fort", area: "Hauz Khas",
                      tagline: "Ruins over a reservoir, deer park behind. Free entry.",
                      category: .sights, perHead: 0, listPrice: nil,
                      offer: nil, offerWindow: nil,
                      openWindow: "Open till 6:00 pm", travelNote: "12 min by cab",
                      imageSeed: 7,
                      story: "A fourteenth-century madrasa and tomb complex sitting directly above a reservoir, with a deer park behind it and the whole of Hauz Khas Village — bars, boutiques, more bars — starting the moment you walk back out the gate. The ruins themselves take twenty minutes; the appeal is the arcade of arches facing west over the water, which is where everyone ends up sitting until they close it.",
                      highlights: [
                        "Free entry, but gates shut firmly at 6 — no late entry",
                        "West-facing arcade over the reservoir is the spot worth walking to",
                        "Deer park entrance is a separate gate behind the complex",
                        "Opens straight onto Hauz Khas Village for whatever comes next"
                      ],
                      insiderTip: "Uneven stone throughout and no lighting after dusk — worth knowing if anyone's in bad shoes."),
            Candidate(name: "Lodhi Art District", area: "Lodhi Colony",
                      tagline: "India's first open-air public art district. Entirely walkable.",
                      category: .sights, perHead: 0, listPrice: nil,
                      offer: nil, offerWindow: nil,
                      openWindow: "Always open", travelNote: "7 min by cab",
                      imageSeed: 8,
                      story: "Fifty-odd large-scale murals painted across the facades of a 1940s government housing colony, by artists from more than two dozen countries. The whole thing is a public street — no gate, no ticket, no closing time — laid out across a handful of parallel blocks you can cover on foot in under an hour. Works get painted over and replaced every year, so it is rarely the same district twice.",
                      highlights: [
                        "Roughly 50 murals across Blocks 3 through 12, all walkable",
                        "No gate and no closing time — the only always-open option here",
                        "Murals rotate annually; older works get painted over",
                        "Khanna Market at the edge for coffee when the walking is done"
                      ],
                      insiderTip: "Start at Meharchand Market and walk inward — doing it in reverse means finishing in a residential dead end."),
            Candidate(name: "Agrasen ki Baoli", area: "Connaught Place",
                      tagline: "108 steps down into a 14th-century stepwell. Cool, echoey.",
                      category: .sights, perHead: 0, listPrice: nil,
                      offer: nil, offerWindow: nil,
                      openWindow: "Open till 6:00 pm", travelNote: "16 min by metro",
                      imageSeed: 9,
                      story: "A 60-metre stepwell dropped into the middle of a block of office towers, 108 stone steps descending in a narrowing perspective that gets colder and quieter the further down you go. It takes fifteen minutes to see and is the most photographed staircase in the city for good reason. The sound is the surprising part — voices from the top of the well arrive at the bottom several seconds late.",
                      highlights: [
                        "108 steps down, and the temperature drops noticeably at the base",
                        "Fifteen minutes start to finish — pairs well with anything nearby",
                        "Free entry, no ticket counter, closes at 6 sharp",
                        "Barakhamba Road metro is a ten-minute walk"
                      ],
                      insiderTip: "Weekday mornings are near-empty. By late afternoon the lower steps are a queue of people waiting to photograph them.")
        ]),

        Deck(category: .nightlife, slotName: "Late", window: "10:00 pm – late", candidates: [
            Candidate(name: "Piano Man", area: "Safdarjung Enclave",
                      tagline: "Live jazz, low ceiling, no talking through the set.",
                      category: .nightlife, perHead: 1_400, listPrice: 1_800,
                      offer: "Cover waived before 9", offerWindow: "till 9:00 pm",
                      openWindow: "Sets at 9:00 & 11:00 pm", travelNote: "11 min by cab",
                      imageSeed: 10,
                      story: "A basement room built around the music rather than the bar — low ceiling, red velvet, a grand piano and a house policy that people actually respect: you do not talk through the set. Delhi's serious jazz musicians play here, along with a steady rotation of touring acts, and the sound engineering is far better than the room's size suggests. Two sets a night, and the late one is usually the looser of the two.",
                      highlights: [
                        "Two sets nightly at 9 and 11 — the late set runs looser",
                        "House rule against talking through the music is genuinely enforced",
                        "Seating is first-come; the room fills 30 minutes before each set",
                        "Cocktails are strong and the kitchen stays open between sets"
                      ],
                      insiderTip: "Get there for the 9 pm set and the cover is waived — but you need to be through the door before it starts, not before it ends."),
            Candidate(name: "Summer House Café", area: "Hauz Khas Village",
                      tagline: "Rooftop, resident DJs, the reliable default.",
                      category: .nightlife, perHead: 1_600, listPrice: 2_000,
                      offer: "1+1 till 10 pm", offerWindow: "till 10:00 pm",
                      openWindow: "Open till 1:00 am", travelNote: "4 min walk",
                      imageSeed: 11,
                      story: "The rooftop everyone defaults to, and it has stayed the default for a decade because it does not get anything badly wrong. Resident DJs work house and disco most nights, the terrace catches whatever breeze exists, and the crowd is broad enough that no one feels out of place. Nothing here will surprise you — that is precisely the argument for it when a group cannot agree on anything else.",
                      highlights: [
                        "Rooftop terrace plus an indoor floor — usable even if it rains",
                        "Resident DJs lean house and disco; live acts on some weeknights",
                        "1+1 until 10 pm applies across the full bar menu",
                        "Four minutes on foot from the Hauz Khas Village entrance"
                      ],
                      insiderTip: "It goes from half-full to a queue at the door around 10:30 — arrive before that or plan to wait."),
            Candidate(name: "Ghost Street", area: "Cyber Hub",
                      tagline: "Asian street-food bar. Loud, cheap, always full.",
                      category: .nightlife, perHead: 1_100, listPrice: 1_300,
                      offer: "Squad shots round", offerWindow: "till 11:00 pm",
                      openWindow: "Open till 1:00 am", travelNote: "41 min by cab — flagged",
                      imageSeed: 12,
                      story: "Modelled on a Chinese night market and committed to the bit — neon signage, hawker stalls around the perimeter, communal tables down the middle and a noise level that makes conversation a shouting exercise. The food is Asian street snacking done cheaply and well: bao, skewers, dumplings by the basket. It is the cheapest option in this slot and comfortably the most chaotic.",
                      highlights: [
                        "Cheapest per-head option in this slot by a clear margin",
                        "Communal seating — a group of six gets a table without waiting",
                        "Bao, skewers and dumplings are what the kitchen does properly",
                        "Extremely loud; a poor choice if the night is meant to wind down"
                      ],
                      insiderTip: "Forty-one minutes out means one cab each way. Only worth it if the squad is starting the night in Gurugram.")
        ]),

        Deck(category: .discover, slotName: "Something new", window: "flexible", candidates: [
            Candidate(name: "Smaaash Go-Karting", area: "Cyber Hub",
                      tagline: "Indoor karting, 12 laps. Someone will get competitive.",
                      category: .discover, perHead: 900, listPrice: 1_200,
                      offer: "Group of 6 — 2 free laps", offerWindow: "weekdays",
                      openWindow: "Open till 11:00 pm", travelNote: "36 min by cab",
                      imageSeed: 13,
                      story: "An indoor entertainment complex whose karting track is the only part worth the trip — a proper banked circuit with electric karts, timing transponders and a leaderboard that goes up on a screen after every heat. Twelve laps is roughly eight minutes of driving and enough for someone in the group to take it far too seriously. The rest of the floor is VR booths and cricket simulators of wildly varying quality.",
                      highlights: [
                        "Twelve timed laps with a live leaderboard after each heat",
                        "Closed-toe shoes required — they will turn you away in sandals",
                        "Karts are electric, so the indoor track stays breathable",
                        "Weekday group deal adds two free laps for six or more"
                      ],
                      insiderTip: "Book the last heat of the evening — the track empties out and they rarely enforce the lap count."),
            Candidate(name: "Kiran Nadar Museum", area: "Saket",
                      tagline: "Modern Indian art, currently showing a Gaitonde retrospective.",
                      category: .discover, perHead: 0, listPrice: nil,
                      offer: nil, offerWindow: nil,
                      openWindow: "Open till 6:30 pm", travelNote: "13 min by cab",
                      imageSeed: 14,
                      story: "A private museum with one of the most significant collections of modern and contemporary Indian art anywhere, and it charges nothing to walk in. The current Gaitonde retrospective pulls together canvases that normally sit in private hands and rarely travel — the kind of show that would carry a ticket price and a queue almost anywhere else. Two floors, unhurried, and quiet enough to be a genuine break from the day.",
                      highlights: [
                        "Free entry, no booking, two floors of permanent and rotating work",
                        "Gaitonde retrospective includes canvases rarely shown publicly",
                        "Inside Select Citywalk, so food and cabs are immediately to hand",
                        "Ninety minutes covers it properly; an hour covers it well enough"
                      ],
                      insiderTip: "Last entry is 6, not 6:30 — the closing time on the listing is when they turn the lights off."),
            Candidate(name: "Depot48 — Open Mic", area: "Safdarjung",
                      tagline: "Thursday open mic. Free entry, two-drink minimum.",
                      category: .discover, perHead: 800, listPrice: nil,
                      offer: nil, offerWindow: nil,
                      openWindow: "Doors 8:30 pm", travelNote: "9 min by cab",
                      imageSeed: 15,
                      story: "A small, wood-panelled bar that hands its stage over on Thursdays to whoever signs up — songwriters, stand-ups, poets, and a reliable proportion of people who should not have. That unevenness is the appeal: the room is warm about it, the crowd is generous, and every few weeks someone genuinely good turns up unannounced. Entry is free against a two-drink minimum, which is where the per-head figure comes from.",
                      highlights: [
                        "Sign-up sheet opens at the door — anyone in the group can play",
                        "Free entry against a two-drink minimum, no cover charge",
                        "Small room, maybe sixty people; it fills by nine",
                        "Sets run short, so a bad act is over in four minutes"
                      ],
                      insiderTip: "The list caps at about fifteen performers. If someone wants a slot, get there when doors open at 8:30."),
            Candidate(name: "Adventure Island", area: "Rohini",
                      tagline: "Amusement park. Unserious, and that's the appeal.",
                      category: .discover, perHead: 1_500, listPrice: 1_800,
                      offer: "Group pass — 6 for 5", offerWindow: "all day",
                      openWindow: "Open till 8:00 pm", travelNote: "52 min by cab — flagged",
                      imageSeed: 16,
                      story: "A full-scale amusement park in north Delhi with roller coasters, a drop tower and a boating lake, aimed squarely at families and entirely unbothered about being cool. Taken on its own terms it is a good time — the rides are real rides, the queues on weekdays are short, and a group of adults treating it unironically tends to have a better day than they expected. The distance is the only serious argument against it.",
                      highlights: [
                        "Fifteen-plus rides including two coasters and a drop tower",
                        "Weekday queues are short; weekends are a different park entirely",
                        "Group pass gives six entries for the price of five",
                        "Closes at 8, and the last ride admission is well before that"
                      ],
                      insiderTip: "Fifty-two minutes each way and a hard 8 pm close — this only works as a full afternoon, never as a stop between others.")
        ])
    ]
}
