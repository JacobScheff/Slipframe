//
//  PlayHUDView.swift
//  Endless Runner
//
//  World-anchored play / score panel fixed above the track.
//

import SwiftUI

struct PlayHUDView: View {
    @EnvironmentObject private var gameModel: GameModel

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

    /// Temporary test control — remove once biome QA is done.
    private var debugEnvironmentPicker: some View {
        VStack(spacing: 10) {
            Text("Debug Environment")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker("Environment Mode", selection: debugModeBinding) {
                Text("Normal (random)").tag(DebugPickerValue.normal)
                ForEach(EnvironmentID.allCases) { id in
                    Text("Force: \(id.displayName)").tag(DebugPickerValue.force(id))
                }
            }
            .pickerStyle(.menu)
            .font(.title3)
        }
        .padding(.top, 8)
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
