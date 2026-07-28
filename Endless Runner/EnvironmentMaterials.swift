//
//  EnvironmentMaterials.swift
//  Endless Runner
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
        let body = TintColor(r: tint.r, g: tint.g, b: tint.b, a: opacity)
        material.baseColor = .init(tint: uiColor(body))
        material.roughness = .init(floatLiteral: 0.35)
        material.metallic = .init(floatLiteral: 0.05)
        material.emissiveColor = .init(color: uiColor(emissive))
        material.emissiveIntensity = emissiveIntensity
        material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        return material
    }

    static func coin(_ tint: TintColor) -> SimpleMaterial {
        simple(tint, metallic: true, roughness: 0.25)
    }

    /// Soft translucent haze volume for Fog Hollow (not a solid occluding plate).
    static func fogVolume(_ tint: TintColor) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        // Keep per-layer alpha low; many overlapping layers build density gradually.
        let alpha = max(0.015, min(0.1, tint.a))
        material.baseColor = .init(tint: uiColor(TintColor(r: tint.r, g: tint.g, b: tint.b, a: alpha)))
        material.roughness = .init(floatLiteral: 1.0)
        material.metallic = .init(floatLiteral: 0.0)
        material.emissiveColor = .init(color: uiColor(TintColor(r: tint.r, g: tint.g, b: tint.b, a: 1)))
        material.emissiveIntensity = 0.04
        material.blending = .transparent(opacity: .init(floatLiteral: alpha))
        return material
    }

    static func crystalHalf(type: CrystalHalfType, charged: Bool) -> PhysicallyBasedMaterial {
        let tint = CrystalCombine.tint(for: type, charged: charged)
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: uiColor(tint))
        material.roughness = .init(floatLiteral: charged ? 0.15 : 0.35)
        material.metallic = .init(floatLiteral: 0.2)
        material.emissiveColor = .init(color: uiColor(tint))
        material.emissiveIntensity = charged ? 1.1 : 0.55
        return material
    }
}
