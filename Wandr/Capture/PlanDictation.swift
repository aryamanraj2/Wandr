//
//  PlanDictation.swift
//  Wandr
//
//  Live, on-device dictation for the capture screen.
//
//  Uses SpeechAnalyzer + SpeechTranscriber (iOS 26+) rather than the legacy
//  SFSpeechRecognizer: it runs entirely on device, streams volatile results
//  while the host is still talking, and hands back finalized text without a
//  round trip. The audio tap also publishes a smoothed amplitude so the orb
//  can react to the voice rather than loop a canned animation.
//

import AVFoundation
import Foundation
import OSLog
import Speech

private let logger = Logger(subsystem: "com.wandr.app", category: "dictation")

/// Failures that are ours rather than the framework's, so they can carry a
/// sentence worth showing instead of arriving as an opaque NSError.
enum DictationError: LocalizedError {
    case locale(Locale)
    case unsupported(Locale)

    var errorDescription: String? {
        switch self {
        case .locale(let locale):
            "Speech models for \(locale.identifier) could not be reserved."
        case .unsupported(let locale):
            "On-device dictation isn't available for \(locale.identifier) here. Type your plan instead."
        }
    }
}

@MainActor
@Observable
final class PlanDictation {

    enum Phase: Equatable {
        case idle
        /// Mic granted, model warming up. The orb holds still here — a pulse
        /// would claim we're hearing something when we aren't yet.
        case preparing
        case listening
        /// Recoverable: permission refused, model unavailable, engine failure.
        /// Carries a sentence the view can show verbatim.
        case failed(String)
    }

    private(set) var phase: Phase = .idle

    /// Everything the transcriber has committed, plus anything typed. The
    /// view binds a `TextField` straight to this, so speech and keyboard
    /// edit one buffer instead of two that have to be reconciled.
    var transcript: String = ""

    /// The tail the transcriber is still revising. Rendered dimmer and never
    /// merged until it finalizes, so words don't visibly rewrite themselves.
    private(set) var volatile: String = ""

    /// Smoothed 0...1 microphone amplitude. Drives the orb's rings.
    private(set) var level: Double = 0

    var isListening: Bool { phase == .listening || phase == .preparing }

    /// What the user has actually committed — the thing we plan from.
    var spokenPlan: String {
        transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Machinery

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var analyzer: SpeechAnalyzer?
    @ObservationIgnored private var transcriber: SpeechTranscriber?
    @ObservationIgnored private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    @ObservationIgnored private var resultsTask: Task<Void, Never>?
    @ObservationIgnored private var levelTask: Task<Void, Never>?

    // MARK: Control

    func toggle() async {
        if isListening {
            await stop()
        } else {
            await start()
        }
    }

    func start() async {
        guard !isListening else { return }
        phase = .preparing
        volatile = ""

        guard await AVAudioApplication.requestRecordPermission() else {
            phase = .failed("Wandr needs the microphone to hear your plan. Turn it on in Settings.")
            return
        }

        do {
            try await beginTranscribing()
            phase = .listening
        } catch {
            teardown()
            // The user gets the calm sentence; the log gets the truth. Without
            // this the underlying error was discarded at the catch, so every
            // distinct failure — no model, no reservation, audio session
            // refused — presented identically and none could be told apart.
            logger.error("Dictation failed to start: \(error, privacy: .public)")
            phase = .failed(Self.explain(error))
        }
    }

    /// Folds any in-flight volatile tail into the transcript before returning,
    /// so releasing the mic never drops the last few words.
    func stop() async {
        guard isListening else { return }
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        teardown()
        phase = .idle
        withCommittedVolatile()
        level = 0
    }

    func clear() {
        transcript = ""
        volatile = ""
    }

    // MARK: Speech pipeline

    private func beginTranscribing() async throws {
        let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current)
            ?? Locale(identifier: "en-US")

        // Progressive preset: volatile results as they're heard, finalized
        // results behind them. Without it the screen sits blank mid-sentence.
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        self.transcriber = transcriber

        // `noModel` says the configuration has no model behind it, but not
        // which half is at fault — the locale we picked, or the fact that no
        // asset was ever installed for it. Asking the inventory directly is
        // the only way to tell those apart, and it costs one call.
        // Bound outside the log call: string interpolation is an autoclosure,
        // which cannot carry an `await`.
        let status = await AssetInventory.status(forModules: [transcriber])
        let installed = await SpeechTranscriber.installedLocales.map(\.identifier)
        let reserved = await AssetInventory.reservedLocales.map(\.identifier)
        logger.log("""
            Speech preflight — locale \(locale.identifier, privacy: .public), \
            status \(String(describing: status), privacy: .public), \
            installed \(installed, privacy: .public), \
            reserved \(reserved, privacy: .public)
            """)

        guard status != .unsupported else {
            throw DictationError.unsupported(locale)
        }

        // Models are downloaded on demand, once per locale. Doing it here (not
        // lazily mid-sentence) keeps the first word from being swallowed.
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            logger.log("Downloading speech model for \(locale.identifier, privacy: .public)")
            try await request.downloadAndInstall()
        }

        // Downloading the model is not the same as being allowed to use it.
        // An app holds a small number of locale reservations, and the
        // transcriber only produces results for a locale it has reserved —
        // without this the pipeline starts cleanly and then stays silent,
        // which is exactly the failure that looks like a dead microphone.
        if await !AssetInventory.reservedLocales.contains(locale) {
            guard try await AssetInventory.reserve(locale: locale) else {
                throw DictationError.locale(locale)
            }
        }

        analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        inputContinuation = continuation

        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    self?.receive(text, isFinal: result.isFinal)
                }
            } catch {
                self?.transcriptionFailed()
            }
        }

        try await analyzer.start(inputSequence: stream)
        try await startEngine(feeding: continuation)
    }

    private func receive(_ text: String, isFinal: Bool) {
        if isFinal {
            volatile = ""
            appendFinalized(text)
        } else {
            volatile = text
        }
    }

    private func appendFinalized(_ text: String) {
        let piece = text.trimmingCharacters(in: .whitespaces)
        guard !piece.isEmpty else { return }
        if transcript.isEmpty {
            transcript = piece
        } else {
            let joiner = transcript.hasSuffix(" ") ? "" : " "
            transcript += joiner + piece
        }
    }

    private func withCommittedVolatile() {
        guard !volatile.isEmpty else { return }
        appendFinalized(volatile)
        volatile = ""
    }

    /// Distinct causes get distinct sentences. A dead mic and an undownloaded
    /// model need different things from the user, so collapsing them into one
    /// "try typing instead" hides the only actionable part.
    ///
    /// Matched on `error.code` rather than in a `catch`: `insufficientResources`
    /// is a Swift-only `static var`, so it exists on `SFSpeechError.Code` but
    /// never as a shorthand member on `SFSpeechError` itself.
    private static func explain(_ error: Error) -> String {
        if let error = error as? DictationError {
            return error.localizedDescription
        }
        if let error = error as? SFSpeechError {
            switch error.code {
            case .insufficientResources:
                return "The device is busy with another transcription. Try again in a moment."
            case .noModel, .cannotAllocateUnsupportedLocale:
                return "On-device dictation isn't available on this device yet. Type your plan instead."
            case .tooManyAssetLocalesAllocated:
                return "Too many speech languages are reserved. Free one in Settings and try again."
            default:
                break
            }
        }
        return "Couldn't start listening. Try typing it instead."
    }

    private func transcriptionFailed() {
        teardown()
        phase = .failed("Lost the transcription. Your words so far are kept.")
    }

    // MARK: Audio

    /// Owns the engine and the audio session. It is an actor, not a set of
    /// methods on this @MainActor class, because `setCategory` and session
    /// activation take a system round trip — on the main thread that shows up
    /// as a hitch on the very tap that starts listening.
    actor Microphone {

        private let engine = AVAudioEngine()

        func start(
            analyzerFormat: AVAudioFormat?,
            feeding input: AsyncStream<AnalyzerInput>.Continuation,
            metering level: AsyncStream<Double>.Continuation
        ) async throws {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            // iOS 27's async pair. Activation can wait on the system audio
            // server, so it never belongs on a synchronous path.
            _ = try await session.activate(options: [])

            let node = engine.inputNode
            let format = node.outputFormat(forBus: 0)

            // The converter resamples the mic's native format into whatever the
            // transcriber wants. It is only ever touched inside the tap callback,
            // which the engine serializes onto one render thread.
            nonisolated(unsafe) let converter = AnalyzerInputConverter(
                analyzerFormat: analyzerFormat ?? format
            )

            // iOS 27 deprecates this in favour of a throwing variant, but that
            // one ships unrefined in the current SDK (its NSError** parameter
            // imports as Void and cannot be called from Swift). Revisit once the
            // overlay lands; the deprecated call is still fully functional.
            node.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, time in
                level.yield(PlanDictation.amplitude(of: buffer))
                if let converted = try? converter.convert(buffer, at: time) {
                    for piece in converted {
                        input.yield(piece)
                    }
                }
            }

            engine.prepare()
            try engine.start()
        }

        /// Deactivation is the call the runtime specifically warns about, so it
        /// uses the async form and stays off the main thread either way.
        func stop() async {
            guard engine.isRunning else { return }
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            _ = try? await AVAudioSession.sharedInstance().deactivate(options: .notifyOthersOnDeactivation)
        }
    }

    /// Resolved once per session; nil falls back to the mic's own format.
    @ObservationIgnored private var analyzerFormat: AVAudioFormat?
    @ObservationIgnored private let microphone = Microphone()

    private func startEngine(feeding continuation: AsyncStream<AnalyzerInput>.Continuation) async throws {
        let (levels, levelContinuation) = AsyncStream<Double>.makeStream()
        levelTask = Task { [weak self] in
            for await value in levels {
                self?.absorb(value)
            }
        }

        try await microphone.start(
            analyzerFormat: analyzerFormat,
            feeding: continuation,
            metering: levelContinuation
        )
    }

    /// Tears down the observable state immediately so the UI settles on the
    /// same frame as the tap, then lets the hardware wind down behind it.
    private func teardown() {
        inputContinuation?.finish()
        inputContinuation = nil
        resultsTask?.cancel()
        resultsTask = nil
        levelTask?.cancel()
        levelTask = nil
        analyzer = nil
        transcriber = nil
        Task { await microphone.stop() }
    }

    // MARK: Level metering

    /// Asymmetric smoothing: rise fast so the orb answers a syllable on the
    /// frame it lands, fall slow so it settles instead of strobing per word.
    private func absorb(_ raw: Double) {
        let coefficient = raw > level ? 0.55 : 0.12
        level = level + (raw - level) * coefficient
    }

    /// RMS in dBFS, mapped onto a floor that keeps room tone at rest.
    nonisolated static func amplitude(of buffer: AVAudioPCMBuffer) -> Double {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }

        var sum: Float = 0
        for index in 0..<count {
            let sample = channel[index]
            sum += sample * sample
        }
        let rms = (sum / Float(count)).squareRoot()

        let decibels = 20 * log10(max(Double(rms), 1e-7))
        let floor = -50.0
        return max(0, min(1, (decibels - floor) / -floor))
    }
}

