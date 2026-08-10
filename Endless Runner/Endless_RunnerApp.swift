//
//  Endless_RunnerApp.swift
//  Slipframe
//
//  Created by Jacob Scheff on 7/23/24.
//

import RealityKit
import SwiftUI

@main
@MainActor
struct Endless_RunnerApp: App {
    @StateObject private var gameModel: GameModel
    @State private var immersionState: ImmersionStyle = .mixed

    init() {
        _gameModel = StateObject(wrappedValue: GameModel())
        // Must happen before any RealityView loads entities that carry it.
        RiftMoteComponent.registerComponent()
    }

    var body: some SwiftUI.Scene {
        // Immersive-first: Info.plist preferred scene role launches this space.
        ImmersiveSpace(id: "RunnerSpace") {
            ImmersiveView()
                .environmentObject(gameModel)
                .environmentObject(gameModel.personalBests)
                .environmentObject(gameModel.gameCenter)
                .onAppear {
                    gameModel.gameCenter.start()
                }
        }
        .immersionStyle(selection: $immersionState, in: .mixed)

        // Presentation anchor for GameKit sign-in (UIKit modal). Opened on demand.
        WindowGroup(id: GameCenterAuthScene.id) {
            GameCenterAuthWindow()
                .environmentObject(gameModel.gameCenter)
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)
    }
}
