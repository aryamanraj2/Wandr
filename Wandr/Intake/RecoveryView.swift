//
//  RecoveryView.swift
//  Wandr
//
//  Docs recovery state: the only fallback when a summary can't be supplied. There is no
//  mock chat, no transcript import, no in-app summarizer — the host is simply invited to
//  ask Siri to send the summary again.
//

import SwiftUI

struct RecoveryView: View {
    let inbox: IntakeInbox
    let reason: RecoveryReason

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Wandr.secondaryText)

            Text("Let’s try that again")
                .font(.wandrTitle(24))
                .foregroundStyle(Wandr.primaryText)

            Text(reason.message)
                .font(.body)
                .foregroundStyle(Wandr.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Metrics.gutter + 8)
        .background(Wandr.pageBackground)
        .safeAreaBar(edge: .bottom) {
            VStack(spacing: 10) {
                Button {
                    inbox.returnToAwaiting()
                } label: {
                    Text("Back to start")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)

                Button {
                    inbox.openShortcutSetup()
                } label: {
                    Text("Re-check chat import setup")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 2)
                }
                .buttonStyle(.glass)
            }
            .tint(Wandr.ink)
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 8)
        }
        .tint(Wandr.ink)
    }
}

#Preview {
    RecoveryView(inbox: IntakeInbox(), reason: .emptySummary)
}
