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
        return (0..<8).map { index in
            let side: Float = index.isMultiple(of: 2) ? -1 : 1
            let size = sample(natural ? 0.86...1.12 : 0.95...1.05)
            let height = natural ? sample(0.94...1.08) : 1
            return Placement(
                position: SIMD3(side * sample(3.05...3.45), 0,
                                -4.0 - Float(index / 2) * 5.4 + sample(-0.38...0.38)),
                scale: SIMD3(size, size * height, size),
                yaw: sample(-angle...angle),
                lean: natural ? sample(-0.045...0.045) : 0
            )
        }
    }
}

/// Pure naming contract shared by the asset manifest, gameplay and tests.
enum BiomeAssetID {
    static let wallVariantCount = 3

    static func wall(_ biome: EnvironmentID, seed: UInt64) -> String {
        "wall_\(biome.rawValue)_\(seed % UInt64(wallVariantCount))"
    }

    static func crystal(_ type: CrystalHalfType, charged: Bool) -> String {
        "crystal_\(type == .blue ? "azure" : "coral")\(charged ? "_charged" : "")"
    }

    static let shared = [
        "rift_frame", "rift_aperture", "rift_energy", "junction_frame", "junction_aperture", "track_segment",
        "rail_segment", "track_endcap", "start_pad", "token",
        "crystal_azure", "crystal_azure_charged", "crystal_coral", "crystal_coral_charged",
        "crystal_combined", "fx_shard", "gust_ribbon", "glyph_risk", "glyph_aegis",
        "glyph_overdrive", "glyph_precision", "glyph_lock", "glyph_magnet",
        "hazard_duck", "hazard_jump"
    ]

    static var required: [String] {
        shared + EnvironmentID.allCases.flatMap { biome in
            (0..<wallVariantCount).map { wall(biome, seed: UInt64($0)) }
                + ["floor_\(biome.rawValue)", "environment_\(biome.rawValue)",
                   "preview_\(biome.rawValue)", "prop_\(biome.rawValue)"]
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
        prototypes[name]?.clone(recursive: true)
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
        for node in models(in: root) where hasRole(node, "ghost_body") {
            guard var model = node.components[ModelComponent.self] else { continue }
            model.materials = model.materials.map { source -> any RealityKit.Material in
                var material = (source as? PhysicallyBasedMaterial) ?? PhysicallyBasedMaterial()
                material.baseColor = .init(tint: UIColor(red: 0.48, green: 0.76, blue: 0.84, alpha: 1))
                material.roughness = .init(floatLiteral: 0.2)
                material.emissiveColor = .init(color: UIColor(red: 0.18, green: 0.31, blue: 0.38, alpha: 1))
                material.emissiveIntensity = 0.18
                material.blending = .transparent(opacity: .init(floatLiteral: opacity))
                return material
            }
            node.components.set(model)
        }
        // An edge cue remains even on the deliberately faint ghost variant.
        tint(root, role: "ghost_edge", color: UIColor(red: 0.60, green: 0.88, blue: 1, alpha: CGFloat(max(0.22, opacity))))
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

    static func crystal(type: CrystalHalfType, charged: Bool, radius: Float) -> Entity {
        let root = Entity()
        if let visual = clone(BiomeAssetID.crystal(type, charged: charged)) {
            visual.scale = SIMD3(repeating: radius / 0.07)
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
