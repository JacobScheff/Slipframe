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
        XCTAssertEqual(model.score, 5)
        XCTAssertEqual(model.coinsCollected, 1)
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
        XCTAssertEqual(
            LeaderboardBoard.matching(.daily)?.categoryKey,
            "daily.\(dayKey)"
        )
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
        XCTAssertEqual(GameCenterLeaderboardID.allConfiguredIDs.count, 16)
        XCTAssertTrue(Set(GameCenterLeaderboardID.allConfiguredIDs).count == 16)
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

    func testJumpBarrierHitsStandingBodyProbe() {
        let feet = JumpHeightDetection.bodyProbe(
            fromHead: SIMD3(0, 1.55, 0),
            eyeHeight: 1.55
        )
        let hit = WallCollision.pointHitsJumpBarrier(
            point: feet,
            wallZ: 0,
            centerX: 0,
            halfWidth: 1.1,
            halfDepth: 0.2,
            clearanceY: 0.25,
            minY: -0.5
        )
        XCTAssertTrue(hit)
    }

    func testJumpBarrierClearedWhenBodyProbeIsHigh() {
        // ~0.3 m jump raises the universal-down feet probe above the hurdle.
        let feet = JumpHeightDetection.bodyProbe(
            fromHead: SIMD3(0, 1.85, 0),
            eyeHeight: 1.55
        )
        let hit = WallCollision.pointHitsJumpBarrier(
            point: feet,
            wallZ: 0,
            centerX: 0,
            halfWidth: 1.1,
            halfDepth: 0.2,
            clearanceY: 0.25,
            minY: -0.5
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

    // MARK: - Helpers

    private func makeIsolatedBestStore() -> PersonalBestStore {
        let suite = "test.personalBests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return PersonalBestStore(defaults: defaults, storageKey: suite)
    }

    private func makeIsolatedGameModel() -> GameModel {
        GameModel(
            personalBests: makeIsolatedBestStore(),
            scoreSubmitter: MockGameCenterSubmitter()
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

