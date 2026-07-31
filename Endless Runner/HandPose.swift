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

    /// Tip→wrist average below this supports a closed hand (meters).
    static let fistMaxTipToWrist: Float = 0.13
    /// Tip→wrist average above this supports an open hand.
    static let openMinTipToWrist: Float = 0.16

    /// Strict tip curl — tips parked near knuckles (partial close, palm toward camera).
    static let fistTipPastKnuckle: Float = 0.02
    static let fistTipToKnuckle: Float = 0.05
    /// Tip folded past the knuckle toward the palm (full fist; tip→wrist ≤ knuckle→wrist).
    static let fistTipTuckedPastKnuckle: Float = 0.0
    /// Clear extension past the knuckle ⇒ open finger.
    static let openTipPastKnuckle: Float = 0.065
    static let openTipToKnuckle: Float = 0.1

    /// Occlusion-resistant curl: intermediate tip folded toward knuckle / palm.
    /// Scored even when tips remain "tracked" with bad estimates inside a fist.
    static let fistIntermediateToKnuckle: Float = 0.07
    static let fistIntermediateToWrist: Float = 0.11
    /// Average intermediate→wrist below this + no extension ⇒ closed hand.
    static let fistMaxIntermediateToWrist: Float = 0.10

    static let fistMinCurledFingers = 3
    static let fistMinOccludedCurledFingers = 2
    static let openMinExtendedFingers = 3

    /// Thumb tip near index tip ⇒ pinch/grab.
    static let pinchDistance: Float = 0.045

    static func isGrabPose(anchor: HandAnchor) -> Bool {
        classify(anchor: anchor) == .fist
    }

    static func isOpenPose(anchor: HandAnchor) -> Bool {
        classify(anchor: anchor) == .open
    }

    static func isFist(anchor: HandAnchor) -> Bool {
        isGrabPose(anchor: anchor)
    }

    /// Classifies fist vs open.
    ///
    /// A *fully* closed fist often keeps fingertips marked tracked with poor
    /// estimates on visionOS, while a *partial* close tracks tips near the
    /// knuckles. Tip curl therefore accepts both knuckle-parked and tucked
    /// tips, and intermediate-joint curl is always scored so full fists
    /// register even when tip tracking lies.
    static func classify(anchor: HandAnchor) -> Pose {
        guard anchor.isTracked else { return .unknown }
        guard let skeleton = anchor.handSkeleton else { return .unknown }

        let origin = anchor.originFromAnchorTransform
        let wrist = skeleton.joint(.wrist)
        guard wrist.isTracked else { return .unknown }
        let wristWorld = worldPosition(origin: origin, joint: wrist)

        // Pinch is a clear grab.
        let thumb = skeleton.joint(.thumbTip)
        let indexTipJoint = skeleton.joint(.indexFingerTip)
        if thumb.isTracked, indexTipJoint.isTracked {
            let thumbWorld = worldPosition(origin: origin, joint: thumb)
            let indexWorld = worldPosition(origin: origin, joint: indexTipJoint)
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
        var midToWrist: [Float] = []
        var tipExtended = 0
        var intermediateCurled = 0
        var curledFingers = 0
        var tipsTracked = 0

        for finger in fingers {
            let knuckle = skeleton.joint(finger.knuckle)
            let knuckleWorld: SIMD3<Float>? = knuckle.isTracked
                ? worldPosition(origin: origin, joint: knuckle)
                : nil

            var fingerIntermediateCurled = false
            let intermediate = skeleton.joint(finger.intermediate)
            if intermediate.isTracked {
                let midWorld = worldPosition(origin: origin, joint: intermediate)
                let midWristDist = simd_distance(midWorld, wristWorld)
                midToWrist.append(midWristDist)
                if midWristDist <= fistIntermediateToWrist {
                    fingerIntermediateCurled = true
                }
                if let knuckleWorld,
                   simd_distance(midWorld, knuckleWorld) <= fistIntermediateToKnuckle {
                    fingerIntermediateCurled = true
                }
                if fingerIntermediateCurled {
                    intermediateCurled += 1
                }
            }

            var fingerTipCurled = false
            var fingerTipExtended = false
            let tip = skeleton.joint(finger.tip)
            if tip.isTracked {
                tipsTracked += 1
                let tipWorld = worldPosition(origin: origin, joint: tip)
                let toWrist = simd_distance(tipWorld, wristWorld)
                tipToWrist.append(toWrist)

                if let knuckleWorld {
                    let knuckleToWrist = simd_distance(knuckleWorld, wristWorld)
                    let tipPastKnuckle = toWrist - knuckleToWrist
                    let tipToKnuckle = simd_distance(tipWorld, knuckleWorld)

                    // Knuckle-parked (partial close) or tucked into palm (full fist).
                    if tipPastKnuckle <= fistTipTuckedPastKnuckle
                        || (tipPastKnuckle <= fistTipPastKnuckle && tipToKnuckle <= fistTipToKnuckle) {
                        fingerTipCurled = true
                    } else if tipPastKnuckle >= openTipPastKnuckle || tipToKnuckle >= openTipToKnuckle {
                        fingerTipExtended = true
                    }
                } else if toWrist <= fistMaxTipToWrist {
                    fingerTipCurled = true
                }
            }

            // Phantom tip extension inside a fist: prefer intermediate fold.
            if fingerTipExtended && !fingerIntermediateCurled {
                tipExtended += 1
                continue
            }
            if fingerTipCurled || fingerIntermediateCurled {
                curledFingers += 1
            }
        }

        // Full fist with mostly missing tips, intermediates folded in.
        if tipsTracked <= 1 && intermediateCurled >= fistMinOccludedCurledFingers {
            return .fist
        }
        if tipsTracked <= 2 && intermediateCurled >= 3 {
            return .fist
        }

        // Combined curl — tip and/or intermediate evidence per finger.
        if curledFingers >= fistMinCurledFingers {
            return .fist
        }

        // Intermediate-only closed hand (tips tracked but in the dead-band).
        if intermediateCurled >= fistMinCurledFingers && tipExtended == 0 {
            return .fist
        }

        if tipToWrist.count >= 3 {
            let average = tipToWrist.reduce(0, +) / Float(tipToWrist.count)
            if average <= fistMaxTipToWrist && curledFingers >= 2 && tipExtended == 0 {
                return .fist
            }
            if average >= openMinTipToWrist && tipExtended >= openMinExtendedFingers {
                return .open
            }
            if average >= openMinTipToWrist && curledFingers == 0 && tipExtended >= 2 {
                return .open
            }
        }

        // Closed-hand path from intermediate reach when tip metrics are noisy.
        if midToWrist.count >= 3 {
            let midAverage = midToWrist.reduce(0, +) / Float(midToWrist.count)
            if midAverage <= fistMaxIntermediateToWrist
                && tipExtended == 0
                && intermediateCurled >= fistMinOccludedCurledFingers {
                return .fist
            }
        }

        if tipExtended >= openMinExtendedFingers && curledFingers == 0 {
            return .open
        }

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
