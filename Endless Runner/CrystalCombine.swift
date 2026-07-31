//
//  CrystalCombine.swift
//  Endless Runner
//
//  Pure Crystal Cave half-crystal rules (grab/merge payouts).
//

import Foundation

enum CrystalHalfType: String, CaseIterable, Equatable {
    case red
    case blue
}

enum CrystalCombine {
    static let baseCoinPoints = 10
    /// ~1% of spawned halves are charged.
    static let chargedSpawnChance: Float = 0.01
    /// Hands must be within this distance to merge (meters).
    static let combineDistance: Float = 0.22

    static func canMerge(left: CrystalHalfType, right: CrystalHalfType) -> Bool {
        left != right
    }

    /// Payout for a successful different-type merge.
    /// - normal + normal → 5×
    /// - one charged → 10×
    /// - both charged → 1000×
    static func mergePayout(leftCharged: Bool, rightCharged: Bool) -> Int {
        switch (leftCharged, rightCharged) {
        case (true, true):
            return baseCoinPoints * 1000
        case (true, false), (false, true):
            return baseCoinPoints * 10
        case (false, false):
            return baseCoinPoints * 5
        }
    }

    static func makeHalf(rng: inout some RandomNumberGenerator) -> (type: CrystalHalfType, charged: Bool) {
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
