//
//  HandPose.swift
//  Endless Runner
//
//  Lightweight fist heuristic from ARKit hand joints.
//

import ARKit
import Foundation
import simd

enum HandPose {
    /// Average fingertip-to-wrist distance below this ⇒ fist (meters).
    /// Real closed hands often sit around 0.10–0.13 m; the old 0.095 was too strict.
    static let fistTipToWristDistance: Float = 0.135
    /// Tip near its knuckle means that finger is curled.
    static let curledTipToKnuckleDistance: Float = 0.065
    /// Need at least this many curled fingers (excluding thumb).
    static let minCurledFingers = 3

    static func isFist(anchor: HandAnchor) -> Bool {
        guard anchor.isTracked, let skeleton = anchor.handSkeleton else { return false }

        let origin = anchor.originFromAnchorTransform
        let wrist = skeleton.joint(.wrist)
        guard wrist.isTracked else { return false }
        let wristWorld = worldPosition(origin: origin, joint: wrist)

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

        guard tipToWrist.count >= 3 else { return false }

        let averageTipToWrist = tipToWrist.reduce(0, +) / Float(tipToWrist.count)
        if averageTipToWrist <= fistTipToWristDistance {
            return true
        }
        return curledCount >= minCurledFingers
    }

    private static func worldPosition(
        origin: simd_float4x4,
        joint: HandSkeleton.Joint
    ) -> SIMD3<Float> {
        let world = origin * joint.anchorFromJointTransform
        return SIMD3(world.columns.3.x, world.columns.3.y, world.columns.3.z)
    }
}
