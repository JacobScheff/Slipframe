//
//  Endless_RunnerTests.swift
//  Endless RunnerTests
//
//  Created by Jacob Scheff on 7/23/24.
//

import XCTest
@testable import Endless_Runner

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
}
