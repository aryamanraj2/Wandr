// ScheduleView.swift Wandr The second surface: the plan laid out against real time. The date bar shows only the days the itinerary actually spans — one day renders as a single pill, three days as three. It is never a full calendar.

import SwiftUI

struct ScheduleView: View {

    /// Stops handed over from curation. Falls back to the demo day when empty.
    init(stops: [ScheduleBlock] = []) {
        let day = DemoPlan.days[0]
        _blocks = State(initialValue: stops.isEmpty ? DemoPlan.blocks(for: day) : stops)
    }

    @State private var blocks: [ScheduleBlock]
    @State private var selectedDay: PlanDay.ID = DemoPlan.days[0].id
    @State private var liftedID: ScheduleBlock.ID?

    /// The finished plan, presented over the timeline. This is where the flow ends — the schedule is the working surface, the summary is the document.
    @State private var showSummary = false

    @Environment(\.dismiss) private var dismiss

    /// Only the days the itinerary actually has stops on. A day with nothing planned is not a date the user needs to see.
    private var days: [PlanDay] {
        let plannedIDs = Set(blocks.map(\.dayID))
        return DemoPlan.days.filter { plannedIDs.contains($0.id) }
    }

    /// The visible span of the selected day, in minutes from midnight — derived from the stops actually on it rather than fixed to an evening. See `DaySpan`.
    private var dayRange: ClosedRange<Int> {
        DaySpan.covering(blocks.filter { $0.dayID == selectedDay })
    }

    private var timelineHeight: CGFloat {
        CGFloat(dayRange.upperBound - dayRange.lowerBound) * Metrics.pointsPerMinute
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    masthead
                    if days.count > 1 { dateBar }
                    timeline
                }
            }
            // A lifted block is being directly manipulated — the scroll view must not steal the gesture out from under it.
            .scrollDisabled(liftedID != nil)
            .background(Wandr.pageBackground)
            .scrollEdgeEffectStyle(.soft, for: .top)
            // Stops handed in may not land on the demo's first day.
            .onAppear {
                if let first = days.first, !days.contains(where: { $0.id == selectedDay }) {
                    selectedDay = first.id
                }
            }
            .overlay(alignment: .bottomTrailing) { sendButton }
            .sheet(isPresented: $showSummary) {
                ItinerarySummaryView(blocks: blocks)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        }
        .tint(Wandr.brand)
    }

    // MARK: Masthead

    private var masthead: some View {
        HStack(alignment: .center) {
            // Italic serif display — the editorial voice, and the one place the app allows itself a flourish.
            Text("Schedule")
                .font(.wandrDisplay(46))
                .italic()
                .foregroundStyle(Wandr.primaryText)

            Spacer()
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 4)
        .padding(.bottom, 22)
    }

    // MARK: Controls

    /// Floats over the timeline rather than living in the toolbar — finishing the plan is the one thing you can do from anywhere in the scroll.
    private var sendButton: some View {
        Button {
            showSummary = true
        } label: {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Wandr.cream)
                // Nudged to sit optically centred — the glyph leans up-right.
                .offset(x: -1, y: 1)
                .frame(width: 58, height: 58)
                .background {
                    Circle().fill(Wandr.brand)
                }
                .shadow(color: Wandr.brand.opacity(0.30), radius: 16, x: 0, y: 8)
        }
        .buttonStyle(WandrPressStyle())
        .padding(.trailing, Metrics.gutter)
        .padding(.bottom, 28)
        .accessibilityLabel("Send to squad")
    }

    // MARK: Date bar

    private var dateBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(days) { day in
                    dayPill(day)
                }
            }
            .padding(.horizontal, Metrics.gutter)
        }
        .scrollIndicators(.hidden)
        .padding(.bottom, 26)
    }

    private func dayPill(_ day: PlanDay) -> some View {
        let selected = day.id == selectedDay
        let stopCount = blocks.filter { $0.dayID == day.id }.count

        return Button {
            withAnimation(.wandrTransition) { selectedDay = day.id }
        } label: {
            VStack(spacing: 5) {
                Text(day.weekday)
                    .wandrLabelStyle(selected ? Wandr.cream.opacity(0.7) : Wandr.secondaryText)

                Text(day.dayNumber)
                    .font(.wandrTitle(26))
                    .monospacedDigit()
                    .foregroundStyle(selected ? Wandr.cream : Wandr.primaryText)

                Circle()
                    .fill(selected ? Wandr.cream.opacity(0.8) : Wandr.mist)
                    .frame(width: 4, height: 4)
                    .opacity(stopCount > 0 ? 1 : 0)
            }
            .frame(width: 82, height: 92)
            .background {
                RoundedRectangle(cornerRadius: 20)
                    .fill(selected ? Wandr.brand : Wandr.mist.opacity(0.35))
            }
        }
        .buttonStyle(WandrPressStyle())
        .accessibilityLabel("\(day.weekday) \(day.dayNumber)")
        .accessibilityValue(stopCount == 1 ? "1 stop" : "\(stopCount) stops")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Timeline

    // The timeline's one grid. The clock column and the track have to agree on where the hour starts, or the ruler a block is dragged against is not the ruler it is drawn against.

    /// The clock column, wide enough for the longest label the ruler can produce ("12 am").
    private static let clockColumn: CGFloat = 44
    private static let clockSpacing: CGFloat = 10

    /// Where the hour begins: everything right of this is plan, everything left of it is the ruler measuring it.
    private static var trackInset: CGFloat { clockColumn + clockSpacing }

    private var timeline: some View {
        ZStack(alignment: .topLeading) {
            hourRules

            ForEach($blocks) { $block in
                if block.dayID == selectedDay {
                    TimelineBlockView(
                        block: $block,
                        liftedID: $liftedID,
                        dayRange: dayRange
                    )
                    .padding(.leading, Self.trackInset)
                    .padding(.trailing, Metrics.gutter)
                    .offset(y: yPosition(for: block.startMinute))
                }
            }
        }
        .frame(height: timelineHeight, alignment: .top)
        .padding(.bottom, 60)
        .animation(.wandrTransition, value: selectedDay)
        // The span follows the stops, so committing a stop outside it grows the day. Animated, that reads as the ruler making room; unanimated it is a jump.
        .animation(.wandrTransition, value: dayRange)
    }

    /// Hour gridlines and the left-hand clock gutter. Deliberately quiet — this is the ruler the content is measured against, not content itself. The dashes only exist while a block is in the air: at rest the plan should read as a finished itinerary, not as something sitting on graph paper, and a ruler is only worth drawing at the moment something is being measured against it. The clock gutter stays either way, since the times are what anchor the plan.
    private var hourRules: some View {
        let firstHour = dayRange.lowerBound / 60
        let lastHour = dayRange.upperBound / 60
        let measuring = liftedID != nil

        return ForEach(firstHour...lastHour, id: \.self) { hour in
            HStack(spacing: Self.clockSpacing) {
                Text(hourLabel(hour))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Wandr.secondaryText.opacity(0.75))
                    .frame(width: Self.clockColumn, alignment: .trailing)

                // Dashed, so the ruler reads as a guide rather than a divider.
                Line()
                    .stroke(Wandr.mist.opacity(0.85),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round,
                                               dash: [5, 6]))
                    .frame(height: 1.5)
                    .opacity(measuring ? 1 : 0)
                    // Drawing in from the clock gutter outward makes the grid feel like it is being laid down, not switched on.
                    .scaleEffect(x: measuring ? 1 : 0.9, anchor: .leading)
                    .animation(
                        .wandrTransition.delay(Double(hour - firstHour) * 0.012),
                        value: measuring
                    )
            }
            .padding(.trailing, Metrics.gutter)
            // Collapsed to nothing so the row's *centre* is the hour, not its top edge. Offsetting the row as-is hangs it below the line by half a line of type, which puts the ruler and the blocks — whose tops sit exactly on the minute — a few points out of register with each other: a stop at 8:00 draws just above the 8 am rule it is supposed to start on.
            .frame(height: 0)
            .offset(y: yPosition(for: hour * 60))
            .accessibilityHidden(true)
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        let h24 = hour % 24
        let suffix = h24 < 12 ? "am" : "pm"
        var h = h24 % 12
        if h == 0 { h = 12 }
        return "\(h) \(suffix)"
    }

    private func yPosition(for minute: Int) -> CGFloat {
        CGFloat(minute - dayRange.lowerBound) * Metrics.pointsPerMinute
    }
}

/// A single horizontal rule, so it can carry a dash pattern.
private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

#Preview {
    ScheduleView()
}
