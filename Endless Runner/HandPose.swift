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
    static let fistMaxTipToWrist: Float = 0.145
    /// Tip→wrist average above this supports an open hand.
    static let openMinTipToWrist: Float = 0.165

    /// Tip not much past the knuckle ⇒ curled (relative, works across hand sizes).
    static let fistTipPastKnuckle: Float = 0.035
    /// Tip clearly past the knuckle ⇒ extended.
    static let openTipPastKnuckle: Float = 0.07

    /// Absolute tip→knuckle fallback when relative measure is unavailable.
    static let fistTipToKnuckle: Float = 0.075
    static let openTipToKnuckle: Float = 0.105

    /// Intermediate tip folded in (fingertips often occlude in a fist).
    static let fistIntermediateToKnuckle: Float = 0.06

    static let fistMinCurledFingers = 2
    static let openMinExtendedFingers = 3
    static let minMeasuredFingers = 2

    /// Thumb tip near index tip ⇒ pinch/grab.
    static let pinchDistance: Float = 0.05

    static func isGrabPose(anchor: HandAnchor) -> Bool {
        classify(anchor: anchor) == .fist
    }

    static func isOpenPose(anchor: HandAnchor) -> Bool {
        classify(anchor: anchor) == .open
    }

    static func isFist(anchor: HandAnchor) -> Bool {
        isGrabPose(anchor: anchor)
    }

    /// Fist / open / unknown with a dead-band so open hands don't count as fists,
    /// while real closed hands still register via tip reach or knuckle-relative curl.
    static func classify(anchor: HandAnchor) -> Pose {
        guard anchor.isTracked else { return .unknown }
        guard let skeleton = anchor.handSkeleton else { return .unknown }

        let origin = anchor.originFromAnchorTransform
        let wrist = skeleton.joint(.wrist)
        guard wrist.isTracked else { return .unknown }
        let wristWorld = worldPosition(origin: origin, joint: wrist)

        // Pinch is a clear grab.
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
            let knuckleWorld: SIMD3<Float>? = knuckle.isTracked
                ? worldPosition(origin: origin, joint: knuckle)
                : nil

            let tip = skeleton.joint(finger.tip)
            if tip.isTracked {
                let tipWorld = worldPosition(origin: origin, joint: tip)
                let toWrist = simd_distance(tipWorld, wristWorld)
                tipToWrist.append(toWrist)

                if let knuckleWorld {
                    let knuckleToWrist = simd_distance(knuckleWorld, wristWorld)
                    let tipPastKnuckle = toWrist - knuckleToWrist
                    let tipToKnuckle = simd_distance(tipWorld, knuckleWorld)

                    // Relative curl is stabler across hand sizes than absolute tip→knuckle.
                    if tipPastKnuckle <= fistTipPastKnuckle || tipToKnuckle <= fistTipToKnuckle {
                        curledCount += 1
                    } else if tipPastKnuckle >= openTipPastKnuckle && tipToKnuckle >= openTipToKnuckle {
                        extendedCount += 1
                    }
                } else if toWrist <= fistMaxTipToWrist {
                    curledCount += 1
                }
                continue
            }

            // Tips often vanish in a fist — intermediates still track.
            let intermediate = skeleton.joint(finger.intermediate)
            if intermediate.isTracked, let knuckleWorld {
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
            // Open only with clear extension — dead-band in between stays unknown.
            if average >= openMinTipToWrist && extendedCount >= 2 {
                return .open
            }
            if average >= openMinTipToWrist && extendedCount >= openMinExtendedFingers {
                return .open
            }
            if average >= openMinTipToWrist && curledCount == 0 {
                return .open
            }
        }

        if extendedCount >= openMinExtendedFingers && curledCount == 0 {
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
