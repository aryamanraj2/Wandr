//
//  WandrApp.swift
//  Wandr
//
//  Created by aryaman jaiswal on 18/07/26.
//

import SwiftUI

@main
struct WandrApp: App {
    init() {
        #if DEBUG
        // UI-testing hook: seed the intake inbox with a summary at launch, mimicking a
        // Siri/Shortcut handoff without needing the real intent. e.g.
        //   xcrun simctl launch <dev> aryaman.Wandr WANDR_SEED_SUMMARY='{"area":"CP"}'
        if let seed = ProcessInfo.processInfo.environment["WANDR_SEED_SUMMARY"], !seed.isEmpty {
            MainActor.assumeIsolated {
                IntakeInbox.shared.receive(rawText: seed)
            }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
