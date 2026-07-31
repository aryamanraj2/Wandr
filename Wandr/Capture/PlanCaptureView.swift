// PlanCaptureView.swift Wandr Step one of an outing: the host says what they want. Everything downstream — research, decks, schedule — is derived from what lands here, so the screen holds exactly one object and one line of guidance. Two ways in, one buffer out. Speaking and typing edit the same text, so switching between them mid-thought never costs you a word.

import SwiftUI

struct PlanCaptureView: View {

    /// Handed the finished brief. The caller moves on to curation.
    var onCommit: (String) -> Void

    /// Backs out without planning anything. Optional so previews and any caller that owns its own dismissal can leave it off — but `RootView` always supplies it, because this screen is a full-screen state rather than a sheet and there would otherwise be no way off it.
    var onCancel: (() -> Void)?

    @State private var dictation = PlanDictation()
    @State private var mode: OrbMode = .orb
    @FocusState private var composing: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hasPlan: Bool { !dictation.spokenPlan.isEmpty }

    /// Failures need words, or a dead mic looks like a dead app. Everything else the orb says itself, and the status line below only names it.
    private var failure: String? {
        if case .failed(let reason) = dictation.phase { return reason }
        return nil
    }

    /// The orb's vocabulary, derived from the dictation phase. `heard` is the one state the phase
    /// cannot express on its own: the mic is idle either because nothing has been said yet or
    /// because something has, and those two should not look the same.
    private var activity: OrbActivity {
        switch dictation.phase {
        case .preparing:     return .waking
        case .listening:     return .listening
        case .idle, .failed: return hasPlan ? .heard : .resting
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            masthead

            // Typing anchors the field high on the page instead of centring it. Nothing then depends on keyboard avoidance moving the layout — the field is simply never where the keyboard goes.
            if mode == .composer {
                Spacer().frame(height: 28)
            } else {
                Spacer(minLength: 20)
            }

            orb
                .padding(.horizontal, mode == .composer ? 0 : Metrics.gutter)
                // The aura no longer reserves space, so the orb gets its breathing room explicitly. Composer mode wants none of it: the controls belong directly under the field.
                .padding(.vertical, mode == .composer ? 0 : 36)

            // While typing, the controls ride directly under the field rather than at the screen's bottom edge. The keyboard does not shrink the safe area here, so anything anchored to the bottom ends up underneath it — this puts them somewhere it cannot reach.
            if mode == .composer {
                footer
                    .padding(.top, 20)
            }

            transcriptWell

            Spacer(minLength: 20)
        }
        .padding(.horizontal, Metrics.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Applied outside the sized frame, matching the pattern that already works in CurationView. Inside it, the bar was being laid out against the content's own box rather than the screen's bottom edge.
        .safeAreaInset(edge: .bottom) {
            // Bottom bar only when the orb owns the screen; in composer mode the same controls are inline above, so this would duplicate them.
            if mode == .orb {
                footer
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.bottom, 12)
            }
        }
        .background(pageWash)
        // Everything the host says here goes straight into an on-device generation. Loading the model is the biggest part of that first call, so it starts now, while they are still deciding what to say, rather than after they tap. `prewarm()` is a non-blocking hint and returns immediately.
        .onAppear { FreeTextSummaryExtractor().prewarm() }
        // One spring governs the whole morph, so the silhouette, the frame, and the surrounding layout arrive together rather than in three passes.
        .animation(.wandrMorph, value: mode)
        .animation(.wandrResponse, value: dictation.phase)
        .animation(.wandrResponse, value: hasPlan)
        .sensoryFeedback(.selection, trigger: dictation.isListening)
        .sensoryFeedback(.success, trigger: hasPlan && !dictation.isListening)
    }

    /// A flat field behind a lit object reads as a sticker on paper. One soft pool of light behind
    /// the orb, on the same axis as the orb's own highlight, is enough to place it in a room.
    private var pageWash: some View {
        ZStack {
            Wandr.pageBackground
            RadialGradient(
                colors: [Wandr.paper.opacity(0.95), Wandr.paper.opacity(0)],
                center: UnitPoint(x: 0.5, y: 0.42),
                startRadius: 30,
                endRadius: 440
            )
        }
        .ignoresSafeArea()
    }

    // MARK: Masthead

    /// Centred on the orb's axis. The screen is one object under one line; hanging the title off the left edge broke that symmetry.
    private var masthead: some View {
        VStack(spacing: 10) {
            // Off the 40pt display ramp on purpose: CurationView earns that size because it heads a scrolling list, but here the orb is the subject and a full masthead competes with it.
            Text("Wandr away!")
                .font(.wandrDisplay(30))
                // Heavier than the display ramp's bold. At this size the extra weight is what carries the line, which is why it can stay small enough to leave the orb as the subject.
                .fontWeight(.black)
                .foregroundStyle(Wandr.primaryText)
                .multilineTextAlignment(.center)

            // The one line of guidance, and the app's honest microphone indicator. It changes with
            // the state rather than appearing only on failure, so the orb is never a mute object
            // the host has to guess at — and "Listening" is stated in words, not only in motion.
            Text(statusLine)
                .font(.callout)
                .foregroundStyle(failure == nil ? Wandr.secondaryText : Wandr.accent(for: .food))
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
                .frame(maxWidth: 320)
                .fixedSize(horizontal: false, vertical: true)
                .animation(.wandrResponse, value: statusLine)
        }
        // Enough gap under the status bar that the line reads as placed rather than pinned to the top edge.
        .padding(.top, 72)
        .frame(maxWidth: .infinity)
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

    // MARK: The object

    private var orb: some View {
        PlanOrb(
            mode: mode,
            activity: activity,
            level: dictation.level
        ) {
            face
        }
        .accessibilityElement(children: .contain)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    /// The mic does not hand off to a text field, it *shrinks into* one: the same glyph that filled
    /// the orb becomes the field's leading icon, so there is one continuous object across the morph
    /// rather than two views trading places. Tapping it in the composer is the way back to voice.
    private var face: some View {
        HStack(spacing: mode == .composer ? 10 : 0) {
            micControl

            if mode == .composer {
                composerField
                    // Staged behind the shape: the silhouette starts flattening first and the field's
                    // content arrives once there is a field-shaped space for it. On the way out the
                    // text leaves immediately, so the shape is never seen swelling around live text.
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: 0.20).delay(0.14)),
                        removal: .opacity.animation(.easeOut(duration: 0.10))
                    ))
            }
        }
        .padding(.horizontal, mode == .composer ? 18 : 0)
    }

    private var micControl: some View {
        Button {
            if mode == .composer {
                leaveComposer()
            } else {
                Task { await dictation.toggle() }
            }
        } label: {
            Image(systemName: "mic.fill")
                .font(.system(size: 46, weight: .regular))
                .foregroundStyle(Wandr.onBrand.opacity(mode == .composer ? 0.7 : 1))
                // Cast down and to the right, away from the orb's own light. A flat glyph on a lit
                // curved surface reads as pasted over the orb; a contact shadow puts it on the face.
                // Dropped in the composer, where the glyph is a small icon on a flat field.
                .shadow(color: Wandr.charcoal.opacity(mode == .composer ? 0 : 0.32), radius: 9, x: 2, y: 5)
                // Reduce Motion keeps the state legible without the pulse.
                .symbolEffect(
                    .breathe,
                    options: .repeating,
                    isActive: dictation.isListening && !reduceMotion && mode == .orb
                )
                // Scaled rather than resized: a font-size change is not animatable, and this glyph has
                // to travel continuously for the morph to read as one object changing posture.
                .scaleEffect(mode == .composer ? 0.42 : 1, anchor: .center)
                .frame(width: mode == .composer ? 24 : nil, height: mode == .composer ? 44 : nil)
                .frame(maxWidth: mode == .composer ? nil : .infinity,
                       maxHeight: mode == .composer ? nil : .infinity)
                .contentShape(.rect)
        }
        // A semantic Button, not a tap gesture: this keeps VoiceOver, Switch Control, and keyboard activation for the screen's primary action.
        .buttonStyle(WandrPressStyle())
        .accessibilityLabel(micLabel)
        .accessibilityAddTraits(dictation.isListening ? [.startsMediaSession] : [])
    }

    private var micLabel: String {
        if mode == .composer { return "Speak instead" }
        return dictation.isListening ? "Stop listening" : "Describe your plan out loud"
    }

    /// Typed on the same face the mic sat on rather than reverting to a light box mid-morph.
    private var composerField: some View {
        TextField("", text: $dictation.transcript, axis: .vertical)
            .lineLimit(1...3)
            .font(.body)
            .foregroundStyle(Wandr.onBrand)
            // Without this the caret and selection take the app's accent, which is the exact colour
            // of the face they are drawn on.
            .tint(Wandr.cream)
            .focused($composing)
            // The return key is the tick — `.done` already renders a checkmark on the keyboard itself, so an accessory bar above it would be a second control for the same commit.
            .submitLabel(.done)
            .onSubmit(commit)
            // Drawn rather than passed as the field's title: the system renders its placeholder in
            // a fixed grey that cannot be restyled reliably, and that grey on indigo is barely
            // legible. The label is reattached below so VoiceOver is unaffected.
            .overlay(alignment: .leading) {
                if dictation.transcript.isEmpty {
                    Text("What are we planning?")
                        .font(.body)
                        .foregroundStyle(Wandr.cream.opacity(0.55))
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel("What are we planning?")
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

    /// Sits below the object, never inside it. Finalized text is ink; the tail the transcriber is still revising stays slate, so you can see the difference between what's committed and what's still being heard.
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
            .padding(.top, 28)
            .padding(.horizontal, 8)
            .transition(.opacity)
            .animation(.wandrResponse, value: dictation.volatile)
        }
    }

    // MARK: Footer

    /// A ZStack, not an HStack: the input-mode toggle stays on the screen's centre line whether or not there is a plan to send.
    private var footer: some View {
        ZStack {
            circleControl(
                systemName: mode == .composer ? "mic" : "keyboard",
                label: mode == .composer ? "Speak instead" : "Type instead"
            ) {
                if mode == .composer {
                    leaveComposer()
                } else {
                    enterComposer()
                }
            }

            // Balances "Plan it" on the right. Without it this screen is a one-way door: it fills the window, so there is no navigation chrome to escape by.
            if let onCancel {
                HStack {
                    circleControl(systemName: "xmark", label: "Cancel") {
                        composing = false
                        Task {
                            await dictation.stop()
                            onCancel()
                        }
                    }
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
                    .tint(Wandr.brand)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
                }
            }
        }
        .padding(.top, 8)
    }

    /// The secondary controls on this screen were bare glyphs floating on the page, which is what
    /// made a finished screen look half-built. Given the same glass shape the rest of the app uses
    /// for its controls, they read as buttons at a glance and pick up the system's own press and
    /// focus behaviour for free.
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
        mode = .orb
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
