//
//  HandPose.swift
//  Endless Runner
//
//  Grab-pose heuristic from ARKit hand joints for Crystal Cave.
//

import ARKit
import Foundation
import simd

enum HandPose {
    /// Tip-to-wrist average above this ⇒ confidently open (meters).
    static let openTipToWristDistance: Float = 0.15
    /// Tip near knuckle ⇒ that finger is curled.
    static let curledTipToKnuckleDistance: Float = 0.095
    /// Intermediate-tip near knuckle also counts (tips often occlude in a fist).
    static let curledIntermediateToKnuckleDistance: Float = 0.07
    static let minCurledFingers = 2
    /// Thumb tip near index tip counts as a grab/pinch.
    static let pinchDistance: Float = 0.055

    /// True when the hand is closed enough to grab a crystal half.
    ///
    /// Closed fists often occlude fingertips in visionOS tracking, so missing /
    /// sparse tip data is treated as a grab. Only a clearly extended open hand
    /// returns false — that matches "drop when you open your fist".
    static func isGrabPose(anchor: HandAnchor) -> Bool {
        guard anchor.isTracked else { return false }
        guard let skeleton = anchor.handSkeleton else {
            // visionOS sometimes delivers tracked hands without a skeleton.
            return true
        }

        let origin = anchor.originFromAnchorTransform
        let wrist = skeleton.joint(.wrist)
        guard wrist.isTracked else { return true }
        let wristWorld = worldPosition(origin: origin, joint: wrist)

        // Pinch is an easy, reliable grab gesture.
        let thumb = skeleton.joint(.thumbTip)
        let index = skeleton.joint(.indexFingerTip)
        if thumb.isTracked, index.isTracked {
            let thumbWorld = worldPosition(origin: origin, joint: thumb)
            let indexWorld = worldPosition(origin: origin, joint: index)
            if simd_distance(thumbWorld, indexWorld) <= pinchDistance {
                return true
            }
        }

        let fingers: [(
            tip: HandSkeleton.JointName,
            intermediate: HandSkeleton.JointName,
            knuckle: HandSkeleton.JointName
        )] = [
            (.indexFingerTip, .indexFingerIntermediateTip, .indexFingerKnuckle),
            (.middleFingerTip, .middleFingerIntermediateTip, .middleFingerKnuckle),
            (.ringFingerTip, .ringFingerIntermediateTip, .ringFingerKnuckle),
            (.littleFingerTip, .littleFingerIntermediateTip, .littleFingerKnuckle)
        ]

        var tipToWrist: [Float] = []
        var curledCount = 0

        for finger in fingers {
            let knuckle = skeleton.joint(finger.knuckle)
            let knuckleWorld: SIMD3<Float>? = knuckle.isTracked
                ? worldPosition(origin: origin, joint: knuckle)
                : nil

            let tip = skeleton.joint(finger.tip)
            if tip.isTracked {
                let tipWorld = worldPosition(origin: origin, joint: tip)
                tipToWrist.append(simd_distance(tipWorld, wristWorld))
                if let knuckleWorld,
                   simd_distance(tipWorld, knuckleWorld) <= curledTipToKnuckleDistance {
                    curledCount += 1
                    continue
                }
            }

            // Tips often vanish inside a fist — intermediate joints still track.
            let intermediate = skeleton.joint(finger.intermediate)
            if intermediate.isTracked, let knuckleWorld {
                let midWorld = worldPosition(origin: origin, joint: intermediate)
                if simd_distance(midWorld, knuckleWorld) <= curledIntermediateToKnuckleDistance {
                    curledCount += 1
                }
            }
        }

        if curledCount >= minCurledFingers {
            return true
        }

        if tipToWrist.count >= 3 {
            let averageTipToWrist = tipToWrist.reduce(0, +) / Float(tipToWrist.count)
            // Clearly open hand with extended fingers.
            if averageTipToWrist >= openTipToWristDistance && curledCount < 2 {
                return false
            }
            // Shorter tip reach ⇒ closed / grabbing.
            return true
        }

        // Sparse tip data is common while fisting (occlusion). Treat as grab.
        return true
    }

    /// Kept for call sites / tests that still say "fist".
    static func isFist(anchor: HandAnchor) -> Bool {
        isGrabPose(anchor: anchor)
    }

    private static func worldPosition(
        origin: simd_float4x4,
        joint: HandSkeleton.Joint
    ) -> SIMD3<Float> {
        let world = origin * joint.anchorFromJointTransform
        return SIMD3(world.columns.3.x, world.columns.3.y, world.columns.3.z)
    }
}
