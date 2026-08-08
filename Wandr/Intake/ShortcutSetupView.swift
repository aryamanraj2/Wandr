// ShortcutSetupView.swift Wandr First-launch onboarding (Docs/AI-Integration-Blueprint.md Phase 1): walk the host through installing the distributable Wandr chat-import Shortcut once. The Shortcut chains the messaging app's own message access → `Use Model` (Wandr's extraction prompt) → this app's intent, so Wandr's code never touches the transcript.

import SwiftUI
import AppIntents
import UIKit

/// The page carries exactly one filled button — "Done".
///
/// It used to carry four, stacked down its length: get the shortcut, copy the prompt, done, plus the
/// system Shortcuts chip in black. Four full-width slabs in the same tone say four equally urgent
/// things, which is the same as saying nothing, and it is most of why a three-step page read as a
/// form. The steps' own actions are glass now; the only solid control is the one that leaves.
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
        WandrMasthead(
            title: "Set up chat import",
            deck: "One-time setup. After this, a summary of any group chat is one Siri phrase away — and Wandr still never reads the chat itself.",
            // A hair off the default poster size. At 46 this particular string breaks after "chat"
            // and leaves "import" alone on a line, which reads as a title that ran out of room.
            size: 40
        )
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
                // A ring rather than a filled disc. Three solid indigo circles running down the left
                // edge of a page that also had three solid indigo buttons on it made the whole
                // screen one colour with holes in it; drawn, the numbers stay legible as structure
                // and stop competing with the things that are actually pressable.
                Text("\(number)")
                    .font(.footnote.weight(.bold).monospacedDigit())
                    .foregroundStyle(Wandr.brand)
                    .frame(width: 26, height: 26)
                    .background {
                        Circle().stroke(Wandr.brand.opacity(0.45), lineWidth: 1.5)
                    }

                if !isLast {
                    Rectangle()
                        .fill(Wandr.hairline)
                        .frame(width: 1)
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
                        .wandrActionLabel(.subheadline.weight(.semibold))
                }
                .wandrQuietAction()
            }

            // `.automatic` resolves to a filled black slab, which on a pale cyan page was the
            // single heaviest object on the screen — a strange amount of emphasis for "open the
            // Shortcuts app", sitting directly under the step's actual action. The outline variant
            // is the same control at the weight it deserves, and left-aligned at small size it reads
            // as the secondary route it is rather than a second call to action.
            ShortcutsLink()
                .shortcutsLinkStyle(.lightOutline)
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
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
                    .contentTransition(.symbolEffect(.replace))
                    .wandrActionLabel(.subheadline.weight(.semibold))
            }
            .wandrQuietAction()
            .tint(didCopyPrompt ? Wandr.accent(for: .discover) : Wandr.brand)
            .sensoryFeedback(.success, trigger: didCopyPrompt)

            WandrFoldout(title: "See what it says", image: .wandrClipboardText) {
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
                Text("Done").wandrActionLabel()
            }
            .wandrPrimaryAction()

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

#Preview {
    ShortcutSetupView(inbox: IntakeInbox())
}
