// ItinerarySummaryView.swift Wandr The last surface: the plan, finished. Everything before this is a working screen — decks are swiped, blocks are dragged. This one is a document. Nothing here moves under a finger, so the layout can afford the things a manipulable timeline cannot: a real masthead, a spine that connects the night into one line, and the gaps between stops named out loud rather than left as empty space. Positions are stated, not measured. The schedule renders against a clock because you edit it there; here each stop is simply the next one, so the spine spaces them evenly and the times are read as labels.

import SwiftUI

struct ItinerarySummaryView: View {
    let blocks: [ScheduleBlock]

    // The document's one column grid. Every row on the page — each stop and the closing cap — is built from these three, so the clock gutter, the spine, and the cards can never drift out of line with each other the way they do when a row hand-rolls its own spacing.

    /// Wide enough for the longest clock the day can produce ("12:30"), which a tighter gutter silently squeezes.
    private static let clockGutter: CGFloat = 58
    /// The spine's axis. Nodes are centred on it regardless of their own diameter.
    private static let spineWidth: CGFloat = 9
    private static let rowSpacing: CGFloat = 12

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Flipped once on appear to run the staggered reveal down the spine.
    @State private var revealed = false

    /// True once the masthead has cleared the navigation bar and the short title takes over up there.
    @State private var headerCollapsed = false

    /// Every stop in order. A summary has no day picker — a multi-day plan reads top to bottom, sectioned, rather than one day at a time.
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
            // Threshold rather than raw offset: state changes on the two frames where the masthead crosses the bar, not on every scroll tick.
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
        .tint(Wandr.brand)
    }

    // MARK: Masthead

    /// Fades out as the bar title fades in, so the two read as one title moving up rather than two titles briefly sharing the screen.
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

    /// Three figures, set as a row of columns divided by hairlines. This is the whole plan in one glance — everything below it is the detail.
    ///
    /// The columns take their natural widths and the *gaps* are what get distributed evenly, rather than the other way round. Splitting the card into equal thirds looks orderly in the abstract but these three figures are nothing like equal in length: a stop count is one glyph and a window is a pair of clock times, so equal thirds truncate the window to make room for whitespace beside the count, and push the longest figure hard against a hairline. Even gaps read as balanced and, more importantly, hold for any values the night produces.
    private var ledger: some View {
        HStack(alignment: .center, spacing: 0) {
            Spacer(minLength: 10)
            ledgerColumn(value: "\(stops.count)", label: stops.count == 1 ? "Stop" : "Stops")
            Spacer(minLength: 10)
            ledgerDivider
            Spacer(minLength: 10)
            ledgerColumn(value: spanValue, label: "Window")
            Spacer(minLength: 10)
            ledgerDivider
            Spacer(minLength: 10)
            ledgerColumn(value: bookedValue, label: "Booked")
            Spacer(minLength: 10)
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
                .font(.wandrTitle(20))
                .monospacedDigit()
                .foregroundStyle(Wandr.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(label)
                .wandrLabelStyle()
                .lineLimit(1)
        }
        // Ahead of the spacers, so a column states the width it needs before any of them take their share.
        .layoutPriority(1)
    }

    private var ledgerDivider: some View {
        Rectangle()
            .fill(Wandr.hairline)
            .frame(width: 1, height: 32)
    }

    /// First door to last — the outer bounds of the night.
    private var spanValue: String {
        guard let start = stops.first?.startMinute,
              let end = stops.map(\.endMinute).max() else { return "—" }
        return timeRange(start, end)
    }

    /// A span set the way it would be written rather than the way it is stored. When both ends fall in the same half of the day the first meridiem is redundant — "9:45pm–11:15pm" says "pm" twice to no one's benefit — but across midnight both are load-bearing, so the rule is conditional, not a blanket trim.
    private func timeRange(_ start: Int, _ end: Int) -> String {
        let opening = meridiem(start) == meridiem(end)
            ? hourMinute(start)
            : compactClock(start)
        return "\(opening)–\(compactClock(end))"
    }

    /// Time actually spoken for, which is not the same as the span. The difference between the two is the slack, and it is worth showing.
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
                // Where this day's stops fall in the document, not in the day. The stagger is one cascade down the whole page — restarting it per day makes the second morning arrive at the same instant as the first evening.
                let dayOffset = stops.prefix { $0.dayID != day.id }.count

                ForEach(Array(dayStops.enumerated()), id: \.element.id) { index, stop in
                    stopRow(
                        stop,
                        number: index + 1,
                        next: index + 1 < dayStops.count ? dayStops[index + 1] : nil,
                        revealIndex: dayOffset + index
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

    /// One stop: the clock in the gutter, a node on the spine, the card, and — when there is dead time before the next stop — the gap named beneath it.
    ///
    /// Every row draws its connector, including the last: the spine is terminated by the closing cap rather than by running out of stops. A final segment that simply stops short leaves the checkmark below it reading as a stray mark rather than the end of a line.
    private func stopRow(
        _ stop: ScheduleBlock,
        number: Int,
        next: ScheduleBlock?,
        revealIndex: Int
    ) -> some View {
        let gap = next.map { $0.startMinute - stop.endMinute } ?? 0
        let accent = Wandr.accent(for: stop.category)

        return HStack(alignment: .top, spacing: Self.rowSpacing) {
            clockGutter(stop)

            spine(accent: accent, drawsConnector: true)

            VStack(alignment: .leading, spacing: 0) {
                stopCard(stop, number: number, accent: accent)

                if let next, gap > 0 {
                    gapNote(minutes: gap, arriving: next)
                } else {
                    // Back to back, or the last stop running into the closing cap — either way the spine still needs breathing room to travel through.
                    Color.clear.frame(height: 22)
                }
            }
        }
        // Each stop arrives just after the one above it, so the eye is walked down the spine in the order the night happens. The slight scale is what makes a row *arrive* rather than merely fade up in place.
        .opacity(revealed ? 1 : 0)
        .offset(y: revealed ? 0 : 14)
        .scaleEffect(revealed ? 1 : 0.98, anchor: .topLeading)
        .animation(
            reduceMotion ? nil : .wandrTransition.delay(Double(revealIndex) * 0.06),
            value: revealed
        )
    }

    /// The clock, hung on the right edge of the gutter so every stop's time aligns into a single column running down the page.
    ///
    /// The meridiem deliberately skips `wandrLabelStyle`. That treatment adds letter tracking, which is applied *after* the final glyph as well as between glyphs — so a right-aligned label carries an invisible trailing space and sits a hair left of the clock above it. Everywhere else that is imperceptible; in a two-line stack whose entire job is to line up, it is the misalignment.
    private func clockGutter(_ stop: ScheduleBlock) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(hourMinute(stop.startMinute))
                .font(.wandrClock(17))
                .monospacedDigit()
                .foregroundStyle(Wandr.primaryText)
                .frame(maxWidth: .infinity, alignment: .trailing)

            Text(meridiem(stop.startMinute).uppercased())
                .font(.wandrLabel)
                .foregroundStyle(Wandr.secondaryText)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(width: Self.clockGutter, alignment: .trailing)
        // The card carries the spoken time; this is the same fact, set twice.
        .accessibilityHidden(true)
    }

    /// The through-line. A filled node per stop, dashed between them, so the night reads as one continuous thing rather than a list of four cards.
    private func spine(accent: Color, drawsConnector: Bool) -> some View {
        VStack(spacing: 5) {
            Circle()
                .fill(accent)
                .frame(width: Self.spineWidth, height: Self.spineWidth)
                .padding(.top, 17)

            if drawsConnector {
                VerticalRule()
                    .stroke(Wandr.mist,
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 5]))
                    .frame(width: 1.5)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(width: Self.spineWidth)
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

                // One line, always. Wrapped onto two it stops reading as a caption under the venue and starts reading as a second fact about it.
                Text("\(timeRange(stop.startMinute, stop.endMinute)) · \(duration(stop.durationMinutes))")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Wandr.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
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
        .shadow(color: Wandr.charcoal.opacity(0.05), radius: 5, x: 0, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Stop \(number), \(stop.title), \(stop.category.title)")
        .accessibilityValue("\(stop.startLabel) to \(stop.endLabel)")
    }

    /// Unplanned time, stated. Left as blank space it reads as a layout gap; named, it reads as room in the evening.
    private func gapNote(minutes: Int, arriving: ScheduleBlock) -> some View {
        Text("\(duration(minutes)) free · then \(arriving.title)")
            .font(.caption)
            .foregroundStyle(Wandr.secondaryText)
            .padding(.vertical, 11)
            .padding(.leading, 2)
            .accessibilityLabel("\(duration(minutes)) free before \(arriving.title)")
    }

    // MARK: Closing

    /// A terminal cap on the spine. Without it the last dashed segment stops in mid-air and the plan reads as truncated rather than finished.
    ///
    /// Built from the same three measurements as `stopRow`, so its text starts on exactly the same vertical as the stop cards above it. It previously carried its own leading padding on top of a node wider than the axis it sat on, which pushed the line right of the column it was supposed to close.
    private var closing: some View {
        HStack(alignment: .center, spacing: Self.rowSpacing) {
            Color.clear.frame(width: Self.clockGutter, height: 1)

            // Larger than a spine node — it is a cap, not another stop — but still centred on the axis, and small enough that its overflow stays inside the row's gap.
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Wandr.cream)
                .frame(width: 16, height: 16)
                .background { Circle().fill(Wandr.brand) }
                .frame(width: Self.spineWidth)

            Text(stops.map(\.endMinute).max().map { "Night ends \(ScheduleBlock.clock($0))" } ?? "")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Wandr.secondaryText)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metrics.gutter)
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
                .tint(Wandr.brand)

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

    /// Bare clock for the ledger, where two of them sit side by side and the full "10:00 pm" twice over is more punctuation than information.
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
