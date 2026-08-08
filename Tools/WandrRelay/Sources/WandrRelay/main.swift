// main.swift WandrRelay Bring the listener up and hand every connection to the store.
//
// The transport is raw `Network.framework` rather than `URLSession`, on both ends. App Transport Security applies only to the URL Loading System, so `ws://localhost:8787` over `NWConnection` needs no `NSAppTransportSecurity` entry — which matters because the app has `GENERATE_INFOPLIST_FILE = YES` and no Info.plist at all, and ATS is a nested dictionary that cannot be expressed as an `INFOPLIST_KEY_*` build setting. Loopback also never triggers local-network privacy. Net: zero Info.plist, entitlement or project-setting changes anywhere in this feature.

import Foundation
import Network

// Line-buffered, so `swift run WandrRelay | tee relay.log` shows each event as it happens rather than in a block when the process finally exits.
setvbuf(stdout, nil, _IOLBF, 0)

let store = RoomStore()
let queue = DispatchQueue(label: "wandr.relay.listener")

let parameters = NWParameters.tcp
// Without this a restart cannot bind for ~60s while the previous socket sits in TIME_WAIT — which during a demo reads as "the relay is broken".
parameters.allowLocalEndpointReuse = true

let websocket = NWProtocolWebSocket.Options()
websocket.autoReplyPing = true
parameters.defaultProtocolStack.applicationProtocols.insert(websocket, at: 0)

guard let port = NWEndpoint.Port(rawValue: SquadWire.port) else {
    fatalError("port \(SquadWire.port) is not a valid port number")
}

let listener: NWListener
do {
    listener = try NWListener(using: parameters, on: port)
} catch {
    Log.line("✗ could not listen on \(SquadWire.port): \(error)")
    exit(1)
}

listener.stateUpdateHandler = { state in
    switch state {
    case .ready:
        Log.line("● WandrRelay listening on ws://localhost:\(SquadWire.port)")
        Log.line("  simulators reach this as localhost — they share the Mac's network stack.")
        Log.line("")
    case .failed(let error):
        Log.line("✗ listener failed: \(error)")
        exit(1)
    default:
        break
    }
}

listener.newConnectionHandler = { connection in
    let peer = Peer(
        connection: connection,
        onMessage: { message, peer in store.handle(message, from: peer) },
        onClose: { peer in store.disconnect(peer) }
    )
    store.accept(peer)
    peer.start(on: queue)
}

listener.start(queue: queue)
dispatchMain()
