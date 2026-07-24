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
            Text("Dodge walls with your body.\nGrab gold coins with your hands.")
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
        return "Ready."
    }
}

#Preview {
    PlayHUDView()
        .environmentObject(GameModel())
}
