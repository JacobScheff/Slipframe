//
//  StormWind.swift
//  Endless Runner
//
//  Pure helpers for Storm Pass shove telegraph + direction rules.
//

import Foundation

enum StormWind {
    /// Warning bar width factor: expand toward the shove, then shrink back to 0.
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
        // Ease in while shrinking back along the same axis.
        return (1 - t) * (1 - t)
    }

    /// Next shove direction (±1). Offset step is clamped to -1…+1 from start.
    /// Away from center must return; at center may pick either side.
    static func nextDirection(offsetStep: Int, preferredFromGap: Float?) -> Float {
        if offsetStep > 0 { return -1 }
        if offsetStep < 0 { return 1 }
        if let preferred = preferredFromGap, abs(preferred) > 0.01 {
            return preferred >= 0 ? 1 : -1
        }
        return Bool.random() ? 1 : -1
    }

    static func applyStep(offsetStep: Int, direction: Float) -> Int {
        let delta = direction >= 0 ? 1 : -1
        return max(-1, min(1, offsetStep + delta))
    }
}
