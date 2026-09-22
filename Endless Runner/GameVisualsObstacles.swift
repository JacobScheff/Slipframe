// Blender-authored biome obstacles. Collision remains in WallCollision.swift.
import RealityKit
import UIKit
import simd

extension GameVisualBuilders {
    private static func varyAccent(_ root: Entity, profile: EnvironmentProfile, seed: UInt64) {
        BiomeAssetCatalog.tint(
            root,
            role: "accent",
            color: SpawnVisualVariation.accent(
                base: EnvironmentMaterials.uiColor(profile.palette.wallEmissive),
                alternate: EnvironmentMaterials.uiColor(profile.palette.portalAccent),
                seed: seed
            )
        )
    }

    static func makeBiomeObstacle(
        biome: EnvironmentID, width: Float, height: Float, depth: Float,
        profile: EnvironmentProfile, seed: UInt64
    ) -> Entity {
        let root = BiomeAssetCatalog.obstacle(
            BiomeAssetID.wall(biome, seed: seed),
            dimensions: SIMD3(width, height, depth), nominal: SIMD3(0.7, 1.8, 0.7))
        root.name = "wallSlab"
        varyAccent(root, profile: profile, seed: seed)
        if biome == .ghostGlass {
            BiomeAssetCatalog.ghostOpacity(root, opacity: profile.palette.wallOpacity)
        }
        return root
    }

    static func makeGhostShatterPane(width: Float, height: Float, depth: Float,
                                      opacity: Float, seed: UInt64) -> Entity {
        let root = BiomeAssetCatalog.obstacle(
            BiomeAssetID.wall(.ghostGlass, seed: seed),
            dimensions: SIMD3(width, height, depth), nominal: SIMD3(0.7, 1.8, 0.7))
        root.name = "wallSlab"
        BiomeAssetCatalog.ghostOpacity(root, opacity: opacity)
        return root
    }

    static func makeDuckTendrilCurtain(width: Float, height: Float, depth: Float, seed: UInt64) -> Entity {
        let root = BiomeAssetCatalog.obstacle(BiomeAssetID.varied("hazard_duck", seed: seed),
            dimensions: SIMD3(width, height, depth), nominal: SIMD3(2.5, 0.75, 0.595))
        root.name = "duckSlab"
        varyAccent(root, profile: EnvironmentCatalog.profile(for: .lowCrawl), seed: seed)
        return root
    }

    static func makeSummitSpikeRidge(width: Float, height: Float, depth: Float, seed: UInt64) -> Entity {
        let root = BiomeAssetCatalog.obstacle(BiomeAssetID.varied("hazard_jump", seed: seed),
            dimensions: SIMD3(width, height, depth), nominal: SIMD3(2.5, 0.14, 0.22))
        root.name = "jumpSlab"
        varyAccent(root, profile: EnvironmentCatalog.profile(for: .summitStep), seed: seed)
        return root
    }
}
