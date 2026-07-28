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
    static let fistTipDistance: Float = 0.095

    static func isFist(anchor: HandAnchor) -> Bool {
        guard anchor.isTracked, let skeleton = anchor.handSkeleton else { return false }

        let origin = anchor.originFromAnchorTransform
        let wrist = skeleton.joint(.wrist)
        guard wrist.isTracked else { return false }
        let wristWorld = worldPosition(origin: origin, joint: wrist)

        let tipNames: [HandSkeleton.JointName] = [
            .indexFingerTip,
            .middleFingerTip,
            .ringFingerTip,
            .littleFingerTip
        ]

        var distances: [Float] = []
        for name in tipNames {
            let tip = skeleton.joint(name)
            guard tip.isTracked else { continue }
            let tipWorld = worldPosition(origin: origin, joint: tip)
            distances.append(simd_distance(tipWorld, wristWorld))
        }
        guard distances.count >= 3 else { return false }

        let average = distances.reduce(0, +) / Float(distances.count)
        return average <= fistTipDistance
    }

    private static func worldPosition(
        origin: simd_float4x4,
        joint: HandSkeleton.Joint
    ) -> SIMD3<Float> {
        let world = origin * joint.anchorFromJointTransform
        return SIMD3(world.columns.3.x, world.columns.3.y, world.columns.3.z)
    }
}
