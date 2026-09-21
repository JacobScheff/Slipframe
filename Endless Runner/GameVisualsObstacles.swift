// Blender-authored biome obstacles. Collision remains in WallCollision.swift.
import RealityKit
import UIKit
import simd

extension GameVisualBuilders {
    static func makeBiomeObstacle(
        biome: EnvironmentID, width: Float, height: Float, depth: Float,
        profile: EnvironmentProfile, seed: UInt64
    ) -> Entity {
        let root = BiomeAssetCatalog.obstacle(
            BiomeAssetID.wall(biome, seed: seed),
            dimensions: SIMD3(width, height, depth), nominal: SIMD3(0.7, 1.8, 0.7))
        root.name = "wallSlab"
        if biome == .ghostGlass {
            BiomeAssetCatalog.ghostOpacity(root, opacity: max(0.60, profile.palette.wallOpacity))
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
        let root = BiomeAssetCatalog.obstacle("hazard_duck",
            dimensions: SIMD3(width, height, depth), nominal: SIMD3(2.5, 0.75, 0.595))
        root.name = "duckSlab"
        return root
    }

    static func makeSummitSpikeRidge(width: Float, height: Float, depth: Float, seed: UInt64) -> Entity {
        let root = BiomeAssetCatalog.obstacle("hazard_jump",
            dimensions: SIMD3(width, height, depth), nominal: SIMD3(2.5, 0.14, 0.22))
        root.name = "jumpSlab"
        return root
    }
}
