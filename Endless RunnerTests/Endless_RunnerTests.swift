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
    func testStartRunResetsScoreAndFlags() {
        let model = GameModel()
        model.score = 40
        model.isGameOver = true
        model.isPlaying = false

        model.startRun()

        XCTAssertEqual(model.score, 0)
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

    func testEndRunStopsPlayback() {
        let model = GameModel()
        model.startRun()
        model.addScore(5)

        model.endRun()

        XCTAssertFalse(model.isPlaying)
        XCTAssertTrue(model.isGameOver)
        XCTAssertEqual(model.score, 5)
    }
}
