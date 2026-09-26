// Blender-authored USDZ prototypes. Loaded once before the world is attached;
// spawn paths only clone shared meshes/materials and never touch disk.
import Foundation
import RealityKit
import UIKit
import OSLog
import simd

/// Cosmetic-only, repeatable placement. Never consumes the obstacle/wind RNG.
enum SceneryVariation {
    struct Placement: Equatable {
        let position: SIMD3<Float>
        let scale: SIMD3<Float>
        let yaw: Float
        let lean: Float
        let variant: Int
    }

    static func placements(biome: EnvironmentID, seed: UInt64) -> [Placement] {
        // Service cabinets and structural ribs should stay level and aligned.
        guard biome != .lowCrawl else { return [] }
        var hash = seed ^ 0x5343_454E_4552_5931
        for byte in biome.rawValue.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100_0000_01B3
        }
        var rng = SeededGenerator(seed: hash)
        // Explicit 24-bit conversion makes these cosmetic samples stable across platforms.
        func sample(_ range: ClosedRange<Float>) -> Float {
            let unit = Float(rng.next() >> 40) / Float(0xFF_FFFF)
            return range.lowerBound + unit * (range.upperBound - range.lowerBound)
        }
        let natural = biome == .emberRun || biome == .summitStep || biome == .crystalCave
        let angle: Float = natural ? 0.24 : 0.08
        // Shuffle small bags so every silhouette appears, without the obvious
        // 0-1-2 repeat. Keep sampling explicit for stable cross-platform replays.
        let variantCount = BiomeAssetID.propVariantCount(biome)
        var variants = Array(0..<variantCount)
        var previousVariant: Int?
        return (0..<8).map { index in
            if index.isMultiple(of: variantCount) {
                if variantCount > 1 {
                    for slot in stride(from: variantCount - 1, through: 1, by: -1) {
                        variants.swapAt(slot, Int(rng.next() % UInt64(slot + 1)))
                    }
                    if variants[0] == previousVariant {
                        variants.swapAt(0, 1 + Int(rng.next() % UInt64(variantCount - 1)))
                    }
                }
            }
            let variant = variants[index % variantCount]
            previousVariant = variant
            let side: Float = index.isMultiple(of: 2) ? -1 : 1
            let size = sample(natural ? 0.86...1.12 : 0.95...1.05)
            let height = natural ? sample(0.94...1.08) : 1
            return Placement(
                position: SIMD3(side * sample(3.05...3.45), 0,
                                -4.0 - Float(index / 2) * 5.1
                                    - (index.isMultiple(of: 2) ? 0 : 1.05) + sample(-0.30...0.30)),
                scale: SIMD3(size, size * height, size),
                yaw: sample(-angle...angle),
                lean: natural ? sample(-0.045...0.045) : 0,
                variant: variant
            )
        }
    }
}

/// Stable, cosmetic-only samples for spawned art. This deliberately has no
/// dependency on `gameplayRNG`: changing an accent must never change a daily
/// pattern, collision, pickup value, or wind sequence.
enum SpawnVisualVariation {
    private static func mixed(_ seed: UInt64, salt: UInt64) -> UInt64 {
        var value = seed &+ salt &+ 0x9E37_79B9_7F4A_7C15
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    /// Fixed 24-bit conversion keeps the visual result stable across devices.
    static func unit(_ seed: UInt64, salt: UInt64 = 0) -> Float {
        Float(mixed(seed, salt: salt) >> 40) / Float(0xFF_FFFF)
    }

    static func accent(base: UIColor, alternate: UIColor, seed: UInt64) -> UIColor {
        // Keep every warning/readability color in its biome family; this is a
        // modest shift, not a recolor that could make a hazard misleading.
        EnvironmentMaterials.lerpColor(base, alternate, 0.10 + unit(seed) * 0.32)
    }

    static func yaw(_ seed: UInt64) -> Float {
        (unit(seed, salt: 0x5941_57) - 0.5) * 0.42
    }

    static func variant(_ seed: UInt64, count: Int = 3) -> Int {
        Int(mixed(seed, salt: 0x5348_4150_45) % UInt64(count))
    }
}

/// Pure naming contract shared by the asset manifest, gameplay and tests.
enum BiomeAssetID {
    static let authoredBiomes: [EnvironmentID] = EnvironmentID.allCases
    static let wallVariantCount = 3

    static func propVariantCount(_ biome: EnvironmentID) -> Int {
        biome == .lowCrawl ? 1 : 3
    }

    static func prop(_ biome: EnvironmentID, variant: Int) -> String {
        let index = variant % propVariantCount(biome)
        return "prop_\(biome.rawValue)" + (index == 0 ? "" : "_\(index)")
    }

    static func wall(_ biome: EnvironmentID, seed: UInt64) -> String {
        "wall_\(biome.rawValue)_\(SpawnVisualVariation.variant(seed, count: wallVariantCount))"
    }

    static func varied(_ base: String, seed: UInt64) -> String {
        let variant = SpawnVisualVariation.variant(seed)
        return base + (variant == 0 ? "" : "_\(variant)")
    }

    static func crystal(_ type: CrystalHalfType, charged: Bool, seed: UInt64) -> String {
        varied("crystal_\(type == .blue ? "azure" : "coral")\(charged ? "_charged" : "")", seed: seed)
    }

    static let shared = [
        "rift_frame", "rift_aperture", "rift_energy", "junction_frame", "junction_aperture", "track_segment",
        "rail_segment", "track_endcap", "start_pad", "token",
        "crystal_azure", "crystal_azure_charged", "crystal_coral", "crystal_coral_charged",
        "crystal_combined", "fx_shard", "gust_ribbon", "glyph_risk", "glyph_aegis",
        "glyph_overdrive", "glyph_precision", "glyph_lock", "glyph_magnet",
        "hazard_duck", "hazard_jump",
        "foundry_door_panel", "foundry_shape_sphere", "foundry_shape_cube",
        "foundry_shape_diamond", "orbit_hoop_segment", "orbit_marker",
        "orbit_shutter_blade", "orbit_shutter_band", "orbit_shutter_rim",
        "orbit_shutter_hub"
    ]

    static var required: [String] {
        let variants = ["hazard_duck", "hazard_jump", "token", "crystal_azure",
                        "crystal_coral", "crystal_azure_charged", "crystal_coral_charged"]
            .flatMap { base in (1...2).map { "\(base)_\($0)" } }
        return shared + variants + authoredBiomes.flatMap { biome in
            (0..<wallVariantCount).map { "wall_\(biome.rawValue)_\($0)" }
                + ["floor_\(biome.rawValue)", "environment_\(biome.rawValue)",
                   "preview_\(biome.rawValue)"]
                + (0..<propVariantCount(biome)).map { prop(biome, variant: $0) }
        }
    }
}

@MainActor
enum BiomeAssetCatalog {
    private static var prototypes: [String: Entity] = [:]
    private static var loadTask: Task<Void, Never>?
    private static let logger = Logger(subsystem: "Slipframe", category: "ArtAssets")
    private(set) static var missingAssets: [String] = []

    static func preload() async {
        if let task = loadTask {
            await task.value
            return
        }
        let task = Task { @MainActor in
            for name in BiomeAssetID.required {
                guard let url = Bundle.main.url(forResource: name, withExtension: "usdz", subdirectory: "ArtAssets") else {
                    missingAssets.append(name)
                    logger.error("Missing bundled art: \(name, privacy: .public)")
                    continue
                }
                do {
                    prototypes[name] = try await Entity(contentsOf: url)
                } catch {
                    missingAssets.append(name)
                    logger.error("Cannot load \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        loadTask = task
        await task.value
    }

    static func clone(_ name: String) -> Entity? {
        guard let clone = prototypes[name]?.clone(recursive: true) else { return nil }
        if name.hasPrefix("prop_ghostGlass") || name == "preview_ghostGlass" {
            ghostOpacity(clone, opacity: 0.012)
        }
        return clone
    }

    /// Exports bake all transforms to their vertices, including Blender's Z→Y up
    /// rotation. Single-mesh assets can be used directly for the portal mask/VFX.
    static func mesh(_ name: String) -> MeshResource? {
        guard let prototype = prototypes[name] else { return nil }
        return models(in: prototype).first?.components[ModelComponent.self]?.mesh
    }

    static func models(in root: Entity) -> [Entity] {
        var result: [Entity] = []
        if root.components[ModelComponent.self] != nil { result.append(root) }
        for child in root.children { result.append(contentsOf: models(in: child)) }
        return result
    }

    static func motionBindings(in root: Entity) -> [AuthoredMotion] {
        models(in: root).compactMap { entity in
            if hasRole(entity, "motion_rotor") {
                return AuthoredMotion(entity: entity, base: entity.transform, kind: .rotor)
            }
            if hasRole(entity, "motion_float") {
                return AuthoredMotion(entity: entity, base: entity.transform, kind: .floating)
            }
            return nil
        }
    }

    /// USD import can preserve the object Xform or its Mesh child as the model
    /// owner. Export names both; ancestor lookup also tolerates an importer rename.
    private static func hasRole(_ entity: Entity, _ role: String) -> Bool {
        var current: Entity? = entity
        while let node = current {
            if node.name.contains("__\(role)__") { return true }
            current = node.parent
        }
        return false
    }

    static func tint(_ root: Entity, role: String, color: UIColor) {
        for node in models(in: root) where hasRole(node, role) {
            guard var model = node.components[ModelComponent.self] else { continue }
            model.materials = [UnlitMaterial(color: color)]
            node.components.set(model)
        }
    }

    static func ghostOpacity(_ root: Entity, opacity: Float) {
        let bodyOpacity = min(0.02, max(0.001, opacity))
        for node in models(in: root) {
            guard var model = node.components[ModelComponent.self] else { continue }
            let edge = hasRole(node, "ghost_edge") || hasRole(node, "accent")
            model.materials = model.materials.map { _ -> any RealityKit.Material in
                var material = PhysicallyBasedMaterial()
                material.baseColor = .init(tint: UIColor(red: 0.48, green: 0.76, blue: 0.84, alpha: 1))
                material.roughness = .init(floatLiteral: 0.38)
                material.emissiveColor = .init(color: UIColor(red: 0.18, green: 0.31, blue: 0.38, alpha: 1))
                material.emissiveIntensity = edge ? 0.025 : 0
                material.blending = .transparent(opacity: .init(floatLiteral: edge ? min(0.035, bodyOpacity * 2.5) : bodyOpacity))
                return material
            }
            node.components.set(model)
        }
    }

    static func obstacle(_ id: String, dimensions: SIMD3<Float>, nominal: SIMD3<Float>) -> Entity {
        let root = Entity()
        if let visual = clone(id) {
            visual.scale = dimensions / nominal
            root.addChild(visual)
        } else {
            // A damaged bundle must never produce an invisible collision volume.
            let fallback = ModelEntity(
                mesh: .generateBox(width: dimensions.x, height: dimensions.y, depth: dimensions.z),
                materials: [SimpleMaterial(color: .systemOrange, roughness: 0.6, isMetallic: false)]
            )
            root.addChild(fallback)
        }
        return root
    }

    static func crystal(type: CrystalHalfType, charged: Bool, radius: Float, seed: UInt64 = 0) -> Entity {
        let root = Entity()
        if let visual = clone(BiomeAssetID.crystal(type, charged: charged, seed: seed)) {
            visual.scale = SIMD3(repeating: radius / 0.07)
            visual.orientation = simd_quatf(angle: SpawnVisualVariation.yaw(seed), axis: SIMD3(0, 1, 0))
            if charged {
                BiomeAssetCatalog.tint(
                    visual,
                    role: "charged_core",
                    color: SpawnVisualVariation.accent(
                        base: .white,
                        alternate: type == .blue ? .systemCyan : .systemPink,
                        seed: seed
                    )
                )
            }
            root.addChild(visual)
        } else {
            root.addChild(ModelEntity(mesh: .generateSphere(radius: radius),
                materials: [EnvironmentMaterials.crystalHalf(type: type, charged: charged)]))
        }
        return root
    }
}

/// Portable animation of named Blender mesh parts. No rig, shader-node animation,
/// simulation cache or Blender constraint needs to survive the USD conversion.
@MainActor
struct AuthoredMotion {
    enum Kind { case rotor, floating }
    let entity: Entity
    let base: Transform
    let kind: Kind

    func update(time: Float) {
        switch kind {
        case .rotor:
            // The distant turbine's pivot is authored at this point in its Y-up mesh.
            let pivot = SIMD3<Float>(0, 4.2, -28)
            let rotation = simd_quatf(angle: time * 0.18, axis: SIMD3(0, 0, 1))
            entity.orientation = rotation * base.rotation
            entity.position = base.translation + pivot - rotation.act(pivot)
        case .floating:
            entity.position = base.translation + SIMD3(0, sin(time * 0.65) * 0.065, 0)
        }
    }
}
