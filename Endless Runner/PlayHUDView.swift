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
        VStack(spacing: 14) {
            Text("Endless Runner")
                .font(.title2.weight(.semibold))

            HStack(spacing: 28) {
                labeledValue(title: "Score", value: "\(gameModel.score)")
                labeledValue(title: "Coins", value: "\(gameModel.coinsCollected)")
            }

            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            controls
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .frame(minWidth: 320)
        .glassBackgroundEffect()
    }

    @ViewBuilder
    private var controls: some View {
        if gameModel.isGameOver {
            Button("Restart") {
                gameModel.startRun()
            }
            .buttonStyle(.borderedProminent)
        } else if !gameModel.isPlaying {
            Button("Start Run") {
                gameModel.startRun()
            }
            .buttonStyle(.borderedProminent)
        } else {
            Text("Dodge walls with head and hands.\nGrab gold coins with your hands.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("End Run") {
                gameModel.endRun()
            }
        }
    }

    private func labeledValue(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title.monospacedDigit().weight(.bold))
        }
        .frame(minWidth: 90)
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
