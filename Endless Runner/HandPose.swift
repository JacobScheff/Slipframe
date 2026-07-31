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
    /// Kept low so partial / facing-away opens still release a held half.
    static let openMinTipToWrist: Float = 0.12

    /// Strict tip curl — tips parked near knuckles (partial close, palm toward camera).
    static let fistTipPastKnuckle: Float = 0.02
    static let fistTipToKnuckle: Float = 0.05
    /// Tip folded past the knuckle toward the palm (full fist; tip→wrist ≤ knuckle→wrist).
    static let fistTipTuckedPastKnuckle: Float = 0.0
    /// Tip extension past the knuckle ⇒ open finger (lenient for reliable release).
    static let openTipPastKnuckle: Float = 0.03
    static let openTipToKnuckle: Float = 0.065

    /// Occlusion-resistant curl: intermediate tip folded toward knuckle / palm.
    static let fistIntermediateToKnuckle: Float = 0.07
    static let fistIntermediateToWrist: Float = 0.11
    /// Average intermediate→wrist below this + no extension ⇒ closed hand.
    static let fistMaxIntermediateToWrist: Float = 0.10

    /// Intermediate tip stretched away from wrist / knuckle ⇒ open finger.
    /// Works when the hand faces away and tip estimates are noisy.
    static let openIntermediateToWrist: Float = 0.10
    static let openIntermediatePastKnuckle: Float = 0.015
    static let openMinIntermediateToWrist: Float = 0.105

    /// Index↔little tip span — open hands are wide even when facing away.
    static let openFingerSpan: Float = 0.07

    static let fistMinCurledFingers = 3
    static let fistMinOccludedCurledFingers = 2
    /// Two extended fingers is enough — open is the release signal.
    static let openMinExtendedFingers = 2

    /// Thumb tip near index tip ⇒ pinch/grab.
    static let pinchDistance: Float = 0.045

    /// Hold/grab when the hand is tracked and not fully open.
    static func isGrabPose(anchor: HandAnchor) -> Bool {
        guard anchor.isTracked else { return false }
        return classify(anchor: anchor) != .open
    }

    static func isOpenPose(anchor: HandAnchor) -> Bool {
        classify(anchor: anchor) == .open
    }

    static func isFist(anchor: HandAnchor) -> Bool {
        classify(anchor: anchor) == .fist
    }

    /// Classifies fist vs open.
    ///
    /// Crystal Cave holds on anything that is *not* a clear open hand, so open
    /// detection is the release signal. Open scoring uses tip extension,
    /// intermediate stretch, and finger span so a facing-away open palm still
    /// drops. Fist paths remain for diagnostics / pinch shortcuts.
    static func classify(anchor: HandAnchor) -> Pose {
        guard anchor.isTracked else { return .unknown }
        guard let skeleton = anchor.handSkeleton else { return .unknown }

        let origin = anchor.originFromAnchorTransform
        let wrist = skeleton.joint(.wrist)
        guard wrist.isTracked else { return .unknown }
        let wristWorld = worldPosition(origin: origin, joint: wrist)

        // Pinch is a clear grab (not open).
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
        var intermediateExtended = 0
        var intermediateCurled = 0
        var curledFingers = 0
        var extendedFingers = 0
        var tipsTracked = 0

        for finger in fingers {
            let knuckle = skeleton.joint(finger.knuckle)
            let knuckleWorld: SIMD3<Float>? = knuckle.isTracked
                ? worldPosition(origin: origin, joint: knuckle)
                : nil

            var fingerIntermediateCurled = false
            var fingerIntermediateExtended = false
            let intermediate = skeleton.joint(finger.intermediate)
            if intermediate.isTracked {
                let midWorld = worldPosition(origin: origin, joint: intermediate)
                let midWristDist = simd_distance(midWorld, wristWorld)
                midToWrist.append(midWristDist)

                if midWristDist <= fistIntermediateToWrist {
                    fingerIntermediateCurled = true
                }
                if let knuckleWorld {
                    let midToKnuckle = simd_distance(midWorld, knuckleWorld)
                    if midToKnuckle <= fistIntermediateToKnuckle {
                        fingerIntermediateCurled = true
                    }
                    let knuckleToWrist = simd_distance(knuckleWorld, wristWorld)
                    let midPastKnuckle = midWristDist - knuckleToWrist
                    if midPastKnuckle >= openIntermediatePastKnuckle
                        || midWristDist >= openIntermediateToWrist {
                        fingerIntermediateExtended = true
                    }
                } else if midWristDist >= openIntermediateToWrist {
                    fingerIntermediateExtended = true
                }

                if fingerIntermediateCurled {
                    intermediateCurled += 1
                    fingerIntermediateExtended = false
                } else if fingerIntermediateExtended {
                    intermediateExtended += 1
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

                    if tipPastKnuckle <= fistTipTuckedPastKnuckle
                        || (tipPastKnuckle <= fistTipPastKnuckle && tipToKnuckle <= fistTipToKnuckle) {
                        fingerTipCurled = true
                    } else if tipPastKnuckle >= openTipPastKnuckle || tipToKnuckle >= openTipToKnuckle {
                        fingerTipExtended = true
                    }
                } else if toWrist <= fistMaxTipToWrist {
                    fingerTipCurled = true
                } else if toWrist >= openMinTipToWrist {
                    fingerTipExtended = true
                }
            }

            let fingerCurled = fingerTipCurled || fingerIntermediateCurled
            let fingerExtended = (fingerTipExtended || fingerIntermediateExtended) && !fingerCurled
            if fingerExtended {
                extendedFingers += 1
                if fingerTipExtended { tipExtended += 1 }
            } else if fingerCurled {
                curledFingers += 1
            }
        }

        // Open first — release signal must win when the palm is clearly spread.
        let tipAverage: Float? = tipToWrist.count >= 3
            ? tipToWrist.reduce(0, +) / Float(tipToWrist.count)
            : nil
        let midAverage: Float? = midToWrist.count >= 3
            ? midToWrist.reduce(0, +) / Float(midToWrist.count)
            : nil

        let indexTip = skeleton.joint(.indexFingerTip)
        let littleTip = skeleton.joint(.littleFingerTip)
        var wideSpan = false
        if indexTip.isTracked, littleTip.isTracked {
            let indexWorld = worldPosition(origin: origin, joint: indexTip)
            let littleWorld = worldPosition(origin: origin, joint: littleTip)
            wideSpan = simd_distance(indexWorld, littleWorld) >= openFingerSpan
        }

        if extendedFingers >= openMinExtendedFingers && curledFingers <= 2 {
            return .open
        }
        if tipExtended >= openMinExtendedFingers && curledFingers <= 1 {
            return .open
        }
        if intermediateExtended >= openMinExtendedFingers && curledFingers <= 2 {
            return .open
        }
        if let tipAverage, tipAverage >= openMinTipToWrist, curledFingers <= 1, extendedFingers >= 1 {
            return .open
        }
        if let midAverage, midAverage >= openMinIntermediateToWrist, curledFingers <= 2, extendedFingers >= 1 {
            return .open
        }
        // Wide index↔little span is a strong open signal even facing away.
        if wideSpan {
            return .open
        }
        // Reach-only fallback when finger curl labels are noisy.
        if let tipAverage, tipAverage >= openMinTipToWrist, curledFingers <= 2 {
            return .open
        }
        if let midAverage, midAverage >= openMinIntermediateToWrist, curledFingers <= 2 {
            return .open
        }

        // Closed / grab paths.
        if tipsTracked <= 1 && intermediateCurled >= fistMinOccludedCurledFingers {
            return .fist
        }
        if tipsTracked <= 2 && intermediateCurled >= 3 {
            return .fist
        }
        if curledFingers >= fistMinCurledFingers && extendedFingers == 0 {
            return .fist
        }
        if intermediateCurled >= fistMinCurledFingers && extendedFingers == 0 {
            return .fist
        }
        if let tipAverage, tipAverage <= fistMaxTipToWrist, curledFingers >= 2, extendedFingers == 0 {
            return .fist
        }
        if let midAverage,
           midAverage <= fistMaxIntermediateToWrist,
           extendedFingers == 0,
           intermediateCurled >= fistMinOccludedCurledFingers {
            return .fist
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
