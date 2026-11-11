//
//  GameModel.swift
//  Slipframe
//
//  Shared run state for the endless-runner loop.
//

import Foundation
import SwiftUI

/// Live run metrics.
/// Kept off `GameModel.objectWillChange` so RealityView is not invalidated mid-tick.
@MainActor
final class RunStats: ObservableObject {
    @Published var score: Int = 0
    @Published var coinsCollected: Int = 0
    @Published var flow: Int = 0
    @Published var shieldCharges: Int = 0
    @Published var risk: RiftRisk = .stable
    @Published var modifier: RiftModifier? = nil
    @Published var highestFlow: Int = 0
    @Published var nearMisses: Int = 0
    @Published var portalsCrossed: Int = 0
    @Published var shieldsBroken: Int = 0
}

@MainActor
final class GameModel: ObservableObject {
    /// Run metrics — do not mark these `@Published` on `GameModel` itself.
    let stats = RunStats()

    /// Local personal bests for Normal / Loop / Daily.
    let personalBests: PersonalBestStore

    /// Game Center submit/load. Tests may override submission via `scoreSubmitter`.
    let gameCenter: GameCenterService
    private let scoreSubmitterOverride: (any GameCenterSubmitting)?
    private let defaults: UserDefaults
    private let showsTrackKey: String
    /// Carries fractional risk/Flow rewards so per-meter score ticks stay mathematically fair.
    private var scoreRemainder: Float = 0

    @Published var isPlaying: Bool = false
    @Published var isGameOver: Bool = false
    /// True during Normal mode's wordless three-rift recovery/choice event.
    @Published var isChoosingPortal: Bool = false
    @Published var portalOptions: [RiftPortalOption] = []

    /// Floor track slab is visual-only — play volume is unchanged when this is off.
    @Published var showsTrack: Bool {
        didSet { defaults.set(showsTrack, forKey: showsTrackKey) }
    }
    @Published var showsRoomGrid: Bool {
        didSet { defaults.set(showsRoomGrid, forKey: "settings.showsRoomGrid.v1") }
    }

    /// True while the headset is outside the logical play rectangle during a run.
    @Published var isOffPlayfield: Bool = false
    @Published var playKind: PlayModeKind = .normal
    @Published var soloEnvironment: EnvironmentID = .emberRun
    @Published var playlistEnvironments: Set<EnvironmentID> = [.emberRun, .summitStep, .lowCrawl]
    /// Nil = random start from the selected playlist set.
    @Published var playlistStart: EnvironmentID? = nil

    /// Fog / Summit Step asks ImmersiveView to dim passthrough when density > 0.
    @Published var prefersRoomDimming: Bool = false

    /// Bumped on each restart so the immersive session can reset run content (not pose).
    @Published private(set) var runID: Int = 0
    @Published private(set) var fieldIsClear = true
    @Published private(set) var activeEnvironment: EnvironmentID = .emberRun
    private(set) var runDate = Date()
    private(set) var runMode: PlayMode = .normal
    private(set) var runPlaylistStart: EnvironmentID?
    private var playlistPreviewSeed = Int.random(in: 0..<1024)

    /// Which metrics improved on the most recent finished run (nil if playlist / no board).
    @Published private(set) var lastPersonalBestUpdate: PersonalBestUpdate?

    /// Default args are created inside the body — default-parameter expressions are nonisolated
    /// and cannot call `@MainActor` initializers like `PersonalBestStore()` / `GameCenterService()`.
    init(
        personalBests: PersonalBestStore? = nil,
        gameCenter: GameCenterService? = nil,
        scoreSubmitter: (any GameCenterSubmitting)? = nil,
        defaults: UserDefaults? = nil,
        showsTrackKey: String = "settings.showsTrack.v1"
    ) {
        let bests = personalBests ?? PersonalBestStore()
        let center = gameCenter ?? GameCenterService()
        self.personalBests = bests
        self.gameCenter = center
        self.scoreSubmitterOverride = scoreSubmitter
        self.defaults = defaults ?? .standard
        self.showsTrackKey = showsTrackKey
        self.showsRoomGrid = self.defaults.object(forKey: "settings.showsRoomGrid.v1") as? Bool ?? true
        if self.defaults.object(forKey: showsTrackKey) == nil {
            self.showsTrack = true
        } else {
            self.showsTrack = self.defaults.bool(forKey: showsTrackKey)
        }
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

    func previewEnvironment(on date: Date = Date()) -> EnvironmentID? {
        switch resolvedPlayMode {
        case .normal:
            return .emberRun
        case .solo(let id):
            return id
        case .playlist(let selected, let start):
            if let start { return start }
            let choices = EnvironmentID.allCases.filter { selected.contains($0) }
            guard !choices.isEmpty else { return nil }
            return choices[playlistPreviewSeed % choices.count]
        case .daily:
            return DailyChallenge.previewSequence(dayKey: DailyChallenge.dayKey(for: date), count: 1).first
        }
    }

    func togglePlaylistBiome(_ id: EnvironmentID) {
        if playlistEnvironments.contains(id) {
            playlistEnvironments.remove(id)
            if playlistStart == id { playlistStart = nil }
        } else {
            playlistEnvironments.insert(id)
        }
    }

    func enterBiome(_ id: EnvironmentID) {
        guard activeEnvironment != id else { return }
        activeEnvironment = id
    }

    func markFieldClear() {
        fieldIsClear = true
    }

    func startRun() {
        guard canStartRun, !isPlaying else { return }
        runDate = Date()
        runMode = resolvedPlayMode
        let startingBiome = previewEnvironment(on: runDate) ?? .emberRun
        runPlaylistStart = playKind == .playlist ? startingBiome : nil
        playlistPreviewSeed = Int.random(in: 0..<1024)
        activeEnvironment = startingBiome
        fieldIsClear = false
        stats.score = 0
        stats.coinsCollected = 0
        stats.flow = 0
        stats.shieldCharges = 0
        stats.risk = .stable
        stats.modifier = nil
        stats.highestFlow = 0
        stats.nearMisses = 0
        stats.portalsCrossed = 0
        stats.shieldsBroken = 0
        scoreRemainder = 0
        isChoosingPortal = false
        portalOptions = []
        isPlaying = true
        isGameOver = false
        prefersRoomDimming = false
        isOffPlayfield = false
        lastPersonalBestUpdate = nil
        runID += 1
    }

    func addScore(_ points: Int) {
        guard isPlaying else { return }
        let flowMultiplier = 1 + Float(stats.flow) / 100
        let modifierMultiplier: Float = stats.modifier == .overdrive ? 1.25 : 1
        let reward = Float(points) * stats.risk.scoreMultiplier * flowMultiplier * modifierMultiplier
        let accumulated = reward + scoreRemainder
        let wholePoints = Int(accumulated.rounded(.down))
        scoreRemainder = accumulated - Float(wholePoints)
        stats.score += wholePoints
    }

    /// Tokens remain a separate leaderboard counter while also feeding Flow.
    func collectCoin(count: Int = 1) {
        guard isPlaying else { return }
        let tokenValue = stats.modifier == .tokenSurge ? 2 : 1
        stats.coinsCollected += count * tokenValue
        addFlow((stats.modifier == .overdrive ? 8 : 5) * count)
    }

    func configureStage(risk: RiftRisk, modifier: RiftModifier?) {
        stats.risk = risk
        stats.modifier = modifier
        stats.shieldCharges = modifier == .aegis ? 1 : 0
    }

    func addFlow(_ amount: Int) {
        guard isPlaying else { return }
        stats.flow = min(100, stats.flow + max(0, amount))
        stats.highestFlow = max(stats.highestFlow, stats.flow)
    }

    func decayFlow(_ amount: Int = 1) {
        guard isPlaying else { return }
        stats.flow = max(0, stats.flow - max(0, amount))
    }

    func registerNearMiss() {
        guard isPlaying else { return }
        stats.nearMisses += 1
        let bonusGain: Int
        if stats.modifier == .closeCall {
            bonusGain = 28
        } else if stats.modifier == .overdrive {
            bonusGain = 20
        } else {
            bonusGain = 14
        }
        addFlow(bonusGain)
        addScore(stats.modifier == .closeCall ? 6 : 3)
    }

    /// Returns true when an Aegis charge absorbed the collision.
    func absorbHitIfPossible() -> Bool {
        guard stats.shieldCharges > 0 else { return false }
        stats.shieldCharges -= 1
        stats.shieldsBroken += 1
        stats.flow = max(0, stats.flow / 2)
        return true
    }

    func recordPortalCrossing() {
        guard isPlaying else { return }
        stats.portalsCrossed += 1
    }

    func endRun() {
        guard isPlaying else { return }
        isGameOver = true
        isPlaying = false
        isChoosingPortal = false
        portalOptions = []
        prefersRoomDimming = false
        isOffPlayfield = false
        recordPersonalBestsIfNeeded()
    }

    /// Persists local bests and submits to Game Center for Normal, Loop, and Daily.
    private func recordPersonalBestsIfNeeded() {
        guard let board = LeaderboardBoard.matching(runMode, on: runDate) else {
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
