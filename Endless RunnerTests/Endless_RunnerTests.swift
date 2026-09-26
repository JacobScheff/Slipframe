//
//  Endless_RunnerTests.swift
//  SlipframeTests
//
//  Created by Jacob Scheff on 7/23/24.
//

import XCTest
@testable import Endless_Runner
import Combine
import simd
import RealityKit

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

    func testCollectCoinIncrementsCountOnly() {
        let model = GameModel()
        model.collectCoin()
        XCTAssertEqual(model.coinsCollected, 0)
        XCTAssertEqual(model.score, 0)

        model.startRun()
        model.collectCoin()
        model.collectCoin()

        XCTAssertEqual(model.coinsCollected, 2)
        XCTAssertEqual(model.score, 0)
    }

    func testEndRunStopsPlayback() {
        let model = makeIsolatedGameModel()
        model.startRun()
        model.addScore(5)
        model.collectCoin()

        model.endRun()

        XCTAssertFalse(model.isPlaying)
        XCTAssertTrue(model.isGameOver)
        XCTAssertFalse(model.isGameOverMenuVisible)
        XCTAssertEqual(model.score, 5)
        XCTAssertEqual(model.coinsCollected, 1)

        model.revealGameOverMenu()
        XCTAssertTrue(model.isGameOverMenuVisible)
        XCTAssertTrue(model.pendingMenuReveal)
    }

    func testPersonalBestStoreRecordsIndependentScoreAndCoinBests() {
        let store = makeIsolatedBestStore()
        let first = store.record(category: "normal", score: 100, coins: 3)
        XCTAssertTrue(first.scoreImproved)
        XCTAssertTrue(first.coinsImproved)
        XCTAssertEqual(store.best(for: "normal"), PersonalBest(bestScore: 100, bestCoins: 3))

        let scoreOnly = store.record(category: "normal", score: 150, coins: 1)
        XCTAssertTrue(scoreOnly.scoreImproved)
        XCTAssertFalse(scoreOnly.coinsImproved)
        XCTAssertEqual(store.best(for: "normal"), PersonalBest(bestScore: 150, bestCoins: 3))

        let coinsOnly = store.record(category: "normal", score: 120, coins: 8)
        XCTAssertFalse(coinsOnly.scoreImproved)
        XCTAssertTrue(coinsOnly.coinsImproved)
        XCTAssertEqual(store.best(for: "normal"), PersonalBest(bestScore: 150, bestCoins: 8))

        let noChange = store.record(category: "normal", score: 150, coins: 8)
        XCTAssertFalse(noChange.anyImproved)
    }

    func testPersonalBestStorePersistsAcrossInstances() {
        let suite = "test.personalBests.persist.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let writer = PersonalBestStore(defaults: defaults, storageKey: suite)
        writer.record(category: "emberRun", score: 88, coins: 4)

        let reader = PersonalBestStore(defaults: defaults, storageKey: suite)
        XCTAssertEqual(reader.best(for: "emberRun"), PersonalBest(bestScore: 88, bestCoins: 4))
    }

    func testEndRunRecordsBestsForNormalLoopAndDailyButNotPlaylist() {
        let store = makeIsolatedBestStore()
        let model = GameModel(personalBests: store)

        model.playKind = .normal
        model.startRun()
        model.addScore(40)
        model.collectCoin(count: 2)
        model.endRun()
        XCTAssertEqual(store.best(for: "normal"), PersonalBest(bestScore: 40, bestCoins: 2))
        XCTAssertEqual(model.lastPersonalBestUpdate, PersonalBestUpdate(scoreImproved: true, coinsImproved: true))

        model.playKind = .solo
        model.soloEnvironment = .crystalCave
        model.startRun()
        XCTAssertNil(model.lastPersonalBestUpdate)
        model.addScore(12)
        model.collectCoin(count: 5)
        model.endRun()
        XCTAssertEqual(store.best(for: "crystalCave"), PersonalBest(bestScore: 12, bestCoins: 5))
        XCTAssertEqual(store.best(for: "normal").bestScore, 40)
        XCTAssertEqual(store.best(for: "summitStep").bestScore, 0)

        model.playKind = .daily
        model.startRun()
        model.addScore(7)
        model.collectCoin()
        model.endRun()
        let dailyKey = "daily.\(DailyChallenge.dayKey())"
        XCTAssertEqual(store.best(for: dailyKey), PersonalBest(bestScore: 7, bestCoins: 1))

        model.playKind = .playlist
        model.playlistEnvironments = [.emberRun]
        model.startRun()
        model.addScore(999)
        model.collectCoin(count: 99)
        model.endRun()
        XCTAssertNil(model.lastPersonalBestUpdate)
        XCTAssertNil(PlayMode.playlist(environments: [.emberRun], start: nil).leaderboardCategory)
        XCTAssertEqual(store.best(for: "normal").bestScore, 40)
        XCTAssertEqual(store.best(for: dailyKey).bestScore, 7)
    }

    func testLeaderboardBoardBrowseableAndMatching() {
        let boards = LeaderboardBoard.browseable()
        let dayKey = DailyChallenge.dayKey()
        XCTAssertEqual(boards.first, .normal)
        XCTAssertEqual(boards.dropFirst().first, .daily(dayKey: dayKey))
        XCTAssertEqual(
            Array(boards.dropFirst(2)),
            EnvironmentID.allCases.map { LeaderboardBoard.loop($0) }
        )
        XCTAssertEqual(boards.count, 1 + 1 + EnvironmentID.allCases.count)

        XCTAssertEqual(LeaderboardBoard.matching(.normal)?.categoryKey, "normal")
        XCTAssertEqual(LeaderboardBoard.matching(.solo(.stormPass))?.categoryKey, "stormPass")
        XCTAssertNil(LeaderboardBoard.matching(.playlist(environments: [.emberRun], start: nil)))
        XCTAssertNil(LeaderboardBoard.matching(.tutorial))
        XCTAssertEqual(
            LeaderboardBoard.matching(.daily)?.categoryKey,
            "daily.\(dayKey)"
        )
    }

    func testTutorialScriptSectionOrderAndTimestamps() {
        let sections = TutorialCatalog.sections
        XCTAssertEqual(sections.map(\.id), [
            .basics, .ducking, .movingWalls, .phantomWalls,
            .crystalCave, .jumping, .overdrive, .outro
        ])
        XCTAssertEqual(sections[0].environment, .emberRun)
        XCTAssertEqual(sections[1].environment, .lowCrawl)
        XCTAssertEqual(sections[2].environment, .stormPass)
        XCTAssertEqual(sections[3].environment, .ghostGlass)
        XCTAssertEqual(sections[4].environment, .crystalCave)
        XCTAssertEqual(sections[5].environment, .summitStep)
        XCTAssertEqual(sections[6].environment, .emberRun)
        XCTAssertGreaterThan(sections[6].speedMultiplier, 1.2)
        XCTAssertTrue(sections[6].hidesOverlay)
        XCTAssertTrue(sections[7].isOutro)

        XCTAssertEqual(TutorialCatalog.section(at: 0).id, .basics)
        XCTAssertEqual(TutorialCatalog.section(at: 26).id, .ducking)
        XCTAssertEqual(TutorialCatalog.section(at: 42).id, .movingWalls)
        XCTAssertEqual(TutorialCatalog.section(at: 71).id, .phantomWalls)
        XCTAssertEqual(TutorialCatalog.section(at: 93).id, .crystalCave)
        XCTAssertEqual(TutorialCatalog.section(at: 120).id, .jumping)
        XCTAssertEqual(TutorialCatalog.section(at: 144).id, .overdrive)
        XCTAssertEqual(TutorialCatalog.section(at: 171).id, .outro)
        XCTAssertEqual(TutorialMusic.cue, "tutorial")
    }

    func testTutorialDirectorAdvancesAndFinishes() {
        let director = TutorialDirector()
        director.begin()
        XCTAssertEqual(director.currentSection.id, .basics)

        var frame = director.update(deltaTime: 26)
        XCTAssertTrue(frame.didEnterSection)
        XCTAssertEqual(frame.section.id, .ducking)

        _ = director.update(deltaTime: 145) // past silence
        frame = director.update(deltaTime: 0.05)
        XCTAssertEqual(frame.section.id, .outro)
        XCTAssertNotNil(frame.successBanner)
        XCTAssertEqual(frame.successBanner?.text, "TEST RUN SUCCEEDED")
        XCTAssertFalse(frame.shouldFinish)

        // Appear + hold + exit is ~5.3s — step through it.
        var finished = false
        var sawFullAppear = false
        for _ in 0..<80 {
            let step = director.update(deltaTime: 0.1)
            if let banner = step.successBanner, banner.appear > 0.95, banner.exit < 0.05 {
                sawFullAppear = true
            }
            if step.shouldFinish {
                finished = true
                break
            }
        }
        XCTAssertTrue(sawFullAppear)
        XCTAssertTrue(finished)
    }

    func testTutorialFinishRequestsMenuRevealWithoutCuttingMusicCue() {
        let suite = "test.tutorial.reveal.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let model = GameModel(
            personalBests: makeIsolatedBestStore(),
            scoreSubmitter: MockGameCenterSubmitter(),
            defaults: defaults,
            tutorialCompletedKey: suite
        )
        model.startTutorial()
        model.finishTutorial(markCompleted: true, revealMenu: true)
        XCTAssertTrue(model.pendingMenuReveal)
        XCTAssertEqual(TutorialCatalog.sections.last?.title, "TEST RUN SUCCEEDED")
    }

    func testLazyLockHoldsWithinThresholdThenFollows() {
        let origin = LazyLockPose(position: SIMD3(0, 1.5, -1.6), yaw: 0)
        let tiny = LazyLockPose(position: SIMD3(0.02, 1.5, -1.6), yaw: 0.02)
        let held = LazyLock.step(current: origin, desired: tiny, deltaTime: 1 / 60)
        XCTAssertEqual(held.position.x, origin.position.x, accuracy: 0.0001)

        let far = LazyLockPose(position: SIMD3(0.5, 1.5, -1.6), yaw: 0.5)
        let moved = LazyLock.step(current: origin, desired: far, deltaTime: 0.25)
        XCTAssertGreaterThan(moved.position.x, origin.position.x)
        XCTAssertLessThan(moved.position.x, far.position.x)
    }

    func testTutorialRunDisablesScoringAndFinishesCleanly() {
        let suite = "test.tutorial.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let model = GameModel(
            personalBests: makeIsolatedBestStore(),
            scoreSubmitter: MockGameCenterSubmitter(),
            defaults: defaults,
            tutorialCompletedKey: suite
        )
        XCTAssertFalse(model.hasCompletedTutorial)

        model.startTutorial()
        XCTAssertTrue(model.isTutorialRun)
        XCTAssertEqual(model.resolvedPlayMode, .tutorial)

        model.addScore(50)
        model.collectCoin(count: 3)
        XCTAssertEqual(model.score, 0)
        XCTAssertEqual(model.coinsCollected, 0)

        model.finishTutorial(markCompleted: true)
        XCTAssertFalse(model.isPlaying)
        XCTAssertFalse(model.isGameOver)
        XCTAssertFalse(model.isTutorialRun)
        XCTAssertTrue(model.hasCompletedTutorial)
    }

    func testSkipTutorialArmsGameOverClearThenFinalizes() {
        let suite = "test.tutorial.skip.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let model = GameModel(
            personalBests: makeIsolatedBestStore(),
            scoreSubmitter: MockGameCenterSubmitter(),
            defaults: defaults,
            tutorialCompletedKey: suite
        )
        model.startTutorial()
        XCTAssertEqual(model.tutorialOverlayOpacity, 1, accuracy: 0.001)

        model.skipTutorial()
        XCTAssertFalse(model.isPlaying)
        XCTAssertTrue(model.isGameOver)
        XCTAssertTrue(model.isTutorialRun)
        XCTAssertFalse(model.pendingMenuReveal)

        model.finalizeTutorialSkip()
        XCTAssertFalse(model.isTutorialRun)
        XCTAssertFalse(model.isGameOver)
        XCTAssertTrue(model.hasCompletedTutorial)
        XCTAssertTrue(model.pendingMenuReveal)
    }

    func testEnvironmentDirectorTutorialForcesSilentBiomeSwitches() {
        let director = EnvironmentDirector()
        director.beginRun(mode: .tutorial)
        XCTAssertEqual(director.currentID, .emberRun)

        director.forceEnvironment(.lowCrawl, telegraph: true)
        XCTAssertEqual(director.currentID, .lowCrawl)

        // Auto-rotate must not fire while in tutorial.
        for _ in 0..<5 {
            let frame = director.update(deltaTime: 30)
            XCTAssertFalse(frame.didEnterEnvironment)
            XCTAssertEqual(frame.currentID, .lowCrawl)
        }

        director.forceEnvironment(.summitStep, telegraph: true)
        XCTAssertEqual(director.currentID, .summitStep)
    }

    func testGameCenterLeaderboardIDsAreStable() {
        XCTAssertEqual(
            GameCenterLeaderboardID.identifier(metric: .score, board: .normal),
            "score.normal"
        )
        XCTAssertEqual(
            GameCenterLeaderboardID.identifier(metric: .coins, board: .loop(.crystalCave)),
            "coins.crystalCave"
        )
        // Daily ASC boards are recurring — day key is not part of the ID.
        XCTAssertEqual(
            GameCenterLeaderboardID.identifier(metric: .score, board: .daily(dayKey: "2026-08-05")),
            "score.daily"
        )
        XCTAssertEqual(
            GameCenterLeaderboardID.identifier(metric: .coins, board: .daily(dayKey: "2099-01-01")),
            "coins.daily"
        )
        let expectedBoardIDs = 2 * (EnvironmentID.allCases.count + 2)
        XCTAssertEqual(GameCenterLeaderboardID.allConfiguredIDs.count, expectedBoardIDs)
        XCTAssertEqual(Set(GameCenterLeaderboardID.allConfiguredIDs).count, expectedBoardIDs)
    }

    func testEndRunSubmitsScoreAndCoinsToGameCenterExceptPlaylist() {
        let store = makeIsolatedBestStore()
        let submitter = MockGameCenterSubmitter()
        let model = GameModel(personalBests: store, scoreSubmitter: submitter)

        model.playKind = .normal
        model.startRun()
        model.addScore(33)
        model.collectCoin(count: 4)
        model.endRun()
        XCTAssertEqual(submitter.submissions.count, 1)
        XCTAssertEqual(submitter.submissions[0].board, .normal)
        XCTAssertEqual(submitter.submissions[0].score, 33)
        XCTAssertEqual(submitter.submissions[0].coins, 4)

        model.playKind = .solo
        model.soloEnvironment = .emberRun
        model.startRun()
        model.addScore(10)
        model.endRun()
        XCTAssertEqual(submitter.submissions.count, 2)
        XCTAssertEqual(submitter.submissions[1].board, .loop(.emberRun))

        model.playKind = .playlist
        model.playlistEnvironments = [.summitStep]
        model.startRun()
        model.addScore(500)
        model.collectCoin(count: 50)
        model.endRun()
        XCTAssertEqual(submitter.submissions.count, 2, "Playlist runs must not submit")
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

    func testJumpBodyProbeUsesUniversalDownNotHeadsetTilt() {
        // Probe must stay on the headset XZ even if a local-down cast would drift.
        let head = SIMD3<Float>(0.4, 1.55, -0.2)
        let probe = JumpHeightDetection.bodyProbe(fromHead: head, eyeHeight: 1.55)
        XCTAssertEqual(probe.x, head.x, accuracy: 0.0001)
        XCTAssertEqual(probe.z, head.z, accuracy: 0.0001)
        XCTAssertEqual(probe.y, 0, accuracy: 0.0001)
        XCTAssertEqual(JumpHeightDetection.universalDown, SIMD3<Float>(0, -1, 0))
    }

    func testJumpBarrierHitsWhenHeadsetHasNotRisen() {
        let head = SIMD3<Float>(0, 1.55, 0)
        let rise = JumpHeightDetection.headRise(headY: head.y, standingEyeHeight: 1.55)
        let hit = WallCollision.pointHitsJumpBarrier(
            point: head,
            wallZ: 0,
            centerX: 0,
            halfWidth: 1.1,
            halfDepth: 0.16,
            headRise: rise,
            minRise: 0.04
        )
        XCTAssertTrue(hit)
    }

    func testJumpBarrierClearedWithSmallHeadsetRise() {
        let head = SIMD3<Float>(0, 1.60, 0)
        let rise = JumpHeightDetection.headRise(headY: head.y, standingEyeHeight: 1.55)
        XCTAssertGreaterThanOrEqual(rise, 0.04)
        let hit = WallCollision.pointHitsJumpBarrier(
            point: head,
            wallZ: 0,
            centerX: 0,
            halfWidth: 1.1,
            halfDepth: 0.16,
            headRise: rise,
            minRise: 0.04
        )
        XCTAssertFalse(hit)
    }

    func testStandingHeightMedianIgnoresOutlierBobs() {
        // Periodic idle samples; a single high/low bob should not become baseline.
        let samples: [Float] = [1.54, 1.56, 1.55, 1.70, 1.53, 1.55, 1.57]
        let median = JumpHeightDetection.medianHeight(of: samples)
        XCTAssertEqual(median, 1.55, accuracy: 0.0001)
        XCTAssertTrue(JumpHeightDetection.isPlausibleStandingHeight(1.55))
        XCTAssertFalse(JumpHeightDetection.isPlausibleStandingHeight(0.4))
    }

    func testStandingHeightMedianHandlesLargeSampleBuffer() {
        var samples = Array(repeating: Float(1.55), count: 99)
        samples.append(1.90) // one jump outlier in a full 100-sample buffer
        XCTAssertEqual(JumpHeightDetection.medianHeight(of: samples), 1.55, accuracy: 0.0001)
    }

    func testPlayfieldFloorYDoesNotBuryTrackWhenHeadsetPoseIsUnset() {
        // First immersive-space frame often reports headset Y at the origin.
        // Subtracting eye height would place the track 1.55m underground.
        XCTAssertEqual(
            PlayfieldPlacement.floorY(headWorldY: 0, anchoredFloorY: nil),
            0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            PlayfieldPlacement.floorY(headWorldY: 0.4, anchoredFloorY: nil),
            0,
            accuracy: 0.0001
        )
    }

    func testPlayfieldFloorYUsesDetectedFloorWhenAvailable() {
        XCTAssertEqual(
            PlayfieldPlacement.floorY(headWorldY: 0, anchoredFloorY: 0.02),
            0.02,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            PlayfieldPlacement.floorY(headWorldY: 1.6, anchoredFloorY: -0.04),
            -0.04,
            accuracy: 0.0001
        )
    }

    func testPlayfieldFloorYFallsBackToEyeHeightOnceHeadsetIsPlausible() {
        let headY: Float = 1.6
        XCTAssertEqual(
            PlayfieldPlacement.floorY(headWorldY: headY, anchoredFloorY: nil),
            headY - PlayfieldPlacement.fallbackEyeHeight,
            accuracy: 0.0001
        )
        XCTAssertGreaterThanOrEqual(
            PlayfieldPlacement.minPlausibleHeadWorldY,
            0.9
        )
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

    func testCrystalGrabIgnoresWristKeepsHandAndGrip() {
        let wrist = SIMD3<Float>(0, 1.0, 0)
        let indexTip = SIMD3<Float>(0.05, 1.05, -0.08)
        let middleTip = SIMD3<Float>(0.02, 1.06, -0.09)
        let thumbTip = SIMD3<Float>(-0.03, 1.04, -0.06)
        let grip = SIMD3<Float>(0.01, 1.03, -0.05)
        let contacts = [wrist, indexTip, middleTip, thumbTip]

        let grabPoints = CrystalCombine.handOnlyContacts(from: contacts, grip: grip)

        XCTAssertFalse(grabPoints.contains(where: { distance($0, wrist) < 0.001 }))
        XCTAssertTrue(grabPoints.contains(where: { distance($0, indexTip) < 0.001 }))
        XCTAssertTrue(grabPoints.contains(where: { distance($0, middleTip) < 0.001 }))
        XCTAssertTrue(grabPoints.contains(where: { distance($0, thumbTip) < 0.001 }))
        XCTAssertTrue(grabPoints.contains(where: { distance($0, grip) < 0.001 }))
        XCTAssertEqual(grabPoints.count, 4)
    }

    func testCrystalGrabHandOnlyContactsEmptyWithoutTips() {
        let wristOnly = [SIMD3<Float>(0, 1.0, 0)]
        XCTAssertTrue(CrystalCombine.handOnlyContacts(from: wristOnly).isEmpty)
        XCTAssertTrue(CrystalCombine.handOnlyContacts(from: []).isEmpty)
    }

    func testCrystalMergeCoinAwards() {
        XCTAssertEqual(CrystalCombine.mergeCoinAward(leftCharged: false, rightCharged: false), 5)
        XCTAssertEqual(CrystalCombine.mergeCoinAward(leftCharged: true, rightCharged: false), 50)
        XCTAssertEqual(CrystalCombine.mergeCoinAward(leftCharged: false, rightCharged: true), 50)
        XCTAssertEqual(CrystalCombine.mergeCoinAward(leftCharged: true, rightCharged: true), 10_000)
    }

    func testCollectCoinCountOverrideDoesNotAffectScore() {
        let model = GameModel()
        model.startRun()
        model.collectCoin(count: CrystalCombine.mergeCoinAward(leftCharged: true, rightCharged: false))
        XCTAssertEqual(model.coinsCollected, 50)
        XCTAssertEqual(model.score, 0)
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
        director.beginRun(mode: .normal)
        XCTAssertEqual(director.currentID, .emberRun)
        XCTAssertEqual(director.currentProfile.twist, .baseline)
    }

    func testNormalModeRequestsJunctionInsteadOfRandomlySwitching() {
        let director = EnvironmentDirector()
        director.beginRun(mode: .normal)

        let frame = director.update(deltaTime: director.currentSwitchInterval + 1)
        XCTAssertTrue(frame.requestsJunction)
        XCTAssertTrue(director.isAwaitingNormalChoice)
        XCTAssertFalse(frame.didEnterEnvironment)
        XCTAssertEqual(frame.currentID, .emberRun)

        // Pending choices do not retrigger every frame.
        let waitingFrame = director.update(deltaTime: 1)
        XCTAssertFalse(waitingFrame.requestsJunction)
        XCTAssertFalse(waitingFrame.didEnterEnvironment)
        XCTAssertTrue(director.isAwaitingNormalChoice)
        XCTAssertEqual(director.currentID, .emberRun)
        director.revealNormalDestinationPalette(.crystalCave)
        XCTAssertEqual(director.currentID, .emberRun)
        XCTAssertEqual(
            director.displayedPalette,
            EnvironmentCatalog.profile(for: .crystalCave).palette
        )
        director.chooseNormalEnvironment(.crystalCave)
        XCTAssertFalse(director.isAwaitingNormalChoice)
        XCTAssertEqual(director.currentID, .crystalCave)
    }

    func testNormalModeDrainsBeforeMusicBoundaryAndWaitsToPresentChoice() {
        let director = EnvironmentDirector()
        director.beginRun(mode: .normal)
        let drainStart = director.currentSwitchInterval - EnvironmentDirector.normalDrainLeadSeconds

        XCTAssertFalse(director.update(deltaTime: drainStart - 0.01).requestsJunction)
        XCTAssertTrue(director.update(deltaTime: 0.02).requestsJunction)
        XCTAssertFalse(director.hasReachedNormalMusicEnd)

        _ = director.update(deltaTime: EnvironmentDirector.normalDrainLeadSeconds)
        XCTAssertTrue(director.hasReachedNormalMusicEnd)
    }

    func testFoundryStopsSpawningEarlyEnoughForSlowDoors() {
        let director = EnvironmentDirector()
        director.beginRun(mode: .normal)
        director.forceEnvironment(.vectorFoundry)
        let drainStart = director.currentSwitchInterval - 16

        XCTAssertFalse(director.update(deltaTime: drainStart - 0.01).requestsJunction)
        XCTAssertTrue(director.update(deltaTime: 0.02).requestsJunction)
        XCTAssertFalse(director.hasReachedNormalMusicEnd)
    }

    func testJunctionOffersDistinctBiomesWithIndependentContracts() {
        var rng = SeededGenerator(seed: 0x51_1F_AA)
        let options = RiftJunctionRules.makeOptions(excluding: .emberRun, rng: &rng)

        XCTAssertEqual(options.count, 3)
        XCTAssertEqual(Set(options.map(\.environment)).count, 3)
        XCTAssertFalse(options.map(\.environment).contains(.emberRun))
        XCTAssertTrue(options.allSatisfy { RiftRisk.allCases.contains($0.risk) })
        XCTAssertTrue(options.allSatisfy { option in
            option.modifier.map { RiftModifier.allCases.contains($0) } ?? true
        })

        var sawRepeatedDifficulty = false
        var sawRepeatedModifier = false
        for seed in 1...32 {
            var sampleRNG = SeededGenerator(seed: UInt64(seed))
            let sample = RiftJunctionRules.makeOptions(excluding: .emberRun, rng: &sampleRNG)
            sawRepeatedDifficulty = sawRepeatedDifficulty || Set(sample.map(\.risk)).count < 3
            sawRepeatedModifier = sawRepeatedModifier
                || Set(sample.map { $0.modifier?.rawValue ?? "none" }).count < 3
        }
        XCTAssertTrue(sawRepeatedDifficulty)
        XCTAssertTrue(sawRepeatedModifier)
    }

    func testPortalModifiersAndNoModifierAreUniformlyRandom() {
        var rng = SeededGenerator(seed: 0xA11_0F_7)
        let keys = ["none"] + RiftModifier.allCases.map(\.rawValue)
        var counts = Dictionary(uniqueKeysWithValues: keys.map { ($0, 0) })
        let junctions = 7_000
        var sampledAuthoredOptions = 0

        for _ in 0..<junctions {
            let options = RiftJunctionRules.makeOptions(excluding: .emberRun, rng: &rng)
            for option in options where BiomeAssetID.authoredBiomes.contains(option.environment) {
                counts[option.modifier?.rawValue ?? "none", default: 0] += 1
                sampledAuthoredOptions += 1
            }
        }

        let expected = Double(sampledAuthoredOptions) / Double(keys.count)
        for key in keys {
            let actual = Double(counts[key, default: 0])
            XCTAssertEqual(actual, expected, accuracy: expected * 0.08, key)
        }
    }

    func testJunctionLaneSelectionUsesNearestBodyLane() {
        XCTAssertEqual(RiftJunctionRules.nearestOptionIndex(headX: -0.8, laneSpacing: 0.75), 0)
        XCTAssertEqual(RiftJunctionRules.nearestOptionIndex(headX: 0, laneSpacing: 0.75), 1)
        XCTAssertEqual(RiftJunctionRules.nearestOptionIndex(headX: 0.82, laneSpacing: 0.75), 2)
    }

    func testStageModifiersApplyCompleteRewardsAndShieldRules() {
        let model = GameModel()
        model.startRun()
        model.configureStage(risk: .unstable, modifier: .tokenSurge)
        model.collectCoin()
        XCTAssertEqual(model.coinsCollected, 2)
        XCTAssertGreaterThan(model.stats.flow, 0)
        XCTAssertEqual(model.stats.highestFlow, model.stats.flow)
        model.recordPortalCrossing()
        XCTAssertEqual(model.stats.portalsCrossed, 1)

        model.configureStage(risk: .charged, modifier: .aegis)
        XCTAssertEqual(model.stats.shieldCharges, 1)
        XCTAssertTrue(model.absorbHitIfPossible())
        XCTAssertEqual(model.stats.shieldCharges, 0)
        XCTAssertEqual(model.stats.shieldsBroken, 1)
        XCTAssertFalse(model.absorbHitIfPossible())
    }

    func testExpandedPortalModifiersHaveCompleteGameplayValues() {
        XCTAssertEqual(RiftModifier.allCases.count, 6)
        XCTAssertEqual(RiftModifier.magnet.pickupRadiusBonus, 0.16, accuracy: 0.001)
        XCTAssertEqual(RiftModifier.closeCall.nearMissRange, 0.32, accuracy: 0.001)
        XCTAssertEqual(RiftModifier.bonusBank.scoreBonusDecayInterval, 1.5, accuracy: 0.001)

        let model = GameModel()
        model.startRun()
        model.configureStage(risk: .stable, modifier: .closeCall)
        model.registerNearMiss()
        XCTAssertEqual(model.stats.nearMisses, 1)
        XCTAssertEqual(model.stats.flow, 28)
        XCTAssertEqual(model.score, 7)
    }

    func testFractionalRiskRewardsCarryAcrossDistanceTicks() {
        let model = GameModel()
        model.startRun()
        model.configureStage(risk: .charged, modifier: nil)
        model.addScore(1)
        model.addScore(1)
        XCTAssertEqual(model.score, 3)
    }

    func testEnvironmentDirectorSoloModeLocksBiome() {
        let director = EnvironmentDirector()
        director.beginRun(mode: .solo(.summitStep))
        XCTAssertEqual(director.currentID, .summitStep)

        // Even after many switch intervals, solo biome should stick.
        for _ in 0..<5 {
            let frame = director.update(deltaTime: director.currentSwitchInterval + 1)
            XCTAssertEqual(frame.currentID, .summitStep)
            XCTAssertFalse(frame.didEnterEnvironment)
        }
    }

    func testEnvironmentDirectorPlaylistStaysInPoolAndAvoidsCurrent() {
        let pool: Set<EnvironmentID> = [.emberRun, .lowCrawl, .stormPass]
        let director = EnvironmentDirector()
        director.beginRun(mode: .playlist(environments: pool, start: .lowCrawl))
        XCTAssertEqual(director.currentID, .lowCrawl)

        for _ in 0..<12 {
            let previous = director.currentID
            let frame = director.update(deltaTime: director.currentSwitchInterval + 1)
            XCTAssertTrue(frame.didEnterEnvironment)
            XCTAssertTrue(pool.contains(frame.currentID))
            XCTAssertNotEqual(frame.currentID, previous)
        }
    }

    func testEnvironmentDirectorPlaylistSingleBiomeLoops() {
        let director = EnvironmentDirector()
        director.beginRun(mode: .playlist(environments: [.ghostGlass], start: nil))
        XCTAssertEqual(director.currentID, .ghostGlass)
        let frame = director.update(deltaTime: director.currentSwitchInterval + 1)
        // Only one option — stay put (no churn).
        XCTAssertEqual(frame.currentID, .ghostGlass)
        XCTAssertFalse(frame.didEnterEnvironment)
    }

    func testAutomaticModesWaitForCompleteTrackBeforeChangingBiome() {
        let director = EnvironmentDirector()
        director.beginRun(mode: .playlist(environments: [.emberRun, .stormPass], start: .emberRun))

        let beforeEnd = director.update(deltaTime: director.currentSwitchInterval - 0.01)
        XCTAssertFalse(beforeEnd.didEnterEnvironment)
        XCTAssertEqual(director.currentID, .emberRun)

        let atEnd = director.update(deltaTime: 0.02)
        XCTAssertTrue(atEnd.didEnterEnvironment)
        XCTAssertEqual(director.currentID, .stormPass)
    }

    func testDailyChallengeDayKeyUsesEasternTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // 2026-07-31 03:30 UTC == 2026-07-30 23:30 EDT — still previous Eastern day.
        let components = DateComponents(year: 2026, month: 7, day: 31, hour: 3, minute: 30)
        let date = calendar.date(from: components)!
        XCTAssertEqual(DailyChallenge.dayKey(for: date), "2026-07-30")

        // 2026-07-31 04:30 UTC == 2026-07-31 00:30 EDT — new Eastern day.
        let after = calendar.date(from: DateComponents(year: 2026, month: 7, day: 31, hour: 4, minute: 30))!
        XCTAssertEqual(DailyChallenge.dayKey(for: after), "2026-07-31")
    }

    func testDailyChallengeSeedIsStableAndPreviewMatchesDirector() {
        let key = "2026-07-31"
        XCTAssertEqual(DailyChallenge.seed(for: key), DailyChallenge.seed(for: key))
        XCTAssertNotEqual(DailyChallenge.seed(for: key), DailyChallenge.seed(for: "2026-08-01"))

        let preview = DailyChallenge.previewSequence(dayKey: key, count: 5)
        XCTAssertEqual(preview.count, 5)
        for index in 1..<preview.count {
            XCTAssertNotEqual(preview[index], preview[index - 1])
        }

        // Same day key → same sequence on a second call (shared worldwide).
        XCTAssertEqual(preview, DailyChallenge.previewSequence(dayKey: key, count: 5))
    }

    func testDailyChallengeCountdownFormatsAndRolloverPositive() {
        XCTAssertEqual(DailyChallenge.formatCountdown(3661), "01:01:01")
        XCTAssertGreaterThan(DailyChallenge.secondsUntilRollover(), 0)
    }

    func testDailyScoreShareMessageIncludesScoreAndDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = DailyChallenge.timeZone
        let date = calendar.date(from: DateComponents(year: 2026, month: 8, day: 13, hour: 12))!
        let display = DailyChallenge.displayDate(for: date)

        let withScore = DailyScoreShare.message(score: 420, date: date)
        XCTAssertTrue(withScore.contains("420"))
        XCTAssertTrue(withScore.contains("Slipframe Daily"))
        XCTAssertTrue(withScore.contains(display))

        let withoutScore = DailyScoreShare.message(score: 0, date: date)
        XCTAssertFalse(withoutScore.contains("I scored"))
        XCTAssertTrue(withoutScore.contains(display))
    }

    func testDailyScoreShareMessagesURLPrefillsBody() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = DailyChallenge.timeZone
        let date = calendar.date(from: DateComponents(year: 2026, month: 8, day: 13, hour: 12))!
        let url = DailyScoreShare.messagesURL(score: 88, date: date)
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.scheme, "sms")
        let body = URLComponents(url: url!, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "body" })?
            .value
        XCTAssertEqual(body, DailyScoreShare.message(score: 88, date: date))
    }

    func testDailyGameplaySeedIsStableAndDistinctFromBiomeSeed() {
        let key = "2026-07-31"
        XCTAssertEqual(DailyChallenge.gameplaySeed(for: key), DailyChallenge.gameplaySeed(for: key))
        XCTAssertNotEqual(DailyChallenge.gameplaySeed(for: key), DailyChallenge.seed(for: key))
        XCTAssertNotEqual(
            DailyChallenge.gameplaySeed(for: key),
            DailyChallenge.gameplaySeed(for: "2026-08-01")
        )
    }

    func testDailyGameplayGeneratorProducesIdenticalWallPatternStream() {
        // Same weighted table shape as GameWorld.randomWallLanes (lane raw values).
        let patterns: [[Int]] = [
            [-1], [0], [1],
            [-1], [0], [1],
            [-1], [1],
            [-1, 0], [0, 1], [-1, 1],
            [-1, 1], [-1, 0], [0, 1]
        ]
        let key = "2026-07-31"
        var a = DailyChallenge.makeGameplayGenerator(dayKey: key)
        var b = DailyChallenge.makeGameplayGenerator(dayKey: key)
        for _ in 0..<48 {
            XCTAssertEqual(
                patterns.randomElement(using: &a),
                patterns.randomElement(using: &b)
            )
        }
    }

    func testSeededStormWallPicksAreDeterministic() {
        let patterns: [[Int]] = [
            [-1], [0], [1],
            [-1, 0], [0, 1], [-1, 1]
        ]
        var a = SeededGenerator(seed: 0xC0FFEE)
        var b = SeededGenerator(seed: 0xC0FFEE)
        for _ in 0..<30 {
            let leftA = StormWind.chooseWallLanes(
                from: patterns,
                offsetStep: 0,
                pendingDirection: -1,
                rng: &a
            )
            let leftB = StormWind.chooseWallLanes(
                from: patterns,
                offsetStep: 0,
                pendingDirection: -1,
                rng: &b
            )
            XCTAssertEqual(leftA, leftB)
            XCTAssertFalse(leftA.contains(-1))
        }
    }

    func testPlaylistCannotStartWhenEmpty() {
        let model = GameModel()
        model.playKind = .playlist
        model.playlistEnvironments = []
        XCTAssertFalse(model.canStartRun)
        model.startRun()
        XCTAssertFalse(model.isPlaying)
        XCTAssertEqual(model.runID, 0)

        model.playlistEnvironments = [.emberRun]
        XCTAssertTrue(model.canStartRun)
        model.startRun()
        XCTAssertTrue(model.isPlaying)
    }

    func testResolvedPlayModeMappings() {
        let model = GameModel()
        model.playKind = .normal
        XCTAssertEqual(model.resolvedPlayMode, .normal)

        model.playKind = .solo
        model.soloEnvironment = .crystalCave
        XCTAssertEqual(model.resolvedPlayMode, .solo(.crystalCave))

        model.playKind = .playlist
        model.playlistEnvironments = [.summitStep, .stormPass]
        model.playlistStart = .stormPass
        XCTAssertEqual(
            model.resolvedPlayMode,
            .playlist(environments: [.summitStep, .stormPass], start: .stormPass)
        )

        model.playlistStart = .emberRun // not in set → treated as random
        if case .playlist(_, let start) = model.resolvedPlayMode {
            XCTAssertNil(start)
        } else {
            XCTFail("Expected playlist mode")
        }

        model.playKind = .daily
        XCTAssertEqual(model.resolvedPlayMode, .daily)
    }

    func testSwitchIntervalUsesFullTrackDuration() {
        let interval = EnvironmentDirector.switchInterval(forTrackDuration: 47, crossfade: 1.25)
        XCTAssertEqual(interval, 47, accuracy: 0.001)
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

    func testSummitStepPaletteIsWarmAndDistinctFromLowCrawl() {
        let summit = EnvironmentCatalog.profile(for: .summitStep).palette
        let crawl = EnvironmentCatalog.profile(for: .lowCrawl).palette
        XCTAssertEqual(EnvironmentCatalog.profile(for: .summitStep).twist, .summitStep)
        // Warm gold vs cool blue portal accents.
        XCTAssertGreaterThan(summit.portalRim.r, summit.portalRim.b)
        XCTAssertGreaterThan(crawl.portalRim.b, crawl.portalRim.r)
        XCTAssertNotEqual(summit.coinTint, crawl.coinTint)
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

    func testGhostGlassMixesReadableAndSpectralWalls() {
        let ghost = EnvironmentCatalog.profile(for: .ghostGlass)
        XCTAssertEqual(ghost.twist, .ghostWalls)
        XCTAssertGreaterThan(ghost.ghostWallChance, 0)
        XCTAssertLessThan(ghost.ghostWallChance, 1)
        XCTAssertGreaterThan(ghost.ghostWallOpacity, 0.04)
        XCTAssertLessThan(ghost.ghostWallOpacity, ghost.palette.wallOpacity)
        XCTAssertGreaterThan(ghost.palette.wallEmissiveIntensity, 0)
        // White-ish tint (high RGB, low chroma).
        XCTAssertGreaterThan(ghost.palette.wallTint.r, 0.9)
        XCTAssertGreaterThan(ghost.palette.wallTint.g, 0.9)
        XCTAssertGreaterThan(ghost.palette.wallTint.b, 0.9)
        // No biome uses fogDensity as a gameplay / room-dimming flag.
        XCTAssertEqual(ghost.palette.fogDensity, 0)
    }

    func testNoBiomeUsesFogDensity() {
        for id in EnvironmentID.allCases {
            let density = EnvironmentCatalog.profile(for: id).palette.fogDensity
            XCTAssertEqual(density, 0, "Unexpected fog on \(id.displayName)")
        }
    }

    func testSummitStepWallsAreMoreOpaqueThanGhostGlass() {
        let summit = EnvironmentCatalog.profile(for: .summitStep).palette
        let ghost = EnvironmentCatalog.profile(for: .ghostGlass)
        XCTAssertGreaterThan(summit.wallOpacity, 0.25)
        XCTAssertGreaterThan(summit.wallOpacity, ghost.ghostWallOpacity)
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
        director.beginRun(mode: .solo(.lowCrawl))
        XCTAssertTrue(director.isTeachingLowCrawl)
        for _ in 0..<crawl.lowCrawlTeachCount {
            director.noteDuckGateSpawned()
        }
        XCTAssertFalse(director.isTeachingLowCrawl)
    }

    func testSummitStepTeachCountIsPositive() {
        let summit = EnvironmentCatalog.profile(for: .summitStep)
        XCTAssertEqual(summit.twist, .summitStep)
        XCTAssertGreaterThan(summit.summitStepTeachCount, 0)
        XCTAssertGreaterThan(summit.jumpHazardChance, 0)
        let director = EnvironmentDirector()
        director.beginRun(mode: .solo(.summitStep))
        XCTAssertTrue(director.isTeachingSummitStep)
        for _ in 0..<summit.summitStepTeachCount {
            director.noteJumpGateSpawned()
        }
        XCTAssertFalse(director.isTeachingSummitStep)
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
        director.beginRun(mode: .normal)
        let expected = GameMusic.fallbackTrackDuration
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

    func testWallEmergeProgressEasesOutFromInfinity() {
        XCTAssertEqual(WallEmerge.progress(elapsed: -1), 0, accuracy: 0.0001)
        XCTAssertEqual(WallEmerge.progress(elapsed: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(WallEmerge.progress(elapsed: WallEmerge.duration), 1, accuracy: 0.0001)
        XCTAssertEqual(WallEmerge.progress(elapsed: WallEmerge.duration * 2), 1, accuracy: 0.0001)

        let early = WallEmerge.progress(elapsed: WallEmerge.duration * 0.25)
        let mid = WallEmerge.progress(elapsed: WallEmerge.duration * 0.5)
        let late = WallEmerge.progress(elapsed: WallEmerge.duration * 0.75)
        // Ease-out: first quarter covers more than linear 0.25.
        XCTAssertGreaterThan(early, 0.25)
        XCTAssertGreaterThan(mid, early)
        XCTAssertGreaterThan(late, mid)
        XCTAssertLessThan(late, 1)
    }

    func testWallEmergeLocalZAndScaleLerpTowardExit() {
        let exitLocalZ: Float = 0.35
        XCTAssertEqual(
            WallEmerge.localZ(progress: 0, exitLocalZ: exitLocalZ),
            WallEmerge.startDepth,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            WallEmerge.localZ(progress: 1, exitLocalZ: exitLocalZ),
            exitLocalZ,
            accuracy: 0.0001
        )
        let midZ = WallEmerge.localZ(progress: 0.5, exitLocalZ: exitLocalZ)
        XCTAssertEqual(
            midZ,
            WallEmerge.startDepth + (exitLocalZ - WallEmerge.startDepth) * 0.5,
            accuracy: 0.0001
        )

        XCTAssertEqual(WallEmerge.scale(progress: 0), WallEmerge.startScale, accuracy: 0.0001)
        XCTAssertEqual(WallEmerge.scale(progress: 1), 1, accuracy: 0.0001)
        XCTAssertEqual(
            WallEmerge.scale(progress: 0.5),
            WallEmerge.startScale + (1 - WallEmerge.startScale) * 0.5,
            accuracy: 0.0001
        )
    }

    func testWallEmergeSpawnPlayfieldZStartsFurtherBack() {
        let mouth: Float = -7.65
        XCTAssertEqual(
            WallEmerge.spawnPlayfieldZ(mouthSpawnZ: mouth),
            mouth - WallEmerge.spawnLead,
            accuracy: 0.0001
        )
        XCTAssertLessThan(WallEmerge.startDepth, -12)
        XCTAssertGreaterThan(WallEmerge.duration, 0.55)
        XCTAssertGreaterThan(WallEmerge.spawnLead, 0)
    }

    func testWallEmergeFloorAnchorKeepsBottomOnPortalLip() {
        let portalHeight: Float = 2.5
        let centerY: Float = 0.9
        let portalHalf = portalHeight * 0.5

        let startY = WallEmerge.portalLocalY(
            playfieldCenterY: centerY,
            scale: WallEmerge.startScale,
            portalHeight: portalHeight,
            floorAnchored: true
        )
        let startBottom = startY - centerY * WallEmerge.startScale
        XCTAssertEqual(startBottom, -portalHalf, accuracy: 0.0001)

        let endY = WallEmerge.portalLocalY(
            playfieldCenterY: centerY,
            scale: 1,
            portalHeight: portalHeight,
            floorAnchored: true
        )
        XCTAssertEqual(endY, centerY - portalHalf, accuracy: 0.0001)

        // Duck / non-floor kinds keep a fixed center while scaling.
        let duckY = WallEmerge.portalLocalY(
            playfieldCenterY: 1.375,
            scale: WallEmerge.startScale,
            portalHeight: portalHeight,
            floorAnchored: false
        )
        XCTAssertEqual(duckY, 1.375 - portalHalf, accuracy: 0.0001)
    }

    func testWallEmergeEnvironmentLightingBlendsAcrossPortalPlane() {
        let halfDepth: Float = 0.35
        XCTAssertEqual(
            WallEmerge.environmentLightingWeight(portalLocalZ: -1, halfDepth: halfDepth),
            0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            WallEmerge.environmentLightingWeight(portalLocalZ: -halfDepth, halfDepth: halfDepth),
            0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            WallEmerge.environmentLightingWeight(portalLocalZ: 0, halfDepth: halfDepth),
            0.5,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            WallEmerge.environmentLightingWeight(portalLocalZ: halfDepth, halfDepth: halfDepth),
            1,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            WallEmerge.environmentLightingWeight(portalLocalZ: 2, halfDepth: halfDepth),
            1,
            accuracy: 0.0001
        )
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
        model.collectCoin()

        XCTAssertEqual(gameModelPublishCount, publishesAfterStart,
                       "Score/coin ticks must not invalidate ImmersiveView/RealityView")
        // addScore: 1 publish; collectCoin: coins only = 1 publish.
        XCTAssertEqual(statsPublishCount, statsAfterStart + 2)
        XCTAssertEqual(model.score, 5)
        XCTAssertEqual(model.coinsCollected, 1)

        _ = gameModelWatch
        _ = statsWatch
    }

    func testPlayfieldVolumeTreatsTrackInteriorAsInBounds() {
        XCTAssertTrue(PlayfieldVolume.containsHead(SIMD3<Float>(0, 1.5, 0)))
        XCTAssertTrue(PlayfieldVolume.containsHead(SIMD3<Float>(0.7, 1.5, -2)))
        // Outer lane + wall reach ~±1.1; still inside the dodge band.
        XCTAssertTrue(PlayfieldVolume.containsHead(SIMD3<Float>(-1.05, 1.6, 0.2)))
    }

    func testPlayfieldVolumeRejectsSteppingOffTheSidesOrBehindThePad() {
        // A sidestep off the lanes (well inside the 3.2 m floor slab) counts as leaving.
        XCTAssertFalse(PlayfieldVolume.containsHead(SIMD3<Float>(1.4, 1.5, 0)))
        XCTAssertFalse(PlayfieldVolume.containsHead(SIMD3<Float>(-1.4, 1.5, 0)))
        XCTAssertFalse(PlayfieldVolume.containsHead(SIMD3<Float>(1.7, 1.5, 0)))
        XCTAssertFalse(PlayfieldVolume.containsHead(SIMD3<Float>(0, 1.5, 0.9)))
        XCTAssertFalse(PlayfieldVolume.containsHead(SIMD3<Float>(0, 1.5, -13)))
    }

    func testStreamFlowSlowsAndSpeedsUpOverTheSameWindow() {
        XCTAssertEqual(StreamFlow.speedupSeconds, StreamFlow.slowdownSeconds, accuracy: 0.001)
        XCTAssertGreaterThan(StreamFlow.slowdownSeconds, 1.5)

        var flow = StreamFlow()
        XCTAssertEqual(flow.motionScale, 1, accuracy: 0.001)

        flow.update(inBounds: false, deltaTime: StreamFlow.slowdownSeconds)
        XCTAssertEqual(flow.scale, 0, accuracy: 0.001)
        XCTAssertEqual(flow.motionScale, 0, accuracy: 0.001)
        XCTAssertTrue(flow.isStopped)

        flow.update(inBounds: true, deltaTime: StreamFlow.speedupSeconds * 0.5)
        XCTAssertGreaterThan(flow.scale, 0.4)
        XCTAssertLessThan(flow.scale, 0.7)

        flow.update(inBounds: true, deltaTime: StreamFlow.speedupSeconds)
        XCTAssertEqual(flow.scale, 1, accuracy: 0.001)
        XCTAssertEqual(flow.motionScale, 1, accuracy: 0.001)
    }

    func testStreamFlowMusicRateAndGainMapToStop() {
        XCTAssertEqual(StreamFlow.musicRate(for: 1), 1, accuracy: 0.001)
        XCTAssertEqual(StreamFlow.musicRate(for: 0), 0.5, accuracy: 0.001)
        XCTAssertEqual(StreamFlow.musicGain(for: 1), 1, accuracy: 0.001)
        XCTAssertEqual(StreamFlow.musicGain(for: 0), 0, accuracy: 0.001)
        XCTAssertLessThan(StreamFlow.musicGain(for: 0.1), 1)
    }

    func testShowsTrackDefaultsOnAndPersists() {
        let suite = "test.showsTrack.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = GameModel(
            personalBests: makeIsolatedBestStore(),
            scoreSubmitter: MockGameCenterSubmitter(),
            defaults: defaults,
            tutorialCompletedKey: "\(suite).tutorial",
            showsTrackKey: "\(suite).track"
        )
        XCTAssertTrue(first.showsTrack)

        first.showsTrack = false
        let second = GameModel(
            personalBests: makeIsolatedBestStore(),
            scoreSubmitter: MockGameCenterSubmitter(),
            defaults: defaults,
            tutorialCompletedKey: "\(suite).tutorial",
            showsTrackKey: "\(suite).track"
        )
        XCTAssertFalse(second.showsTrack)
    }

    func testStartRunClearsOffPlayfieldFlag() {
        let model = makeIsolatedGameModel()
        model.isOffPlayfield = true
        model.startRun()
        XCTAssertFalse(model.isOffPlayfield)
        model.isOffPlayfield = true
        model.endRun()
        XCTAssertFalse(model.isOffPlayfield)
    }

    func testGameMusicPlaybackFlowRecordsScale() {
        let music = GameMusic.shared
        music.prepare()
        music.resetPlaybackFlow()
        XCTAssertEqual(music.playbackFlow, 1, accuracy: 0.001)
        music.setPlaybackFlow(0)
        XCTAssertEqual(music.playbackFlow, 0, accuracy: 0.001)
        music.resetPlaybackFlow()
        XCTAssertEqual(music.playbackFlow, 1, accuracy: 0.001)
        music.stop()
    }

    func testBiomeAndModeCardsExposeSymbols() {
        for id in EnvironmentID.allCases {
            XCTAssertFalse(id.symbolName.isEmpty)
            XCTAssertFalse(id.twistCaption.isEmpty)
        }
        for kind in PlayModeKind.allCases {
            XCTAssertFalse(kind.symbolName.isEmpty)
            XCTAssertFalse(kind.cardBlurb.isEmpty)
        }
    }

    func testNewBiomeProfilesAndPlaceholderResources() {
        XCTAssertEqual(EnvironmentCatalog.profile(for: .vectorFoundry).twist, .telekinesis)
        XCTAssertEqual(EnvironmentCatalog.profile(for: .orbitGate).twist, .orbitGate)
        XCTAssertEqual(EnvironmentID.vectorFoundry.musicCue, EnvironmentID.crystalCave.musicCue)
        XCTAssertEqual(EnvironmentID.orbitGate.musicCue, EnvironmentID.stormPass.musicCue)
        XCTAssertFalse(BiomeAssetID.required.contains("environment_vectorFoundry"))
        XCTAssertFalse(BiomeAssetID.required.contains("environment_orbitGate"))
        XCTAssertEqual(EnvironmentID.allCases.count, BiomeAssetID.authoredBiomes.count + 2)
        let foundryModifiers = RiftJunctionRules.modifierPool(for: .vectorFoundry)
        XCTAssertEqual(foundryModifiers.count, 5)
        XCTAssertTrue(foundryModifiers.contains(.some(.aegis)))
        XCTAssertFalse(foundryModifiers.contains(.some(.magnet)))
        XCTAssertFalse(foundryModifiers.contains(.some(.closeCall)))
    }

    func testFoundryForceRespondsToTranslationAndHandRotation() {
        let start = HandPose.ForceBasis(finger: SIMD3(0, 1, 0), palm: SIMD3(0, 0, -1))
        let turned = HandPose.ForceBasis(finger: SIMD3(0.4, 0.9, 0),
                                         palm: SIMD3(0.3, 0.1, -0.95))
        let origin = SIMD2<Float>(0, 1.2)
        let translated = FoundryForceSteering.target(
            grabShape: origin, handDelta: SIMD2(0.2, 0.1),
            startBasis: start, currentBasis: start
        )
        XCTAssertEqual(translated.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(translated.y, 1.45, accuracy: 0.001)

        let rotated = FoundryForceSteering.target(
            grabShape: origin, handDelta: .zero,
            startBasis: start, currentBasis: turned
        )
        XCTAssertGreaterThan(rotated.x, 0.35)
        XCTAssertGreaterThan(rotated.y, origin.y)
    }

    func testOrbitGateCyclesPatternsAndRequiresTimedWedge() {
        XCTAssertEqual((0..<6).map { OrbitGateGeometry.patternIndex(spawnCount: $0) },
                       [0, 0, 1, 2, 0, 1])
        XCTAssertLessThan(OrbitGateGeometry.timedGapClearance(localX: 0, localY: 0), 0)
        XCTAssertGreaterThan(OrbitGateGeometry.timedGapClearance(localX: 0.6, localY: 0), 0)
        XCTAssertLessThan(OrbitGateGeometry.timedGapClearance(localX: -0.6, localY: 0), 0)
        XCTAssertLessThan(OrbitGateGeometry.timedGapClearance(localX: 0.6, localY: 0.5), 0)
    }

    // MARK: - Authored art, cosmetic variation and portable animation

    func testSceneryVariationIsRepeatableAndSeeded() {
        for biome in EnvironmentID.allCases where biome != .lowCrawl {
            let first = SceneryVariation.placements(biome: biome, seed: 125)
            XCTAssertEqual(first.count, 8)
            XCTAssertEqual(first, SceneryVariation.placements(biome: biome, seed: 125))
            XCTAssertNotEqual(first, SceneryVariation.placements(biome: biome, seed: 126))
            XCTAssertEqual(Set(first.map(\.variant)), Set(0..<BiomeAssetID.propVariantCount(biome)))
            for (left, right) in zip(first, first.dropFirst()) {
                XCTAssertNotEqual(left.variant, right.variant)
            }
            for pair in stride(from: 0, to: first.count, by: 2) {
                XCTAssertGreaterThan(first[pair].position.z - first[pair + 1].position.z, 0.44)
            }
        }
        XCTAssertTrue(SceneryVariation.placements(biome: .lowCrawl, seed: 125).isEmpty)
    }

    func testSceneryVariationStaysModestAndOutsideLanes() {
        for biome in EnvironmentID.allCases {
            for seed in 0..<32 {
                for placement in SceneryVariation.placements(biome: biome, seed: UInt64(seed)) {
                    XCTAssertGreaterThanOrEqual(abs(placement.position.x), 3.05)
                    XCTAssertLessThan(placement.position.z, -3.5)
                    XCTAssertGreaterThan(placement.position.z, -21)
                    XCTAssertTrue((0.85...1.13).contains(placement.scale.x))
                    XCTAssertTrue((0.80...1.22).contains(placement.scale.y))
                    XCTAssertLessThanOrEqual(abs(placement.yaw), 0.24)
                    XCTAssertLessThanOrEqual(abs(placement.lean), 0.045)
                    XCTAssertTrue((0..<BiomeAssetID.propVariantCount(biome)).contains(placement.variant))
                }
            }
        }
    }

    func testSceneryDoesNotAdvanceDailyGameplayStream() {
        var gameplay = DailyChallenge.makeGameplayGenerator(dayKey: "2026-09-20")
        var control = DailyChallenge.makeGameplayGenerator(dayKey: "2026-09-20")
        for biome in EnvironmentID.allCases {
            _ = SceneryVariation.placements(biome: biome, seed: 42)
            XCTAssertEqual(gameplay.next(), control.next())
        }
    }

    func testSpawnVisualVariationIsRepeatableAndDoesNotUseGameplayStream() {
        XCTAssertEqual(SpawnVisualVariation.unit(71), SpawnVisualVariation.unit(71))
        XCTAssertNotEqual(SpawnVisualVariation.unit(71), SpawnVisualVariation.unit(72))
        XCTAssertNotEqual(SpawnVisualVariation.yaw(71), SpawnVisualVariation.yaw(72))
        XCTAssertLessThanOrEqual(abs(SpawnVisualVariation.yaw(71)), 0.21)

        var gameplay = DailyChallenge.makeGameplayGenerator(dayKey: "2026-09-21")
        var control = DailyChallenge.makeGameplayGenerator(dayKey: "2026-09-21")
        for seed in 0..<24 {
            _ = SpawnVisualVariation.unit(UInt64(seed))
            _ = SpawnVisualVariation.yaw(UInt64(seed))
            XCTAssertEqual(gameplay.next(), control.next())
        }
    }

    func testRainLoopFadesAtWrapAndFallsDownward() {
        let rain = RiftMoteComponent(basePosition: .zero, phase: 0, radius: 0.09, falling: true)
        XCTAssertEqual(rain.sample(at: 0).opacity, 0)
        XCTAssertGreaterThan(rain.sample(at: 0.5).offset.y, rain.sample(at: 1.0).offset.y)
        XCTAssertGreaterThan(rain.sample(at: 0.5).opacity, 0.5)
        XCTAssertLessThan(rain.sample(at: 1 / 0.55).opacity, 0.001)
    }

    func testAuthoredTurbineRotationKeepsItsPivotFixed() {
        let node = Entity()
        let motion = AuthoredMotion(entity: node, base: node.transform, kind: .rotor)
        let pivot = SIMD3<Float>(0, 4.2, -28)
        motion.update(time: 12)
        let transformed = node.position + node.orientation.act(pivot)
        XCTAssertLessThan(simd_distance(transformed, pivot), 0.0001)
        let first = node.transform
        motion.update(time: 12)
        XCTAssertLessThan(simd_distance(node.position, first.translation), 0.0001)
    }

    func testEveryAuthoredAssetIsBundledAndLoads() async throws {
        XCTAssertEqual(BiomeAssetID.required.count, 91)
        XCTAssertEqual(Set(BiomeAssetID.required).count, BiomeAssetID.required.count)
        await BiomeAssetCatalog.preload()
        XCTAssertTrue(BiomeAssetCatalog.missingAssets.isEmpty, "Missing: \(BiomeAssetCatalog.missingAssets)")
        for name in BiomeAssetID.required {
            XCTAssertNotNil(Bundle.main.url(forResource: name, withExtension: "usdz", subdirectory: "ArtAssets"), name)
            let model = try XCTUnwrap(BiomeAssetCatalog.clone(name), name)
            XCTAssertFalse(BiomeAssetCatalog.models(in: model).isEmpty, name)
        }
    }

    func testImportedWallVariantsPreserveCollisionEnvelope() async {
        await BiomeAssetCatalog.preload()
        for biome in EnvironmentID.allCases {
            var seen = Set<String>()
            for seed in 0..<32 {
                seen.insert(BiomeAssetID.wall(biome, seed: UInt64(seed)))
                let wall = GameVisualBuilders.makeBiomeObstacle(biome: biome, width: 0.7, height: 1.8, depth: 0.7,
                    profile: EnvironmentCatalog.profile(for: biome), seed: UInt64(seed))
                let size = wall.visualBounds(relativeTo: wall).extents
                XCTAssertEqual(size.x, 0.7, accuracy: 0.002, biome.rawValue)
                XCTAssertEqual(size.y, 1.8, accuracy: 0.002, biome.rawValue)
                XCTAssertEqual(size.z, 0.7, accuracy: 0.002, biome.rawValue)
            }
            XCTAssertEqual(seen.count, BiomeAssetID.wallVariantCount)
        }
    }

    func testSpecialHazardVariantsRetainTheirClearanceEnvelope() async {
        await BiomeAssetCatalog.preload()
        for seed in 0..<32 {
            let duck = GameVisualBuilders.makeDuckTendrilCurtain(width: 2.5, height: 0.75, depth: 0.595, seed: UInt64(seed))
            let jump = GameVisualBuilders.makeSummitSpikeRidge(width: 2.5, height: 0.14, depth: 0.22, seed: UInt64(seed))
            for (entity, expected) in [(duck, SIMD3<Float>(2.5, 0.75, 0.595)), (jump, SIMD3<Float>(2.5, 0.14, 0.22))] {
                let bounds = entity.visualBounds(relativeTo: entity)
                XCTAssertLessThan(simd_distance(bounds.extents, expected), 0.002)
                XCTAssertLessThan(simd_length(bounds.center), 0.002)
            }
        }
    }

    func testImportedWorldsExposeTheirAnimationParts() async throws {
        await BiomeAssetCatalog.preload()
        for name in ["environment_stormPass", "environment_ghostGlass", "environment_crystalCave"] {
            let world = try XCTUnwrap(BiomeAssetCatalog.clone(name))
            XCTAssertFalse(BiomeAssetCatalog.motionBindings(in: world).isEmpty, name)
        }
    }

    func testImportedDecorationsAreGroundedAndOutsidePlaySpace() async {
        await BiomeAssetCatalog.preload()
        for biome in EnvironmentID.allCases {
            let interior = GameVisualBuilders.makePortalInterior(portalHeight: 2.5, biome: biome, scenerySeed: 42)
            for prop in interior.children where prop.name.hasPrefix("sceneryVariation_") {
                let bounds = prop.visualBounds(relativeTo: interior)
                XCTAssertEqual(bounds.min.y, -1.25, accuracy: 0.002)
                XCTAssertTrue(bounds.min.x > 1.85 || bounds.max.x < -1.85, biome.rawValue)
                XCTAssertNil(prop.components[CollisionComponent.self])
            }
        }
    }

    func testPortalEnergyAnimationDoesNotMoveFrameOrAperture() async throws {
        await BiomeAssetCatalog.preload()
        let rim = GameVisualBuilders.makePortalRim(width: 3.6, height: 2.5, cornerRadius: 0.2, thickness: 0.1)
        let frame = try XCTUnwrap(rim.children.first)
        let before = frame.visualBounds(relativeTo: rim)
        GameVisualBuilders.animatePortalEnergy(in: rim, name: "riftEnergyOuter", time: 17, speed: 0.15)
        let after = frame.visualBounds(relativeTo: rim)
        XCTAssertLessThan(simd_distance(before.min, after.min), 0.0001)
        XCTAssertLessThan(simd_distance(before.max, after.max), 0.0001)
        let ring = try XCTUnwrap(rim.children.first(where: { $0.name == "riftEnergyOuter" })?.children.first)
        XCTAssertNotEqual(ring.orientation.angle, 0)
    }

    // MARK: - Helpers

    private func makeIsolatedBestStore() -> PersonalBestStore {
        let suite = "test.personalBests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return PersonalBestStore(defaults: defaults, storageKey: suite)
    }

    private func makeIsolatedGameModel() -> GameModel {
        let suite = "test.gameModel.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return GameModel(
            personalBests: makeIsolatedBestStore(),
            scoreSubmitter: MockGameCenterSubmitter(),
            defaults: defaults,
            tutorialCompletedKey: suite
        )
    }
}

@MainActor
private final class MockGameCenterSubmitter: GameCenterSubmitting {
    struct Submission: Equatable {
        let board: LeaderboardBoard
        let score: Int
        let coins: Int
    }

    private(set) var submissions: [Submission] = []

    func submitRun(board: LeaderboardBoard, score: Int, coins: Int) {
        submissions.append(Submission(board: board, score: score, coins: coins))
    }
}

