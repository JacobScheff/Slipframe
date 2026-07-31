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

    // MARK: - Level select draft (committed via resolvedPlayMode on Start)

    @Published var playKind: PlayModeKind = .normal
    @Published var soloEnvironment: EnvironmentID = .emberRun
    @Published var playlistEnvironments: Set<EnvironmentID> = [.emberRun, .fogHollow, .lowCrawl]
    /// Nil = random start from the selected playlist set.
    @Published var playlistStart: EnvironmentID? = nil

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

    /// Mode used for the active / next run.
    var resolvedPlayMode: PlayMode {
        switch playKind {
        case .normal:
            return .normal
        case .solo:
            return .solo(soloEnvironment)
        case .playlist:
            let envs = playlistEnvironments
            let start = playlistStart.flatMap { envs.contains($0) ? $0 : nil }
            return .playlist(environments: envs, start: start)
        case .daily:
            return .daily
        }
    }

    var canStartRun: Bool {
        switch playKind {
        case .playlist:
            return !playlistEnvironments.isEmpty
        case .normal, .solo, .daily:
            return true
        }
    }

    func startRun() {
        guard canStartRun else { return }
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
