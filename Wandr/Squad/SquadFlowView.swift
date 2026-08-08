// SquadFlowView.swift Wandr The room, whatever phase it is in. The leader and the joiners run this same switch — the phase is on the wire, so all three devices change screen on the same snapshot. They differ only in what the last two phases mean: at `adjusting` the leader is arranging the timeline and everyone else is watching them do it, and at `published` the leader has already opened the summary locally while the joiners get it here.

import SwiftUI

struct SquadFlowView: View {
    let room: SquadRoom

    /// Leaving the room. `nil` for a joiner mid-flow, who has nothing behind them.
    var onCancel: (() -> Void)?

    /// Leader only: every slot has a winner. Hand the winners up so curation can open the schedule.
    var onSettled: (([(slotID: String, candidate: Candidate)]) -> Void)?

    /// Leader only: the relay never came up. Fall back to voting on this device.
    var onFallBackOffline: (() -> Void)?

    /// Held rather than rebuilt: in live mode a `PollSession` is a window onto the room, and a new one per render would be a new window every frame. Created once here because it opens nothing — unlike `SquadRoom`, which must never be built inside a view.
    @State private var session: PollSession?

    var body: some View {
        Group {
            switch room.phase {
            case .lobby:
                SquadLobbyView(room: room, onCancel: onCancel, onFallBackOffline: onFallBackOffline)

            case .voting:
                if let session {
                    SquadPollView(session: session)
                } else {
                    waiting("Opening the ballot…")
                }

            case .adjusting:
                // The leader does not linger here — `onSettled` lifts them straight into the schedule.
                waiting("\(room.leaderName) is finalising the timeline…")

            case .published:
                ItinerarySummaryView(blocks: room.itinerary)
            }
        }
        .task {
            if session == nil { session = PollSession(room: room) }
        }
        .onChange(of: room.phase) { _, phase in
            if phase == .adjusting, room.isLeader {
                onSettled?(room.winners())
            }
        }
        .animation(.wandrTransition, value: room.phase)
    }

    private func waiting(_ text: String) -> some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Wandr.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Wandr.pageBackground)
    }
}
