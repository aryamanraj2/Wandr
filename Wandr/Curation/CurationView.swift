//
//  CurationView.swift
//  Wandr
//
//  The first modal after a plan is researched: what's actually on the table.
//  One deck per slot — Food, Sights, Nightlife, Discover — each a stack of
//  grounded candidates the host swipes through.
//

import SwiftUI

struct CurationView: View {
    @State private var decks: [Deck]
    @State private var scrolledDeck: Deck.ID?
    @State private var showSchedule = false

    /// True once the display header has scrolled up under the navigation bar,
    /// at which point the short title takes over up there.
    @State private var headerCollapsed = false

    // Send-to-Squad. The slate goes to a per-slot vote; the winners seed the schedule.
    @State private var showPoll = false
    @State private var pollSession: PollSession?
    @State private var stopsFromPoll: [ScheduleBlock] = []

    /// Group size from the confirmed brief, pre-filling the poll's quorum. `nil` when the
    /// summary left it open — the poll falls back to the slate's implied size.
    private let groupSize: Int?

    /// One-line explanation shown when the group's time window shaped the plan
    /// (e.g. "You're free 8–9 pm — time for one stop"). `nil` for an open plan.
    private let banner: String?

    /// Per-category window [start...end] in minutes, so the squad's winners land
    /// inside the group's real window on the schedule. Empty ⇒ category defaults.
    private let slotWindows: [StopCategory: ClosedRange<Int>]

    /// Preview / design-pass entry point: the hardcoded demo decks, no window.
    init(groupSize: Int? = nil) {
        _decks = State(initialValue: DemoPlan.decks)
        self.groupSize = groupSize
        self.banner = nil
        self.slotWindows = [:]
    }

    /// The live entry point: model-curated, grounded decks with a window banner and
    /// window-aware schedule placement.
    init(
        decks: [Deck],
        groupSize: Int?,
        banner: String?,
        slotWindows: [StopCategory: ClosedRange<Int>]
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

                    ForEach($decks) { $deck in
                        // Leading rule rather than trailing, so the list does
                        // not end on a divider pointing at nothing.
                        if deck.id != decks.first?.id {
                            WandrDashedRule()
                        }

                        DeckView(deck: $deck)
                            .id(deck.id)
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                .scrollTargetLayout()
            }
            .scrollPosition(id: $scrolledDeck, anchor: .top)
            // Threshold rather than raw offset: state only changes on the two
            // frames where the header crosses the bar, not on every scroll tick.
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > Metrics.headerCollapse
            } action: { _, collapsed in
                withAnimation(.wandrResponse) { headerCollapsed = collapsed }
            }
            .background(Wandr.pageBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Stops")
                        .font(.headline)
                        .foregroundStyle(Wandr.primaryText)
                        .opacity(headerCollapsed ? 1 : 0)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    categoryJumpMenu
                }
            }
            .safeAreaBar(edge: .bottom) {
                summaryBar
            }
            // Soft on both edges: content feathers away under the toolbar the
            // same way it does under the summary bar, rather than hitting a
            // hard ribbon across the top.
            .scrollEdgeEffectStyle(.soft, for: .top)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            // The poll is the doorway to the schedule: once it locks, its winners
            // become the stops, and dismissing it opens the laid-out night.
            .sheet(isPresented: $showPoll, onDismiss: {
                if !stopsFromPoll.isEmpty { showSchedule = true }
            }) {
                if let pollSession {
                    SquadPollView(session: pollSession) { winners in
                        stopsFromPoll = scheduleBlocks(from: winners)
                        showPoll = false
                    }
                }
            }
            .sheet(isPresented: $showSchedule) {
                ScheduleView(stops: stopsFromPoll)
            }
        }
        .tint(Wandr.ink)
    }

    // MARK: Intro

    /// Fades out as the bar title fades in, so the two read as one title
    /// moving up rather than two titles briefly on screen together.
    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pick your stops")
                .font(.wandrDisplay(40))
                .foregroundStyle(Wandr.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)

            // The one line that makes a time-boxed night read differently from an
            // open one: it names the window and how many stops it fits.
            if let banner {
                Label(banner, systemImage: "clock.badge.checkmark")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Wandr.primaryText.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .opacity(headerCollapsed ? 0 : 1)
    }

    // MARK: Toolbar

    /// Jumping between decks is a navigation job, so it belongs in a menu —
    /// not a second row of custom chrome competing with the tab area.
    private var categoryJumpMenu: some View {
        Menu {
            ForEach(decks) { deck in
                Button {
                    withAnimation(.wandrTransition) { scrolledDeck = deck.id }
                } label: {
                    Label {
                        Text(deck.slotName)
                        if !deck.shortlist.isEmpty {
                            Text("\(deck.shortlist.count) on the slate")
                        }
                    } icon: {
                        Image(systemName: deck.shortlist.isEmpty
                              ? deck.category.symbol
                              : "checkmark.circle.fill")
                    }
                }
            }
        } label: {
            Label("Jump to slot", systemImage: "list.bullet.indent")
        }
    }

    // MARK: Summary bar

    /// A single glass action floating over the deck, not a bar drawn across it.
    private var summaryBar: some View {
        GlassEffectContainer(spacing: 14) {
            HStack(spacing: 14) {
                Spacer(minLength: 0)

                Button {
                    pollSession = PollSession(decks: decks, groupSize: groupSize)
                    showPoll = true
                } label: {
                    Label("Send to Squad", systemImage: "paperplane.fill")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 4)
                }
                // The one tinted surface on screen — the primary action earns it.
                .buttonStyle(.glassProminent)
                .tint(Wandr.ink)
                .disabled(slateCount == 0)
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 8)
        }
        .animation(.wandrResponse, value: slateCount)
    }

    // MARK: Handoff

    /// The squad's per-slot winners become the schedule. Each slot contributes one
    /// block, timed by category. Real slot times come from `FeasibilityValidator`;
    /// these category defaults are placeholders for the design pass.
    private func scheduleBlocks(
        from winners: [(slotID: String, candidate: Candidate)]
    ) -> [ScheduleBlock] {
        let day = DemoPlan.days[0]
        return winners.map { _, candidate in
            // A window-shaped plan places the block inside the group's real window
            // and clamps its length to fit; an open plan uses the category default.
            let start: Int
            let duration: Int
            if let window = slotWindows[candidate.category] {
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
                dayID: day.id
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
