//
//  Endless_RunnerTests.swift
//  Endless RunnerTests
//
//  Created by Jacob Scheff on 7/23/24.
//

import XCTest
@testable import Endless_Runner
import simd

@MainActor
final class Endless_RunnerTests: XCTestCase {
    func testStartRunResetsScoreCoinsAndFlags() {
        let model = GameModel()
        model.score = 40
        model.coinsCollected = 3
        model.isGameOver = true
        model.isPlaying = false

        model.startRun()

        XCTAssertEqual(model.score, 0)
        XCTAssertEqual(model.coinsCollected, 0)
        XCTAssertTrue(model.isPlaying)
        XCTAssertFalse(model.isGameOver)
        XCTAssertEqual(model.runID, 1)
    }

    func testAddScoreOnlyWhilePlaying() {
        let model = GameModel()
        model.addScore(10)
        XCTAssertEqual(model.score, 0)

        model.startRun()
        model.addScore(10)
        XCTAssertEqual(model.score, 10)
    }

    func testCollectCoinIncrementsCountAndScore() {
        let model = GameModel()
        model.collectCoin(points: 10)
        XCTAssertEqual(model.coinsCollected, 0)
        XCTAssertEqual(model.score, 0)

        model.startRun()
        model.collectCoin(points: 10)
        model.collectCoin(points: 10)

        XCTAssertEqual(model.coinsCollected, 2)
        XCTAssertEqual(model.score, 20)
    }

    func testEndRunStopsPlayback() {
        let model = GameModel()
        model.startRun()
        model.addScore(5)
        model.collectCoin(points: 10)

        model.endRun()

        XCTAssertFalse(model.isPlaying)
        XCTAssertTrue(model.isGameOver)
        XCTAssertEqual(model.score, 15)
        XCTAssertEqual(model.coinsCollected, 1)
    }

    func testCenterSlabDoesNotHitDodgedHead() {
        let halfWidth = WallCollision.halfWidth(visualWidth: 0.7, inset: 0.12)
        let halfDepth = WallCollision.halfDepth(visualThickness: 0.7)
        // Standing in the left gap clears a center-only wall.
        let head = SIMD3<Float>(-0.55, 1.5, 0)
        let hit = WallCollision.pointHitsSlabs(
            point: head,
            wallZ: 0,
            slabXs: [0],
            halfWidth: halfWidth,
            halfDepth: halfDepth,
            minY: 0.4,
            maxY: 2.2
        )
        XCTAssertFalse(hit)
    }

    func testCenterSlabHitsStandingHead() {
        let halfWidth = WallCollision.halfWidth(visualWidth: 0.7, inset: 0.12)
        let halfDepth = WallCollision.halfDepth(visualThickness: 0.7)
        let head = SIMD3<Float>(0, 1.5, 0)
        let hit = WallCollision.pointHitsSlabs(
            point: head,
            wallZ: 0,
            slabXs: [0],
            halfWidth: halfWidth,
            halfDepth: halfDepth,
            minY: 0.4,
            maxY: 2.2
        )
        XCTAssertTrue(hit)
    }

    func testDistantCenterWallDoesNotHitYet() {
        let halfWidth = WallCollision.halfWidth(visualWidth: 0.7, inset: 0.12)
        let halfDepth = WallCollision.halfDepth(visualThickness: 0.7)
        // Thick visuals used to false-trigger around 0.5 m; kill depth is thinner.
        let head = SIMD3<Float>(0, 1.5, 0)
        let hit = WallCollision.pointHitsSlabs(
            point: head,
            wallZ: -0.5,
            slabXs: [0],
            halfWidth: halfWidth,
            halfDepth: halfDepth,
            minY: 0.4,
            maxY: 2.2
        )
        XCTAssertFalse(hit)
        XCTAssertLessThan(halfDepth, 0.25)
    }

    func testHandTouchingSideSlabCountsAsHit() {
        let halfWidth = WallCollision.halfWidth(visualWidth: 0.7, inset: 0.12) + 0.12
        let halfDepth = WallCollision.halfDepth(visualThickness: 0.7) + 0.12
        let hand = SIMD3<Float>(0.75, 1.1, 0)
        let hit = WallCollision.pointHitsSlabs(
            point: hand,
            wallZ: 0,
            slabXs: [0.75],
            halfWidth: halfWidth,
            halfDepth: halfDepth,
            minY: 0.05,
            maxY: 1.95
        )
        XCTAssertTrue(hit)
    }

    func testHandNearSlabWithPalmRadiusCountsAsHit() {
        // Wrist/palm slightly outside the visual slab still counts with hand radius.
        let halfWidth = WallCollision.halfWidth(visualWidth: 0.7, inset: 0.12) + 0.12
        let halfDepth = WallCollision.halfDepth(visualThickness: 0.7) + 0.12
        let hand = SIMD3<Float>(0.75 - 0.30, 1.1, 0)
        let hit = WallCollision.pointHitsSlabs(
            point: hand,
            wallZ: 0,
            slabXs: [0.75],
            halfWidth: halfWidth,
            halfDepth: halfDepth,
            minY: 0.05,
            maxY: 1.95
        )
        XCTAssertTrue(hit)
    }

    func testHandOutsideSlabDoesNotCountAsHit() {
        let halfWidth = WallCollision.halfWidth(visualWidth: 0.7, inset: 0.12) + 0.12
        let halfDepth = WallCollision.halfDepth(visualThickness: 0.7) + 0.12
        // Hand hanging near body while a side slab is out at the lane center.
        let hand = SIMD3<Float>(0.2, 1.0, 0)
        let hit = WallCollision.pointHitsSlabs(
            point: hand,
            wallZ: 0,
            slabXs: [0.75],
            halfWidth: halfWidth,
            halfDepth: halfDepth,
            minY: 0.05,
            maxY: 1.95
        )
        XCTAssertFalse(hit)
    }

    func testDuckBarrierHitsStandingHead() {
        let head = SIMD3<Float>(0, 1.5, 0)
        let hit = WallCollision.pointHitsDuckBarrier(
            point: head,
            wallZ: 0,
            centerX: 0,
            halfWidth: 1.1,
            halfDepth: 0.2,
            clearanceY: 0.95,
            maxY: 2.2
        )
        XCTAssertTrue(hit)
    }

    func testDuckBarrierClearedWhenHeadIsLow() {
        let head = SIMD3<Float>(0, 0.8, 0)
        let hit = WallCollision.pointHitsDuckBarrier(
            point: head,
            wallZ: 0,
            centerX: 0,
            halfWidth: 1.1,
            halfDepth: 0.2,
            clearanceY: 0.95,
            maxY: 2.2
        )
        XCTAssertFalse(hit)
    }

    func testSweptZCatchesTunnelingWall() {
        // Wall jumped from z=-0.4 to z=0.4 in one frame past a head at z=0.
        XCTAssertTrue(
            WallCollision.overlapsSweptZ(
                pointZ: 0,
                wallZ: 0.4,
                previousWallZ: -0.4,
                halfDepth: 0.2
            )
        )
    }

    func testWallNotRetiredByForwardHandBeforeHead() {
        // Forward hand at z=-0.5 must not count as "passed" while head is still at 0
        // and the wall is still in front (z=-0.2).
        let wallZ: Float = -0.2
        let headZ: Float = 0
        let forwardHandZ: Float = -0.5
        let halfDepth: Float = 0.2
        XCTAssertFalse(
            WallCollision.hasPassedContact(wallZ: wallZ, contactZ: headZ, halfDepth: halfDepth)
        )
        // Old buggy rule used the forward hand and retired the wall too early:
        XCTAssertTrue(
            WallCollision.hasPassedContact(wallZ: wallZ, contactZ: forwardHandZ, halfDepth: halfDepth)
        )
    }

    func testCrystalMergeRequiresDifferentTypes() {
        XCTAssertTrue(CrystalCombine.canMerge(left: .red, right: .blue))
        XCTAssertFalse(CrystalCombine.canMerge(left: .red, right: .red))
        XCTAssertFalse(CrystalCombine.canMerge(left: .blue, right: .blue))
    }

    func testCrystalMergePayouts() {
        XCTAssertEqual(CrystalCombine.mergePayout(leftCharged: false, rightCharged: false), 50)
        XCTAssertEqual(CrystalCombine.mergePayout(leftCharged: true, rightCharged: false), 100)
        XCTAssertEqual(CrystalCombine.mergePayout(leftCharged: false, rightCharged: true), 100)
        XCTAssertEqual(CrystalCombine.mergePayout(leftCharged: true, rightCharged: true), 10_000)
    }

    func testCrystalChargedSpawnRateAroundOnePercent() {
        var rng = SeededGenerator(seed: 42)
        var charged = 0
        let trials = 20_000
        for _ in 0..<trials {
            if CrystalCombine.makeHalf(rng: &rng).charged {
                charged += 1
            }
        }
        let rate = Double(charged) / Double(trials)
        XCTAssertGreaterThan(rate, 0.005)
        XCTAssertLessThan(rate, 0.02)
    }

    func testEnvironmentDirectorStartsOnEmberRun() {
        let director = EnvironmentDirector()
        director.beginRun(debugMode: .normal)
        XCTAssertEqual(director.currentID, .emberRun)
        XCTAssertEqual(director.currentProfile.twist, .baseline)
    }

    func testEnvironmentDirectorForceModeLocksBiome() {
        let director = EnvironmentDirector()
        director.beginRun(debugMode: .force(.fogHollow))
        XCTAssertEqual(director.currentID, .fogHollow)

        // Even after many switch intervals, forced biome should stick.
        for _ in 0..<5 {
            let frame = director.update(deltaTime: director.currentSwitchInterval + 1)
            XCTAssertEqual(frame.currentID, .fogHollow)
            XCTAssertFalse(frame.didEnterEnvironment)
        }
    }

    func testSwitchIntervalFollowsTrackDurationMinusCrossfade() {
        let interval = EnvironmentDirector.switchInterval(forTrackDuration: 47, crossfade: 1.25)
        XCTAssertEqual(interval, 45.75, accuracy: 0.001)
    }

    func testSwitchIntervalClampsShortAndLongTracks() {
        let short = EnvironmentDirector.switchInterval(forTrackDuration: 5, crossfade: 1.25)
        let long = EnvironmentDirector.switchInterval(forTrackDuration: 400, crossfade: 1.25)
        XCTAssertEqual(short, EnvironmentCatalog.minSwitchInterval)
        XCTAssertEqual(long, EnvironmentCatalog.maxSwitchInterval)
    }

    func testEnvironmentDirectorRandomNextAvoidsCurrent() {
        for id in EnvironmentID.allCases {
            var rng = SeededGenerator(seed: UInt64(id.hashValue))
            for _ in 0..<20 {
                let next = EnvironmentDirector.randomNext(excluding: id, rng: &rng)
                XCTAssertNotEqual(next, id)
            }
        }
    }

    func testFogHollowPaletteIsDarkerAndFoggierThanEmber() {
        let ember = EnvironmentCatalog.profile(for: .emberRun).palette
        let fog = EnvironmentCatalog.profile(for: .fogHollow).palette
        XCTAssertLessThan(fog.ambienceBrightness, ember.ambienceBrightness)
        XCTAssertGreaterThan(fog.fogDensity, ember.fogDensity)
        XCTAssertLessThan(fog.wallOpacity, ember.wallOpacity)
    }

    func testGhostGlassUsesWhiteTransparentWalls() {
        let ghost = EnvironmentCatalog.profile(for: .ghostGlass)
        XCTAssertEqual(ghost.twist, .ghostWalls)
        XCTAssertEqual(ghost.ghostWallChance, 1.0, accuracy: 0.001)
        XCTAssertLessThan(ghost.ghostWallOpacity, 0.03)
        // White-ish tint (high RGB, low chroma).
        XCTAssertGreaterThan(ghost.palette.wallTint.r, 0.9)
        XCTAssertGreaterThan(ghost.palette.wallTint.g, 0.9)
        XCTAssertGreaterThan(ghost.palette.wallTint.b, 0.9)
        // No room-dimming flag outside Fog Hollow.
        XCTAssertEqual(ghost.palette.fogDensity, 0)
    }

    func testOnlyFogHollowUsesFogDensity() {
        for id in EnvironmentID.allCases {
            let density = EnvironmentCatalog.profile(for: id).palette.fogDensity
            if id == .fogHollow {
                // Fog Hollow dims passthrough; density is the biome flag (no fog boxes).
                XCTAssertGreaterThan(density, 0)
            } else {
                XCTAssertEqual(density, 0, "Unexpected fog on \(id.displayName)")
            }
        }
    }

    func testFogHollowWallsAreMoreOpaqueThanGhostGlass() {
        let fog = EnvironmentCatalog.profile(for: .fogHollow).palette
        let ghost = EnvironmentCatalog.profile(for: .ghostGlass)
        XCTAssertGreaterThan(fog.wallOpacity, 0.25)
        XCTAssertGreaterThan(fog.wallOpacity, ghost.ghostWallOpacity)
    }

    func testAdjacentDoubleLaneWallsSpreadApartSlightly() {
        let spacing: Float = 0.75
        let spread: Float = 0.09
        let leftCenter = Set([-1, 0])
        let leftX = ObstacleLayout.slabLocalX(
            laneRaw: -1,
            blockingLaneRaws: leftCenter,
            laneSpacing: spacing,
            adjacentSpread: spread
        )
        let centerX = ObstacleLayout.slabLocalX(
            laneRaw: 0,
            blockingLaneRaws: leftCenter,
            laneSpacing: spacing,
            adjacentSpread: spread
        )
        XCTAssertEqual(leftX, -0.75 - spread, accuracy: 0.0001)
        XCTAssertEqual(centerX, 0 + spread, accuracy: 0.0001)

        // Non-adjacent left+right stays on lane centers.
        let leftRight = Set([-1, 1])
        XCTAssertEqual(
            ObstacleLayout.slabLocalX(
                laneRaw: -1,
                blockingLaneRaws: leftRight,
                laneSpacing: spacing,
                adjacentSpread: spread
            ),
            -0.75,
            accuracy: 0.0001
        )
    }

    func testLowCrawlTeachCountIsPositive() {
        let crawl = EnvironmentCatalog.profile(for: .lowCrawl)
        XCTAssertEqual(crawl.twist, .lowCrawl)
        XCTAssertGreaterThan(crawl.lowCrawlTeachCount, 0)
        let director = EnvironmentDirector()
        director.beginRun(debugMode: .force(.lowCrawl))
        XCTAssertTrue(director.isTeachingLowCrawl)
        for _ in 0..<crawl.lowCrawlTeachCount {
            director.noteDuckGateSpawned()
        }
        XCTAssertFalse(director.isTeachingLowCrawl)
    }

    func testGameMusicCrossfadeRecordsCueAndFallbackDuration() {
        let music = GameMusic.shared
        music.prepare()
        let duration = music.crossfade(
            to: EnvironmentID.stormPass.musicCue,
            duration: 1.25,
            loop: false
        )
        XCTAssertEqual(music.currentCue, "stormPass")
        // No bundled track in test host → fallback duration.
        XCTAssertEqual(duration, GameMusic.fallbackTrackDuration)
        XCTAssertEqual(music.trackDuration(for: "stormPass"), GameMusic.fallbackTrackDuration)
        music.stop()
        XCTAssertNil(music.currentCue)
    }

    func testEnvironmentDirectorUsesMusicDurationForSwitchInterval() {
        let director = EnvironmentDirector()
        director.beginRun(debugMode: .normal)
        let expected = EnvironmentDirector.switchInterval(
            forTrackDuration: GameMusic.fallbackTrackDuration,
            crossfade: EnvironmentCatalog.ambienceLerpSeconds
        )
        XCTAssertEqual(director.currentSwitchInterval, expected, accuracy: 0.001)
    }

    func testStormWindOscillatesWithinOneStepOfCenter() {
        XCTAssertEqual(StormWind.nextDirection(offsetStep: 0, preferredFromGap: 1), 1, accuracy: 0.001)
        XCTAssertEqual(StormWind.nextDirection(offsetStep: 0, preferredFromGap: -1), -1, accuracy: 0.001)
        // After a left shove, next must return right — never left again.
        XCTAssertEqual(StormWind.nextDirection(offsetStep: -1, preferredFromGap: -1), 1, accuracy: 0.001)
        XCTAssertEqual(StormWind.nextDirection(offsetStep: 1, preferredFromGap: 1), -1, accuracy: 0.001)

        XCTAssertEqual(StormWind.applyStep(offsetStep: 0, direction: -1), -1)
        XCTAssertEqual(StormWind.applyStep(offsetStep: -1, direction: 1), 0)
        XCTAssertEqual(StormWind.applyStep(offsetStep: 0, direction: 1), 1)
        XCTAssertEqual(StormWind.applyStep(offsetStep: 1, direction: -1), 0)
        // Clamp so stacked same-side shoves cannot exceed ±1.
        XCTAssertEqual(StormWind.applyStep(offsetStep: -1, direction: -1), -1)
        XCTAssertEqual(StormWind.applyStep(offsetStep: 1, direction: 1), 1)
    }

    func testStormGustBarExpandsThenShrinksToZero() {
        let finish: Float = 0.42
        XCTAssertEqual(StormWind.gustExpandAmount(progress: 0, expandFinishAt: finish), 0, accuracy: 0.001)
        XCTAssertEqual(StormWind.gustExpandAmount(progress: finish, expandFinishAt: finish), 1, accuracy: 0.001)
        let midShrink = StormWind.gustExpandAmount(progress: 0.7, expandFinishAt: finish)
        XCTAssertGreaterThan(midShrink, 0)
        XCTAssertLessThan(midShrink, 1)
        XCTAssertEqual(StormWind.gustExpandAmount(progress: 1, expandFinishAt: finish), 0, accuracy: 0.001)
    }
}

/// Deterministic RNG for spawn-rate tests.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x4d595df4d0f33173 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}
