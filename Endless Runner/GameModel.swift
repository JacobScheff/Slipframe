//
//  GameModel.swift
//  Slipframe
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
    /// HUD metrics — do not mark these `@Published` on `GameModel` itself.
    let stats = RunStats()

    /// Local personal bests for Normal / Loop / Daily. Observed separately by the leaderboard panel.
    let personalBests: PersonalBestStore

    /// Game Center submit/load. Tests may override submission via `scoreSubmitter`.
    let gameCenter: GameCenterService
    private let scoreSubmitterOverride: (any GameCenterSubmitting)?
    private let defaults: UserDefaults
    private let tutorialCompletedKey: String
    private let showsTrackKey: String
    /// Carries fractional risk/Flow rewards so per-meter score ticks stay mathematically fair.
    private var scoreRemainder: Float = 0

    @Published var isPlaying: Bool = false
    @Published var isGameOver: Bool = false
    /// Delayed until the crash hold and field-collapse animation have completed.
    @Published private(set) var isGameOverMenuVisible: Bool = false
    @Published var immersiveSpaceOpen: Bool = false
    /// True during Normal mode's wordless three-rift recovery/choice event.
    @Published var isChoosingPortal: Bool = false

    /// Floor track slab is visual-only — play volume is unchanged when this is off.
    @Published var showsTrack: Bool {
        didSet { defaults.set(showsTrack, forKey: showsTrackKey) }
    }

    /// True while the headset is outside the logical play rectangle during a run.
    @Published var isOffPlayfield: Bool = false

    /// True while a guided tutorial run is active (soft hits, no score).
    @Published private(set) var isTutorialRun: Bool = false

    // MARK: - Tutorial overlay (lazy-locked attachment)

    @Published var tutorialOverlayTitle: String = ""
    @Published var tutorialOverlayBody: String = ""
    @Published var tutorialOverlayOpacity: Float = 0
    @Published var tutorialBannerText: String? = nil
    @Published var tutorialBannerScale: Float = 1
    @Published var tutorialBannerOpacity: Float = 0
    @Published var tutorialBannerGlow: Float = 0
    @Published var tutorialBannerExit: Float = 0
    /// After tutorial outro, menu chrome rises into place once.
    @Published var pendingMenuReveal: Bool = false

    // MARK: - Level select draft (committed via resolvedPlayMode on Start)

    @Published var playKind: PlayModeKind = .normal
    @Published var soloEnvironment: EnvironmentID = .emberRun
    @Published var playlistEnvironments: Set<EnvironmentID> = [.emberRun, .summitStep, .lowCrawl]
    /// Nil = random start from the selected playlist set.
    @Published var playlistStart: EnvironmentID? = nil

    /// Fog / Summit Step asks ImmersiveView to dim passthrough when density > 0.
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
        scoreSubmitter: (any GameCenterSubmitting)? = nil,
        defaults: UserDefaults? = nil,
        tutorialCompletedKey: String = "tutorial.completed.v1",
        showsTrackKey: String = "settings.showsTrack.v1"
    ) {
        let bests = personalBests ?? PersonalBestStore()
        let center = gameCenter ?? GameCenterService()
        self.personalBests = bests
        self.gameCenter = center
        self.scoreSubmitterOverride = scoreSubmitter
        self.defaults = defaults ?? .standard
        self.tutorialCompletedKey = tutorialCompletedKey
        self.showsTrackKey = showsTrackKey
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

    var hasCompletedTutorial: Bool {
        get { defaults.bool(forKey: tutorialCompletedKey) }
        set { defaults.set(newValue, forKey: tutorialCompletedKey) }
    }

    /// Mode used for the active / next run.
    var resolvedPlayMode: PlayMode {
        if isTutorialRun { return .tutorial }
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
        if isTutorialRun { return true }
        switch playKind {
        case .playlist:
            return !playlistEnvironments.isEmpty
        case .normal, .solo, .daily:
            return true
        }
    }

    func startRun() {
        guard canStartRun else { return }
        beginPlayback(tutorial: false)
    }

    func startTutorial() {
        beginPlayback(tutorial: true)
    }

    /// Soft exit from tutorial — returns to Ready (not game-over).
    func finishTutorial(markCompleted: Bool = true, revealMenu: Bool = true) {
        guard isTutorialRun else { return }
        isPlaying = false
        isGameOver = false
        isTutorialRun = false
        prefersRoomDimming = false
        isOffPlayfield = false
        clearTutorialOverlay()
        pendingMenuReveal = revealMenu
        if markCompleted {
            hasCompletedTutorial = true
        }
    }

    /// Stop playback and arm the normal game-over field clear; menu returns after dissolve.
    func skipTutorial() {
        guard isTutorialRun, isPlaying else { return }
        // Leaving mid-track — stop the master cue so the menu isn't under a half-song.
        if GameMusic.shared.currentCue == TutorialMusic.cue {
            GameMusic.shared.stop()
        }
        clearTutorialOverlay()
        isPlaying = false
        isGameOver = true
        isChoosingPortal = false
        prefersRoomDimming = false
        isOffPlayfield = false
        // Keep `isTutorialRun` true so HUD/panels stay in tutorial-skip mode until
        // `finalizeTutorialSkip()` runs after walls/coins dissolve.
    }

    /// Called by GameWorld once the post-skip dissolve finishes.
    func finalizeTutorialSkip() {
        guard isTutorialRun else { return }
        isTutorialRun = false
        isGameOver = false
        isPlaying = false
        prefersRoomDimming = false
        isOffPlayfield = false
        hasCompletedTutorial = true
        pendingMenuReveal = true
        clearTutorialOverlay()
    }

    func consumeMenuReveal() {
        pendingMenuReveal = false
    }

    func addScore(_ points: Int) {
        guard isPlaying, !isTutorialRun else { return }
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
        guard isPlaying, !isTutorialRun else { return }
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
        guard isPlaying, !isTutorialRun else { return }
        stats.flow = min(100, stats.flow + max(0, amount))
        stats.highestFlow = max(stats.highestFlow, stats.flow)
    }

    func decayFlow(_ amount: Int = 1) {
        guard isPlaying, !isTutorialRun else { return }
        stats.flow = max(0, stats.flow - max(0, amount))
    }

    func registerNearMiss() {
        guard isPlaying, !isTutorialRun else { return }
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
        guard isPlaying, !isTutorialRun else { return }
        stats.portalsCrossed += 1
    }

    func endRun() {
        guard isPlaying else { return }
        // Tutorial never hard-fails into game-over.
        if isTutorialRun {
            finishTutorial(markCompleted: false)
            return
        }
        isGameOverMenuVisible = false
        isGameOver = true
        isPlaying = false
        isChoosingPortal = false
        prefersRoomDimming = false
        isOffPlayfield = false
        recordPersonalBestsIfNeeded()
    }

    /// Called by GameWorld after all failed-run geometry has moved out of view.
    func revealGameOverMenu() {
        guard isGameOver, !isGameOverMenuVisible else { return }
        pendingMenuReveal = true
        isGameOverMenuVisible = true
    }

    func applyTutorialOverlay(
        title: String,
        body: String,
        opacity: Float,
        banner: TutorialSuccessBanner?
    ) {
        if tutorialOverlayTitle != title { tutorialOverlayTitle = title }
        if tutorialOverlayBody != body { tutorialOverlayBody = body }
        if tutorialOverlayOpacity != opacity { tutorialOverlayOpacity = opacity }
        if let banner {
            if tutorialBannerText != banner.text { tutorialBannerText = banner.text }
            if tutorialBannerScale != banner.scale { tutorialBannerScale = banner.scale }
            if tutorialBannerOpacity != banner.opacity { tutorialBannerOpacity = banner.opacity }
            if tutorialBannerGlow != banner.pulse { tutorialBannerGlow = banner.pulse }
            if tutorialBannerExit != banner.exit { tutorialBannerExit = banner.exit }
        } else {
            if tutorialBannerText != nil { tutorialBannerText = nil }
            if tutorialBannerOpacity != 0 { tutorialBannerOpacity = 0 }
            if tutorialBannerGlow != 0 { tutorialBannerGlow = 0 }
            if tutorialBannerExit != 0 { tutorialBannerExit = 0 }
            if tutorialBannerScale != 1 { tutorialBannerScale = 1 }
        }
    }

    func clearTutorialOverlay() {
        tutorialOverlayTitle = ""
        tutorialOverlayBody = ""
        tutorialOverlayOpacity = 0
        tutorialBannerText = nil
        tutorialBannerScale = 1
        tutorialBannerOpacity = 0
        tutorialBannerGlow = 0
        tutorialBannerExit = 0
    }

    private func beginPlayback(tutorial: Bool) {
        if !tutorial {
            guard canStartRun else { return }
        }
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
        isGameOverMenuVisible = false
        isChoosingPortal = false
        isPlaying = true
        isGameOver = false
        isTutorialRun = tutorial
        prefersRoomDimming = false
        isOffPlayfield = false
        lastPersonalBestUpdate = nil
        pendingMenuReveal = false
        clearTutorialOverlay()
        // Seed coaching opacity immediately so Skip isn't hidden for a frame on auto-start.
        if tutorial {
            tutorialOverlayOpacity = 1
        }
        runID += 1
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
