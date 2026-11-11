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
    @StateObject private var tutorial = SpatialTutorial()
    @State private var tutorialSubscription: EventSubscription?

    private enum Panel: Hashable {
        case console, hud, tutorial
    }

    var body: some View {
        RealityView { content, attachments in
            await BiomeAssetCatalog.preload()
            guard !Task.isCancelled else { return }
            gameWorld.attach(to: content, gameModel: gameModel)
            tutorialSubscription = content.subscribe(to: SceneEvents.Update.self) { event in
                guard gameModel.showsTutorial else { return }
                tutorial.tick(event.deltaTime, tracking: gameWorld.tutorialTracking())
            }
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
            Attachment(id: Panel.tutorial) {
                TutorialControls(tutorial: tutorial, close: {
                    gameModel.showsTutorial = false
                }, startNormal: {
                    tutorial.stop()
                    gameModel.showsTutorial = false
                    gameModel.playKind = .normal
                    gameModel.startRun()
                })
            }
            Attachment(id: Panel.hud) {
                RunHUD(model: gameModel, stats: gameModel.stats)
            }
        }
        .gesture(SpatialTapGesture().targetedToAnyEntity().onEnded { value in
            guard gameModel.showsTutorial else { return }
            tutorial.tap(value.entity)
        })
        .onChange(of: tutorial.index) { _, _ in
            if gameModel.showsTutorial { gameWorld.pulseTutorialRoom() }
        }
        .onChange(of: gameModel.showsTutorial) { _, showing in
            if showing {
                tutorial.begin(head: gameWorld.tutorialTracking().head, surface: gameWorld.tutorialSurfacePoint())
                gameWorld.pulseTutorialRoom()
            }
            else { tutorial.stop() }
        }
        .preferredSurroundingsEffect(gameModel.prefersRoomDimming ? .dark : nil)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { gameModel.gameCenter.refreshAuthState() }
            else if gameModel.showsTutorial { tutorial.paused = true }
        }
        .onDisappear {
            isWorldReady = false
            tutorialSubscription = nil
            tutorial.remove()
            gameModel.showsTutorial = false
            gameModel.isPlaying = false
            gameModel.isOffPlayfield = false
            dismissWindow(id: GameCenterAuthWindow.id)
            gameWorld.teardown()
        }
    }

    private func syncPanels(_ attachments: RealityViewAttachments) {
        tutorial.reduceMotion = reduceMotion
        tutorial.mount(in: gameWorld.root, panel: attachments.entity(for: Panel.tutorial))
        tutorial.root.isEnabled = gameModel.showsTutorial
        tutorial.controls.isEnabled = gameModel.showsTutorial
        attachments.entity(for: Panel.console)?.isEnabled = !gameModel.showsTutorial
        gameWorld.setTutorialVisible(gameModel.showsTutorial)
        gameWorld.syncInterface(
            console: attachments.entity(for: Panel.console),
            hud: attachments.entity(for: Panel.hud),
            reduceMotion: reduceMotion
        )
    }
}
