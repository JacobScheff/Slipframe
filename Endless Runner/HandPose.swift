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

    /// Strict tip curl — partial closes should not count; need tips near knuckles.
    static let fistTipPastKnuckle: Float = 0.02
    static let fistTipToKnuckle: Float = 0.05
    /// Clear extension past the knuckle ⇒ open finger.
    static let openTipPastKnuckle: Float = 0.065
    static let openTipToKnuckle: Float = 0.1

    /// Occlusion-resistant curl: intermediate tip folded toward knuckle / palm.
    static let fistIntermediateToKnuckle: Float = 0.07
    static let fistIntermediateToWrist: Float = 0.11

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
    /// Important: a *fully* closed fist often occludes fingertips in visionOS, while a
    /// *partial* close still tracks tips. Tip-based curl is therefore strict, and
    /// missing tips fall back to intermediate-joint curl so full fists still register.
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
        var tipCurled = 0
        var tipExtended = 0
        var occludedCurled = 0
        var tipsTracked = 0

        for finger in fingers {
            let knuckle = skeleton.joint(finger.knuckle)
            let knuckleWorld: SIMD3<Float>? = knuckle.isTracked
                ? worldPosition(origin: origin, joint: knuckle)
                : nil

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

                    // Strict: only tightly curled tips count (avoids "almost closed").
                    if tipPastKnuckle <= fistTipPastKnuckle && tipToKnuckle <= fistTipToKnuckle {
                        tipCurled += 1
                    } else if tipPastKnuckle >= openTipPastKnuckle || tipToKnuckle >= openTipToKnuckle {
                        tipExtended += 1
                    }
                }
            } else {
                // Full fist path: tip missing — score curl from intermediate joints.
                let intermediate = skeleton.joint(finger.intermediate)
                if intermediate.isTracked {
                    let midWorld = worldPosition(origin: origin, joint: intermediate)
                    let midToWrist = simd_distance(midWorld, wristWorld)
                    var curled = midToWrist <= fistIntermediateToWrist
                    if let knuckleWorld,
                       simd_distance(midWorld, knuckleWorld) <= fistIntermediateToKnuckle {
                        curled = true
                    }
                    if curled { occludedCurled += 1 }
                }
            }
        }

        // Full fist: few/no tips, but intermediates folded in.
        if tipsTracked <= 1 && occludedCurled >= fistMinOccludedCurledFingers {
            return .fist
        }
        if tipsTracked <= 2 && occludedCurled >= 3 {
            return .fist
        }

        // Strict tip fist (fully curled fingertips still visible).
        if tipCurled >= fistMinCurledFingers {
            return .fist
        }

        if tipToWrist.count >= 3 {
            let average = tipToWrist.reduce(0, +) / Float(tipToWrist.count)
            // Very short tip reach + mostly curled ⇒ fist.
            if average <= fistMaxTipToWrist && tipCurled >= 2 && tipExtended == 0 {
                return .fist
            }
            // Clear open hand.
            if average >= openMinTipToWrist && tipExtended >= openMinExtendedFingers {
                return .open
            }
            if average >= openMinTipToWrist && tipCurled == 0 && tipExtended >= 2 {
                return .open
            }
        }

        if tipExtended >= openMinExtendedFingers && tipCurled == 0 {
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
