//
//  ContentView.swift
//  Endless Runner
//
//  Launcher window: open / leave the immersive play space.
//  Score and run controls live on the track-anchored HUD.
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

            Text(statusText)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if !gameModel.immersiveSpaceOpen {
                Button("Enter Play Space") {
                    Task {
                        await openImmersiveSpace(id: "RunnerSpace")
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("Score and coins are on the panel above the track.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Leave Play Space") {
                    Task {
                        await dismissImmersiveSpace()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .frame(minWidth: 320, minHeight: 200)
    }

    private var statusText: String {
        if !gameModel.immersiveSpaceOpen {
            return "Open the play space to begin.\nThe score panel stays fixed above the track."
        }
        return "Play space open."
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environmentObject(GameModel())
}
