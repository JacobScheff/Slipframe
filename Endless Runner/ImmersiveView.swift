//
//  ImmersiveView.swift
//  Endless Runner
//
//  Mixed immersive play space for the base runner loop.
//

import SwiftUI
import RealityKit

struct ImmersiveView: View {
    @EnvironmentObject private var gameModel: GameModel
    @State private var gameWorld = GameWorld()

    var body: some View {
        RealityView { content in
            gameWorld.attach(to: content, gameModel: gameModel)
        } update: { _ in
            gameWorld.syncRun(with: gameModel)
        }
        .onAppear {
            gameModel.immersiveSpaceOpen = true
        }
        .onDisappear {
            gameModel.immersiveSpaceOpen = false
            gameModel.isPlaying = false
            gameWorld.teardown()
        }
    }
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environmentObject(GameModel())
}
