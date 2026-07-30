
import SwiftUI

@main
struct WandrApp: App {
    init() {
        #if DEBUG
        // UI-testing hook: seed the intake inbox with a summary at launch, mimicking a Siri/Shortcut handoff, e.g. xcrun simctl launch <dev> aryaman.Wandr WANDR_SEED_SUMMARY='{"area":"CP"}'
        if let seed = ProcessInfo.processInfo.environment["WANDR_SEED_SUMMARY"], !seed.isEmpty {
            MainActor.assumeIsolated {
                IntakeInbox.shared.receive(rawText: seed)
            }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            rootContent
                // Wandr is light-mode only. The palette is a light cyan field with charcoal and
                // indigo used as accents on top of it — there is no dark counterpart to fall back
                // to, so the scheme is pinned rather than left to adapt into something unpainted.
                .preferredColorScheme(.light)
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        #if DEBUG
        if let screen = DebugScreen.requested {
            screen.view
        } else {
            RootView()
        }
        #else
        RootView()
        #endif
    }
}
