//
//  GameModel.swift
//  Endless Runner
//
//  Shared UI / run state for the endless-runner loop.
//

import Foundation
import SwiftUI

/// Score / coin counters observed by the HUD only.
/// Kept off `GameModel.objectWillChange` so RealityView is not invalidated mid-tick.
@MainActor
final class RunStats: ObservableObject {
    @Published var score: Int = 0
    @Published var coinsCollected: Int = 0
}

@MainActor
final class GameModel: ObservableObject {
    /// HUD metrics — do not mark these `@Published` on `GameModel` itself.
    let stats = RunStats()

    @Published var isPlaying: Bool = false
    @Published var isGameOver: Bool = false
    @Published var immersiveSpaceOpen: Bool = false

    /// Temporary debug control: Normal rotates biomes; Force locks one biome.
    @Published var environmentDebugMode: EnvironmentDebugMode = .normal

    /// Fog Hollow asks ImmersiveView to dim passthrough (Vision Pro room dimming).
    @Published var prefersRoomDimming: Bool = false

    /// Bumped on each restart so the immersive session can reset its world.
    @Published private(set) var runID: Int = 0

    /// Convenience accessors for gameplay / tests (not `@Published` on this object).
    var score: Int {
        get { stats.score }
        set { stats.score = newValue }
    }

    var coinsCollected: Int {
        get { stats.coinsCollected }
        set { stats.coinsCollected = newValue }
    }

    func startRun() {
        stats.score = 0
        stats.coinsCollected = 0
        isGameOver = false
        isPlaying = true
        prefersRoomDimming = false
        runID += 1
    }

    func addScore(_ points: Int) {
        guard isPlaying else { return }
        stats.score += points
    }

    /// Coins are a separate counter — score is distance-only.
    func collectCoin(count: Int = 1) {
        guard isPlaying else { return }
        stats.coinsCollected += count
    }

    func endRun() {
        guard isPlaying else { return }
        isPlaying = false
        isGameOver = true
        prefersRoomDimming = false
    }
}
