//
//  WandrShortcuts.swift
//  Wandr
//
//  The app's single AppShortcutsProvider. Exposes the intake intent to Siri and
//  Spotlight with zero user setup, using the conversational phrases from
//  Docs/AI-Orchestration-Flow.md. This is the fallback channel; the primary channel
//  is the distributable Wandr Shortcut the host installs during onboarding.
//

import AppIntents

struct WandrShortcuts: AppShortcutsProvider {

    static var shortcutTileColor: ShortcutTileColor = .teal

    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlanOutingFromSiriSummaryIntent(),
            phrases: [
                "Plan this group outing in \(.applicationName)",
                "Use \(.applicationName) to plan this outing",
                "Plan our after-work plans in \(.applicationName)"
            ],
            shortTitle: "Plan Outing",
            systemImageName: "sparkles"
        )
    }
}
