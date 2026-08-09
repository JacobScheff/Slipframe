//
//  EnvironmentDirector.swift
//  Endless Runner
//
//  Owns biome timing, mode-based selection, and palette blending.
//  Biome dwell time follows each track's length via GameMusic.
//

import Foundation

struct EnvironmentFrame {
    var currentID: EnvironmentID
    var profile: EnvironmentProfile
    var displayedPalette: EnvironmentPalette
    /// 1 while settled; dips toward 0 during a switch telegraph.
    var telegraphStrength: Float
    var didEnterEnvironment: Bool
    var previousID: EnvironmentID?
}

@MainActor
final class EnvironmentDirector {
    private(set) var currentID: EnvironmentID = .emberRun
    private(set) var displayedPalette: EnvironmentPalette
    private(set) var targetPalette: EnvironmentPalette
    /// Seconds to stay in the current biome (matches active track length).
    private(set) var currentSwitchInterval: Float = EnvironmentCatalog.fallbackSwitchInterval

    private var elapsedInEnvironment: Float = 0
    private var blendElapsed: Float = EnvironmentCatalog.ambienceLerpSeconds
    private var blendFrom: EnvironmentPalette
    private var telegraphRemaining: Float = 0
    private var duckGatesSpawnedThisVisit = 0
    private var playMode: PlayMode = .normal
    private var dailyRNG: SeededGenerator?

    init() {
        let starter = EnvironmentCatalog.profile(for: .emberRun)
        displayedPalette = starter.palette
        targetPalette = starter.palette
        blendFrom = starter.palette
    }

    var currentProfile: EnvironmentProfile {
        EnvironmentCatalog.profile(for: currentID)
    }

    var isTeachingLowCrawl: Bool {
        currentProfile.twist == .lowCrawl
            && duckGatesSpawnedThisVisit < currentProfile.lowCrawlTeachCount
    }

    func noteDuckGateSpawned() {
        duckGatesSpawnedThisVisit += 1
    }

    func beginRun(mode: PlayMode) {
        playMode = mode
        dailyRNG = nil

        let start: EnvironmentID
        switch mode {
        case .normal:
            start = .emberRun
        case .solo(let id):
            start = id
        case .playlist(let environments, let preferredStart):
            let pool = Array(environments)
            if let preferredStart, environments.contains(preferredStart) {
                start = preferredStart
            } else {
                start = pool.randomElement() ?? .emberRun
            }
        case .daily:
            let key = DailyChallenge.dayKey()
            var rng = DailyChallenge.makeGenerator(dayKey: key)
            start = EnvironmentID.allCases.randomElement(using: &rng) ?? .emberRun
            dailyRNG = rng
        }

        enter(start, telegraph: false, announceMusic: true)
    }

    /// Idle preview when the player changes mode selection (no music hitch).
    func previewMode(_ mode: PlayMode) {
        playMode = mode
        let start: EnvironmentID
        switch mode {
        case .normal:
            start = .emberRun
        case .solo(let id):
            start = id
        case .playlist(let environments, let preferredStart):
            if let preferredStart, environments.contains(preferredStart) {
                start = preferredStart
            } else {
                start = environments.first ?? .emberRun
            }
        case .daily:
            let preview = DailyChallenge.previewSequence(dayKey: DailyChallenge.dayKey(), count: 1)
            start = preview.first ?? .emberRun
        }
        if start != currentID {
            enter(start, telegraph: false, announceMusic: false)
        }
    }

    func update(deltaTime: Float) -> EnvironmentFrame {
        var didEnter = false
        var previous: EnvironmentID?

        elapsedInEnvironment += deltaTime
        if telegraphRemaining > 0 {
            telegraphRemaining = max(0, telegraphRemaining - deltaTime)
        }

        if case .solo(let forced) = playMode {
            if forced != currentID {
                previous = currentID
                enter(forced, telegraph: true, announceMusic: true)
                didEnter = true
            }
        } else if elapsedInEnvironment >= currentSwitchInterval {
            if let next = pickNextEnvironment(), next != currentID {
                previous = currentID
                enter(next, telegraph: true, announceMusic: true)
                didEnter = true
            } else {
                // Singleton playlist (or empty pool): hold the current biome another interval.
                elapsedInEnvironment = 0
            }
        }

        blendElapsed += deltaTime
        let blendT = min(1, blendElapsed / EnvironmentCatalog.ambienceLerpSeconds)
        displayedPalette = blendPalette(from: blendFrom, to: targetPalette, t: blendT)

        let telegraph: Float
        if telegraphRemaining > 0 {
            let u = telegraphRemaining / EnvironmentCatalog.telegraphSeconds
            telegraph = Float(sin(Double(u) * .pi))
        } else {
            telegraph = 0
        }

        return EnvironmentFrame(
            currentID: currentID,
            profile: currentProfile,
            displayedPalette: displayedPalette,
            telegraphStrength: telegraph,
            didEnterEnvironment: didEnter,
            previousID: previous
        )
    }

    /// Pure helper — `nonisolated` so daily preview / tests can call it off the main actor.
    nonisolated static func randomNext<RNG: RandomNumberGenerator>(
        excluding current: EnvironmentID,
        from pool: [EnvironmentID] = Array(EnvironmentID.allCases),
        rng: inout RNG
    ) -> EnvironmentID {
        let options = pool.filter { $0 != current }
        if options.isEmpty {
            return current
        }
        return options.randomElement(using: &rng) ?? current
    }

    nonisolated static func randomNext(
        excluding current: EnvironmentID,
        from pool: [EnvironmentID] = Array(EnvironmentID.allCases)
    ) -> EnvironmentID {
        var rng = SystemRandomNumberGenerator()
        return randomNext(excluding: current, from: pool, rng: &rng)
    }

    /// Biome dwell time for a cue: full track length, minus the crossfade so the
    /// next biome starts as the current song is fading out.
    nonisolated static func switchInterval(forTrackDuration trackDuration: Float, crossfade: Float) -> Float {
        let usable = trackDuration - crossfade
        return min(
            EnvironmentCatalog.maxSwitchInterval,
            max(EnvironmentCatalog.minSwitchInterval, usable)
        )
    }

    private func pickNextEnvironment() -> EnvironmentID? {
        switch playMode {
        case .solo:
            return nil
        case .normal:
            return Self.randomNext(excluding: currentID)
        case .playlist(let environments, _):
            let pool = Array(environments)
            guard !pool.isEmpty else { return nil }
            return Self.randomNext(excluding: currentID, from: pool)
        case .daily:
            guard var rng = dailyRNG else {
                return Self.randomNext(excluding: currentID)
            }
            let next = Self.randomNext(excluding: currentID, rng: &rng)
            dailyRNG = rng
            return next
        }
    }

    private func enter(_ id: EnvironmentID, telegraph: Bool, announceMusic: Bool) {
        currentID = id
        elapsedInEnvironment = 0
        duckGatesSpawnedThisVisit = 0
        blendFrom = displayedPalette
        targetPalette = EnvironmentCatalog.profile(for: id).palette
        blendElapsed = 0
        telegraphRemaining = telegraph ? EnvironmentCatalog.telegraphSeconds : 0
        if announceMusic {
            let trackDuration = playMusic(for: id)
            currentSwitchInterval = Self.switchInterval(
                forTrackDuration: trackDuration,
                crossfade: EnvironmentCatalog.ambienceLerpSeconds
            )
        } else {
            currentSwitchInterval = EnvironmentCatalog.fallbackSwitchInterval
        }
    }

    @discardableResult
    private func playMusic(for id: EnvironmentID) -> Float {
        let loop: Bool
        if case .solo = playMode {
            loop = true
        } else {
            loop = false
        }
        return GameMusic.shared.crossfade(
            to: id.musicCue,
            duration: EnvironmentCatalog.ambienceLerpSeconds,
            loop: loop
        )
    }

    private func blendPalette(from: EnvironmentPalette, to: EnvironmentPalette, t: Float) -> EnvironmentPalette {
        EnvironmentPalette(
            floor: from.floor.mixed(toward: to.floor, t: t),
            laneStripe: from.laneStripe.mixed(toward: to.laneStripe, t: t),
            portalRim: from.portalRim.mixed(toward: to.portalRim, t: t),
            portalVoid: from.portalVoid.mixed(toward: to.portalVoid, t: t),
            portalRail: from.portalRail.mixed(toward: to.portalRail, t: t),
            portalAccent: from.portalAccent.mixed(toward: to.portalAccent, t: t),
            ambienceBrightness: from.ambienceBrightness + (to.ambienceBrightness - from.ambienceBrightness) * t,
            fogDensity: from.fogDensity + (to.fogDensity - from.fogDensity) * t,
            fogColor: from.fogColor.mixed(toward: to.fogColor, t: t),
            wallTint: from.wallTint.mixed(toward: to.wallTint, t: t),
            wallEmissive: from.wallEmissive.mixed(toward: to.wallEmissive, t: t),
            wallOpacity: from.wallOpacity + (to.wallOpacity - from.wallOpacity) * t,
            wallEmissiveIntensity: from.wallEmissiveIntensity + (to.wallEmissiveIntensity - from.wallEmissiveIntensity) * t,
            coinTint: from.coinTint.mixed(toward: to.coinTint, t: t)
        )
    }
}
