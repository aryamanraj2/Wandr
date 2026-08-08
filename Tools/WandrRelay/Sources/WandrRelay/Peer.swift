// Peer.swift WandrRelay One connected device. It owns an `NWConnection`, pulls `ClientMessage`s off it, and carries the membership the store assigns it on host/join. That membership is the reason the relay is safe without accounts: a `.vote` message says *what* was voted for and never *who* voted, so the relay attributes it to the identity this connection joined under and a client cannot vote on anyone else's behalf.

import Foundation
import Network

final class Peer {
    let connection: NWConnection

    // Membership. Written and read only on `RoomStore`'s serial queue — the store is the single place that decides who a connection is.
    var code: RoomCode?
    var participant: ParticipantID?
    var name = "—"

    private let onMessage: (ClientMessage, Peer) -> Void
    private let onClose: (Peer) -> Void

    init(
        connection: NWConnection,
        onMessage: @escaping (ClientMessage, Peer) -> Void,
        onClose: @escaping (Peer) -> Void
    ) {
        self.connection = connection
        self.onMessage = onMessage
        self.onClose = onClose
    }

    func start(on queue: DispatchQueue) {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .failed, .cancelled:
                onClose(self)
            default:
                break
            }
        }
        connection.start(queue: queue)
        receive()
    }

    /// One message at a time, re-arming after each. `receiveMessage` hands over a whole WebSocket message, so there is no framing to do here.
    private func receive() {
        connection.receiveMessage { [weak self] data, context, _, error in
            guard let self else { return }

            if let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
                as? NWProtocolWebSocket.Metadata, metadata.opcode == .close {
                connection.cancel()
                return
            }

            if let data, !data.isEmpty {
                if let message = SquadWire.decode(ClientMessage.self, from: data) {
                    onMessage(message, self)
                } else {
                    // Loud rather than silent: an undecodable message means the two ends have drifted, and that is exactly the failure this symlinked-protocol design exists to prevent.
                    Log.line("✗ undecodable client message (\(data.count)B): \(String(decoding: data.prefix(240), as: UTF8.self))")
                }
            }

            guard error == nil else {
                connection.cancel()
                return
            }
            receive()
        }
    }

    func send(_ message: ServerMessage) {
        guard let data = SquadWire.encode(message) else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "wandr", metadata: [metadata])
        connection.send(
            content: data,
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed { _ in }
        )
    }
}
