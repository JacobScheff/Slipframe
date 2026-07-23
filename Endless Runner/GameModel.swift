//
//  GameModel.swift
//  Endless Runner
//
//  Shared UI / run state for the base endless-runner loop.
//

import Foundation
import SwiftUI

@MainActor
final class GameModel: ObservableObject {
    @Published var score: Int = 0
    @Published var isPlaying: Bool = false
    @Published var isGameOver: Bool = false
    @Published var immersiveSpaceOpen: Bool = false

    /// Bumped on each restart so the immersive session can reset its world.
    @Published private(set) var runID: Int = 0

    func startRun() {
        score = 0
        isGameOver = false
        isPlaying = true
        runID += 1
    }

    func addScore(_ points: Int) {
        guard isPlaying else { return }
        score += points
    }

    func endRun() {
        guard isPlaying else { return }
        isPlaying = false
        isGameOver = true
    }
}
