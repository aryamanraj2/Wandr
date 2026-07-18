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
        case curating(brief: String)
    }

    @State private var stage: Stage = .capture

    var body: some View {
        ZStack {
            switch stage {
            case .capture:
                PlanCaptureView { brief in
                    withAnimation(.wandrTransition) {
                        stage = .curating(brief: brief)
                    }
                }
                // Forward and back use opposing directions, so the plan reads
                // as something you handed over rather than a screen swap.
                .transition(.asymmetric(
                    insertion: .opacity,
                    removal: .opacity.combined(with: .scale(scale: 0.97))
                ))

            case .curating:
                CurationView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
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
