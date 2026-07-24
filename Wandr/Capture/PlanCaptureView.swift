//
//  PlanCaptureView.swift
//  Wandr
//
//  Step one of an outing: the host says what they want. Everything downstream
//  — research, decks, schedule — is derived from what lands here, so the
//  screen holds exactly one object and one sentence of instruction.
//
//  Two ways in, one buffer out. Speaking and typing edit the same text, so
//  switching between them mid-thought never costs you a word.
//

import SwiftUI

struct PlanCaptureView: View {

    /// Handed the finished brief. The caller moves on to curation.
    var onCommit: (String) -> Void

    /// Backs out without planning anything. Optional so previews and any caller that
    /// owns its own dismissal can leave it off — but `RootView` always supplies it,
    /// because this screen is a full-screen state rather than a sheet and there would
    /// otherwise be no way off it.
    var onCancel: (() -> Void)?

    @State private var dictation = PlanDictation()
    @State private var mode: OrbMode = .orb
    @FocusState private var composing: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hasPlan: Bool { !dictation.spokenPlan.isEmpty }

    /// Nothing to say when things are working — the orb already says it.
    /// Failures still need words, though, or a dead mic looks like a dead app.
    private var failure: String? {
        if case .failed(let reason) = dictation.phase { return reason }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            masthead

            // Typing anchors the field high on the page instead of centring
            // it. Nothing then depends on keyboard avoidance moving the
            // layout — the field is simply never where the keyboard goes.
            if mode == .composer {
                Spacer().frame(height: 32)
            } else {
                Spacer(minLength: 24)
            }

            orb
                .padding(.horizontal, mode == .composer ? 0 : Metrics.gutter)
                // The bloom no longer reserves space, so the orb gets its
                // breathing room explicitly. Composer mode wants none of it:
                // the controls belong directly under the field.
                .padding(.vertical, mode == .composer ? 0 : 40)

            // While typing, the controls ride directly under the field rather
            // than at the screen's bottom edge. The keyboard does not shrink
            // the safe area here, so anything anchored to the bottom ends up
            // underneath it — this puts them somewhere it cannot reach.
            if mode == .composer {
                footer
                    .padding(.top, 20)
            }

            transcriptWell

            Spacer(minLength: 24)
        }
        .padding(.horizontal, Metrics.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Applied outside the sized frame, matching the pattern that already
        // works in CurationView. Inside it, the bar was being laid out against
        // the content's own box rather than the screen's bottom edge.
        .safeAreaInset(edge: .bottom) {
            // Bottom bar only when the orb owns the screen; in composer mode
            // the same controls are inline above, so this would duplicate them.
            if mode == .orb {
                footer
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.bottom, 12)
            }
        }
        .background(Wandr.pageBackground)
        // One spring governs the whole morph, so the shape, the padding, and
        // the surrounding layout arrive together rather than in three passes.
        .animation(.wandrTransition, value: mode)
        .animation(.wandrResponse, value: dictation.phase)
        .sensoryFeedback(.selection, trigger: dictation.isListening)
        .sensoryFeedback(.success, trigger: hasPlan && !dictation.isListening)
    }

    // MARK: Masthead

    /// Centred on the orb's axis. The screen is one object under one line;
    /// hanging the title off the left edge broke that symmetry.
    private var masthead: some View {
        VStack(spacing: 8) {
            // Off the 40pt display ramp on purpose: CurationView earns that
            // size because it heads a scrolling list, but here the orb is the
            // subject and a full masthead competes with it.
            Text("Wandr away!")
                .font(.wandrDisplay(30))
                // Heavier than the display ramp's bold. At this size the extra
                // weight is what carries the line, which is why it can stay
                // small enough to leave the orb as the subject.
                .fontWeight(.black)
                .foregroundStyle(Wandr.primaryText)
                .multilineTextAlignment(.center)

            if let failure {
                Text(failure)
                    .font(.callout)
                    .foregroundStyle(Wandr.secondaryText)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
        }
        // Enough gap under the status bar that the line reads as placed rather
        // than pinned to the top edge.
        .padding(.top, 80)
        .frame(maxWidth: .infinity)
    }

    // MARK: The object

    private var orb: some View {
        PlanOrb(
            mode: mode,
            isListening: dictation.isListening,
            level: dictation.level
        ) {
            face
        }
        // A semantic Button, not a tap gesture: this keeps VoiceOver, Switch
        // Control, and keyboard activation for the screen's primary action.
        .contentShape(.rect(cornerRadius: 30))
        .accessibilityElement(children: .contain)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var face: some View {
        if mode == .composer {
            composerField
        } else {
            micButton
        }
    }

    private var micButton: some View {
        Button {
            Task { await dictation.toggle() }
        } label: {
            Image(systemName: "mic.fill")
                .font(.system(size: 46, weight: .regular))
                .foregroundStyle(Wandr.primaryText)
                // Reduce Motion keeps the state legible without the pulse.
                .symbolEffect(
                    .breathe,
                    options: .repeating,
                    isActive: dictation.isListening && !reduceMotion
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.circle)
        }
        .buttonStyle(WandrPressStyle())
        .accessibilityLabel(dictation.isListening ? "Stop listening" : "Describe your plan out loud")
        .accessibilityAddTraits(dictation.isListening ? [.startsMediaSession] : [])
    }

    private var composerField: some View {
        TextField(
            "What are we planning?",
            text: $dictation.transcript,
            axis: .vertical
        )
        .lineLimit(1...3)
        .font(.body)
        .foregroundStyle(Wandr.primaryText)
        .focused($composing)
        // The return key is the tick — `.done` already renders a checkmark on
        // the keyboard itself, so an accessory bar above it would be a second
        // control for the same commit.
        .submitLabel(.done)
        .onSubmit(commit)
        .padding(.horizontal, 20)
    }

    // MARK: Transcript

    /// One attributed run rather than two concatenated `Text`s, so the
    /// committed and in-flight halves reflow as a single paragraph instead of
    /// breaking at the seam between them.
    private var heardSoFar: AttributedString {
        var committed = AttributedString(dictation.spokenPlan)
        committed.foregroundColor = Wandr.primaryText

        guard !dictation.volatile.isEmpty else { return committed }

        var tail = AttributedString(committed.characters.isEmpty ? dictation.volatile : " \(dictation.volatile)")
        tail.foregroundColor = Wandr.secondaryText
        return committed + tail
    }

    /// Sits below the object, never inside it. Finalized text is ink; the tail
    /// the transcriber is still revising stays slate, so you can see the
    /// difference between what's committed and what's still being heard.
    @ViewBuilder
    private var transcriptWell: some View {
        if mode == .orb, hasPlan || !dictation.volatile.isEmpty {
            ScrollView {
                Text(heardSoFar)
            }
            .font(.title3)
            .multilineTextAlignment(.center)
            .frame(maxHeight: 140)
            .scrollIndicators(.hidden)
            .padding(.top, 32)
            .padding(.horizontal, 8)
            .transition(.opacity)
            .animation(.wandrResponse, value: dictation.volatile)
        }
    }

    // MARK: Footer

    /// A ZStack, not an HStack: the keyboard glyph stays on the screen's
    /// centre line whether or not there is a plan to send.
    private var footer: some View {
        ZStack {
            Button {
                mode = mode == .composer ? .orb : .composer
                if mode == .composer {
                    Task { await dictation.stop() }
                    composing = true
                } else {
                    composing = false
                }
            } label: {
                Image(systemName: mode == .composer ? "mic" : "keyboard")
                    .font(.title3)
                    .foregroundStyle(Wandr.secondaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(WandrPressStyle())
            .accessibilityLabel(mode == .composer ? "Speak instead" : "Type instead")

            // Balances "Plan it" on the right. Without it this screen is a one-way
            // door: it fills the window, so there is no navigation chrome to escape by.
            if let onCancel {
                HStack {
                    Button {
                        composing = false
                        Task {
                            await dictation.stop()
                            onCancel()
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Wandr.secondaryText)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(WandrPressStyle())
                    .accessibilityLabel("Cancel")

                    Spacer()
                }
            }

            if hasPlan {
                HStack {
                    Spacer()
                    Button(action: commit) {
                        Label("Plan it", systemImage: "arrow.right")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 4)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Wandr.ink)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
        }
        .animation(.wandrResponse, value: hasPlan)
        .padding(.top, 8)
    }

    // MARK: Commit

    private func commit() {
        let plan = dictation.spokenPlan
        guard !plan.isEmpty else { return }
        composing = false
        Task {
            await dictation.stop()
            onCommit(dictation.spokenPlan.isEmpty ? plan : dictation.spokenPlan)
        }
    }
}

#Preview {
    PlanCaptureView { _ in }
}
