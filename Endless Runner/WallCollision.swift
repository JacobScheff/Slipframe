//
//  WallCollision.swift
//  Slipframe
//
//  Pure AABB helpers for wall / duck / jump-hazard hits. A contact (head, hand,
//  or body probe) only counts when it overlaps a slab's kill box — not merely
//  the same lane.
//

import simd

enum WallKind: Equatable {
    case standard
    case ghost
    case duck
    case jump
}

enum JumpHeightDetection {
    /// Playfield / world down. Never use headset-local down — tilting the
    /// device must not walk a height sample sideways.
    static let universalDown = SIMD3<Float>(0, -1, 0)

    /// How far the headset has risen above the standing eye height, measured
    /// along universal up (playfield Y). Ignores headset pitch/roll.
    static func headRise(headY: Float, standingEyeHeight: Float) -> Float {
        headY - standingEyeHeight
    }

    /// Body/feet probe from headset translation along universal down (XZ stays
    /// under the headset even if the display is tilted).
    static func bodyProbe(fromHead head: SIMD3<Float>, eyeHeight: Float) -> SIMD3<Float> {
        head + universalDown * eyeHeight
    }

    /// Median of standing-height samples (middle value after sort).
    static func medianHeight(of samples: [Float]) -> Float? {
        guard !samples.isEmpty else { return nil }
        let sorted = samples.sorted()
        return sorted[sorted.count / 2]
    }

    /// True when a headset Y reading is plausible for standing calibration.
    static func isPlausibleStandingHeight(_ height: Float) -> Bool {
        height >= 1.1 && height <= 2.1
    }
}

enum ObstacleLayout {
    /// True when exactly two neighboring lanes are blocked (spread-apart double wall).
    static func isAdjacentDouble(blockingLaneRaws: Set<Int>) -> Bool {
        guard blockingLaneRaws.count == 2 else { return false }
        let ordered = blockingLaneRaws.sorted()
        guard let first = ordered.first, let last = ordered.last else { return false }
        return last - first == 1
    }

    /// Local X for a lane slab. Adjacent double-lane blocks get a slight extra gap.
    static func slabLocalX(
        laneRaw: Int,
        blockingLaneRaws: Set<Int>,
        laneSpacing: Float,
        adjacentSpread: Float
    ) -> Float {
        var x = Float(laneRaw) * laneSpacing
        guard isAdjacentDouble(blockingLaneRaws: blockingLaneRaws) else { return x }
        let ordered = blockingLaneRaws.sorted()
        guard let first = ordered.first, let last = ordered.last else { return x }
        if laneRaw == first { x -= adjacentSpread }
        if laneRaw == last { x += adjacentSpread }
        return x
    }

    /// Open outer lane raw (−1 left / +1 right) when exactly one adjacent double leaves one side open.
    /// `[left, center]` → right; `[center, right]` → left. Center-open or non-doubles → nil.
    static func adjacentDoubleOpenLaneRaw(blockingLaneRaws: Set<Int>) -> Int? {
        guard isAdjacentDouble(blockingLaneRaws: blockingLaneRaws) else { return nil }
        let open = Set([-1, 0, 1]).subtracting(blockingLaneRaws)
        guard open.count == 1, let lane = open.first, lane != 0 else { return nil }
        return lane
    }

    /// True when two consecutive adjacent doubles force a full cross-corridor dodge (left↔right).
    static func requiresOppositeOpenLaneSpacing(
        previousOpenLaneRaw: Int?,
        nextOpenLaneRaw: Int?
    ) -> Bool {
        guard let previousOpenLaneRaw, let nextOpenLaneRaw else { return false }
        return previousOpenLaneRaw != nextOpenLaneRaw
    }
}

enum WallCollision {
    /// Visual walls are thick for readability; the kill volume stays thinner so
    /// a slab does not register a hit while it still looks ~0.5 m away.
    static func halfDepth(visualThickness: Float, maxHalf: Float = 0.18, pad: Float = 0.02) -> Float {
        min(visualThickness * 0.5, maxHalf) + pad
    }

    static func halfWidth(visualWidth: Float, inset: Float) -> Float {
        max(0.05, visualWidth * 0.5 - inset)
    }

    /// True when `pointZ` overlaps the swept slab interval from last frame → this frame.
    static func overlapsSweptZ(
        pointZ: Float,
        wallZ: Float,
        previousWallZ: Float,
        halfDepth: Float
    ) -> Bool {
        let lo = min(wallZ, previousWallZ) - halfDepth
        let hi = max(wallZ, previousWallZ) + halfDepth
        return pointZ >= lo && pointZ <= hi
    }

    /// True when `point` overlaps any slab centered at `slabXs` on the wall's Z.
    /// When `sealBetweenSlabs` is set, the kill box is one continuous X span from the
    /// leftmost to rightmost slab (closes the squeeze gap on adjacent doubles).
    static func pointHitsSlabs(
        point: SIMD3<Float>,
        wallZ: Float,
        previousWallZ: Float? = nil,
        slabXs: [Float],
        halfWidth: Float,
        halfDepth: Float,
        minY: Float,
        maxY: Float,
        sealBetweenSlabs: Bool = false
    ) -> Bool {
        guard point.y >= minY, point.y <= maxY else { return false }
        let prior = previousWallZ ?? wallZ
        guard overlapsSweptZ(
            pointZ: point.z,
            wallZ: wallZ,
            previousWallZ: prior,
            halfDepth: halfDepth
        ) else { return false }

        if sealBetweenSlabs, let lo = slabXs.min(), let hi = slabXs.max(), hi > lo {
            return point.x >= lo - halfWidth && point.x <= hi + halfWidth
        }

        for slabX in slabXs {
            if point.x >= slabX - halfWidth, point.x <= slabX + halfWidth {
                return true
            }
        }
        return false
    }

    /// Hanging low-ceiling hazard: hit if the contact is inside the XZ box and
    /// still above `clearanceY` (player must duck under).
    static func pointHitsDuckBarrier(
        point: SIMD3<Float>,
        wallZ: Float,
        previousWallZ: Float? = nil,
        centerX: Float,
        halfWidth: Float,
        halfDepth: Float,
        clearanceY: Float,
        maxY: Float
    ) -> Bool {
        guard point.y >= clearanceY, point.y <= maxY else { return false }
        let prior = previousWallZ ?? wallZ
        guard overlapsSweptZ(
            pointZ: point.z,
            wallZ: wallZ,
            previousWallZ: prior,
            halfDepth: halfDepth
        ) else { return false }
        return abs(point.x - centerX) <= halfWidth
    }

    /// Low ground hurdle: hit if the headset XZ is inside the kill box and the
    /// headset has not risen at least `minRise` above standing eye height
    /// (small physical hop clears). Height uses universal up, not headset-local up.
    static func pointHitsJumpBarrier(
        point: SIMD3<Float>,
        wallZ: Float,
        previousWallZ: Float? = nil,
        centerX: Float,
        halfWidth: Float,
        halfDepth: Float,
        headRise: Float,
        minRise: Float
    ) -> Bool {
        guard headRise < minRise else { return false }
        let prior = previousWallZ ?? wallZ
        guard overlapsSweptZ(
            pointZ: point.z,
            wallZ: wallZ,
            previousWallZ: prior,
            halfDepth: halfDepth
        ) else { return false }
        return abs(point.x - centerX) <= halfWidth
    }

    /// True when the wall's back face has fully cleared behind the contact depth.
    static func hasPassedContact(wallZ: Float, contactZ: Float, halfDepth: Float) -> Bool {
        wallZ - contactZ > halfDepth
    }
}
