//
//  WallCollision.swift
//  Endless Runner
//
//  Pure AABB helpers for wall / duck-hazard hits. A contact (head or hand)
//  only counts when it overlaps a slab's kill box — not merely the same lane.
//

import simd

enum WallKind: Equatable {
    case standard
    case ghost
    case duck
}

enum ObstacleLayout {
    /// Local X for a lane slab. Adjacent double-lane blocks get a slight extra gap.
    static func slabLocalX(
        laneRaw: Int,
        blockingLaneRaws: Set<Int>,
        laneSpacing: Float,
        adjacentSpread: Float
    ) -> Float {
        var x = Float(laneRaw) * laneSpacing
        guard blockingLaneRaws.count == 2 else { return x }
        let ordered = blockingLaneRaws.sorted()
        guard let first = ordered.first, let last = ordered.last, last - first == 1 else { return x }
        if laneRaw == first { x -= adjacentSpread }
        if laneRaw == last { x += adjacentSpread }
        return x
    }

    /// Open outer lane raw (−1 left / +1 right) when exactly one adjacent double leaves one side open.
    /// `[left, center]` → right; `[center, right]` → left. Center-open or non-doubles → nil.
    static func adjacentDoubleOpenLaneRaw(blockingLaneRaws: Set<Int>) -> Int? {
        guard blockingLaneRaws.count == 2 else { return nil }
        let ordered = blockingLaneRaws.sorted()
        guard let first = ordered.first, let last = ordered.last, last - first == 1 else { return nil }
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
    static func pointHitsSlabs(
        point: SIMD3<Float>,
        wallZ: Float,
        previousWallZ: Float? = nil,
        slabXs: [Float],
        halfWidth: Float,
        halfDepth: Float,
        minY: Float,
        maxY: Float
    ) -> Bool {
        guard point.y >= minY, point.y <= maxY else { return false }
        let prior = previousWallZ ?? wallZ
        guard overlapsSweptZ(
            pointZ: point.z,
            wallZ: wallZ,
            previousWallZ: prior,
            halfDepth: halfDepth
        ) else { return false }

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

    /// True when the wall's back face has fully cleared behind the contact depth.
    static func hasPassedContact(wallZ: Float, contactZ: Float, halfDepth: Float) -> Bool {
        wallZ - contactZ > halfDepth
    }
}
