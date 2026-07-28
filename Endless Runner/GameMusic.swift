//
//  GameMusic.swift
//  Endless Runner
//
//  Music hook for biome switches. No tracks yet — keep call sites ready so
//  real looping assets can drop in later without touching spawn / twist code.
//

import Foundation

@MainActor
final class GameMusic {
    static let shared = GameMusic()

    /// Last requested cue (biome music key). Useful for debugging / future players.
    private(set) var currentCue: String?
    private(set) var isPrepared = false

    private init() {}

    func prepare() {
        isPrepared = true
        // Future: preload bundled loops keyed by EnvironmentID.musicCue.
    }

    /// Crossfade to the biome cue. Duration is reserved for a real mixer later.
    func crossfade(to cue: String, duration: Float) {
        _ = duration
        currentCue = cue
        // Future: AVAudioPlayerNode / AVAudioEngine crossfade between loops.
    }

    func stop() {
        currentCue = nil
        // Future: fade out and stop active music players.
    }
}
