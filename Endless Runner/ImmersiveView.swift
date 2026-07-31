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
    case levelSelect
    case leaderboard
}

struct ImmersiveView: View {
    @EnvironmentObject private var gameModel: GameModel
    @State private var gameWorld = GameWorld()

    /// Side panels show between runs; hide while a run is active.
    private var showSidePanels: Bool {
        !gameModel.isPlaying
    }

    var body: some View {
        RealityView { content, attachments in
            gameWorld.attach(to: content, gameModel: gameModel)
            attachPanels(from: attachments)
        } update: { _, attachments in
            gameWorld.syncRun(with: gameModel)
            attachPanels(from: attachments)
            gameWorld.setSidePanelsVisible(showSidePanels)
        } attachments: {
            Attachment(id: ImmersiveAttachmentID.playHUD.rawValue) {
                PlayHUDView()
                    .environmentObject(gameModel)
                    .environmentObject(gameModel.stats)
            }
            Attachment(id: ImmersiveAttachmentID.levelSelect.rawValue) {
                LevelSelectView()
                    .environmentObject(gameModel)
                    .opacity(showSidePanels ? 1 : 0)
                    .allowsHitTesting(showSidePanels)
            }
            Attachment(id: ImmersiveAttachmentID.leaderboard.rawValue) {
                LeaderboardPanelView()
                    .opacity(showSidePanels ? 1 : 0)
                    .allowsHitTesting(showSidePanels)
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
        .onChange(of: gameModel.playKind) { _, _ in
            gameWorld.previewPlayMode(gameModel.resolvedPlayMode)
        }
        .onChange(of: gameModel.soloEnvironment) { _, _ in
            gameWorld.previewPlayMode(gameModel.resolvedPlayMode)
        }
        .onChange(of: gameModel.playlistEnvironments) { _, _ in
            gameWorld.previewPlayMode(gameModel.resolvedPlayMode)
        }
        .onChange(of: gameModel.playlistStart) { _, _ in
            gameWorld.previewPlayMode(gameModel.resolvedPlayMode)
        }
    }

    private func attachPanels(from attachments: RealityViewAttachments) {
        if let hud = attachments.entity(for: ImmersiveAttachmentID.playHUD.rawValue) {
            gameWorld.attachHUD(hud)
        }
        if let level = attachments.entity(for: ImmersiveAttachmentID.levelSelect.rawValue) {
            gameWorld.attachLevelSelect(level)
        }
        if let board = attachments.entity(for: ImmersiveAttachmentID.leaderboard.rawValue) {
            gameWorld.attachLeaderboard(board)
        }
    }
}

#Preview(immersionStyle: .mixed) {
    let model = GameModel()
    return ImmersiveView()
        .environmentObject(model)
}
