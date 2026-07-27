//
//  GameSFX.swift
//  Endless Runner
//
//  Temporary placeholder tones until real audio assets are added.
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
    }

    /// Call when the immersive world attaches so the first collect is hitch-free.
    func prepare() {
        prepareSessionIfNeeded()
        for player in coinPlayers {
            player.prepareToPlay()
        }
        hitPlayer?.prepareToPlay()
    }

    func playCoinCollect() {
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
