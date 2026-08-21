//
//  PlayfieldFlow.swift
//  Slipframe
//
//  Logical play-volume bounds and the slowdown / speed-up that happens when
//  the player steps off the track. Pure math so the ramp can be unit-tested
//  without a RealityKit session.
//

import Foundation
import simd

/// Horizontal play rectangle in playfield space (floor at y = 0, stand line at z = 0).
enum PlayfieldVolume {
    /// Half-width of the floor slab (trackWidth 3.2 → ±1.6).
    static let halfWidth: Float = 1.6
    /// Extra X grace so standing on a rail does not count as leaving.
    static let sidePadding: Float = 0.28
    /// How far behind the stand line still counts as on-stage.
    static let behindStandLine: Float = 1.45
    /// How far toward / past the portal still counts as in the game volume.
    static let towardPortal: Float = 12.0

    /// Head is inside the play volume when X stays over the slab (plus padding)
    /// and Z stays between the pad behind the stand line and the portal.
    static func containsHead(
        _ head: SIMD3<Float>,
        halfWidth: Float = halfWidth,
        sidePadding: Float = sidePadding,
        behindStandLine: Float = behindStandLine,
        towardPortal: Float = towardPortal
    ) -> Bool {
        let xLimit = halfWidth + sidePadding
        guard abs(head.x) <= xLimit else { return false }
        guard head.z <= behindStandLine else { return false }
        guard head.z >= -towardPortal else { return false }
        return true
    }
}

/// Smooth 1 → 0 (leave) and 0 → 1 (re-enter) multiplier for obstacle travel
/// and music playback. Leaving eases out over a beat; returning snaps back
/// much faster so the run does not feel stuck.
struct StreamFlow {
    /// Seconds to ease from full speed down to a stop.
    static let slowdownSeconds: Float = 1.15
    /// Seconds to recover from a stop back to full speed.
    static let speedupSeconds: Float = 0.32
    /// Pause music / freeze travel at or below this scale.
    static let stopThreshold: Float = 0.02

    private(set) var scale: Float = 1

    var isStopped: Bool { scale <= Self.stopThreshold }

    mutating func reset() {
        scale = 1
    }

    mutating func update(inBounds: Bool, deltaTime: Float) {
        let dt = max(0, deltaTime)
        let target: Float = inBounds ? 1 : 0
        let duration = inBounds ? Self.speedupSeconds : Self.slowdownSeconds
        let step = duration > 0.001 ? dt / duration : 1
        if target > scale {
            scale = min(target, scale + step)
        } else if target < scale {
            scale = max(target, scale - step)
        }
    }

    /// Smoothstep so obstacles ease into a stop instead of linear-braking.
    var motionScale: Float {
        let t = max(0, min(1, scale))
        return t * t * (3 - 2 * t)
    }

    /// AVAudioPlayer.rate is clamped to 0.5...2.0 — map motion onto that,
    /// then fade volume on the last quarter so the song actually dies out.
    static func musicRate(for motion: Float) -> Float {
        0.5 + 0.5 * max(0, min(1, motion))
    }

    static func musicGain(for motion: Float) -> Float {
        let t = max(0, min(1, motion))
        if t >= 0.22 { return 1 }
        return t / 0.22
    }
}
