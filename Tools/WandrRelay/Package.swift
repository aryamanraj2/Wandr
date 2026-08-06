// swift-tools-version: 5.9
// WandrRelay — the loopback room server for the live squad poll. Deliberately *not* part of the Xcode project: it is a Mac process you run in a terminal while three simulators talk to it over ws://localhost:8787. Every iOS Simulator shares the host Mac's network stack, so `localhost` inside a sim is this machine — which is the whole reason the demo needs no discovery, no Bonjour and no permissions.
//
//   swift run WandrRelay
//
// The two files under Sources/WandrRelay/Shared are symlinks into the app. There is exactly one definition of the wire protocol and one definition of `PollOptionID` / `ParticipantID`, so the relay and the app cannot drift apart.

import PackageDescription

let package = Package(
    name: "WandrRelay",
    platforms: [.macOS(.v14)],
    targets: [
        // Tools version 5.9 keeps this on Swift language mode 5 — the same mode the app builds in, which matters because the two Shared/ files are compiled by both.
        .executableTarget(name: "WandrRelay", path: "Sources/WandrRelay")
    ]
)
