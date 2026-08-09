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

    /// Local personal bests for Normal / Loop / Daily. Observed separately by the leaderboard panel.
    let personalBests: PersonalBestStore

    /// Game Center submit/load. Tests may override submission via `scoreSubmitter`.
    let gameCenter: GameCenterService
    private let scoreSubmitterOverride: (any GameCenterSubmitting)?

    @Published var isPlaying: Bool = false
    @Published var isGameOver: Bool = false
    @Published var immersiveSpaceOpen: Bool = false

    // MARK: - Level select draft (committed via resolvedPlayMode on Start)

    @Published var playKind: PlayModeKind = .normal
    @Published var soloEnvironment: EnvironmentID = .emberRun
    @Published var playlistEnvironments: Set<EnvironmentID> = [.emberRun, .summitStep, .lowCrawl]
    /// Nil = random start from the selected playlist set.
    @Published var playlistStart: EnvironmentID? = nil

    /// Optional passthrough room dimming (currently unused by the biome roster).
    @Published var prefersRoomDimming: Bool = false

    /// Bumped on each restart so the immersive session can reset run content (not pose).
    @Published private(set) var runID: Int = 0

    /// Which metrics improved on the most recent finished run (nil if playlist / no board).
    @Published private(set) var lastPersonalBestUpdate: PersonalBestUpdate?

    /// Default args are created inside the body — default-parameter expressions are nonisolated
    /// and cannot call `@MainActor` initializers like `PersonalBestStore()` / `GameCenterService()`.
    init(
        personalBests: PersonalBestStore? = nil,
        gameCenter: GameCenterService? = nil,
        scoreSubmitter: (any GameCenterSubmitting)? = nil
    ) {
        let bests = personalBests ?? PersonalBestStore()
        let center = gameCenter ?? GameCenterService()
        self.personalBests = bests
        self.gameCenter = center
        self.scoreSubmitterOverride = scoreSubmitter
        center.attachPersonalBests(bests)
    }

    private var activeScoreSubmitter: any GameCenterSubmitting {
        scoreSubmitterOverride ?? gameCenter
    }

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
        lastPersonalBestUpdate = nil
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
        recordPersonalBestsIfNeeded()
    }

    /// Persists local bests and submits to Game Center for Normal, Loop, and Daily.
    private func recordPersonalBestsIfNeeded() {
        guard let board = LeaderboardBoard.matching(resolvedPlayMode) else {
            lastPersonalBestUpdate = nil
            return
        }
        lastPersonalBestUpdate = personalBests.record(
            category: board.categoryKey,
            score: stats.score,
            coins: stats.coinsCollected
        )
        activeScoreSubmitter.submitRun(board: board, score: stats.score, coins: stats.coinsCollected)
    }
}
