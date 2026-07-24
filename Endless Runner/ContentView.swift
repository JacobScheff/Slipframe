//
//  ContentView.swift
//  Endless Runner
//
//  Simple window HUD: open immersive space, start / restart, show score.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var gameModel: GameModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    var body: some View {
        VStack(spacing: 20) {
            Text("Endless Runner")
                .font(.largeTitle)

            Text(scoreText)
                .font(.title)
                .monospacedDigit()

            Text(statusText)
                .foregroundStyle(.secondary)

            if !gameModel.immersiveSpaceOpen {
                Button("Enter Play Space") {
                    Task {
                        await openImmersiveSpace(id: "RunnerSpace")
                    }
                }
                .buttonStyle(.borderedProminent)
            } else if gameModel.isGameOver {
                Button("Restart") {
                    gameModel.startRun()
                }
                .buttonStyle(.borderedProminent)

                Button("Leave Play Space") {
                    Task {
                        await dismissImmersiveSpace()
                    }
                }
            } else if !gameModel.isPlaying {
                Button("Start Run") {
                    gameModel.startRun()
                }
                .buttonStyle(.borderedProminent)

                Button("Leave Play Space") {
                    Task {
                        await dismissImmersiveSpace()
                    }
                }
            } else {
                Text("Dodge red walls with your body.\nGrab gold coins with your hands.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                Button("End Run") {
                    gameModel.endRun()
                }
            }
        }
        .padding(32)
        .frame(minWidth: 360, minHeight: 280)
    }

    private var scoreText: String {
        "Score: \(gameModel.score)"
    }

    private var statusText: String {
        if !gameModel.immersiveSpaceOpen {
            return "Open the play space to begin."
        }
        if gameModel.isGameOver {
            return "Hit a wall — run over."
        }
        if gameModel.isPlaying {
            return "Running…"
        }
        return "Ready."
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environmentObject(GameModel())
}
