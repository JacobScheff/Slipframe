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

    /// Near-invisible holographic volume fill — the "glass box" look is
    /// deliberately avoided. Neon silhouette comes from `hologramEdge` wireframe
    /// overlays, not from a solid translucent slab. `opacity` from the palette
    /// is treated as a soft upper bound; fill stays highly see-through.
    static func wallBody(
        tint: TintColor,
        emissive: TintColor,
        opacity: Float,
        emissiveIntensity: Float
    ) -> PhysicallyBasedMaterial {
        hologramFill(
            tint: tint,
            emissive: emissive,
            opacity: min(0.08, max(0.02, opacity * 0.14)),
            emissiveIntensity: max(0.15, emissiveIntensity * 0.35)
        )
    }

    /// Digital-hologram volume: barely-there tinted fill so the obstacle reads as
    /// light, not glass. Pair with `hologramEdge` wireframe for the neon outline.
    static func hologramFill(
        tint: TintColor,
        emissive: TintColor,
        opacity: Float = 0.055,
        emissiveIntensity: Float = 0.25
    ) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        let clampedOpacity = max(0.015, min(0.1, opacity))
        let body = TintColor(r: tint.r, g: tint.g, b: tint.b, a: clampedOpacity)
        material.baseColor = .init(tint: uiColor(body))
        material.roughness = .init(floatLiteral: 0.05)
        material.metallic = .init(floatLiteral: 0.0)
        material.emissiveColor = .init(color: uiColor(emissive))
        material.emissiveIntensity = emissiveIntensity
        material.blending = .transparent(opacity: .init(floatLiteral: clampedOpacity))
        material.faceCulling = .none
        return material
    }

    /// Bright neon unlit edge / wireframe stroke — biome-colored silhouette glow
    /// that sells the hologram "Fresnel" rim without a custom shader.
    static func hologramEdge(emissive: TintColor, alpha: Float = 1) -> UnlitMaterial {
        let color = UIColor(
            red: CGFloat(emissive.r),
            green: CGFloat(emissive.g),
            blue: CGFloat(emissive.b),
            alpha: CGFloat(max(0.05, min(1, alpha)))
        )
        var material = UnlitMaterial(color: color)
        if alpha < 0.99 {
            material.blending = .transparent(opacity: .init(floatLiteral: max(0.05, min(1, alpha))))
        }
        return material
    }

    /// Ghost Glass fill — essentially invisible. The pane is conveyed by a
    /// faint wireframe (`ghostHologramEdge`), not by a milky glass slab.
    static func ghostWallBody(opacity: Float) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        // Clamp extremely low; front+back faces must not stack into a visible plate.
        let clampedOpacity = max(0.0002, min(0.004, opacity))
        let body = TintColor(r: 0.95, g: 0.97, b: 1.0, a: clampedOpacity)
        material.baseColor = .init(tint: uiColor(body))
        material.roughness = .init(floatLiteral: 0.05)
        material.metallic = .init(floatLiteral: 0.0)
        material.emissiveColor = .init(color: uiColor(TintColor(r: 1, g: 1, b: 1, a: 1)))
        material.emissiveIntensity = 0
        material.blending = .transparent(opacity: .init(floatLiteral: clampedOpacity))
        material.faceCulling = .none
        return material
    }

    /// Barely-there cool wireframe for Ghost Glass — readable only at close range.
    static func ghostHologramEdge() -> UnlitMaterial {
        hologramEdge(emissive: TintColor(r: 0.8, g: 0.9, b: 1.0, a: 1), alpha: 0.18)
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

    /// Crystal Cave obstacle fill — holographic gem volume (highly transparent)
    /// rather than a solid crystal chunk. Neon wireframe edges carry the silhouette.
    static func crystalSpire(tint: TintColor, opacity: Float) -> PhysicallyBasedMaterial {
        hologramFill(
            tint: tint,
            emissive: tint,
            opacity: min(0.09, max(0.03, opacity * 0.16)),
            emissiveIntensity: 0.4
        )
    }
}
