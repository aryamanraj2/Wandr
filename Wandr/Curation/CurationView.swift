// CurationView.swift Wandr The first modal after a plan is researched: what's actually on the table. One deck per slot — Food, Sights, Nightlife, Discover — each a stack of grounded candidates the host swipes through.

import SwiftUI

struct CurationView: View {
    @State private var decks: [Deck]

    /// The finished night, presented *by its data* rather than by a boolean.
    ///
    /// `ScheduleView` seeds its `@State blocks` from `stops` in `init`, so whichever value that initializer first sees is the one it keeps. A `.sheet(isPresented:)` content closure is re-evaluated whenever this view's body is — which, with live snapshots arriving, is often — and an evaluation that happens while the stops are still empty freezes the demo fallback into the schedule's state for good. Keying the sheet on an identified payload gives the schedule a fresh identity per night, so it can only ever be seeded with the squad's actual winners.
    @State private var settled: SettledNight?

    /// One decided night on its way to the schedule. The `id` is what makes the sheet's identity change.
    private struct SettledNight: Identifiable {
        let id = UUID()
        let stops: [ScheduleBlock]
    }

    /// True once the display header has scrolled up under the navigation bar, at which point the short title takes over up there.
    @State private var headerCollapsed = false

    /// Flipped once on appear to deal the slate in from the bottom of the page.
    ///
    /// One gate for the whole page rather than one per deck, and it is read by `DeckView` too: the
    /// decks live in a `LazyVStack`, so a deck built later already sees `true` and is simply there.
    /// That is what keeps this an entrance rather than something that fires again every time a deck
    /// scrolls back into view.
    @State private var dealt = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Send-to-Squad. The slate becomes a real room: the host reads out a code, the squad joins on their own phones, and the winners seed the schedule.
    @State private var room = SquadRoom.shared
    @State private var showSquad = false
    @State private var stopsFromPoll: [ScheduleBlock] = []

    /// The fallback when no relay is running: the original one-device simulation, reachable from the lobby rather than automatic, so it is a choice the host makes rather than a silent downgrade.
    @State private var showOfflinePoll = false
    @State private var offlineSession: PollSession?

    /// Group size from the confirmed brief, pre-filling the poll's quorum. `nil` when the summary left it open — the poll falls back to the slate's implied size.
    private let groupSize: Int?

    /// One-line explanation shown when the group's time window shaped the plan (e.g. "You're free 8–9 pm — time for one stop"). `nil` for an open plan.
    private let banner: String?

    /// Per-category window [start...end] in minutes, so the squad's winners land inside the group's real window on the schedule. Empty ⇒ category defaults. Keyed by `Deck.slotID`, not category: a plan can hold both lunch and dinner, and looking their window up by `.food` would give both the same hour.
    private let slotWindows: [String: ClosedRange<Int>]

    /// Preview / design-pass entry point: the hardcoded demo decks, no window.
    init(groupSize: Int? = nil) {
        _decks = State(initialValue: DemoPlan.decks)
        self.groupSize = groupSize
        self.banner = nil
        self.slotWindows = [:]
    }

    /// The live entry point: model-curated, grounded decks with a window banner and window-aware schedule placement.
    init(
        decks: [Deck],
        groupSize: Int?,
        banner: String?,
        slotWindows: [String: ClosedRange<Int>]
    ) {
        _decks = State(initialValue: decks)
        self.groupSize = groupSize
        self.banner = banner
        self.slotWindows = slotWindows
    }

    /// Total options across every slot that the squad will vote on.
    private var slateCount: Int {
        decks.reduce(0) { $0 + $1.shortlist.count }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 40) {
                    intro
                        .dealIn(dealt, order: 0, reduceMotion: reduceMotion)

                    ForEach($decks) { $deck in
                        // Position in the slate, not in the `ForEach`'s own output. Both the leading
                        // rule and the cascade count decks, and a row index would drift the moment
                        // the rule stops being emitted for the first one.
                        let order = decks.firstIndex { $0.id == deck.id } ?? 0

                        // Rule and deck travel as one object. Emitted as siblings they arrive on
                        // different beats, and a divider landing before the thing it divides reads
                        // as a stray line. The inner spacing matches the stack's so nothing moves.
                        VStack(spacing: 40) {
                            // Leading rule rather than trailing, so the list does not end on a divider pointing at nothing.
                            if order > 0 {
                                WandrDashedRule()
                            }

                            DeckView(deck: $deck, revealed: dealt, dealOrder: order + 1)
                        }
                        .id(deck.id)
                        .dealIn(dealt, order: order + 1, reduceMotion: reduceMotion)
                    }
                }
                .padding(.horizontal, Metrics.gutter)
            }
            // Threshold rather than raw offset: state only changes on the two frames where the header crosses the bar, not on every scroll tick.
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > Metrics.headerCollapse
            } action: { _, collapsed in
                // Assign bare and let the two views that care animate on the value. Wrapping this in `withAnimation` made every deck in the stack a participant in a transaction about a title's opacity — four card stacks, their materials and gradients all re-evaluated on the exact frames the finger was moving.
                headerCollapsed = collapsed
            }
            .background(Wandr.pageBackground)
            // Assigned bare, like `headerCollapsed` above and for the same reason: each section
            // carries its own `.animation(_:value:)` through `dealIn`, so a `withAnimation` here
            // would only widen the transaction to every deck, material and gradient on the page.
            .onAppear {
                guard !dealt else { return }
                dealt = true
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Stops")
                        .font(.headline)
                        .foregroundStyle(Wandr.primaryText)
                        .opacity(headerCollapsed ? 1 : 0)
                        .animation(.wandrResponse, value: headerCollapsed)
                }
            }
            .safeAreaBar(edge: .bottom) {
                summaryBar
            }
            // Soft on both edges: content feathers away under the toolbar the same way it does under the summary bar, rather than hitting a hard ribbon across the top.
            .scrollEdgeEffectStyle(.soft, for: .top)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            // The room is the doorway to the schedule: once every slot has a winner it settles by itself, and leaving it opens the laid-out night. Full-screen rather than a sheet — the host is reading a code out to a table of people, not glancing at a card.
            .fullScreenCover(isPresented: $showSquad, onDismiss: {
                // Handed over on dismiss rather than while the cover is still up: two presentations cannot overlap, and the schedule must not be built until the room has left the screen.
                if !stopsFromPoll.isEmpty { settled = SettledNight(stops: stopsFromPoll) }
            }) {
                SquadFlowView(
                    room: room,
                    onCancel: {
                        room.leave()
                        showSquad = false
                    },
                    onSettled: { winners in
                        stopsFromPoll = scheduleBlocks(from: winners)
                        SquadLog.room("settled: \(winners.count) winners → \(stopsFromPoll.count) stops "
                            + "(\(stopsFromPoll.map(\.title).joined(separator: ", ")))")
                        showSquad = false
                    },
                    onFallBackOffline: {
                        room.leave()
                        offlineSession = PollSession(decks: decks, groupSize: groupSize)
                        showSquad = false
                        showOfflinePoll = true
                    }
                )
            }
            .sheet(isPresented: $showOfflinePoll, onDismiss: {
                if !stopsFromPoll.isEmpty { settled = SettledNight(stops: stopsFromPoll) }
            }) {
                if let offlineSession {
                    SquadPollView(session: offlineSession) { winners in
                        stopsFromPoll = scheduleBlocks(from: winners)
                        showOfflinePoll = false
                    }
                }
            }
            .sheet(item: $settled) { night in
                ScheduleView(stops: night.stops)
            }
        }
        .tint(Wandr.brand)
    }

    // MARK: Intro

    /// Fades out as the bar title fades in, so the two read as one title moving up rather than two titles briefly on screen together.
    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pick your stops")
                .font(.wandrDisplay(40))
                .foregroundStyle(Wandr.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)

            // The one line that makes a time-boxed night read differently from an open one: it names the window and how many stops it fits.
            if let banner {
                Label(banner, systemImage: "clock.badge.checkmark")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Wandr.primaryText.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .opacity(headerCollapsed ? 0 : 1)
        .animation(.wandrResponse, value: headerCollapsed)
    }

    // MARK: Summary bar

    /// A single glass action floating over the deck, not a bar drawn across it.
    private var summaryBar: some View {
        GlassEffectContainer(spacing: 14) {
            HStack(spacing: 14) {
                Spacer(minLength: 0)

                Button {
                    room.host(decks: decks)
                    showSquad = true
                } label: {
                    Label("Send to Squad", systemImage: "paperplane.fill")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 4)
                }
                // The one tinted surface on screen — the primary action earns it.
                .buttonStyle(.glassProminent)
                .tint(Wandr.brand)
                .disabled(slateCount == 0)
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 8)
        }
        .animation(.wandrResponse, value: slateCount)
    }

    // MARK: Handoff

    /// The squad's per-slot winners become the schedule. Each slot contributes one block, timed by category. Real slot times come from `FeasibilityValidator`; these category defaults are placeholders for the design pass.
    private func scheduleBlocks(
        from winners: [(slotID: String, candidate: Candidate)]
    ) -> [ScheduleBlock] {
        let day = DemoPlan.days[0]
        return winners.map { slotID, candidate in
            // A window-shaped plan places the block inside the group's real window and clamps its length to fit; an open plan uses the category default.
            let start: Int
            let duration: Int
            if let window = slotWindows[slotID] {
                start = window.lowerBound
                duration = min(90, max(30, window.upperBound - window.lowerBound))
            } else {
                start = Self.defaultStart(for: candidate.category)
                duration = 90
            }
            return ScheduleBlock(
                title: candidate.name,
                category: candidate.category,
                startMinute: start,
                durationMinutes: duration,
                dayID: day.id,
                imageSeed: candidate.imageSeed
            )
        }
        .sorted { $0.startMinute < $1.startMinute }
    }

    /// A rough time-of-day per slot, so the winners land in a sensible order.
    private static func defaultStart(for category: StopCategory) -> Int {
        switch category {
        case .sights:    return 14 * 60 + 30
        case .discover:  return 17 * 60
        case .food:      return 20 * 60
        case .nightlife: return 22 * 60
        }
    }
}

#Preview {
    CurationView()
}
