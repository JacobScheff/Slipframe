//
//  Endless_RunnerTests.swift
//  Endless RunnerTests
//
//  Created by Jacob Scheff on 7/23/24.
//

import XCTest
@testable import Endless_Runner
import Combine
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
        XCTAssertEqual(CrystalCombine.mergeCoinCount, 3)
    }

    func testCollectCoinCountOverride() {
        let model = GameModel()
        model.startRun()
        model.collectCoin(points: 50, coinCount: CrystalCombine.mergeCoinCount)
        XCTAssertEqual(model.coinsCollected, 3)
        XCTAssertEqual(model.score, 50)
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

    func testEmberCoinSpawnTintKeepsPolishedGold() {
        let ember = EnvironmentCatalog.profile(for: .emberRun)
        let colors = GameCoinTint.tintColors(for: ember)
        // Matches GamePalette.coinGold / coinGoldHot — not palette.coinTint.
        XCTAssertEqual(colors.base.r, 1.0, accuracy: 0.001)
        XCTAssertEqual(colors.base.g, 0.78, accuracy: 0.001)
        XCTAssertEqual(colors.base.b, 0.22, accuracy: 0.001)
        XCTAssertEqual(colors.hot.r, 1.0, accuracy: 0.001)
        XCTAssertEqual(colors.hot.g, 0.92, accuracy: 0.001)
        XCTAssertEqual(colors.hot.b, 0.55, accuracy: 0.001)
        XCTAssertFalse(colors.tintsFaceTexture)
        XCTAssertNotEqual(colors.base, ember.palette.coinTint)
    }

    func testNonEmberBiomesShiftCoinSpawnTintFromPalette() {
        for id in EnvironmentID.allCases where id != .emberRun {
            let profile = EnvironmentCatalog.profile(for: id)
            let colors = GameCoinTint.tintColors(for: profile)
            XCTAssertEqual(colors.base, profile.palette.coinTint, "\(id.displayName) should use palette coinTint")
            XCTAssertTrue(colors.tintsFaceTexture, "\(id.displayName) should tint the coin face")
            XCTAssertNotEqual(
                colors.base,
                GameCoinTint.tintColors(for: EnvironmentCatalog.profile(for: .emberRun)).base,
                "\(id.displayName) coin tint should differ from Ember gold"
            )
        }
    }

    func testBiomeCoinTintsAreDistinctAcrossEnvironments() {
        let tints = EnvironmentID.allCases.map { GameCoinTint.tintColors(for: EnvironmentCatalog.profile(for: $0)).base }
        for i in tints.indices {
            for j in tints.indices where j > i {
                XCTAssertNotEqual(
                    tints[i],
                    tints[j],
                    "Coin tints for \(EnvironmentID.allCases[i].displayName) and \(EnvironmentID.allCases[j].displayName) should differ"
                )
            }
        }
    }

    func testGhostGlassUsesWhiteTransparentWalls() {
        let ghost = EnvironmentCatalog.profile(for: .ghostGlass)
        XCTAssertEqual(ghost.twist, .ghostWalls)
        XCTAssertEqual(ghost.ghostWallChance, 1.0, accuracy: 0.001)
        XCTAssertLessThan(ghost.ghostWallOpacity, 0.01)
        XCTAssertEqual(ghost.palette.wallEmissiveIntensity, 0, accuracy: 0.0001)
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

    func testIsAdjacentDoubleDetectsNeighborPairsOnly() {
        XCTAssertTrue(ObstacleLayout.isAdjacentDouble(blockingLaneRaws: [-1, 0]))
        XCTAssertTrue(ObstacleLayout.isAdjacentDouble(blockingLaneRaws: [0, 1]))
        XCTAssertFalse(ObstacleLayout.isAdjacentDouble(blockingLaneRaws: [-1, 1]))
        XCTAssertFalse(ObstacleLayout.isAdjacentDouble(blockingLaneRaws: [0]))
        XCTAssertFalse(ObstacleLayout.isAdjacentDouble(blockingLaneRaws: [-1, 0, 1]))
    }

    func testAdjacentDoubleGapIsSealedForCollision() {
        let spacing: Float = 0.75
        let spread: Float = 0.09
        let halfWidth = WallCollision.halfWidth(visualWidth: 0.7, inset: 0.12)
        let halfDepth = WallCollision.halfDepth(visualThickness: 0.7)
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
        let slabXs = [leftX, centerX]
        // Midpoint between the two kill boxes — the old squeeze corridor.
        let gapX = (leftX + halfWidth + centerX - halfWidth) * 0.5
        let head = SIMD3<Float>(gapX, 1.5, 0)

        // Without sealing, the spread + hit inset leaves a real gap.
        XCTAssertFalse(
            WallCollision.pointHitsSlabs(
                point: head,
                wallZ: 0,
                slabXs: slabXs,
                halfWidth: halfWidth,
                halfDepth: halfDepth,
                minY: 0.4,
                maxY: 2.2,
                sealBetweenSlabs: false
            )
        )
        // Adjacent doubles seal that span so you cannot slip between them.
        XCTAssertTrue(
            WallCollision.pointHitsSlabs(
                point: head,
                wallZ: 0,
                slabXs: slabXs,
                halfWidth: halfWidth,
                halfDepth: halfDepth,
                minY: 0.4,
                maxY: 2.2,
                sealBetweenSlabs: true
            )
        )
        // Open outer lane (right) stays clear.
        let openLaneHead = SIMD3<Float>(0.75, 1.5, 0)
        XCTAssertFalse(
            WallCollision.pointHitsSlabs(
                point: openLaneHead,
                wallZ: 0,
                slabXs: slabXs,
                halfWidth: halfWidth,
                halfDepth: halfDepth,
                minY: 0.4,
                maxY: 2.2,
                sealBetweenSlabs: true
            )
        )
    }

    func testNonAdjacentDoubleDoesNotSealCenterLane() {
        let halfWidth = WallCollision.halfWidth(visualWidth: 0.7, inset: 0.12)
        let halfDepth = WallCollision.halfDepth(visualThickness: 0.7)
        // left+right keeps the center open — must not become a continuous barrier.
        let slabXs: [Float] = [-0.75, 0.75]
        let centerHead = SIMD3<Float>(0, 1.5, 0)
        XCTAssertFalse(
            WallCollision.pointHitsSlabs(
                point: centerHead,
                wallZ: 0,
                slabXs: slabXs,
                halfWidth: halfWidth,
                halfDepth: halfDepth,
                minY: 0.4,
                maxY: 2.2,
                sealBetweenSlabs: false
            )
        )
    }

    func testAdjacentDoubleOpenLaneRawDetectsOuterGap() {
        // Block left+center → only right is open.
        XCTAssertEqual(
            ObstacleLayout.adjacentDoubleOpenLaneRaw(blockingLaneRaws: [-1, 0]),
            1
        )
        // Block center+right → only left is open.
        XCTAssertEqual(
            ObstacleLayout.adjacentDoubleOpenLaneRaw(blockingLaneRaws: [0, 1]),
            -1
        )
        // Center open (left+right) is not an outer-lane adjacent double.
        XCTAssertNil(ObstacleLayout.adjacentDoubleOpenLaneRaw(blockingLaneRaws: [-1, 1]))
        XCTAssertNil(ObstacleLayout.adjacentDoubleOpenLaneRaw(blockingLaneRaws: [0]))
        XCTAssertNil(ObstacleLayout.adjacentDoubleOpenLaneRaw(blockingLaneRaws: [-1]))
    }

    func testOppositeOpenLaneSpacingRequiredOnlyOnCrossCorridorFlip() {
        XCTAssertTrue(
            ObstacleLayout.requiresOppositeOpenLaneSpacing(
                previousOpenLaneRaw: -1,
                nextOpenLaneRaw: 1
            )
        )
        XCTAssertTrue(
            ObstacleLayout.requiresOppositeOpenLaneSpacing(
                previousOpenLaneRaw: 1,
                nextOpenLaneRaw: -1
            )
        )
        // Same-side opens do not need the extra gap.
        XCTAssertFalse(
            ObstacleLayout.requiresOppositeOpenLaneSpacing(
                previousOpenLaneRaw: -1,
                nextOpenLaneRaw: -1
            )
        )
        XCTAssertFalse(
            ObstacleLayout.requiresOppositeOpenLaneSpacing(
                previousOpenLaneRaw: nil,
                nextOpenLaneRaw: 1
            )
        )
        XCTAssertFalse(
            ObstacleLayout.requiresOppositeOpenLaneSpacing(
                previousOpenLaneRaw: 1,
                nextOpenLaneRaw: nil
            )
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
        XCTAssertTrue(StormWind.gustLineDidDisappear(progress: 1, expandFinishAt: finish))
        XCTAssertFalse(StormWind.gustLineDidDisappear(progress: 0.5, expandFinishAt: finish))
    }

    func testStormGustBarShrinksTowardShoveDirection() {
        let finish: Float = 0.42
        let full: Float = 2.8
        // Expand right: center moves right from the left origin edge.
        let expanding = StormWind.gustBarLayout(
            progress: finish * 0.5,
            expandFinishAt: finish,
            direction: 1,
            fullWidth: full
        )
        XCTAssertGreaterThan(expanding.width, 0.1)
        XCTAssertLessThan(expanding.centerX, 0)

        let fullBar = StormWind.gustBarLayout(
            progress: finish,
            expandFinishAt: finish,
            direction: 1,
            fullWidth: full
        )
        XCTAssertEqual(fullBar.width, full, accuracy: 0.01)
        XCTAssertEqual(fullBar.centerX, 0, accuracy: 0.01)

        // Shrink the other way: remaining segment sits on the right (shove) side.
        let shrinking = StormWind.gustBarLayout(
            progress: 0.75,
            expandFinishAt: finish,
            direction: 1,
            fullWidth: full
        )
        XCTAssertGreaterThan(shrinking.width, 0)
        XCTAssertLessThan(shrinking.width, full)
        XCTAssertGreaterThan(shrinking.centerX, 0)

        let gone = StormWind.gustBarLayout(
            progress: 1,
            expandFinishAt: finish,
            direction: 1,
            fullWidth: full
        )
        XCTAssertEqual(gone.width, 0, accuracy: 0.001)
    }

    func testStormShoveForbidsWallsOnShiftSide() {
        XCTAssertEqual(StormWind.forbiddenOuterLaneRaw(offsetStep: 0, pendingDirection: -1), -1)
        XCTAssertEqual(StormWind.forbiddenOuterLaneRaw(offsetStep: 0, pendingDirection: 1), 1)
        // Held off-center still keeps that outer lane clear between shoves.
        XCTAssertEqual(StormWind.forbiddenOuterLaneRaw(offsetStep: -1, pendingDirection: 0), -1)
        XCTAssertEqual(StormWind.forbiddenOuterLaneRaw(offsetStep: 1, pendingDirection: 0), 1)
        // Pending shove wins over the held offset (return shove bans the return side).
        XCTAssertEqual(StormWind.forbiddenOuterLaneRaw(offsetStep: -1, pendingDirection: 1), 1)
        XCTAssertNil(StormWind.forbiddenOuterLaneRaw(offsetStep: 0, pendingDirection: 0))

        let patterns: [[Int]] = [
            [-1], [0], [1],
            [-1, 0], [0, 1], [-1, 1]
        ]
        for _ in 0..<40 {
            let leftShift = StormWind.chooseWallLanes(
                from: patterns,
                offsetStep: 0,
                pendingDirection: -1
            )
            XCTAssertFalse(leftShift.contains(-1), "Left shove must not spawn a left wall: \(leftShift)")

            let rightShift = StormWind.chooseWallLanes(
                from: patterns,
                offsetStep: 0,
                pendingDirection: 1
            )
            XCTAssertFalse(rightShift.contains(1), "Right shove must not spawn a right wall: \(rightShift)")
        }
    }

    func testGameplayDeltaClampsHitchFramesInsteadOfDiscarding() {
        XCTAssertNil(GameTiming.clampedGameplayDelta(0))
        XCTAssertNil(GameTiming.clampedGameplayDelta(-0.016))
        XCTAssertNil(GameTiming.clampedGameplayDelta(.nan))

        XCTAssertEqual(GameTiming.clampedGameplayDelta(1.0 / 90.0)!, 1.0 / 90.0, accuracy: 0.0001)
        // Previously deltaTime >= 0.25 skipped the whole tick (walls froze).
        XCTAssertEqual(
            GameTiming.clampedGameplayDelta(0.30)!,
            GameTiming.maxGameplayDeltaTime,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            GameTiming.clampedGameplayDelta(1.0)!,
            GameTiming.maxGameplayDeltaTime,
            accuracy: 0.0001
        )
    }

    func testCollectBurstKeepsFullSparkCountAndLifetime() {
        XCTAssertEqual(CollectBurstMotion.sparkCount, 10)
        XCTAssertEqual(CollectBurstMotion.lifetime, 0.35, accuracy: 0.0001)
        XCTAssertEqual(CollectBurstMotion.colors.count, 3)

        for i in 0..<CollectBurstMotion.sparkCount {
            let velocity = CollectBurstMotion.velocity(index: i)
            XCTAssertTrue(velocity.x.isFinite)
            XCTAssertTrue(velocity.y.isFinite)
            XCTAssertTrue(velocity.z.isFinite)
            XCTAssertGreaterThan(velocity.y, 0)
        }
    }

    func testScoreAndCoinUpdatesDoNotPublishThroughGameModel() {
        let model = GameModel()
        var gameModelPublishCount = 0
        var statsPublishCount = 0
        let gameModelWatch = model.objectWillChange.sink { _ in
            gameModelPublishCount += 1
        }
        let statsWatch = model.stats.objectWillChange.sink { _ in
            statsPublishCount += 1
        }

        model.startRun()
        // startRun publishes GameModel flags + RunStats resets.
        XCTAssertGreaterThan(gameModelPublishCount, 0)
        let publishesAfterStart = gameModelPublishCount
        let statsAfterStart = statsPublishCount

        model.addScore(5)
        model.collectCoin(points: 10)

        XCTAssertEqual(gameModelPublishCount, publishesAfterStart,
                       "Score/coin ticks must not invalidate ImmersiveView/RealityView")
        // addScore: 1 publish; collectCoin: coins + score = 2 publishes.
        XCTAssertEqual(statsPublishCount, statsAfterStart + 3)
        XCTAssertEqual(model.score, 15)
        XCTAssertEqual(model.coinsCollected, 1)

        _ = gameModelWatch
        _ = statsWatch
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
