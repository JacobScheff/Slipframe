//
//  GameModel.swift
//  Endless Runner
//
//  Shared UI / run state for the endless-runner loop.
//

import Foundation
import SwiftUI

@MainActor
final class GameModel: ObservableObject {
    @Published var score: Int = 0
    @Published var coinsCollected: Int = 0
    @Published var isPlaying: Bool = false
    @Published var isGameOver: Bool = false
    @Published var immersiveSpaceOpen: Bool = false

    /// Temporary debug control: Normal rotates biomes; Force locks one biome.
    @Published var environmentDebugMode: EnvironmentDebugMode = .normal

    /// Fog Hollow asks ImmersiveView to dim passthrough (Vision Pro room dimming).
    @Published var prefersRoomDimming: Bool = false

    /// Bumped on each restart so the immersive session can reset its world.
    @Published private(set) var runID: Int = 0

    func startRun() {
        score = 0
        coinsCollected = 0
        isGameOver = false
        isPlaying = true
        prefersRoomDimming = false
        runID += 1
    }

    func addScore(_ points: Int) {
        guard isPlaying else { return }
        score += points
    }

    func collectCoin(points: Int = 10) {
        guard isPlaying else { return }
        coinsCollected += 1
        score += points
    }

    func endRun() {
        guard isPlaying else { return }
        isPlaying = false
        isGameOver = true
        prefersRoomDimming = false
    }
}
