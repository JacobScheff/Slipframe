//
//  EnvironmentDirector.swift
//  Endless Runner
//
//  Owns biome timing, random/forced selection, and palette blending.
//  Music hooks fire here; GameMusic can later swap in real tracks.
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

    private var elapsedInEnvironment: Float = 0
    private var blendElapsed: Float = EnvironmentCatalog.ambienceLerpSeconds
    private var blendFrom: EnvironmentPalette
    private var telegraphRemaining: Float = 0
    private var duckGatesSpawnedThisVisit = 0
    private var debugMode: EnvironmentDebugMode = .normal

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

    func beginRun(debugMode: EnvironmentDebugMode) {
        self.debugMode = debugMode
        let start: EnvironmentID
        switch debugMode {
        case .normal:
            start = .emberRun
        case .force(let id):
            start = id
        }
        enter(start, telegraph: false, announceMusic: true)
    }

    /// Call when the HUD debug mode changes mid-session.
    func applyDebugMode(_ mode: EnvironmentDebugMode) {
        debugMode = mode
        switch mode {
        case .normal:
            break
        case .force(let id):
            if id != currentID {
                enter(id, telegraph: true, announceMusic: true)
            }
        }
    }

    func update(deltaTime: Float) -> EnvironmentFrame {
        var didEnter = false
        var previous: EnvironmentID?

        elapsedInEnvironment += deltaTime
        if telegraphRemaining > 0 {
            telegraphRemaining = max(0, telegraphRemaining - deltaTime)
        }

        if case .force(let forced) = debugMode {
            if forced != currentID {
                previous = currentID
                enter(forced, telegraph: true, announceMusic: true)
                didEnter = true
            }
        } else if elapsedInEnvironment >= EnvironmentCatalog.switchInterval {
            let next = Self.randomNext(excluding: currentID)
            previous = currentID
            enter(next, telegraph: true, announceMusic: true)
            didEnter = true
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

    static func randomNext(excluding current: EnvironmentID, rng: inout some RandomNumberGenerator) -> EnvironmentID {
        let options = EnvironmentID.allCases.filter { $0 != current }
        return options.randomElement(using: &rng) ?? .emberRun
    }

    static func randomNext(excluding current: EnvironmentID) -> EnvironmentID {
        var rng = SystemRandomNumberGenerator()
        return randomNext(excluding: current, rng: &rng)
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
            GameMusic.shared.crossfade(
                to: id.musicCue,
                duration: EnvironmentCatalog.ambienceLerpSeconds
            )
        }
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
