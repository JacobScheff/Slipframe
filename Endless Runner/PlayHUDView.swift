//
//  PlayHUDView.swift
//  Endless Runner
//
//  World-anchored play / score panel fixed above the track.
//

import SwiftUI

struct PlayHUDView: View {
    @EnvironmentObject private var gameModel: GameModel
    @State private var isEnvironmentMenuOpen = false

    var body: some View {
        VStack(spacing: 28) {
            Text("Endless Runner")
                .font(.system(size: 48, weight: .semibold))

            HStack(spacing: 56) {
                labeledValue(title: "Score", value: "\(gameModel.score)")
                labeledValue(title: "Coins", value: "\(gameModel.coinsCollected)")
            }

            Text(statusText)
                .font(.title2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            controls

            debugEnvironmentPicker
        }
        .padding(.horizontal, 56)
        .padding(.vertical, 44)
        .frame(minWidth: 720)
        .glassBackgroundEffect()
        // Open menu overlays upward above the HUD so it doesn't grow the card.
        .overlay(alignment: .bottom) {
            if isEnvironmentMenuOpen {
                environmentMenuPanel
                    .padding(.bottom, 96)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .zIndex(isEnvironmentMenuOpen ? 20 : 0)
    }

    @ViewBuilder
    private var controls: some View {
        if gameModel.isGameOver {
            Button("Restart") {
                gameModel.startRun()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .font(.title2)
        } else if !gameModel.isPlaying {
            Button("Start Run") {
                gameModel.startRun()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .font(.title2)
        } else {
            Text("Dodge walls with your head and hands.\nGrab gold coins with your hands.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("End Run") {
                gameModel.endRun()
            }
            .controlSize(.large)
            .font(.title2)
        }
    }

    /// Temporary test control — keep the closed control compact like the original menu.
    private var debugEnvironmentPicker: some View {
        VStack(spacing: 10) {
            Text("Debug Environment")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isEnvironmentMenuOpen.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Text(currentEnvironmentLabel)
                        .font(.title3)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
        .padding(.top, 8)
    }

    private var environmentMenuPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            environmentOptionButton(title: "Normal (random)", value: .normal)
            ForEach(EnvironmentID.allCases) { id in
                environmentOptionButton(
                    title: "Force: \(id.displayName)",
                    value: .force(id)
                )
            }
        }
        .padding(18)
        .frame(minWidth: 520, alignment: .leading)
        .glassBackgroundEffect()
    }

    private func environmentOptionButton(title: String, value: DebugPickerValue) -> some View {
        let selected = debugModeBinding.wrappedValue == value
        return Button {
            debugModeBinding.wrappedValue = value
            withAnimation(.easeInOut(duration: 0.15)) {
                isEnvironmentMenuOpen = false
            }
        } label: {
            HStack(spacing: 16) {
                Text(title)
                    .font(.system(size: 54, weight: selected ? .bold : .medium))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 36, weight: .bold))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var currentEnvironmentLabel: String {
        switch gameModel.environmentDebugMode {
        case .normal:
            return "Normal (random)"
        case .force(let id):
            return "Force: \(id.displayName)"
        }
    }

    private var debugModeBinding: Binding<DebugPickerValue> {
        Binding(
            get: {
                switch gameModel.environmentDebugMode {
                case .normal: return .normal
                case .force(let id): return .force(id)
                }
            },
            set: { value in
                switch value {
                case .normal:
                    gameModel.environmentDebugMode = .normal
                case .force(let id):
                    gameModel.environmentDebugMode = .force(id)
                }
            }
        )
    }

    private func labeledValue(title: String, value: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 56, weight: .bold, design: .monospaced))
        }
        .frame(minWidth: 180)
    }

    private var statusText: String {
        if gameModel.isGameOver {
            return "Hit a wall — run over."
        }
        if gameModel.isPlaying {
            return "Running…"
        }
        return "Obstacles come through the portal — dodge and grab coins."
    }
}

/// Hashable picker tags for the temporary environment debug control.
private enum DebugPickerValue: Hashable {
    case normal
    case force(EnvironmentID)
}

#Preview {
    PlayHUDView()
        .environmentObject(GameModel())
}
