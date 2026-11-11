//
//  ImmersiveView.swift
//  Slipframe
//
//  Mixed immersive play space with an optional wall-anchored portal window.
//

import SwiftUI
import RealityKit

struct ImmersiveView: View {
    @EnvironmentObject private var gameModel: GameModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var gameWorld = GameWorld()
    @State private var isWorldReady = false

    private enum Panel: Hashable {
        case console, hud
    }

    var body: some View {
        RealityView { content, attachments in
            await BiomeAssetCatalog.preload()
            guard !Task.isCancelled else { return }
            gameWorld.attach(to: content, gameModel: gameModel)
            gameWorld.syncRun(with: gameModel)
            syncPanels(attachments)
            isWorldReady = true
        } update: { _, attachments in
            guard isWorldReady else { return }
            gameWorld.syncRun(with: gameModel)
            syncPanels(attachments)
            gameWorld.setTrackVisible(gameModel.showsTrack)
        } attachments: {
            Attachment(id: Panel.console) {
                RunConsole(model: gameModel, recenter: {
                    gameWorld.recalibratePlayfield()
                }, signIn: {
                    openWindow(id: GameCenterAuthWindow.id, value: "sign-in")
                })
            }
            Attachment(id: Panel.hud) {
                RunHUD(model: gameModel, stats: gameModel.stats)
            }
        }
        .preferredSurroundingsEffect(gameModel.prefersRoomDimming ? .dark : nil)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { gameModel.gameCenter.refreshAuthState() }
        }
        .onDisappear {
            isWorldReady = false
            gameModel.isPlaying = false
            gameModel.isOffPlayfield = false
            dismissWindow(id: GameCenterAuthWindow.id)
            gameWorld.teardown()
        }
    }

    private func syncPanels(_ attachments: RealityViewAttachments) {
        gameWorld.syncInterface(
            console: attachments.entity(for: Panel.console),
            hud: attachments.entity(for: Panel.hud),
            reduceMotion: reduceMotion
        )
    }
}
