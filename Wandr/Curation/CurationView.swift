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

    /// `groupSize` threads the confirmed brief's head-count through to the squad poll.
    init(groupSize: Int? = nil) {
        _decks = State(initialValue: DemoPlan.decks)
        self.groupSize = groupSize
    }

    /// Total options across every slot that the squad will vote on.
    private var slateCount: Int {
        decks.reduce(0) { $0 + $1.shortlist.count }
    }

    private var slotsWithOptions: Int {
        decks.filter { !$0.shortlist.isEmpty }.count
    }

    /// Per-head cost is a range, not a figure — the squad has not chosen yet.
    /// Both ends are computed deterministically from dataset fields.
    private var costRange: ClosedRange<Int>? {
        let perSlot = decks.compactMap { deck -> (Int, Int)? in
            let costs = deck.shortlisted.map(\.perHead)
            guard let low = costs.min(), let high = costs.max() else { return nil }
            return (low, high)
        }
        guard !perSlot.isEmpty else { return nil }
        return perSlot.reduce(0, { $0 + $1.0 })...perSlot.reduce(0, { $0 + $1.1 })
    }

    private var costLabel: String {
        guard let range = costRange else { return "Nothing on the slate yet" }
        return range.lowerBound == range.upperBound
            ? "₹\(range.lowerBound) per head"
            : "₹\(range.lowerBound)–\(range.upperBound) per head"
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

                    Color.clear.frame(height: 90)
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
        Text("Pick your stops")
            .font(.wandrDisplay(40))
            .foregroundStyle(Wandr.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
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

    /// Two glass elements floating over the deck, not a bar drawn across it.
    /// They share a `GlassEffectContainer` so they sample the same backdrop and
    /// their lensing blends where they come close, reading as one plane rather
    /// than two pills that happen to be adjacent.
    private var summaryBar: some View {
        GlassEffectContainer(spacing: 14) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(slateCount) on the slate · \(slotsWithOptions)/\(decks.count) slots")
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .contentTransition(.numericText())

                    Text(costLabel)
                        .font(.caption.monospacedDigit())
                        .contentTransition(.numericText())
                        .foregroundStyle(.secondary)
                }
                // Regular glass handles its own legibility — it frosts and
                // shifts tint as cards pass underneath. Painting our own
                // opaque fill here is what kills the effect.
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: .capsule)

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
            ScheduleBlock(
                title: candidate.name,
                category: candidate.category,
                startMinute: Self.defaultStart(for: candidate.category),
                durationMinutes: 90,
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
