//
//  ItinerarySummaryView.swift
//  Wandr
//
//  The last surface: the plan, finished.
//
//  Everything before this is a working screen — decks are swiped, blocks are
//  dragged. This one is a document. Nothing here moves under a finger, so the
//  layout can afford the things a manipulable timeline cannot: a real masthead,
//  a spine that connects the night into one line, and the gaps between stops
//  named out loud rather than left as empty space.
//
//  Positions are stated, not measured. The schedule renders against a clock
//  because you edit it there; here each stop is simply the next one, so the
//  spine spaces them evenly and the times are read as labels.
//

import SwiftUI

struct ItinerarySummaryView: View {
    let blocks: [ScheduleBlock]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Flipped once on appear to run the staggered reveal down the spine.
    @State private var revealed = false

    /// True once the masthead has cleared the navigation bar and the short
    /// title takes over up there.
    @State private var headerCollapsed = false

    /// Every stop in order. A summary has no day picker — a multi-day plan
    /// reads top to bottom, sectioned, rather than one day at a time.
    private var stops: [ScheduleBlock] {
        blocks.sorted { $0.startMinute < $1.startMinute }
    }

    /// Days the plan actually touches, in calendar order.
    private var days: [PlanDay] {
        let planned = Set(blocks.map(\.dayID))
        return DemoPlan.days.filter { planned.contains($0.id) }
    }

    private func stops(on day: PlanDay) -> [ScheduleBlock] {
        stops.filter { $0.dayID == day.id }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    masthead
                    ledger
                    itinerary
                    closing
                }
                .padding(.bottom, 32)
            }
            .background(Wandr.pageBackground)
            // Threshold rather than raw offset: state changes on the two frames
            // where the masthead crosses the bar, not on every scroll tick.
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > Metrics.headerCollapse
            } action: { _, collapsed in
                withAnimation(.wandrResponse) { headerCollapsed = collapsed }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Itinerary")
                        .font(.headline)
                        .foregroundStyle(Wandr.primaryText)
                        .opacity(headerCollapsed ? 1 : 0)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .safeAreaBar(edge: .bottom) { actionBar }
            .onAppear {
                guard !revealed else { return }
                withAnimation(reduceMotion ? nil : .wandrTransition) { revealed = true }
            }
        }
        .tint(Wandr.ink)
    }

    // MARK: Masthead

    /// Fades out as the bar title fades in, so the two read as one title moving
    /// up rather than two titles briefly sharing the screen.
    private var masthead: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(dateLine)
                .wandrLabelStyle()

            Text("The night,\nplanned.")
                .font(.wandrDisplay(44))
                .italic()
                .foregroundStyle(Wandr.primaryText)
                .lineSpacing(-2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 4)
        .padding(.bottom, 26)
        .opacity(headerCollapsed ? 0 : 1)
    }

    private var dateLine: String {
        guard let first = days.first else { return "Itinerary" }
        guard days.count > 1, let last = days.last else {
            return first.date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        }
        return first.date.formatted(.dateTime.day().month(.abbreviated))
            + " – "
            + last.date.formatted(.dateTime.day().month(.abbreviated))
    }

    // MARK: Ledger

    /// Three figures, set as a row of columns divided by hairlines. This is the
    /// whole plan in one glance — everything below it is the detail.
    private var ledger: some View {
        HStack(alignment: .center, spacing: 0) {
            ledgerColumn(value: "\(stops.count)", label: stops.count == 1 ? "Stop" : "Stops")
            ledgerDivider
            ledgerColumn(value: spanValue, label: "Window")
            ledgerDivider
            ledgerColumn(value: bookedValue, label: "Booked")
        }
        .padding(.vertical, 18)
        .background { WandrCardBackground() }
        .padding(.horizontal, Metrics.gutter)
        .padding(.bottom, 34)
        .accessibilityElement(children: .combine)
    }

    private func ledgerColumn(value: String, label: String) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.wandrTitle(21))
                .monospacedDigit()
                .foregroundStyle(Wandr.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(label)
                .wandrLabelStyle()
        }
        .frame(maxWidth: .infinity)
    }

    private var ledgerDivider: some View {
        Rectangle()
            .fill(Wandr.hairline)
            .frame(width: 1, height: 30)
    }

    /// First door to last — the outer bounds of the night.
    private var spanValue: String {
        guard let start = stops.first?.startMinute,
              let end = stops.map(\.endMinute).max() else { return "—" }
        return "\(compactClock(start))–\(compactClock(end))"
    }

    /// Time actually spoken for, which is not the same as the span. The
    /// difference between the two is the slack, and it is worth showing.
    private var bookedValue: String {
        duration(stops.reduce(0) { $0 + $1.durationMinutes })
    }

    // MARK: Itinerary

    @ViewBuilder
    private var itinerary: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.element.id) { dayIndex, day in
                if days.count > 1 {
                    dayHeading(day, isFirst: dayIndex == 0)
                }

                let dayStops = stops(on: day)
                ForEach(Array(dayStops.enumerated()), id: \.element.id) { index, stop in
                    stopRow(
                        stop,
                        number: index + 1,
                        next: index + 1 < dayStops.count ? dayStops[index + 1] : nil,
                        isLast: index == dayStops.count - 1 && dayIndex == days.count - 1,
                        revealIndex: index
                    )
                }
            }
        }
        .padding(.horizontal, Metrics.gutter)
    }

    private func dayHeading(_ day: PlanDay, isFirst: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if !isFirst { WandrDashedRule().padding(.top, 10) }

            Text(day.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                .wandrLabelStyle(Wandr.primaryText.opacity(0.8))
        }
        .padding(.bottom, 18)
    }

    /// One stop: the clock in the gutter, a node on the spine, the card, and —
    /// when there is dead time before the next stop — the gap named beneath it.
    private func stopRow(
        _ stop: ScheduleBlock,
        number: Int,
        next: ScheduleBlock?,
        isLast: Bool,
        revealIndex: Int
    ) -> some View {
        let gap = next.map { $0.startMinute - stop.endMinute } ?? 0
        let accent = Wandr.accent(for: stop.category)

        return HStack(alignment: .top, spacing: 12) {
            clockGutter(stop)

            spine(accent: accent, drawsConnector: !isLast)

            VStack(alignment: .leading, spacing: 0) {
                stopCard(stop, number: number, accent: accent)

                if let next, gap > 0 {
                    gapNote(minutes: gap, arriving: next)
                } else if next != nil {
                    // Back to back — the spine still needs breathing room.
                    Color.clear.frame(height: 22)
                }
            }
        }
        // Each stop arrives just after the one above it, so the eye is walked
        // down the spine in the order the night happens.
        .opacity(revealed ? 1 : 0)
        .offset(y: revealed ? 0 : 14)
        .animation(
            reduceMotion ? nil : .wandrTransition.delay(Double(revealIndex) * 0.06),
            value: revealed
        )
    }

    private func clockGutter(_ stop: ScheduleBlock) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(hourMinute(stop.startMinute))
                .font(.wandrClock(17))
                .monospacedDigit()
                .foregroundStyle(Wandr.primaryText)

            Text(meridiem(stop.startMinute))
                .wandrLabelStyle()
        }
        .frame(width: 54, alignment: .trailing)
        // The card carries the spoken time; this is the same fact, set twice.
        .accessibilityHidden(true)
    }

    /// The through-line. A filled node per stop, dashed between them, so the
    /// night reads as one continuous thing rather than a list of four cards.
    private func spine(accent: Color, drawsConnector: Bool) -> some View {
        VStack(spacing: 5) {
            Circle()
                .fill(accent)
                .frame(width: 9, height: 9)
                .padding(.top, 17)

            if drawsConnector {
                VerticalRule()
                    .stroke(Wandr.sand,
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 5]))
                    .frame(width: 1.5)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(width: 9)
        .accessibilityHidden(true)
    }

    private func stopCard(_ stop: ScheduleBlock, number: Int, accent: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Text("\(number)")
                        .font(.system(size: 10, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Wandr.cream)
                        .frame(width: 17, height: 17)
                        .background { Circle().fill(accent) }

                    Text(stop.category.title)
                        .wandrLabelStyle(accent)
                }

                Text(stop.title)
                    .font(.wandrTitle(20))
                    .foregroundStyle(Wandr.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text("\(stop.startLabel) – \(stop.endLabel) · \(duration(stop.durationMinutes))")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Wandr.secondaryText)
            }

            Spacer(minLength: 0)

            Image(systemName: stop.category.symbol)
                .font(.system(size: 15))
                .foregroundStyle(accent.opacity(0.85))
                .padding(.top, 1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { WandrCardBackground(corner: Metrics.blockCorner) }
        .shadow(color: Wandr.ink.opacity(0.05), radius: 5, x: 0, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Stop \(number), \(stop.title), \(stop.category.title)")
        .accessibilityValue("\(stop.startLabel) to \(stop.endLabel)")
    }

    /// Unplanned time, stated. Left as blank space it reads as a layout gap;
    /// named, it reads as room in the evening.
    private func gapNote(minutes: Int, arriving: ScheduleBlock) -> some View {
        Text("\(duration(minutes)) free · then \(arriving.title)")
            .font(.caption)
            .foregroundStyle(Wandr.secondaryText)
            .padding(.vertical, 11)
            .padding(.leading, 2)
            .accessibilityLabel("\(duration(minutes)) free before \(arriving.title)")
    }

    // MARK: Closing

    /// A terminal cap on the spine. Without it the last dashed segment stops in
    /// mid-air and the plan reads as truncated rather than finished.
    private var closing: some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: 54)

            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Wandr.cream)
                .frame(width: 20, height: 20)
                .background { Circle().fill(Wandr.ink) }
                .frame(width: 9)

            Text(stops.map(\.endMinute).max().map { "Night ends \(ScheduleBlock.clock($0))" } ?? "")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Wandr.secondaryText)
                .padding(.leading, 6)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 20)
        .opacity(revealed ? 1 : 0)
        .animation(
            reduceMotion ? nil : .wandrTransition.delay(Double(stops.count) * 0.06),
            value: revealed
        )
    }

    // MARK: Actions

    /// Glass over the page rather than a bar drawn across it, matching curation.
    private var actionBar: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                ShareLink(item: shareText) {
                    Label("Share plan", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.glassProminent)
                .tint(Wandr.ink)

                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.glass)
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 8)
        }
    }

    /// Plain text, because the plan leaves the app into a group chat.
    private var shareText: String {
        var lines = [dateLine, ""]
        for (index, stop) in stops.enumerated() {
            lines.append("\(index + 1). \(stop.startLabel) — \(stop.title) (\(stop.category.title))")
        }
        lines.append("")
        lines.append("\(stops.count) stops · \(spanValue)")
        return lines.joined(separator: "\n")
    }

    // MARK: Formatting

    private func hourMinute(_ minute: Int) -> String {
        let h24 = (minute / 60) % 24
        let m = minute % 60
        var h = h24 % 12
        if h == 0 { h = 12 }
        return m == 0 ? "\(h)" : String(format: "%d:%02d", h, m)
    }

    private func meridiem(_ minute: Int) -> String {
        ((minute / 60) % 24) < 12 ? "am" : "pm"
    }

    /// Bare clock for the ledger, where two of them sit side by side and the
    /// full "10:00 pm" twice over is more punctuation than information.
    private func compactClock(_ minute: Int) -> String {
        "\(hourMinute(minute))\(meridiem(minute))"
    }

    private func duration(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
    }
}

/// A single vertical line, so it can carry a dash pattern.
private struct VerticalRule: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: 0))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

#Preview("Full day") {
    ItinerarySummaryView(blocks: DemoPlan.blocks(for: DemoPlan.days[0]))
}

#Preview("Single stop") {
    ItinerarySummaryView(blocks: [
        ScheduleBlock(title: "Piano Man", category: .nightlife,
                      startMinute: 20 * 60, durationMinutes: 120,
                      dayID: DemoPlan.days[0].id)
    ])
}
