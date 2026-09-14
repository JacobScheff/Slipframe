//
//  ImmersiveView.swift
//  Slipframe
//
//  Mixed immersive play space with an optional wall-anchored portal window.
//

import SwiftUI
import RealityKit

private enum ImmersiveAttachmentID: String {
    case playHUD
    case menuConsole
    case tutorialOverlay
}

struct ImmersiveView: View {
    @EnvironmentObject private var gameModel: GameModel
    @EnvironmentObject private var gameCenter: GameCenterService
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var gameWorld = GameWorld()
    /// Prevents `openWindow` from spawning duplicate Game Center host windows.
    @State private var isGameCenterAuthWindowOpen = false
    @State private var didOfferAutoTutorial = false

    /// Console shows between runs; hide while a run is active.
    /// Also stay hidden while a skipped tutorial dissolves the field.
    private var showMenuConsole: Bool {
        guard !gameModel.isPlaying else { return false }
        if gameModel.isTutorialRun, gameModel.isGameOver { return false }
        if gameModel.isGameOver { return gameModel.isGameOverMenuVisible }
        return true
    }

    private var showTutorialOverlay: Bool {
        gameModel.isTutorialRun
            || gameModel.tutorialOverlayOpacity > 0.02
            || gameModel.tutorialBannerOpacity > 0.02
    }

    var body: some View {
        RealityView { content, attachments in
            gameWorld.attach(to: content, gameModel: gameModel)
            attachPanels(from: attachments)
        } update: { _, attachments in
            gameWorld.syncRun(with: gameModel)
            attachPanels(from: attachments)
            gameWorld.setMenuChromeVisible(showMenuConsole)
            gameWorld.setTutorialOverlayVisible(showTutorialOverlay)
            gameWorld.setTrackVisible(gameModel.showsTrack)
        } attachments: {
            Attachment(id: ImmersiveAttachmentID.playHUD.rawValue) {
                PlayHUDView()
                    .environmentObject(gameModel)
                    .environmentObject(gameModel.stats)
            }
            Attachment(id: ImmersiveAttachmentID.menuConsole.rawValue) {
                MenuConsoleView()
                    .environmentObject(gameModel)
                    .environmentObject(gameModel.personalBests)
                    .environmentObject(gameModel.gameCenter)
                    .opacity(showMenuConsole ? 1 : 0)
                    .allowsHitTesting(showMenuConsole)
            }
            Attachment(id: ImmersiveAttachmentID.tutorialOverlay.rawValue) {
                TutorialOverlayView()
                    .environmentObject(gameModel)
                    .opacity(showTutorialOverlay ? 1 : 0)
                    .allowsHitTesting(false)
            }
        }
        .preferredSurroundingsEffect(gameModel.prefersRoomDimming ? .dark : nil)
        .onAppear {
            gameModel.immersiveSpaceOpen = true
            gameCenter.start()
            syncGameCenterAuthWindow()
            offerAutoTutorialIfNeeded()
        }
        .onDisappear {
            gameModel.immersiveSpaceOpen = false
            gameModel.isPlaying = false
            gameModel.prefersRoomDimming = false
            if gameModel.isTutorialRun {
                gameModel.finishTutorial(markCompleted: false, revealMenu: false)
            }
            isGameCenterAuthWindowOpen = false
            dismissWindow(id: GameCenterAuthScene.id)
            gameWorld.teardown()
        }
        .onChange(of: gameCenter.needsSignInPresentation) { _, _ in
            syncGameCenterAuthWindow()
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

    private func offerAutoTutorialIfNeeded() {
        guard !didOfferAutoTutorial else { return }
        didOfferAutoTutorial = true
        guard !gameModel.hasCompletedTutorial else { return }
        Task { @MainActor in
            // Let the playfield snap to a real floor plane (and the console
            // mount) before diving in. First launch often has no floor yet.
            let timeoutNanoseconds: UInt64 = 4_000_000_000
            let pollNanoseconds: UInt64 = 100_000_000
            var waited: UInt64 = 0
            while !gameWorld.hasSnappedToFloor, waited < timeoutNanoseconds {
                try? await Task.sleep(nanoseconds: pollNanoseconds)
                waited += pollNanoseconds
                guard gameModel.immersiveSpaceOpen else { return }
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard gameModel.immersiveSpaceOpen,
                  !gameModel.isPlaying,
                  !gameModel.hasCompletedTutorial
            else { return }
            gameModel.startTutorial()
        }
    }

    private func syncGameCenterAuthWindow() {
        if gameCenter.needsSignInPresentation {
            guard !isGameCenterAuthWindowOpen else { return }
            isGameCenterAuthWindowOpen = true
            openWindow(id: GameCenterAuthScene.id)
        } else if isGameCenterAuthWindowOpen {
            isGameCenterAuthWindowOpen = false
            dismissWindow(id: GameCenterAuthScene.id)
        }
    }

    private func attachPanels(from attachments: RealityViewAttachments) {
        if let hud = attachments.entity(for: ImmersiveAttachmentID.playHUD.rawValue) {
            gameWorld.attachHUD(hud)
        }
        if let console = attachments.entity(for: ImmersiveAttachmentID.menuConsole.rawValue) {
            gameWorld.attachMenuConsole(console)
        }
        if let overlay = attachments.entity(for: ImmersiveAttachmentID.tutorialOverlay.rawValue) {
            gameWorld.attachTutorialOverlay(overlay)
        }
    }
}

#Preview(immersionStyle: .mixed) {
    let model = GameModel()
    return ImmersiveView()
        .environmentObject(model)
        .environmentObject(model.gameCenter)
}
