//
//  CrystalCombine.swift
//  Slipframe
//
//  Pure Crystal Cave half-crystal rules (grab/merge coin awards).
//

import Foundation
import simd

enum CrystalHalfType: String, CaseIterable, Equatable {
    case red
    case blue
}

enum CrystalCombine {
    /// Coins awarded for a normal + normal combine.
    static let baseMergeCoins = 5
    /// Multiplier when exactly one half is charged.
    static let oneChargedMultiplier = 10
    /// Multiplier when both halves are charged.
    static let bothChargedMultiplier = 2000
    /// ~1% of spawned halves are charged.
    static let chargedSpawnChance: Float = 0.01
    /// Hands must be within this distance to merge (meters).
    static let combineDistance: Float = 0.22

    /// Half-crystal grab samples. `contactPoints` stores wrist/arm first, then fingertips.
    /// Crystal Cave ignores the wrist so only the hand (tips + optional grip) can pick up a half.
    static func handOnlyContacts(
        from contacts: [SIMD3<Float>],
        grip: SIMD3<Float>? = nil
    ) -> [SIMD3<Float>] {
        var points = Array(contacts.dropFirst())
        if let grip, !points.contains(where: { distance($0, grip) < 0.01 }) {
            points.append(grip)
        }
        return points
    }

    static func canMerge(left: CrystalHalfType, right: CrystalHalfType) -> Bool {
        left != right
    }

    /// Coin award for a successful different-type merge (score is distance-only).
    /// - normal + normal → 5
    /// - one charged → 50
    /// - both charged → 10000
    static func mergeCoinAward(leftCharged: Bool, rightCharged: Bool) -> Int {
        switch (leftCharged, rightCharged) {
        case (true, true):
            return baseMergeCoins * bothChargedMultiplier
        case (true, false), (false, true):
            return baseMergeCoins * oneChargedMultiplier
        case (false, false):
            return baseMergeCoins
        }
    }

    static func makeHalf<RNG: RandomNumberGenerator>(
        rng: inout RNG
    ) -> (type: CrystalHalfType, charged: Bool) {
        let type = CrystalHalfType.allCases.randomElement(using: &rng) ?? .red
        let charged = Float.random(in: 0...1, using: &rng) < chargedSpawnChance
        return (type, charged)
    }

    static func tint(for type: CrystalHalfType, charged: Bool) -> TintColor {
        switch (type, charged) {
        case (.red, false):
            return TintColor(r: 1.0, g: 0.25, b: 0.35, a: 1)
        case (.red, true):
            return TintColor(r: 1.0, g: 0.55, b: 0.15, a: 1)
        case (.blue, false):
            return TintColor(r: 0.25, g: 0.55, b: 1.0, a: 1)
        case (.blue, true):
            return TintColor(r: 0.55, g: 0.85, b: 1.0, a: 1)
        }
    }
}
