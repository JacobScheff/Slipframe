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
    /// Generous tip-to-wrist average for a closed / grabbing hand (meters).
    static let grabTipToWristDistance: Float = 0.17
    /// Tip near knuckle ⇒ that finger is curled.
    static let curledTipToKnuckleDistance: Float = 0.085
    static let minCurledFingers = 2
    /// Thumb tip near index tip counts as a grab/pinch.
    static let pinchDistance: Float = 0.045

    /// True when the hand is closed enough to grab a crystal half.
    /// If the skeleton is missing but the hand is tracked, returns true so
    /// Crystal Cave is still playable (coins already work from contact points alone).
    static func isGrabPose(anchor: HandAnchor) -> Bool {
        guard anchor.isTracked else { return false }
        guard let skeleton = anchor.handSkeleton else {
            // visionOS sometimes delivers tracked hands without a skeleton.
            // Don't hard-block Crystal Cave grabs in that case.
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

        let fingers: [(tip: HandSkeleton.JointName, knuckle: HandSkeleton.JointName)] = [
            (.indexFingerTip, .indexFingerKnuckle),
            (.middleFingerTip, .middleFingerKnuckle),
            (.ringFingerTip, .ringFingerKnuckle),
            (.littleFingerTip, .littleFingerKnuckle)
        ]

        var tipToWrist: [Float] = []
        var curledCount = 0

        for finger in fingers {
            let tip = skeleton.joint(finger.tip)
            guard tip.isTracked else { continue }
            let tipWorld = worldPosition(origin: origin, joint: tip)
            tipToWrist.append(simd_distance(tipWorld, wristWorld))

            let knuckle = skeleton.joint(finger.knuckle)
            if knuckle.isTracked {
                let knuckleWorld = worldPosition(origin: origin, joint: knuckle)
                if simd_distance(tipWorld, knuckleWorld) <= curledTipToKnuckleDistance {
                    curledCount += 1
                }
            }
        }

        if tipToWrist.count >= 2 {
            let averageTipToWrist = tipToWrist.reduce(0, +) / Float(tipToWrist.count)
            if averageTipToWrist <= grabTipToWristDistance {
                return true
            }
        }

        return curledCount >= minCurledFingers
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
