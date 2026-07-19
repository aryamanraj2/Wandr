//
//  ShortcutSetupView.swift
//  Wandr
//
//  First-launch onboarding (Docs/AI-Integration-Blueprint.md Phase 1): walk the host
//  through installing the distributable Wandr chat-import Shortcut once. The Shortcut
//  chains the messaging app's own message access → `Use Model` (Wandr's extraction
//  prompt) → this app's intent, so Wandr's code never touches the transcript.
//

import SwiftUI
import AppIntents
import UIKit

struct ShortcutSetupView: View {
    let inbox: IntakeInbox

    /// The hosted iCloud link to the distributable `.shortcut`. A `.shortcut` cannot be
    /// authored in code — build it in the Shortcuts app and paste its iCloud share link here.
    // TODO: replace with the real iCloud Shortcut link before distribution / demo.
    private static let shortcutURL = URL(string: "https://www.icloud.com/shortcuts/645bdedbff07494dbd6217352be565c8")

    @State private var didCopyPrompt = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header

                step(1, "Install the Wandr shortcut",
                     "Adds a one-tap “summarize this chat and plan it” recipe to your Shortcuts.") {
                    installButtons
                }

                step(2, "Give it Wandr’s prompt",
                     "Open the shortcut’s Use Model step and paste this in, so the summary comes back in the shape Wandr expects.") {
                    promptCard
                }

                step(3, "Try it with Siri",
                     "Once installed, you can also just ask Siri — no shortcut tap needed.") {
                    SiriTipView(intent: PlanOutingFromSiriSummaryIntent())
                        .siriTipViewStyle(.automatic)
                }

                Color.clear.frame(height: 12)
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 12)
        }
        .background(Wandr.pageBackground)
        .safeAreaBar(edge: .bottom) {
            Button {
                inbox.completeShortcutSetup()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .tint(Wandr.ink)
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 8)
        }
        .tint(Wandr.ink)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Set up chat import")
                .font(.wandrDisplay(36))
                .foregroundStyle(Wandr.primaryText)

            Text("One-time setup. After this, a summary of any group chat is one Siri phrase away — and Wandr still never reads the chat itself.")
                .font(.body)
                .foregroundStyle(Wandr.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Step scaffold

    private func step<Content: View>(
        _ number: Int,
        _ title: String,
        _ subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(number)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Wandr.cardSurface)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Wandr.ink))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.wandrTitle(19))
                        .foregroundStyle(Wandr.primaryText)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Wandr.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content()
                .padding(.leading, 42)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Step 1 — install

    private var installButtons: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let url = Self.shortcutURL {
                Link(destination: url) {
                    Label("Get the Wandr shortcut", systemImage: "square.and.arrow.down")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(Wandr.ink)
            }

            ShortcutsLink()
                .shortcutsLinkStyle(.automatic)
        }
    }

    // MARK: Step 2 — prompt

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(ChatExtractionPrompt.text)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Wandr.primaryText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                UIPasteboard.general.string = ChatExtractionPrompt.text
                withAnimation(.wandrResponse) { didCopyPrompt = true }
            } label: {
                Label(didCopyPrompt ? "Copied" : "Copy prompt",
                      systemImage: didCopyPrompt ? "checkmark" : "doc.on.doc")
                    .font(.subheadline.weight(.semibold))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.glass)
            .tint(Wandr.ink)
        }
        .padding(16)
        .background(WandrCardBackground())
    }
}

#Preview {
    ShortcutSetupView(inbox: IntakeInbox())
}
