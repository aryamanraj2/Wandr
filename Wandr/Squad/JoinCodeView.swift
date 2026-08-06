// JoinCodeView.swift Wandr The door for everyone who isn't the host. Joiners never run intake — no Shortcut, no summary, no curation — so without this screen there is no way into the app's state machine at all. Six digits and a name, and they're in the room.
//
// The pad is hand-built rather than a `TextField` with `.numberPad`: the entry is exactly six digits with no editing beyond backspace, and a real keyboard here brings focus management, autocorrect and a resizing layout to a screen that needs none of them.

import SwiftUI

struct JoinCodeView: View {
    let room: SquadRoom

    @State private var digits = ""
    @State private var name: String
    @State private var submitted = false

    @FocusState private var nameFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(room: SquadRoom) {
        self.room = room
        _name = State(initialValue: room.myName)
    }

    private var code: RoomCode? { RoomCode(entering: digits) }

    /// Reject a wrong code by clearing it and saying so, rather than dropping the joiner on a dead screen.
    private var rejected: Bool { submitted && room.failure == .noSuchRoom }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                intro
                boxes
                message
                Spacer(minLength: 12)
                nameField
                pad
            }
            .padding(.horizontal, Metrics.gutter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Wandr.pageBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) {
                        if submitted { room.leave() }
                        dismiss()
                    }
                }
            }
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        }
        .tint(Wandr.brand)
        // The join succeeded the moment the room's first snapshot lands; the shell takes over from there.
        .onChange(of: room.snapshot?.version) { _, version in
            if version != nil { dismiss() }
        }
        .onChange(of: room.failure) { _, failure in
            if failure == .noSuchRoom || failure == .roomFull { digits = "" }
        }
        .animation(.wandrResponse, value: digits)
        .animation(.wandrTransition, value: submitted)
    }

    // MARK: Intro

    private var intro: some View {
        VStack(spacing: 8) {
            Text("Join the squad")
                .font(.wandrDisplay(34))
                .foregroundStyle(Wandr.primaryText)

            Text("Type the six digits the host read out.")
                .font(.subheadline)
                .foregroundStyle(Wandr.secondaryText)
        }
        .multilineTextAlignment(.center)
        .padding(.top, 10)
        .padding(.bottom, 26)
    }

    // MARK: Boxes

    private var boxes: some View {
        HStack(spacing: 10) {
            ForEach(0..<RoomCode.length, id: \.self) { index in
                let character = index < digits.count
                    ? String(Array(digits)[index])
                    : ""

                Text(character)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Wandr.primaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 62)
                    .background {
                        ConcentricRectangle(corners: .concentric(minimum: .fixed(Metrics.blockCorner)))
                            .fill(Wandr.cardSurface)
                    }
                    .overlay {
                        ConcentricRectangle(corners: .concentric(minimum: .fixed(Metrics.blockCorner)))
                            .stroke(
                                index == digits.count ? Wandr.brand.opacity(0.55) : Wandr.mist.opacity(0.5),
                                lineWidth: index == digits.count ? 2 : 1
                            )
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Room code")
        .accessibilityValue(digits.isEmpty ? "empty" : digits.map(String.init).joined(separator: " "))
    }

    // MARK: Status

    @ViewBuilder
    private var message: some View {
        Group {
            if rejected {
                Label("No room with that code.", systemImage: "exclamationmark.circle")
                    .foregroundStyle(Wandr.brand)
            } else if submitted && room.failure == .roomFull {
                Label("That room is full.", systemImage: "person.2.slash")
                    .foregroundStyle(Wandr.brand)
            } else if submitted {
                Label("Knocking…", systemImage: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(Wandr.secondaryText)
            } else {
                Color.clear
            }
        }
        .font(.footnote.weight(.medium))
        .frame(height: 22)
        .padding(.top, 14)
    }

    // MARK: Name

    private var nameField: some View {
        HStack(spacing: 12) {
            Text("You are")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Wandr.secondaryText)

            TextField("Your name", text: $name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Wandr.primaryText)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($nameFocused)
        }
        .padding(16)
        .background(WandrCardBackground())
        .padding(.bottom, 18)
    }

    // MARK: Pad

    private var pad: some View {
        VStack(spacing: 10) {
            ForEach(Self.rows, id: \.self) { row in
                HStack(spacing: 10) {
                    ForEach(row, id: \.self) { key in
                        padKey(key)
                    }
                }
            }
        }
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private func padKey(_ key: String) -> some View {
        switch key {
        case "":
            Color.clear.frame(maxWidth: .infinity).frame(height: 54)

        case "⌫":
            padButton(label: { Image(systemName: "delete.left").font(.title3) }, tint: Wandr.secondaryText) {
                if !digits.isEmpty { digits.removeLast() }
            }
            .accessibilityLabel("Delete")
            .disabled(digits.isEmpty)

        default:
            padButton(label: {
                Text(key).font(.system(size: 24, weight: .medium, design: .rounded)).monospacedDigit()
            }, tint: Wandr.primaryText) {
                guard digits.count < RoomCode.length else { return }
                digits.append(key)
                // Submitting itself, the moment there is something to submit — six digits is unambiguous, and a Join button below a full code is a tap nobody needs to make.
                if let code, !submitted {
                    nameFocused = false
                    submitted = true
                    room.join(code: code, name: name.trimmed.isEmpty ? room.myName : name.trimmed)
                }
            }
        }
    }

    private func padButton<Label: View>(
        @ViewBuilder label: () -> Label,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            label()
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background {
                    ConcentricRectangle(corners: .concentric(minimum: .fixed(Metrics.blockCorner)))
                        .fill(Wandr.cardSurface)
                }
        }
        .buttonStyle(WandrPressStyle())
    }

    private static let rows = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["", "0", "⌫"]
    ]
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
