//
//  RootView.swift
//  Wandr
//
//  Outings-only shell (D3 — no Trips tab in v1).
//
//  Once `TravelPlanningService` lands, this view switches on `PlanningRun.state`
//  (awaitingSiriSummary → hostReview → … → curating → approving). For now it
//  models the two ends of that arc that exist: the host states the plan, then
//  picks from what came back.
//

import SwiftUI

struct RootView: View {

    private enum Stage: Equatable {
        case capture
        case curating
    }

    @State private var stage: Stage = .capture

    /// The interim doorway (§12.1): submitted text becomes a live run through the
    /// real pipeline. Nothing about the host's words is retained here — the harness
    /// puts them into a `PlanningInput` and holds only a status.
    @State private var harness = LivePlanningHarness()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var curating: Bool { stage == .curating }

    var body: some View {
        // Both stages stay mounted and cross-dissolve. Inserting a stage
        // instead — the obvious `switch` — makes its chrome pop: a
        // NavigationStack's bar and a `safeAreaBar` are laid out by UIKit on
        // the first frame, at full opacity, before any SwiftUI transition on
        // the content has moved. That is the header-then-footer flash. Nothing
        // is constructed mid-animation here, so there is nothing to pop.
        ZStack {
            // Both screens sit on the same field, so the dissolve never shows
            // a seam between two backgrounds of the same colour.
            Wandr.pageBackground
                .ignoresSafeArea()

            // The bridge: a ready run's validated plan is what the curation
            // screen draws. Before a plan exists the stage is invisible and
            // empty — DemoPlan is a preview fixture, not a live fallback.
            // Re-keying on the plan ID resets the deck state (cursor,
            // shortlist) whenever a new plan arrives.
            CurationView(decks: liveDecks)
                .id(harness.readyPlan?.id)
                .opacity(curating ? 1 : 0)
                // Settling the last hair of scale, rather than sliding in:
                // the plan was already on its way, this is it arriving.
                .scaleEffect(reduceMotion ? 1 : (curating ? 1 : 1.015))
                .stageParticipant(active: curating)
                .animation(stageAnimation(appearing: curating), value: stage)

            PlanCaptureView { spoken in
                // The submit path is now the live entry point (§12.1). The text goes
                // straight into the harness's `PlanningInput` and nowhere else.
                harness.start(text: spoken)
            }
            .opacity(curating ? 0 : 1)
            .scaleEffect(reduceMotion ? 1 : (curating ? 0.985 : 1))
            .stageParticipant(active: !curating)
            .animation(stageAnimation(appearing: !curating), value: stage)

            // In-flight status while the real pipeline runs. Minimal by design.
            if isRunning {
                runningOverlay
                    .transition(.opacity)
            }
        }
        .animation(.wandrResponse, value: isRunning)
        // A ready run raises the curation screen, now drawing the live plan.
        .onChange(of: harness.status) { _, status in
            if status == .ready { stage = .curating }
        }
        // On failure, the already-authored userMessage — which itself coaches the
        // retry action ("Turn on Apple Intelligence…", "Try again in a few minutes…")
        // — as a minimal alert. Not a redesign.
        .alert(
            "We couldn't finish this plan",
            isPresented: failureAlertPresented,
            presenting: failureMessage
        ) { _ in
            Button("OK") { harness.reset() }
        } message: { message in
            Text(message)
        }
    }

    // MARK: - Live run surfacing

    /// The validated plan mapped for the curation screen. Empty until a run is
    /// ready — never `DemoPlan`, which exists only for previews.
    private var liveDecks: [Deck] {
        guard let plan = harness.readyPlan else { return [] }
        return PlanPresentation.decks(from: plan)
    }

    private var isRunning: Bool {
        if case .running = harness.status { return true }
        return false
    }

    private var failureMessage: String? {
        if case .failed(let message, _) = harness.status { return message }
        return nil
    }

    private var failureAlertPresented: Binding<Bool> {
        Binding(
            get: { if case .failed = harness.status { return true } else { return false } },
            set: { presented in if !presented { harness.reset() } }
        )
    }

    private var runningOverlay: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                Text("Planning your outing…")
                    .font(.subheadline)
                    .foregroundStyle(Wandr.secondaryText)
                Button("Cancel") { harness.cancel() }
                    .buttonStyle(.bordered)
            }
            .padding(28)
            .background(.regularMaterial, in: .rect(cornerRadius: 20))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Planning your outing")
    }

    /// Whichever screen is arriving waits for the other to clear; whichever is
    /// leaving goes immediately. Reads as a handoff in one direction rather
    /// than a symmetric crossfade, and reverses cleanly when the stage does.
    private func stageAnimation(appearing: Bool) -> Animation {
        appearing ? .wandrStageIn : .wandrStageOut
    }
}

private extension View {
    /// A stage that is dissolved out is still in the hierarchy, so it has to be
    /// taken out of the touch and accessibility trees explicitly — otherwise an
    /// invisible screen keeps swallowing taps and reading itself to VoiceOver.
    func stageParticipant(active: Bool) -> some View {
        self
            .allowsHitTesting(active)
            .accessibilityHidden(!active)
    }
}

#Preview("Capture") {
    RootView()
}

#Preview("Curation") {
    CurationView()
}

#Preview("Schedule") {
    ScheduleView()
}
