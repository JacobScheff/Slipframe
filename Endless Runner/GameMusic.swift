//
//  GameMusic.swift
//  Slipframe
//
//  Plays one bundled track per biome. Drop files into Music/
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
    /// 1 = full speed/volume, 0 = paused (player left the play volume).
    private(set) var playbackFlow: Float = 1

    private var playersByCue: [String: AVAudioPlayer] = [:]
    private var durationsByCue: [String: Float] = [:]
    private var activePlayer: AVAudioPlayer?
    private var outgoingPlayer: AVAudioPlayer?
    private var fadeTask: Task<Void, Never>?
    private var didConfigureSession = false
    private var activeBaseVolume: Float = 1
    private var outgoingBaseVolume: Float = 0
    private var isFlowPaused = false

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
            activeBaseVolume = 0
            return trackDuration
        }

        activePlayer?.stop()
        next.stop()
        next.currentTime = 0
        next.numberOfLoops = loop ? -1 : 0
        activeBaseVolume = volume
        outgoingBaseVolume = 0
        isFlowPaused = false
        next.prepareToPlay()
        activePlayer = next
        applyPlaybackFlow()
        if playbackFlow > StreamFlow.stopThreshold {
            next.play()
        } else {
            isFlowPaused = true
        }
        return trackDuration
    }

    /// Drive playback rate + gain from the off-track flow (1 = normal, 0 = stopped).
    func setPlaybackFlow(_ scale: Float) {
        let clamped = max(0, min(1, scale))
        let wasStopped = playbackFlow <= StreamFlow.stopThreshold
        let nowStopped = clamped <= StreamFlow.stopThreshold
        if abs(clamped - playbackFlow) < 0.002, wasStopped == nowStopped {
            return
        }
        playbackFlow = clamped
        applyPlaybackFlow()
    }

    /// Restore full-speed playback (new run, teardown, returning to the menu).
    func resetPlaybackFlow() {
        playbackFlow = 1
        isFlowPaused = false
        applyPlaybackFlow()
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
        activeBaseVolume = 0
        outgoingBaseVolume = 0
        isFlowPaused = false
        playbackFlow = 1
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

        let previous = activePlayer
        let previousBase = activeBaseVolume

        next.stop()
        next.currentTime = 0
        next.numberOfLoops = loop ? -1 : 0
        activeBaseVolume = 0
        next.prepareToPlay()

        if previous === next {
            // Same cue restarted (e.g. force re-enter) — just ramp back up.
            activePlayer = next
            outgoingPlayer = nil
            outgoingBaseVolume = 0
            isFlowPaused = false
            applyPlaybackFlow()
            if playbackFlow > StreamFlow.stopThreshold {
                next.play()
            } else {
                isFlowPaused = true
            }
            fadeTask?.cancel()
            fadeTask = Task { @MainActor [weak self] in
                await self?.rampVolume(of: next, to: 1, over: duration)
            }
            return trackDuration
        }

        activePlayer = next
        outgoingPlayer = previous
        outgoingBaseVolume = previous == nil ? 0 : previousBase
        isFlowPaused = false
        applyPlaybackFlow()
        if playbackFlow > StreamFlow.stopThreshold {
            next.play()
        } else {
            isFlowPaused = true
        }
        fadeTask?.cancel()
        fadeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            async let fadeIn: Void = self.rampVolume(of: next, to: 1, over: duration)
            if let previous {
                await self.rampVolume(of: previous, to: 0, over: duration)
                previous.stop()
                if self.outgoingPlayer === previous {
                    self.outgoingPlayer = nil
                    self.outgoingBaseVolume = 0
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
        activeBaseVolume = 0
        outgoingBaseVolume = 0
        isFlowPaused = false
        playbackFlow = 1
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
            player.enableRate = true
            player.rate = 1
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
        outgoingBaseVolume = activeBaseVolume
        activePlayer = nil
        activeBaseVolume = 0
        fadeTask?.cancel()
        fadeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.rampVolume(of: active, to: 0, over: duration)
            active.stop()
            if self.outgoingPlayer === active {
                self.outgoingPlayer = nil
                self.outgoingBaseVolume = 0
            }
        }
    }

    private func rampVolume(of player: AVAudioPlayer, to target: Float, over duration: Float) async {
        let start = baseVolume(for: player)
        let clampedDuration = max(0.05, duration)
        let steps = max(1, Int(clampedDuration / 0.03))
        for step in 1...steps {
            if Task.isCancelled { return }
            let t = Float(step) / Float(steps)
            setBaseVolume(start + (target - start) * t, for: player)
            applyPlaybackFlow()
            let ns = UInt64((clampedDuration / Float(steps)) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: ns)
        }
        if !Task.isCancelled {
            setBaseVolume(target, for: player)
            applyPlaybackFlow()
        }
    }

    private func baseVolume(for player: AVAudioPlayer) -> Float {
        if player === activePlayer { return activeBaseVolume }
        if player === outgoingPlayer { return outgoingBaseVolume }
        return player.volume
    }

    private func setBaseVolume(_ volume: Float, for player: AVAudioPlayer) {
        if player === activePlayer {
            activeBaseVolume = volume
        } else if player === outgoingPlayer {
            outgoingBaseVolume = volume
        }
    }

    private func applyPlaybackFlow() {
        let rate = StreamFlow.musicRate(for: playbackFlow)
        let gain = StreamFlow.musicGain(for: playbackFlow)
        if let active = activePlayer {
            active.enableRate = true
            active.rate = rate
            active.volume = activeBaseVolume * gain
        }
        if let outgoing = outgoingPlayer {
            outgoing.enableRate = true
            outgoing.rate = rate
            outgoing.volume = outgoingBaseVolume * gain
        }

        let audible = playbackFlow > StreamFlow.stopThreshold
        if audible {
            if isFlowPaused {
                activePlayer?.play()
                outgoingPlayer?.play()
                isFlowPaused = false
            }
        } else if !isFlowPaused {
            activePlayer?.pause()
            outgoingPlayer?.pause()
            isFlowPaused = true
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
