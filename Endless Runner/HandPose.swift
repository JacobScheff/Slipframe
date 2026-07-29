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
    enum Pose: Equatable {
        case fist
        case open
        case unknown
    }

    /// Average tip→wrist below this ⇒ closed fist (meters).
    static let fistMaxTipToWrist: Float = 0.12
    /// Average tip→wrist above this ⇒ open hand.
    static let openMinTipToWrist: Float = 0.155

    /// Tip near knuckle ⇒ curled finger.
    static let fistTipToKnuckle: Float = 0.055
    /// Tip clearly away from knuckle ⇒ extended finger.
    static let openTipToKnuckle: Float = 0.095

    /// Intermediate tip folded in (used when fingertip tracking drops in a fist).
    static let fistIntermediateToKnuckle: Float = 0.048

    static let fistMinCurledFingers = 3
    static let openMinExtendedFingers = 3
    static let minMeasuredFingers = 3

    /// Thumb tip near index tip ⇒ pinch/grab.
    static let pinchDistance: Float = 0.038

    /// True only with positive closed-hand evidence — never defaults to grab.
    static func isGrabPose(anchor: HandAnchor) -> Bool {
        classify(anchor: anchor) == .fist
    }

    static func isOpenPose(anchor: HandAnchor) -> Bool {
        classify(anchor: anchor) == .open
    }

    /// Kept for call sites / tests that still say "fist".
    static func isFist(anchor: HandAnchor) -> Bool {
        isGrabPose(anchor: anchor)
    }

    /// Classifies the hand with a dead-band between fist and open so noisy frames
    /// stay `.unknown` instead of flipping arbitrarily.
    static func classify(anchor: HandAnchor) -> Pose {
        guard anchor.isTracked else { return .unknown }
        guard let skeleton = anchor.handSkeleton else { return .unknown }

        let origin = anchor.originFromAnchorTransform
        let wrist = skeleton.joint(.wrist)
        guard wrist.isTracked else { return .unknown }
        let wristWorld = worldPosition(origin: origin, joint: wrist)

        // Pinch is a clear, intentional grab.
        let thumb = skeleton.joint(.thumbTip)
        let indexTip = skeleton.joint(.indexFingerTip)
        if thumb.isTracked, indexTip.isTracked {
            let thumbWorld = worldPosition(origin: origin, joint: thumb)
            let indexWorld = worldPosition(origin: origin, joint: indexTip)
            if simd_distance(thumbWorld, indexWorld) <= pinchDistance {
                return .fist
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
        var extendedCount = 0

        for finger in fingers {
            let knuckle = skeleton.joint(finger.knuckle)
            guard knuckle.isTracked else { continue }
            let knuckleWorld = worldPosition(origin: origin, joint: knuckle)

            let tip = skeleton.joint(finger.tip)
            if tip.isTracked {
                let tipWorld = worldPosition(origin: origin, joint: tip)
                let toWrist = simd_distance(tipWorld, wristWorld)
                let toKnuckle = simd_distance(tipWorld, knuckleWorld)
                tipToWrist.append(toWrist)

                if toKnuckle <= fistTipToKnuckle {
                    curledCount += 1
                } else if toKnuckle >= openTipToKnuckle && toWrist >= openMinTipToWrist * 0.85 {
                    extendedCount += 1
                }
                continue
            }

            // Fingertips often vanish inside a real fist — intermediates still track.
            let intermediate = skeleton.joint(finger.intermediate)
            if intermediate.isTracked {
                let midWorld = worldPosition(origin: origin, joint: intermediate)
                if simd_distance(midWorld, knuckleWorld) <= fistIntermediateToKnuckle {
                    curledCount += 1
                }
            }
        }

        if curledCount >= fistMinCurledFingers {
            return .fist
        }

        if tipToWrist.count >= minMeasuredFingers {
            let average = tipToWrist.reduce(0, +) / Float(tipToWrist.count)
            if average <= fistMaxTipToWrist {
                return .fist
            }
            if average >= openMinTipToWrist && extendedCount >= openMinExtendedFingers {
                return .open
            }
            if average >= openMinTipToWrist {
                return .open
            }
        }

        if extendedCount >= openMinExtendedFingers {
            return .open
        }

        // Not enough evidence either way — keep prior latch state in GameWorld.
        return .unknown
    }

    private static func worldPosition(
        origin: simd_float4x4,
        joint: HandSkeleton.Joint
    ) -> SIMD3<Float> {
        let world = origin * joint.anchorFromJointTransform
        return SIMD3(world.columns.3.x, world.columns.3.y, world.columns.3.z)
    }
}
