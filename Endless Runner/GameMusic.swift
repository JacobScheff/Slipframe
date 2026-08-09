//
//  GameMusic.swift
//  Endless Runner
//
//  Plays one bundled track per biome. Drop files into Endless Runner/Music/
//  named after each EnvironmentID.musicCue (see Music/README.md).
//

import AVFoundation
import Foundation

@MainActor
final class GameMusic {
    static let shared = GameMusic()

    /// Preferred extensions, in search order.
    static let supportedExtensions = ["m4a", "mp3", "wav", "caf", "aiff"]

    /// Used when a cue has no bundled file yet.
    static let fallbackTrackDuration: Float = 45

    /// Last requested cue (biome music key).
    private(set) var currentCue: String?
    private(set) var isPrepared = false

    private var playersByCue: [String: AVAudioPlayer] = [:]
    private var durationsByCue: [String: Float] = [:]
    private var activePlayer: AVAudioPlayer?
    private var outgoingPlayer: AVAudioPlayer?
    private var fadeTask: Task<Void, Never>?
    private var didConfigureSession = false

    private init() {}

    /// Preload every known biome cue that exists in the app bundle.
    func prepare() {
        prepareSessionIfNeeded()
        for id in EnvironmentID.allCases {
            _ = loadPlayer(for: id.musicCue)
        }
        _ = loadPlayer(for: TutorialMusic.cue)
        isPrepared = true
    }

    /// Current playback time of the active player, if any.
    var playbackTime: Float {
        Float(activePlayer?.currentTime ?? 0)
    }

    /// Start a cue from the beginning (no crossfade). Used by the tutorial master track.
    @discardableResult
    func playFromStart(_ cue: String, loop: Bool = false, volume: Float = 1) -> Float {
        prepareSessionIfNeeded()
        fadeTask?.cancel()
        fadeTask = nil
        outgoingPlayer?.stop()
        outgoingPlayer = nil

        currentCue = cue
        let trackDuration = trackDuration(for: cue)
        guard let next = loadPlayer(for: cue) else {
            activePlayer?.stop()
            activePlayer = nil
            return trackDuration
        }

        activePlayer?.stop()
        next.stop()
        next.currentTime = 0
        next.numberOfLoops = loop ? -1 : 0
        next.volume = volume
        next.prepareToPlay()
        next.play()
        activePlayer = next
        return trackDuration
    }

    /// Immediate stop — used at the tutorial silence cut.
    func stopAbruptly() {
        fadeTask?.cancel()
        fadeTask = nil
        activePlayer?.stop()
        outgoingPlayer?.stop()
        activePlayer = nil
        outgoingPlayer = nil
        currentCue = nil
    }

    /// Duration of the biome track in seconds (fallback if the file is missing).
    func trackDuration(for cue: String) -> Float {
        if let cached = durationsByCue[cue] {
            return cached
        }
        if let player = loadPlayer(for: cue) {
            return Float(player.duration)
        }
        return Self.fallbackTrackDuration
    }

    /// Crossfade to `cue`. Returns the track duration used for biome timing.
    /// - Parameters:
    ///   - cue: `EnvironmentID.musicCue` / filename stem
    ///   - duration: crossfade length in seconds
    ///   - loop: when true (forced biome), the track repeats until stopped
    @discardableResult
    func crossfade(to cue: String, duration: Float, loop: Bool = false) -> Float {
        prepareSessionIfNeeded()
        currentCue = cue

        let trackDuration = trackDuration(for: cue)
        guard let next = loadPlayer(for: cue) else {
            // No file yet — fade out whatever is playing and keep timing via fallback.
            fadeOutActive(over: duration)
            return trackDuration
        }

        next.stop()
        next.currentTime = 0
        next.numberOfLoops = loop ? -1 : 0
        next.volume = 0
        next.prepareToPlay()
        next.play()

        let previous = activePlayer
        if previous === next {
            // Same cue restarted (e.g. force re-enter) — just ramp back up.
            activePlayer = next
            outgoingPlayer = nil
            fadeTask?.cancel()
            fadeTask = Task { @MainActor [weak self] in
                await self?.rampVolume(of: next, to: 1, over: duration)
            }
            return trackDuration
        }

        activePlayer = next
        outgoingPlayer = previous
        fadeTask?.cancel()
        fadeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            async let fadeIn: Void = self.rampVolume(of: next, to: 1, over: duration)
            if let previous {
                await self.rampVolume(of: previous, to: 0, over: duration)
                previous.stop()
                if self.outgoingPlayer === previous {
                    self.outgoingPlayer = nil
                }
            }
            await fadeIn
        }
        return trackDuration
    }

    func stop() {
        fadeTask?.cancel()
        fadeTask = nil
        activePlayer?.stop()
        outgoingPlayer?.stop()
        activePlayer = nil
        outgoingPlayer = nil
        currentCue = nil
    }

    /// Bundle URL for a cue, if a supported file exists under Music/ (or at the bundle root).
    static func bundleURL(for cue: String) -> URL? {
        for ext in supportedExtensions {
            if let url = Bundle.main.url(forResource: cue, withExtension: ext, subdirectory: "Music") {
                return url
            }
            if let url = Bundle.main.url(forResource: cue, withExtension: ext) {
                return url
            }
        }
        return nil
    }

    private func loadPlayer(for cue: String) -> AVAudioPlayer? {
        if let existing = playersByCue[cue] {
            return existing
        }
        guard let url = Self.bundleURL(for: cue) else { return nil }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            playersByCue[cue] = player
            let duration = Float(player.duration)
            if duration.isFinite, duration > 1 {
                durationsByCue[cue] = duration
            } else {
                durationsByCue[cue] = Self.fallbackTrackDuration
            }
            return player
        } catch {
            print("GameMusic: failed to load \(cue): \(error)")
            return nil
        }
    }

    private func fadeOutActive(over duration: Float) {
        guard let active = activePlayer else { return }
        outgoingPlayer = active
        activePlayer = nil
        fadeTask?.cancel()
        fadeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.rampVolume(of: active, to: 0, over: duration)
            active.stop()
            if self.outgoingPlayer === active {
                self.outgoingPlayer = nil
            }
        }
    }

    private func rampVolume(of player: AVAudioPlayer, to target: Float, over duration: Float) async {
        let start = player.volume
        let clampedDuration = max(0.05, duration)
        let steps = max(1, Int(clampedDuration / 0.03))
        for step in 1...steps {
            if Task.isCancelled { return }
            let t = Float(step) / Float(steps)
            player.volume = start + (target - start) * t
            let ns = UInt64((clampedDuration / Float(steps)) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: ns)
        }
        if !Task.isCancelled {
            player.volume = target
        }
    }

    private func prepareSessionIfNeeded() {
        guard !didConfigureSession else { return }
        didConfigureSession = true
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("GameMusic: audio session failed: \(error)")
        }
    }
}
