//
//  RootView.swift
//  Wandr
//
//  Outings-only shell (D3 — no Trips tab in v1).
//
//  Once `TravelPlanningService` lands, this view switches on `PlanningRun.state`
//  (awaitingSiriSummary → hostReview → … → curating → approving). For the design
//  pass it opens straight onto curation, which is where the plan becomes visible.
//

import SwiftUI

struct RootView: View {
    var body: some View {
        CurationView()
    }
}

#Preview("Curation") {
    RootView()
}

#Preview("Schedule") {
    ScheduleView()
}
