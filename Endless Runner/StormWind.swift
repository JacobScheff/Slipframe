//
//  StormWind.swift
//  Endless Runner
//
//  Pure helpers for Storm Pass shove telegraph + direction rules.
//

import Foundation

enum StormWind {
    /// Warning bar width factor: expand toward the shove, then shrink to 0.
    /// `progress` is 0…1 over the full telegraph; `expandFinishAt` is when full width is reached.
    static func gustExpandAmount(progress: Float, expandFinishAt: Float) -> Float {
        let finish = min(0.95, max(0.05, expandFinishAt))
        let p = min(1, max(0, progress))
        if p <= finish {
            let t = p / finish
            // Ease out while growing.
            return 1 - (1 - t) * (1 - t)
        }
        let t = (p - finish) / (1 - finish)
        // Ease in while shrinking away.
        return (1 - t) * (1 - t)
    }

    /// True once the expand+shrink cycle has finished (line fully gone).
    static func gustLineDidDisappear(progress: Float, expandFinishAt: Float) -> Bool {
        let finish = min(0.95, max(0.05, expandFinishAt))
        return progress >= 1 - 0.0001 || (
            progress > finish && gustExpandAmount(progress: progress, expandFinishAt: finish) <= 0.001
        )
    }

    /// Bar geometry for the telegraph.
    /// Expand: origin edge fixed, grows toward shove.
    /// Shrink: opposite — leading edge stays at full extent, bar collapses onward in the shove direction.
    static func gustBarLayout(
        progress: Float,
        expandFinishAt: Float,
        direction: Float,
        fullWidth: Float
    ) -> (width: Float, centerX: Float) {
        let dir: Float = direction >= 0 ? 1 : -1
        let finish = min(0.95, max(0.05, expandFinishAt))
        let amount = gustExpandAmount(progress: progress, expandFinishAt: finish)
        let width = max(0, fullWidth * amount)

        let originEdge = -dir * (fullWidth * 0.5)
        let leadEdge = dir * (fullWidth * 0.5)

        let centerX: Float
        if progress <= finish {
            // Grow from the far/origin side toward the shove.
            centerX = originEdge + dir * (width * 0.5)
        } else {
            // Shrink the other way: wipe toward the shove side.
            centerX = leadEdge - dir * (width * 0.5)
        }
        return (width, centerX)
    }

    /// Next shove direction (±1). Offset step is clamped to -1…+1 from start.
    /// Away from center must return; at center may pick either side.
    static func nextDirection<RNG: RandomNumberGenerator>(
        offsetStep: Int,
        preferredFromGap: Float?,
        rng: inout RNG
    ) -> Float {
        if offsetStep > 0 { return -1 }
        if offsetStep < 0 { return 1 }
        if let preferred = preferredFromGap, abs(preferred) > 0.01 {
            return preferred >= 0 ? 1 : -1
        }
        return Bool.random(using: &rng) ? 1 : -1
    }

    static func nextDirection(offsetStep: Int, preferredFromGap: Float?) -> Float {
        var rng = SystemRandomNumberGenerator()
        return nextDirection(offsetStep: offsetStep, preferredFromGap: preferredFromGap, rng: &rng)
    }

    static func applyStep(offsetStep: Int, direction: Float) -> Int {
        let delta = direction >= 0 ? 1 : -1
        return max(-1, min(1, offsetStep + delta))
    }

    /// Outer lane that must stay empty while shifting / held off-center.
    /// `-1` = left, `+1` = right. Pending shove wins over the held offset.
    static func forbiddenOuterLaneRaw(offsetStep: Int, pendingDirection: Float) -> Int? {
        if pendingDirection < -0.01 { return -1 }
        if pendingDirection > 0.01 { return 1 }
        if offsetStep < 0 { return -1 }
        if offsetStep > 0 { return 1 }
        return nil
    }

    /// Pick a wall lane pattern that never blocks the forbidden outer lane.
    /// Pattern entries use lane raw values: -1 left, 0 center, +1 right.
    static func chooseWallLanes<RNG: RandomNumberGenerator>(
        from patterns: [[Int]],
        offsetStep: Int,
        pendingDirection: Float,
        rng: inout RNG
    ) -> [Int] {
        let forbidden = forbiddenOuterLaneRaw(
            offsetStep: offsetStep,
            pendingDirection: pendingDirection
        )
        let allowed = patterns.filter { pattern in
            guard let forbidden else { return true }
            return !pattern.contains(forbidden)
        }
        return allowed.randomElement(using: &rng) ?? [0]
    }

    static func chooseWallLanes(
        from patterns: [[Int]],
        offsetStep: Int,
        pendingDirection: Float
    ) -> [Int] {
        var rng = SystemRandomNumberGenerator()
        return chooseWallLanes(
            from: patterns,
            offsetStep: offsetStep,
            pendingDirection: pendingDirection,
            rng: &rng
        )
    }
}
