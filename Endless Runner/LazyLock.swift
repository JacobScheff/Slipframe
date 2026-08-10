//
//  LazyLock.swift
//  Slipframe
//
//  Head-relative pose that stays put for small motion, then eases to a new seat.
//

import Foundation
import simd

struct LazyLockPose: Equatable {
    var position: SIMD3<Float>
    /// Yaw around world up (radians), facing the player.
    var yaw: Float
}

enum LazyLock {
    /// Meters — ignore head translation below this.
    static let positionThreshold: Float = 0.11
    /// Radians (~10°) — ignore small yaw changes.
    static let yawThreshold: Float = 0.18
    /// Higher = snappier catch-up once the threshold is exceeded.
    static let followRate: Float = 4.2

    /// Desired overlay seat: ahead of the head, slightly below eye line.
    static func desiredPose(
        headPosition: SIMD3<Float>,
        flatForward: SIMD3<Float>,
        distance: Float = 1.65,
        drop: Float = 0.22
    ) -> LazyLockPose {
        var forward = flatForward
        let len = length(forward)
        if len < 0.05 {
            forward = SIMD3(0, 0, -1)
        } else {
            forward /= len
        }
        let position = headPosition + forward * distance + SIMD3(0, -drop, 0)
        // Face the player: yaw so +Z of the attachment looks toward the head.
        let toHead = headPosition - position
        let yaw = atan2f(toHead.x, toHead.z)
        return LazyLockPose(position: position, yaw: yaw)
    }

    /// Step the locked pose toward `desired` when motion exceeds thresholds.
    static func step(
        current: LazyLockPose?,
        desired: LazyLockPose,
        deltaTime: Float
    ) -> LazyLockPose {
        guard let current else { return desired }

        let posDelta = distance(current.position, desired.position)
        let yawDelta = abs(shortestAngle(from: current.yaw, to: desired.yaw))
        let shouldFollow = posDelta > positionThreshold || yawDelta > yawThreshold
        guard shouldFollow else { return current }

        let t = 1 - exp(-followRate * max(0, deltaTime))
        let position = mix(current.position, desired.position, t: t)
        let yaw = current.yaw + shortestAngle(from: current.yaw, to: desired.yaw) * t
        return LazyLockPose(position: position, yaw: yaw)
    }

    private static func shortestAngle(from: Float, to: Float) -> Float {
        var delta = to - from
        while delta > .pi { delta -= 2 * .pi }
        while delta < -.pi { delta += 2 * .pi }
        return delta
    }
}
