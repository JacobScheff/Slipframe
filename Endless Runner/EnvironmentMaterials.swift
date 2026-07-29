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

    /// Near-invisible glass for Ghost Glass — tiny fill, almost no glow.
    /// Uses its own opacity floor (below normal walls) and back-face culling so
    /// thick slabs don't stack front+back alpha into a solid white sheet.
    static func ghostWallBody(opacity: Float) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        let clampedOpacity = max(0.004, min(0.05, opacity))
        let body = TintColor(r: 0.95, g: 0.97, b: 1.0, a: clampedOpacity)
        material.baseColor = .init(tint: uiColor(body))
        material.roughness = .init(floatLiteral: 0.15)
        material.metallic = .init(floatLiteral: 0.0)
        material.emissiveColor = .init(color: uiColor(TintColor(r: 0.85, g: 0.92, b: 1.0, a: 1)))
        material.emissiveIntensity = 0.015
        material.blending = .transparent(opacity: .init(floatLiteral: clampedOpacity))
        material.faceCulling = .back
        return material
    }

    static func coin(_ tint: TintColor) -> SimpleMaterial {
        simple(tint, metallic: true, roughness: 0.25)
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
