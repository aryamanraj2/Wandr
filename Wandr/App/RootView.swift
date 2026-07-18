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

    /// What the host said. Held here because it outlives the capture screen —
    /// curation is derived from it once there is a service to derive it with.
    @State private var brief = ""

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

            CurationView()
                .opacity(curating ? 1 : 0)
                // Settling the last hair of scale, rather than sliding in:
                // the plan was already on its way, this is it arriving.
                .scaleEffect(reduceMotion ? 1 : (curating ? 1 : 1.015))
                .stageParticipant(active: curating)
                .animation(stageAnimation(appearing: curating), value: stage)

            PlanCaptureView { spoken in
                brief = spoken
                stage = .curating
            }
            .opacity(curating ? 0 : 1)
            .scaleEffect(reduceMotion ? 1 : (curating ? 0.985 : 1))
            .stageParticipant(active: !curating)
            .animation(stageAnimation(appearing: !curating), value: stage)
        }
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
