// ShortcutSetupView.swift Wandr First-launch onboarding (Docs/AI-Integration-Blueprint.md Phase 1): walk the host through installing the distributable Wandr chat-import Shortcut once. The Shortcut chains the messaging app's own message access → `Use Model` (Wandr's extraction prompt) → this app's intent, so Wandr's code never touches the transcript.

import SwiftUI
import AppIntents
import UIKit

struct ShortcutSetupView: View {
    let inbox: IntakeInbox

    /// The hosted iCloud link to the distributable `.shortcut`. A `.shortcut` cannot be authored in code — build it in the Shortcuts app and paste its iCloud share link here.
    // TODO: replace with the real iCloud Shortcut link before distribution / demo.
    private static let shortcutURL = URL(string: "https://www.icloud.com/shortcuts/645bdedbff07494dbd6217352be565c8")

    @State private var didCopyPrompt = false
    @State private var arrived = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, 26)
                    .entrance(arrived, index: 0, reduceMotion: reduceMotion)

                step(1, "Install the Wandr shortcut",
                     "Adds a one-tap “summarize this chat and plan it” recipe to your Shortcuts.") {
                    installButtons
                }
                .entrance(arrived, index: 1, reduceMotion: reduceMotion)

                step(2, "Give it Wandr’s prompt",
                     "Open the shortcut’s Use Model step and paste this in, so the summary comes back in the shape Wandr expects.") {
                    promptStep
                }
                .entrance(arrived, index: 2, reduceMotion: reduceMotion)

                step(3, "Try it with Siri",
                     "Once installed, you can also just ask Siri — no shortcut tap needed.",
                     isLast: true) {
                    SiriTipView(intent: PlanOutingFromSiriSummaryIntent())
                        .siriTipViewStyle(.automatic)
                }
                .entrance(arrived, index: 3, reduceMotion: reduceMotion)
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
        .background(Wandr.pageBackground)
        .safeAreaBar(edge: .bottom) {
            actions
        }
        .tint(Wandr.brand)
        // Onboarding is seen once, which is the whole licence for an entrance here. The stagger
        // follows reading order so the three steps arrive as a sequence rather than a block.
        .onAppear { arrived = true }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Set up chat import")
                .font(.wandrDisplay(34))
                .foregroundStyle(Wandr.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text("One-time setup. After this, a summary of any group chat is one Siri phrase away — and Wandr still never reads the chat itself.")
                .font(.body)
                .foregroundStyle(Wandr.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Step scaffold

    /// The numbers are joined by a rail. Three separately floating numbered blocks read as three
    /// unrelated cards you could do in any order; a connecting line says "first, then, then", which
    /// is the one thing this screen has to communicate before any of its content matters.
    private func step<Content: View>(
        _ number: Int,
        _ title: String,
        _ subtitle: String,
        isLast: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 6) {
                Text("\(number)")
                    .font(.footnote.weight(.bold).monospacedDigit())
                    .foregroundStyle(Wandr.onBrand)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Wandr.brand))

                if !isLast {
                    Rectangle()
                        .fill(Wandr.hairline)
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                }
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.wandrTitle(19))
                        .foregroundStyle(Wandr.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Wandr.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                content()
            }
            // The number sits a hair below the cap height of the title beside it; without this the
            // circle reads as floating above the line it labels.
            .padding(.top, 1)
            .padding(.bottom, isLast ? 0 : 26)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Step \(number). \(title)")
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
                .tint(Wandr.brand)
            }

            ShortcutsLink()
                .shortcutsLinkStyle(.automatic)
        }
    }

    // MARK: Step 2 — prompt

    /// The prompt used to be printed in full, inline, in monospace — several hundred characters of
    /// text nobody needs to read, sitting in the middle of a three-step page and dwarfing the two
    /// steps around it. Nothing about the task requires reading it: you copy it and paste it. So
    /// copying is the visible action and the text itself folds away behind it, still selectable for
    /// anyone who does want to check what they are pasting.
    private var promptStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                UIPasteboard.general.string = ChatExtractionPrompt.text
                withAnimation(.wandrResponse) { didCopyPrompt = true }
            } label: {
                Label(didCopyPrompt ? "Copied to clipboard" : "Copy Wandr’s prompt",
                      systemImage: didCopyPrompt ? "checkmark" : "doc.on.doc")
                    .font(.subheadline.weight(.semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(didCopyPrompt ? Wandr.accent(for: .discover) : Wandr.brand)
            .sensoryFeedback(.success, trigger: didCopyPrompt)

            WandrFoldout(title: "See what it says", systemImage: "text.alignleft") {
                Text(ChatExtractionPrompt.text)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Wandr.secondaryText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 6) {
            Button {
                inbox.completeShortcutSetup()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(Wandr.brand)

            // Installing a Shortcut is a real barrier on first launch, and it is not the only way
            // in. A host who just wants to plan something can skip all of this and say it out loud.
            Button("Skip — just tell Wandr") {
                inbox.beginCapture()
            }
            .font(.subheadline.weight(.medium))
            .buttonStyle(.plain)
            .foregroundStyle(Wandr.brand)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.bottom, 4)
    }
}

// MARK: - Entrance

private extension View {
    /// Modest scale plus opacity, never from zero: a block that grows out of nothing has no
    /// physical form to read on the way in. Reduce Motion gets the arrival with no travel.
    func entrance(_ arrived: Bool, index: Int, reduceMotion: Bool) -> some View {
        opacity(arrived ? 1 : 0)
            .scaleEffect(arrived || reduceMotion ? 1 : 0.97, anchor: .leading)
            .offset(y: arrived || reduceMotion ? 0 : 10)
            .animation(reduceMotion ? .easeOut(duration: 0.2) : .wandrEnter(index), value: arrived)
    }
}

#Preview {
    ShortcutSetupView(inbox: IntakeInbox())
}
