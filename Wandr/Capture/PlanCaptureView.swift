// PlanCaptureView.swift Wandr Step one of an outing: the host says what they want. Everything downstream — research, decks, schedule — is derived from what lands here, so the screen holds one statement, one trace of the voice, and the words as they arrive. Two ways in, one buffer out. Speaking and typing edit the same text, so switching between them mid-thought never costs you a word.

import SwiftUI

struct PlanCaptureView: View {

    /// Handed the finished brief. The caller moves on to curation.
    var onCommit: (String) -> Void

    /// Backs out without planning anything. Optional so previews and any caller that owns its own dismissal can leave it off — but `RootView` always supplies it, because this screen is a full-screen state rather than a sheet and there would otherwise be no way off it.
    var onCancel: (() -> Void)?

    @State private var dictation = PlanDictation()
    @State private var mode: CaptureMode = .voice
    @FocusState private var composing: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hasPlan: Bool { !dictation.spokenPlan.isEmpty }

    /// Failures need words, or a dead mic looks like a dead app.
    private var failure: String? {
        if case .failed(let reason) = dictation.phase { return reason }
        return nil
    }

    /// The screen's vocabulary, derived from the dictation phase. `heard` is the one state the phase
    /// cannot express on its own: the mic is idle either because nothing has been said yet or
    /// because something has, and those two should not look the same.
    private var activity: CaptureActivity {
        switch dictation.phase {
        case .preparing:     return .waking
        case .listening:     return .listening
        case .idle, .failed: return hasPlan ? .heard : .resting
        }
    }

    /// Once there are words to send, sending them is the thing to do — so the mic steps down and
    /// "Plan it" takes the fill. The screen only ever has one filled control; which one it is
    /// changes with what the host has already done.
    private var micIsPrimary: Bool { !hasPlan }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            masthead

            Spacer(minLength: 28)

            // The wave and the words it produced are one thing and travel together. Held apart by
            // their own spacers they read as two unrelated objects adrift on a large empty page,
            // and the wave moved every time the transcript grew.
            VStack(alignment: .leading, spacing: 30) {
                subject

                // While typing, the controls ride directly under the field rather than at the
                // screen's bottom edge. The keyboard does not shrink the safe area here, so anything
                // anchored to the bottom ends up underneath it — this puts them somewhere it cannot
                // reach.
                if mode == .composer {
                    controlRow
                }

                transcriptWell
            }

            // Two below to one above, matching the wait screens: the group settles a third of the
            // way into the space rather than dead centre.
            Spacer(minLength: 28)
            Spacer(minLength: 28)
        }
        .padding(.horizontal, Metrics.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .safeAreaBar(edge: .bottom) {
            // Bottom bar only when the voice screen owns the layout; in composer mode the same
            // controls are inline above, so this would duplicate them.
            if mode == .voice {
                bottomBar
            }
        }
        .background(Wandr.pageBackground)
        // The border carries what the orb's aura used to. A screen edge that lights up while the mic
        // is open is both quieter than a glowing object and the thing iOS itself does — and it
        // leaves the middle of the page to the words, which are the actual subject here.
        .wandrEdgeGlow(dictation.isListening ? .attending : .resting, level: dictation.level)
        // Everything the host says here goes straight into an on-device generation. Loading the
        // model is the biggest part of that first call, so it starts now, while they are still
        // deciding what to say, rather than after they tap. `prewarm()` is a non-blocking hint.
        .onAppear { FreeTextSummaryExtractor().prewarm() }
        .animation(.wandrMorph, value: mode)
        .animation(.wandrResponse, value: dictation.phase)
        .animation(.wandrResponse, value: hasPlan)
        .sensoryFeedback(.selection, trigger: dictation.isListening)
        .sensoryFeedback(.success, trigger: hasPlan && !dictation.isListening)
    }

    // MARK: Masthead

    /// Left-aligned, like every other screen in the flow. It used to be centred, to balance the orb
    /// underneath it; with the orb gone, centring it would be the only centred title in the app.
    private var masthead: some View {
        VStack(alignment: .leading, spacing: 12) {
            WandrMasthead(title: "Wandr away!")

            // The one line of guidance, and the app's honest microphone indicator. It changes with
            // the state rather than appearing only on failure, so the screen is never mute — and
            // "Listening" is stated in words, not only in motion.
            Text(statusLine)
                .font(.body)
                .foregroundStyle(failure == nil ? Wandr.secondaryText : Wandr.accent(for: .food))
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
                .animation(.wandrResponse, value: statusLine)
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusLine: String {
        if let failure { return failure }
        if mode == .composer { return "Type what you’re planning" }

        switch dictation.phase {
        case .preparing:
            return "Getting the mic ready…"
        case .listening:
            return "Listening — tap again when you’re done"
        case .idle, .failed:
            return hasPlan
                ? "Tap Plan it, or keep talking to add more"
                : "Tap to say what you’re planning"
        }
    }

    // MARK: The subject

    /// The voice, or the field that stands in for it. One or the other holds the middle of the page.
    @ViewBuilder
    private var subject: some View {
        if mode == .composer {
            composerField
        } else {
            PlanWave(activity: activity, level: { dictation.level })
                .transition(.opacity)
        }
    }

    /// Typed on a plain field rather than inside a coloured object. There is no shape left to morph
    /// out of, and a field that pretends to be one would be a costume.
    private var composerField: some View {
        TextField("", text: $dictation.transcript, axis: .vertical)
            .lineLimit(1...4)
            .font(.title3)
            .foregroundStyle(Wandr.primaryText)
            .tint(Wandr.brand)
            .focused($composing)
            // The return key is the tick — `.done` already renders a checkmark on the keyboard
            // itself, so an accessory bar above it would be a second control for the same commit.
            .submitLabel(.done)
            .onSubmit(commit)
            // Drawn rather than passed as the field's title: the system renders its placeholder in a
            // fixed grey that cannot be restyled reliably. The label is reattached below so
            // VoiceOver is unaffected.
            .overlay(alignment: .topLeading) {
                if dictation.transcript.isEmpty {
                    Text("What are we planning?")
                        .font(.title3)
                        .foregroundStyle(Wandr.secondaryText.opacity(0.6))
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel("What are we planning?")
            .padding(.vertical, 18)
            .padding(.horizontal, 18)
            .background(WandrCardBackground(corner: Metrics.blockCorner))
            .transition(.opacity)
    }

    // MARK: Transcript

    /// One attributed run rather than two concatenated `Text`s, so the committed and in-flight halves reflow as a single paragraph instead of breaking at the seam between them.
    private var heardSoFar: AttributedString {
        var committed = AttributedString(dictation.spokenPlan)
        committed.foregroundColor = Wandr.primaryText

        guard !dictation.volatile.isEmpty else { return committed }

        var tail = AttributedString(committed.characters.isEmpty ? dictation.volatile : " \(dictation.volatile)")
        tail.foregroundColor = Wandr.secondaryText
        return committed + tail
    }

    /// The words, at a size that says they are the point of the screen. Finalized text is ink; the
    /// tail the transcriber is still revising stays slate, so you can see the difference between
    /// what's committed and what's still being heard.
    @ViewBuilder
    private var transcriptWell: some View {
        if mode == .voice, hasPlan || !dictation.volatile.isEmpty {
            ScrollView {
                Text(heardSoFar)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.title2)
            .frame(maxHeight: 190)
            .scrollIndicators(.hidden)
            .transition(.opacity)
            .animation(.wandrResponse, value: dictation.volatile)
        }
    }

    // MARK: Controls

    private var bottomBar: some View {
        VStack(spacing: 14) {
            if hasPlan {
                Button(action: commit) {
                    Label("Plan it", systemImage: "arrow.forward")
                        .wandrActionLabel()
                }
                .wandrPrimaryAction()
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

            controlRow
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.bottom, 8)
    }

    /// A ZStack, not an HStack: the mic stays on the screen's centre line whether or not there is a
    /// cancel button beside it and whether or not the keyboard toggle is showing.
    private var controlRow: some View {
        ZStack {
            micControl

            HStack {
                if onCancel != nil {
                    circleControl(systemName: "xmark", label: "Cancel") {
                        composing = false
                        Task {
                            await dictation.stop()
                            onCancel?()
                        }
                    }
                }

                Spacer()

                // Only in voice mode. In the composer the mic in the middle is already the way back,
                // so a second toggle here would be two controls for one job.
                if mode == .voice {
                    circleControl(systemName: "keyboard", label: "Type instead") {
                        enterComposer()
                    }
                }
            }
        }
    }

    /// The screen's primary action while there is nothing to send, and a quiet one after that.
    private var micControl: some View {
        Button {
            if mode == .composer {
                leaveComposer()
            } else {
                Task { await dictation.toggle() }
            }
        } label: {
            Image(systemName: mode == .composer ? "waveform" : "mic.fill")
                .font(.system(size: 25, weight: .medium))
                .contentTransition(.symbolEffect(.replace))
                // Reduce Motion keeps the state legible through the wave, the status line, and the
                // border without the pulse.
                .symbolEffect(
                    .breathe,
                    options: .repeating,
                    isActive: dictation.isListening && !reduceMotion && mode == .voice
                )
                .frame(width: 30, height: 30)
        }
        .wandrCircleAction(prominent: micIsPrimary && mode == .voice)
        // A semantic Button, not a tap gesture: this keeps VoiceOver, Switch Control, and keyboard
        // activation for the screen's primary action.
        .accessibilityLabel(micLabel)
        .accessibilityAddTraits(dictation.isListening ? [.startsMediaSession] : [])
    }

    private var micLabel: String {
        if mode == .composer { return "Speak instead" }
        return dictation.isListening ? "Stop listening" : "Describe your plan out loud"
    }

    /// The secondary controls, given the same glass shape the rest of the app uses for its buttons —
    /// so they read as controls at a glance and pick up the system's press and focus behaviour.
    private func circleControl(
        systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .medium))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .tint(Wandr.brand)
        .accessibilityLabel(label)
    }

    // MARK: Mode

    private func enterComposer() {
        mode = .composer
        Task { await dictation.stop() }
        composing = true
    }

    private func leaveComposer() {
        composing = false
        mode = .voice
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

// MARK: - Circle actions

private extension View {

    /// Filled or not, same geometry either way — so the mic keeps its position and size when it
    /// hands the screen's emphasis over to "Plan it", and only its weight changes.
    @ViewBuilder
    func wandrCircleAction(prominent: Bool) -> some View {
        if prominent {
            buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .controlSize(.extraLarge)
                .tint(Wandr.brand)
        } else {
            buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.extraLarge)
                .tint(Wandr.brand)
        }
    }
}

#Preview {
    PlanCaptureView { _ in } onCancel: { }
}
