//
//  Endless_RunnerApp.swift
//  Endless Runner
//
//  Created by Jacob Scheff on 7/23/24.
//

import SwiftUI

@main
struct Endless_RunnerApp: App {
    @StateObject private var gameModel = GameModel()
    @State private var immersionState: ImmersionStyle = .mixed

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
    }
}
