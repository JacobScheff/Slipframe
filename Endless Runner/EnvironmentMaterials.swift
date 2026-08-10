//
//  EnvironmentMaterials.swift
//  Slipframe
//
//  Builds RealityKit materials from EnvironmentPalette / TintColor so custom
//  assets can later reuse the same tint entry points.
//

import RealityKit
import UIKit

enum EnvironmentMaterials {
    static func uiColor(_ tint: TintColor) -> UIColor {
        UIColor(red: CGFloat(tint.r), green: CGFloat(tint.g), blue: CGFloat(tint.b), alpha: CGFloat(tint.a))
    }

    /// Linear component-wise blend between two colors — used to give procedural
    /// rift/obstacle debris a per-instance gradient without a texture lookup.
    static func lerpColor(_ a: UIColor, _ b: UIColor, _ t: Float) -> UIColor {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        let u = CGFloat(max(0, min(1, t)))
        return UIColor(
            red: ar + (br - ar) * u,
            green: ag + (bg - ag) * u,
            blue: ab + (bb - ab) * u,
            alpha: aa + (ba - aa) * u
        )
    }

    static func unlit(_ tint: TintColor) -> UnlitMaterial {
        UnlitMaterial(color: uiColor(tint))
    }

    static func simple(_ tint: TintColor, metallic: Bool = false, roughness: Float = 0.5) -> SimpleMaterial {
        SimpleMaterial(color: uiColor(tint), roughness: MaterialScalarParameter(floatLiteral: roughness), isMetallic: metallic)
    }

    /// Translucent wall body. Opacity/tint come from the active biome palette
    /// (or a ghost override) so USDA wall art can adopt the same parameters later.
    static func wallBody(
        tint: TintColor,
        emissive: TintColor,
        opacity: Float,
        emissiveIntensity: Float
    ) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        let clampedOpacity = max(0.02, min(1, opacity))
        // Keep base color alpha in sync with blending so thick slabs don't read solid.
        let body = TintColor(r: tint.r, g: tint.g, b: tint.b, a: clampedOpacity)
        material.baseColor = .init(tint: uiColor(body))
        material.roughness = .init(floatLiteral: 0.2)
        material.metallic = .init(floatLiteral: 0.0)
        material.emissiveColor = .init(color: uiColor(emissive))
        material.emissiveIntensity = emissiveIntensity
        material.blending = .transparent(opacity: .init(floatLiteral: clampedOpacity))
        material.faceCulling = .none
        return material
    }

    /// Near-invisible glass for Ghost Glass — as transparent as the material allows.
    /// Opacity is low enough that front+back alpha stacking on the jagged
    /// shatter-pane mesh reads no differently than a single face would.
    static func ghostWallBody(opacity: Float) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        let clampedOpacity = max(0.001, min(0.02, opacity))
        let body = TintColor(r: 0.95, g: 0.97, b: 1.0, a: clampedOpacity)
        material.baseColor = .init(tint: uiColor(body))
        material.roughness = .init(floatLiteral: 0.12)
        material.metallic = .init(floatLiteral: 0.0)
        // No emissive — glow was making slabs read solid even at tiny alpha.
        material.emissiveColor = .init(color: uiColor(TintColor(r: 1, g: 1, b: 1, a: 1)))
        material.emissiveIntensity = 0
        material.blending = .transparent(opacity: .init(floatLiteral: clampedOpacity))
        material.faceCulling = .none
        return material
    }

    static func coin(_ tint: TintColor) -> SimpleMaterial {
        simple(tint, metallic: true, roughness: 0.25)
    }

    static func crystalHalf(type: CrystalHalfType, charged: Bool) -> PhysicallyBasedMaterial {
        let tint = CrystalCombine.tint(for: type, charged: charged)
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: uiColor(tint))
        material.roughness = .init(floatLiteral: charged ? 0.1 : 0.28)
        material.metallic = .init(floatLiteral: 0.15)
        material.emissiveColor = .init(color: uiColor(tint))
        material.emissiveIntensity = charged ? 1.1 : 0.55
        // Faceted glassy sheen so the new gem silhouette reads as a cut crystal, not plastic.
        material.clearcoat = .init(floatLiteral: charged ? 1.0 : 0.7)
        material.clearcoatRoughness = .init(floatLiteral: 0.08)
        material.faceCulling = .none
        return material
    }

    /// Full-gem crystal spire material for Crystal Cave's lane-blocking formations —
    /// same family as `crystalHalf`, dimmer/cooler so it reads as scenery, not a pickup.
    static func crystalSpire(tint: TintColor, opacity: Float) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        let body = TintColor(r: tint.r, g: tint.g, b: tint.b, a: max(0.35, min(1, opacity)))
        material.baseColor = .init(tint: uiColor(body))
        material.roughness = .init(floatLiteral: 0.18)
        material.metallic = .init(floatLiteral: 0.1)
        material.emissiveColor = .init(color: uiColor(tint))
        material.emissiveIntensity = 0.5
        material.clearcoat = .init(floatLiteral: 0.85)
        material.clearcoatRoughness = .init(floatLiteral: 0.1)
        material.blending = .transparent(opacity: .init(floatLiteral: max(0.35, min(1, opacity))))
        material.faceCulling = .none
        return material
    }
}
