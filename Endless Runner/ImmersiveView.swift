//
//  ImmersiveView.swift
//  Endless Runner
//
//  Mixed immersive play space with an optional wall-anchored portal window.
//

import SwiftUI
import RealityKit

private enum ImmersiveAttachmentID: String {
    case playHUD
}

struct ImmersiveView: View {
    @EnvironmentObject private var gameModel: GameModel
    @State private var gameWorld = GameWorld()

    var body: some View {
        RealityView { content, attachments in
            gameWorld.attach(to: content, gameModel: gameModel)
            if let hud = attachments.entity(for: ImmersiveAttachmentID.playHUD.rawValue) {
                gameWorld.attachHUD(hud)
            }
        } update: { _, attachments in
            gameWorld.syncRun(with: gameModel)
            if let hud = attachments.entity(for: ImmersiveAttachmentID.playHUD.rawValue) {
                gameWorld.attachHUD(hud)
            }
        } attachments: {
            Attachment(id: ImmersiveAttachmentID.playHUD.rawValue) {
                PlayHUDView()
                    .environmentObject(gameModel)
            }
        }
        .preferredSurroundingsEffect(gameModel.prefersRoomDimming ? .dark : nil)
        .onAppear {
            gameModel.immersiveSpaceOpen = true
        }
        .onDisappear {
            gameModel.immersiveSpaceOpen = false
            gameModel.isPlaying = false
            gameModel.prefersRoomDimming = false
            gameWorld.teardown()
        }
    }
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environmentObject(GameModel())
}
