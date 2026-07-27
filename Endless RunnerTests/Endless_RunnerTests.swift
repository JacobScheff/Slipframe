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
        let halfWidth = WallCollision.halfWidth(visualWidth: 0.7, inset: 0.12)
        let halfDepth = WallCollision.halfDepth(visualThickness: 0.7)
        let hand = SIMD3<Float>(0.75, 1.1, 0)
        let hit = WallCollision.pointHitsSlabs(
            point: hand,
            wallZ: 0,
            slabXs: [0.75],
            halfWidth: halfWidth,
            halfDepth: halfDepth,
            minY: 0.15,
            maxY: 1.85
        )
        XCTAssertTrue(hit)
    }

    func testHandOutsideSlabDoesNotCountAsHit() {
        let halfWidth = WallCollision.halfWidth(visualWidth: 0.7, inset: 0.12)
        let halfDepth = WallCollision.halfDepth(visualThickness: 0.7)
        // Hand hanging near body while a side slab is out at the lane center.
        let hand = SIMD3<Float>(0.2, 1.0, 0)
        let hit = WallCollision.pointHitsSlabs(
            point: hand,
            wallZ: 0,
            slabXs: [0.75],
            halfWidth: halfWidth,
            halfDepth: halfDepth,
            minY: 0.15,
            maxY: 1.85
        )
        XCTAssertFalse(hit)
    }
}
