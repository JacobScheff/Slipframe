//
//  GameSFX.swift
//  Slipframe
//
//  Lightweight synthesized SFX for collect, hit, and wind telegraph cues.
//

import AVFoundation
import Foundation

@MainActor
final class GameSFX {
    static let shared = GameSFX()

    /// Several short coin players so rapid collects do not restart one buffer mid-play.
    private var coinPlayers: [AVAudioPlayer] = []
    private var nextCoinPlayer = 0
    private var hitPlayer: AVAudioPlayer?
    private var windPlayer: AVAudioPlayer?
    private var junctionOpenPlayer: AVAudioPlayer?
    private var junctionCommitPlayers: [RiftRisk: AVAudioPlayer] = [:]
    private var shieldBreakPlayer: AVAudioPlayer?
    private var nearMissPlayer: AVAudioPlayer?
    private var didConfigureSession = false

    private init() {
        for _ in 0..<3 {
            if let player = Self.makePlayer(
                frequencies: [1046.5, 1318.5], // bright C6 → E6 blip
                duration: 0.11,
                volume: 0.5,
                noiseAmount: 0
            ) {
                coinPlayers.append(player)
            }
        }
        hitPlayer = Self.makePlayer(
            frequencies: [140, 90], // low thud
            duration: 0.28,
            volume: 0.65,
            noiseAmount: 0.35
        )
        windPlayer = Self.makePlayer(
            frequencies: [220, 160], // airy whoosh bed
            duration: 1.2, // covers most of the storm telegraph window
            volume: 0.45,
            noiseAmount: 0.65
        )
        junctionOpenPlayer = Self.makePlayer(
            frequencies: [110, 164.8, 246.9], duration: 0.8, volume: 0.5, noiseAmount: 0.08
        )
        junctionCommitPlayers[.stable] = Self.makePlayer(
            frequencies: [261.6, 392], duration: 0.5, volume: 0.5, noiseAmount: 0
        )
        junctionCommitPlayers[.charged] = Self.makePlayer(
            frequencies: [261.6, 392, 523.3], duration: 0.55, volume: 0.58, noiseAmount: 0.04
        )
        junctionCommitPlayers[.unstable] = Self.makePlayer(
            frequencies: [130.8, 261.6, 554.4], duration: 0.65, volume: 0.66, noiseAmount: 0.16
        )
        shieldBreakPlayer = Self.makePlayer(
            frequencies: [880, 440, 220], duration: 0.42, volume: 0.62, noiseAmount: 0.18
        )
        nearMissPlayer = Self.makePlayer(
            frequencies: [740, 990], duration: 0.14, volume: 0.38, noiseAmount: 0.1
        )
    }

    /// Call when the immersive world attaches so the first collect is hitch-free.
    func prepare() {
        prepareSessionIfNeeded()
        for player in coinPlayers {
            player.prepareToPlay()
        }
        hitPlayer?.prepareToPlay()
        windPlayer?.prepareToPlay()
        junctionOpenPlayer?.prepareToPlay()
        junctionCommitPlayers.values.forEach { $0.prepareToPlay() }
        shieldBreakPlayer?.prepareToPlay()
        nearMissPlayer?.prepareToPlay()
    }

    func playCoinCollect() {
        // Start playback after the RealityKit update so AVAudioPlayer cannot hitch the tick.
        DispatchQueue.main.async { [weak self] in
            self?.playCoinCollectNow()
        }
    }

    private func playCoinCollectNow() {
        prepareSessionIfNeeded()
        guard !coinPlayers.isEmpty else { return }
        let player = coinPlayers[nextCoinPlayer % coinPlayers.count]
        nextCoinPlayer = (nextCoinPlayer + 1) % coinPlayers.count
        player.currentTime = 0
        player.play()
    }

    func playWallHit() {
        prepareSessionIfNeeded()
        guard let player = hitPlayer else { return }
        player.currentTime = 0
        player.play()
    }

    /// Storm Pass wind-shove telegraph.
    func playWindWhoosh() {
        prepareSessionIfNeeded()
        guard let player = windPlayer else { return }
        player.currentTime = 0
        player.play()
    }

    func playJunctionOpen() {
        play(junctionOpenPlayer)
    }

    func playJunctionCommit(risk: RiftRisk, laneIndex: Int) {
        let player = junctionCommitPlayers[risk]
        player?.pan = max(-0.75, min(0.75, Float(laneIndex - 1) * 0.7))
        play(player)
    }

    func playShieldBreak() {
        play(shieldBreakPlayer)
    }

    func playNearMiss() {
        play(nearMissPlayer)
    }

    private func play(_ player: AVAudioPlayer?) {
        prepareSessionIfNeeded()
        guard let player else { return }
        player.currentTime = 0
        player.play()
    }

    private func prepareSessionIfNeeded() {
        guard !didConfigureSession else { return }
        didConfigureSession = true
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("GameSFX: audio session failed: \(error)")
        }
    }

    private static func makePlayer(
        frequencies: [Double],
        duration: Double,
        volume: Float,
        noiseAmount: Double
    ) -> AVAudioPlayer? {
        let data = makeToneWAV(
            frequencies: frequencies,
            duration: duration,
            noiseAmount: noiseAmount
        )
        do {
            let player = try AVAudioPlayer(data: data)
            player.volume = volume
            player.prepareToPlay()
            return player
        } catch {
            print("GameSFX: player create failed: \(error)")
            return nil
        }
    }

    /// Tiny in-memory WAV so we do not need bundled audio files yet.
    private static func makeToneWAV(
        frequencies: [Double],
        duration: Double,
        noiseAmount: Double
    ) -> Data {
        let sampleRate = 22_050
        let sampleCount = Int(Double(sampleRate) * duration)
        var samples = [Int16](repeating: 0, count: sampleCount)

        for i in 0..<sampleCount {
            let t = Double(i) / Double(sampleRate)
            var value = 0.0
            for (index, frequency) in frequencies.enumerated() {
                let weight = index == 0 ? 0.7 : 0.3
                value += sin(2.0 * Double.pi * frequency * t) * weight
            }
            if noiseAmount > 0 {
                value += (Double.random(in: -1...1)) * noiseAmount
            }
            // Fast attack, quick decay envelope.
            let attack = min(1.0, t / 0.008)
            let decay = max(0.0, 1.0 - t / duration)
            let envelope = attack * decay * decay
            let clamped = max(-1.0, min(1.0, value * envelope * 0.85))
            samples[i] = Int16(clamped * Double(Int16.max))
        }

        let dataSize = samples.count * 2
        var data = Data()
        data.reserveCapacity(44 + dataSize)

        func appendASCII(_ string: String) {
            data.append(contentsOf: string.utf8)
        }
        func appendUInt16(_ value: UInt16) {
            var le = value.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        func appendUInt32(_ value: UInt32) {
            var le = value.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }

        appendASCII("RIFF")
        appendUInt32(UInt32(36 + dataSize))
        appendASCII("WAVE")
        appendASCII("fmt ")
        appendUInt32(16) // PCM chunk size
        appendUInt16(1) // PCM format
        appendUInt16(1) // mono
        appendUInt32(UInt32(sampleRate))
        appendUInt32(UInt32(sampleRate * 2)) // byte rate
        appendUInt16(2) // block align
        appendUInt16(16) // bits per sample
        appendASCII("data")
        appendUInt32(UInt32(dataSize))

        for sample in samples {
            var le = sample.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        return data
    }
}
