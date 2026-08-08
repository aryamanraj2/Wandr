// SquadTransport.swift Wandr The socket to the relay, and nothing above it: this type knows about bytes, reconnects and backoff, and has never heard of a poll. It hands `SquadRoom` a stream of events and takes `ClientMessage`s back.
//
// **The isolation landmine, and it is the one most likely to bite.** This project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so an un-annotated class here would be implicitly `@MainActor` — and `NWConnection`'s `stateUpdateHandler` / `receiveMessage` closures would then inherit MainActor isolation while actually running on the connection's own `DispatchQueue`. That builds without a single warning and traps at runtime in `_dispatch_assert_queue_fail`. Hence `nonisolated`, explicitly, the same way the domain layer writes `nonisolated struct … : Sendable` everywhere.
//
// The transport is raw `Network.framework` rather than `URLSessionWebSocketTask` on purpose: App Transport Security applies only to the URL Loading System, so plaintext `ws://localhost:8787` here needs no `NSAppTransportSecurity` entry — which the app could not express anyway, since it builds with `GENERATE_INFOPLIST_FILE = YES` and ATS is a nested dictionary with no `INFOPLIST_KEY_*` form. Loopback also never trips local-network privacy.

import Foundation
import Network

/// How the device stands relative to the room.
nonisolated enum SquadConnection: Sendable, Equatable {
    case offline
    case connecting
    case live
}

/// `@unchecked Sendable` states the invariant the whole file is built on rather than papering over a warning: every stored property below is read and written **only** on `queue`, a private serial `DispatchQueue`. The compiler cannot see that, and `NWConnection`'s callbacks genuinely do cross threads, so the guarantee is made here and kept by never touching state outside a `queue.async`.
nonisolated final class SquadTransport: @unchecked Sendable {

    /// Everything arriving from below, in order. One stream rather than two so a state change and the snapshot that follows it can never be observed out of sequence.
    nonisolated enum Event: Sendable {
        case connection(SquadConnection)
        case message(ServerMessage)
    }

    let events: AsyncStream<Event>
    private let continuation: AsyncStream<Event>.Continuation

    /// Every piece of mutable state below is touched only here. That is the whole concurrency story.
    private let queue = DispatchQueue(label: "wandr.squad.transport")

    private var connection: NWConnection?
    private var isReady = false

    /// The message replayed on every (re)connect to re-establish who this device is. Starts as the `.host` or `.join` that opened the room; `SquadRoom` swaps it for a `.join` carrying the assigned code the moment the welcome lands, so a dropped leader rejoins its own room instead of minting a second one.
    private var identity: ClientMessage?

    /// Sent once the socket is up. A tap during a reconnect is a tap the user made and expects to count.
    private var outbox: [ClientMessage] = []

    private var backoff = SquadTransport.minimumBackoff
    private static let minimumBackoff: TimeInterval = 0.25
    private static let maximumBackoff: TimeInterval = 4

    /// Only the current connection's callbacks may act. Cancelling a connection fires its own state handler, and without this a deliberate teardown would look like a drop and schedule a second reconnect on top of the one already in flight.
    private var generation = 0

    private let host: String

    init(host: String = "localhost") {
        self.host = host
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(32))
    }

    // MARK: - Public surface

    /// Opens (or reopens) the socket and identifies this device with `identity`.
    func connect(as identity: ClientMessage) {
        queue.async {
            self.identity = identity
            self.backoff = Self.minimumBackoff
            self.open()
        }
    }

    /// Replaces the message replayed on reconnect without touching the live socket.
    func rememberIdentity(_ identity: ClientMessage) {
        queue.async { self.identity = identity }
    }

    func send(_ message: ClientMessage) {
        queue.async {
            guard self.isReady, let connection = self.connection else {
                self.outbox.append(message)
                return
            }
            self.write(message, on: connection)
        }
    }

    /// Leaves the room for good. No reconnect follows.
    func disconnect() {
        queue.async {
            self.generation += 1
            self.identity = nil
            self.outbox.removeAll()
            self.teardown()
            self.continuation.yield(.connection(.offline))
        }
    }

    // MARK: - Socket

    private func open() {
        teardown()
        generation += 1
        let generation = self.generation

        let parameters = NWParameters.tcp
        let websocket = NWProtocolWebSocket.Options()
        websocket.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(websocket, at: 0)

        guard let url = URL(string: "ws://\(host):\(SquadWire.port)") else { return }
        let connection = NWConnection(to: .url(url), using: parameters)
        self.connection = connection

        SquadLog.net("opening \(url.absoluteString)")
        continuation.yield(.connection(.connecting))

        connection.stateUpdateHandler = { [weak self] state in
            guard let self, generation == self.generation else { return }
            switch state {
            case .ready:
                ready(connection)
            case .waiting(let error):
                // The relay is not answering — refused, or not started yet. `NWConnection` would sit in `.waiting` indefinitely on loopback, so retry on our own schedule rather than never.
                SquadLog.net("waiting: \(error) — is the relay running? (swift run WandrRelay)")
                retry()
            case .failed(let error):
                SquadLog.net("failed: \(error)")
                retry()
            case .cancelled:
                retry()
            default:
                break
            }
        }

        connection.start(queue: queue)
        receive(on: connection)
    }

    private func ready(_ connection: NWConnection) {
        isReady = true
        backoff = Self.minimumBackoff
        SquadLog.net("live — replaying \(identity?.summary ?? "no identity"), \(outbox.count) queued")
        continuation.yield(.connection(.live))

        // Identity first, always: the relay attributes a vote to whoever the connection joined as, so a vote that overtook its own join would be dropped on the floor.
        if let identity { write(identity, on: connection) }
        let queued = outbox
        outbox.removeAll()
        for message in queued { write(message, on: connection) }
    }

    private func receive(on connection: NWConnection) {
        let generation = self.generation
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self, generation == self.generation else { return }

            if let data, !data.isEmpty {
                if let message = SquadWire.decode(ServerMessage.self, from: data) {
                    SquadLog.net("← \(message.summary)")
                    continuation.yield(.message(message))
                } else {
                    // Undecodable means the two ends have drifted, which is the exact failure the symlinked wire file exists to prevent. Never swallow it.
                    SquadLog.problem("undecodable server message (\(data.count)B): \(String(decoding: data.prefix(200), as: UTF8.self))")
                }
            }

            guard error == nil else {
                retry()
                return
            }
            receive(on: connection)
        }
    }

    private func write(_ message: ClientMessage, on connection: NWConnection) {
        guard let data = SquadWire.encode(message) else {
            SquadLog.problem("could not encode \(message.summary)")
            return
        }
        SquadLog.net("→ \(message.summary)")
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "wandr", metadata: [metadata])
        connection.send(
            content: data,
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed { _ in }
        )
    }

    /// Backs off and reopens, as long as this device still believes it belongs to a room. A rebuilt simulator comes back through here and rejoins silently.
    private func retry() {
        guard identity != nil else { return }

        isReady = false
        teardown()
        // Retire this generation before scheduling: cancelling a socket also completes its outstanding `receiveMessage` with an error, and that completion would otherwise land back here and queue a second reconnect on top of this one.
        generation += 1
        continuation.yield(.connection(.offline))

        let delay = backoff
        backoff = min(backoff * 2, Self.maximumBackoff)
        SquadLog.net("reconnecting in \(String(format: "%.2f", delay))s")
        let generation = self.generation

        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, generation == self.generation, identity != nil else { return }
            open()
        }
    }

    private func teardown() {
        isReady = false
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
    }
}
