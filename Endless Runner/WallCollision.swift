//
//  WallCollision.swift
//  Endless Runner
//
//  Pure AABB helpers for red-wall hits. A contact (head or hand) only counts
//  when it overlaps a slab's kill box — not merely the same lane.
//

import simd

enum WallCollision {
    /// Visual walls are thick for readability; the kill volume stays thinner so
    /// a slab does not register a hit while it still looks ~0.5 m away.
    static func halfDepth(visualThickness: Float, maxHalf: Float = 0.18, pad: Float = 0.02) -> Float {
        min(visualThickness * 0.5, maxHalf) + pad
    }

    static func halfWidth(visualWidth: Float, inset: Float) -> Float {
        max(0.05, visualWidth * 0.5 - inset)
    }

    /// True when `point` overlaps any slab centered at `slabXs` on the wall's Z.
    static func pointHitsSlabs(
        point: SIMD3<Float>,
        wallZ: Float,
        slabXs: [Float],
        halfWidth: Float,
        halfDepth: Float,
        minY: Float,
        maxY: Float
    ) -> Bool {
        guard point.y >= minY, point.y <= maxY else { return false }
        guard abs(point.z - wallZ) <= halfDepth else { return false }

        for slabX in slabXs {
            if point.x >= slabX - halfWidth, point.x <= slabX + halfWidth {
                return true
            }
        }
        return false
    }

    /// True when the wall's back face has fully cleared behind the contact depth.
    static func hasPassedContact(wallZ: Float, contactZ: Float, halfDepth: Float) -> Bool {
        wallZ - contactZ > halfDepth
    }
}
