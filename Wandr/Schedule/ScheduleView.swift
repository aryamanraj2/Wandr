//
//  ScheduleView.swift
//  Wandr
//
//  The second surface: the plan laid out against real time.
//  The date bar shows only the days the itinerary actually spans — one day
//  renders as a single pill, three days as three. It is never a full calendar.
//

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

    /// The plan reads as finished until you say otherwise. Editing is a mode you
    /// opt into, and the dashed ruler is the signal that you are in it.
    @State private var isEditing = false

    /// The finished plan, presented over the timeline. This is where the flow
    /// ends — the schedule is the working surface, the summary is the document.
    @State private var showSummary = false

    @Environment(\.dismiss) private var dismiss

    /// Only the days the itinerary actually has stops on. A day with nothing
    /// planned is not a date the user needs to see.
    private var days: [PlanDay] {
        let plannedIDs = Set(blocks.map(\.dayID))
        return DemoPlan.days.filter { plannedIDs.contains($0.id) }
    }

    /// The visible span of the day, in minutes from midnight.
    private let dayRange = (9 * 60)...(24 * 60)

    private var timelineHeight: CGFloat {
        CGFloat(dayRange.upperBound - dayRange.lowerBound) * Metrics.pointsPerMinute
    }

    private var visibleBlocks: [ScheduleBlock] {
        blocks.filter { $0.dayID == selectedDay }.sorted { $0.startMinute < $1.startMinute }
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
            // A lifted block is being directly manipulated — the scroll view must
            // not steal the gesture out from under it.
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
                ToolbarItem(placement: .confirmationAction) {
                    editToggle
                }
            }
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            // The one cue that the plan just became malleable.
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.5),
                             trigger: isEditing)
        }
        .tint(Wandr.ink)
    }

    // MARK: Masthead

    private var masthead: some View {
        HStack(alignment: .center) {
            // Italic serif display — the editorial voice, and the one place
            // the app allows itself a flourish.
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

    /// Mirrors the close button across the header — same disc, opposite corner.
    /// Filled ink when active, so the mode is legible at a glance.
    private var editToggle: some View {
        Button {
            withAnimation(.wandrTransition) { isEditing.toggle() }
        } label: {
            Image(systemName: "scribble")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Wandr.cream)
                .frame(width: 34, height: 34)
                .background {
                    Circle().fill(isEditing ? Wandr.slate : Wandr.ink)
                }
        }
        .buttonStyle(WandrPressStyle())
        .accessibilityLabel("Edit plan")
        .accessibilityValue(isEditing ? "On" : "Off")
        .accessibilityHint("Adjust stop times")
    }

    /// Floats over the timeline rather than living in the toolbar — finishing the
    /// plan is the one thing you can do from anywhere in the scroll.
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
                    Circle().fill(Wandr.ink)
                }
                .shadow(color: Wandr.ink.opacity(0.28), radius: 16, x: 0, y: 8)
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
                    .fill(selected ? Wandr.cream.opacity(0.8) : Wandr.sand)
                    .frame(width: 4, height: 4)
                    .opacity(stopCount > 0 ? 1 : 0)
            }
            .frame(width: 82, height: 92)
            .background {
                RoundedRectangle(cornerRadius: 20)
                    .fill(selected ? Wandr.ink : Wandr.sand.opacity(0.35))
            }
        }
        .buttonStyle(WandrPressStyle())
        .accessibilityLabel("\(day.weekday) \(day.dayNumber)")
        .accessibilityValue(stopCount == 1 ? "1 stop" : "\(stopCount) stops")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Timeline

    private var timeline: some View {
        ZStack(alignment: .topLeading) {
            hourRules

            ForEach($blocks) { $block in
                if block.dayID == selectedDay {
                    TimelineBlockView(
                        block: $block,
                        liftedID: $liftedID,
                        dayRange: dayRange,
                        isEditing: isEditing
                    )
                    .padding(.leading, 62)
                    .padding(.trailing, Metrics.gutter)
                    .offset(y: yPosition(for: block.startMinute))
                }
            }
        }
        .frame(height: timelineHeight, alignment: .top)
        .padding(.bottom, 60)
        .animation(.wandrTransition, value: selectedDay)
    }

    /// Hour gridlines and the left-hand clock gutter. Deliberately quiet —
    /// this is the ruler the content is measured against, not content itself.
    ///
    /// The dashes only exist in edit mode: at rest the plan should read as a
    /// finished itinerary, not as something sitting on graph paper. The clock
    /// gutter stays either way, since the times are what anchor the plan.
    private var hourRules: some View {
        let firstHour = dayRange.lowerBound / 60
        let lastHour = dayRange.upperBound / 60

        return ForEach(firstHour..<lastHour, id: \.self) { hour in
            HStack(spacing: 10) {
                Text(hourLabel(hour))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Wandr.secondaryText.opacity(0.75))
                    .frame(width: 44, alignment: .trailing)

                // Dashed, so the ruler reads as a guide rather than a divider.
                Line()
                    .stroke(Wandr.sand.opacity(0.85),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round,
                                               dash: [5, 6]))
                    .frame(height: 1.5)
                    .opacity(isEditing ? 1 : 0)
                    // Drawing in from the clock gutter outward makes the grid
                    // feel like it is being laid down, not switched on.
                    .scaleEffect(x: isEditing ? 1 : 0.9, anchor: .leading)
                    .animation(
                        .wandrTransition.delay(Double(hour - firstHour) * 0.012),
                        value: isEditing
                    )
            }
            .padding(.trailing, Metrics.gutter)
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
