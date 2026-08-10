//
//  GameVisualsObstacles.swift
//  Slipframe
//
//  Per-biome obstacle "species" — every environment gets its own irregular
//  silhouette instead of one shared rectangular slab. Collision stays a plain
//  AABB (see WallCollision.swift), fully decoupled from these visuals, so the
//  shapes below are free to be as jagged as the art direction wants without
//  ever changing gameplay fairness. Full-height "core" shards always
//  collectively span the whole obstacle width so a player can never mistake
//  a jagged gap for a duck-under opening on a standard wall.
//

import RealityKit
import UIKit
import simd

extension GameVisualBuilders {

    // MARK: - Dispatch

    static func makeBiomeObstacle(
        biome: EnvironmentID,
        width: Float,
        height: Float,
        depth: Float,
        profile: EnvironmentProfile,
        seed: UInt64
    ) -> Entity {
        switch biome {
        case .emberRun:
            return makeEmberShardCluster(width: width, height: height, depth: depth, profile: profile, seed: seed)
        case .summitStep:
            return makeSummitOutcrop(width: width, height: height, depth: depth, profile: profile, seed: seed)
        case .lowCrawl:
            return makeLowCrawlFence(width: width, height: height, depth: depth, profile: profile, seed: seed)
        case .stormPass:
            return makeStormDebrisCluster(width: width, height: height, depth: depth, profile: profile, seed: seed)
        case .crystalCave:
            return makeCrystalSpireCluster(width: width, height: height, depth: depth, profile: profile, seed: seed)
        case .ghostGlass:
            return makeGhostShatterPane(width: width, height: height, depth: depth, opacity: profile.ghostWallOpacity, seed: seed)
        }
    }

    // MARK: - Shared jagged shard cluster

    /// Builds `coreCount` full-height jagged prisms that collectively span the
    /// whole width (so there's no visual gap to be mistaken for a duck-under),
    /// plus a few smaller decorative accent shards for extra silhouette break.
    private static func makeJaggedShardCluster(
        width: Float,
        height: Float,
        depth: Float,
        coreCount: Int,
        sidesRange: ClosedRange<Int>,
        jitterRange: ClosedRange<Float>,
        heightVariance: ClosedRange<Float>,
        leanRange: ClosedRange<Float>,
        seed: UInt64,
        materialFactory: (Int, Float) -> any RealityKit.Material
    ) -> Entity {
        let root = Entity()
        root.name = "wallSlab"
        var rng = SeededGenerator(seed: seed)
        let slotWidth = width / Float(max(1, coreCount))

        for i in 0..<coreCount {
            let sides = Int.random(in: sidesRange, using: &rng)
            let shardHeight = height * Float.random(in: heightVariance, using: &rng)
            let coreWidth = slotWidth * 1.3
            let outline = ProceduralGeometry.jaggedOutline(
                sides: sides,
                radiusX: coreWidth * 0.5,
                radiusY: depth * 0.5 * Float.random(in: 0.75...1.05, using: &rng),
                jitter: Float.random(in: jitterRange, using: &rng),
                noise: ProceduralGeometry.RadialNoise(seed: seed &+ UInt64(i) &+ 41, octaves: 3)
            )
            guard let mesh = try? ProceduralGeometry.extrudedPolygon(points: outline, depth: shardHeight) else { continue }
            let variance = Float.random(in: 0...1, using: &rng)
            let shard = ModelEntity(mesh: mesh, materials: [materialFactory(i, variance)])

            let standUp = simd_quatf(angle: -Float.pi / 2, axis: SIMD3(1, 0, 0))
            let twist = simd_quatf(angle: Float.random(in: -0.3...0.3, using: &rng), axis: SIMD3(0, 1, 0))
            let lean = simd_quatf(angle: Float.random(in: leanRange, using: &rng), axis: SIMD3(0, 0, 1))
            shard.orientation = lean * twist * standUp

            let slotCenter = -width * 0.5 + (Float(i) + 0.5) * slotWidth
            let x = slotCenter + Float.random(in: -slotWidth * 0.08...slotWidth * 0.08, using: &rng)
            let baseY = -height * 0.5 + Float.random(in: -0.04...0.05, using: &rng)
            let z = Float.random(in: -depth * 0.08...depth * 0.08, using: &rng)
            shard.position = SIMD3(x, baseY, z)
            root.addChild(shard)
        }

        let accentCount = Int.random(in: 2...3, using: &rng)
        for i in 0..<accentCount {
            let sides = Int.random(in: sidesRange, using: &rng)
            let accentHeight = height * Float.random(in: 0.22...0.42, using: &rng)
            let accentWidth = slotWidth * Float.random(in: 0.35...0.6, using: &rng)
            let outline = ProceduralGeometry.jaggedOutline(
                sides: sides,
                radiusX: accentWidth * 0.5,
                radiusY: depth * 0.35,
                jitter: Float.random(in: jitterRange, using: &rng),
                noise: ProceduralGeometry.RadialNoise(seed: seed &+ UInt64(i) &+ 777, octaves: 3)
            )
            guard let mesh = try? ProceduralGeometry.extrudedPolygon(points: outline, depth: accentHeight) else { continue }
            let variance = Float.random(in: 0...1, using: &rng)
            let accent = ModelEntity(mesh: mesh, materials: [materialFactory(100 + i, variance)])
            let standUp = simd_quatf(angle: -Float.pi / 2, axis: SIMD3(1, 0, 0))
            let tilt = simd_quatf(angle: Float.random(in: -0.5...0.5, using: &rng), axis: SIMD3(0, 0, 1))
            accent.orientation = tilt * standUp
            accent.position = SIMD3(
                Float.random(in: -width * 0.46...width * 0.46, using: &rng),
                Float.random(in: -height * 0.15...height * 0.55, using: &rng),
                Float.random(in: -depth * 0.2...depth * 0.35, using: &rng)
            )
            root.addChild(accent)
        }

        return root
    }

    // MARK: - Ember Run — magma obelisk cluster

    static func makeEmberShardCluster(
        width: Float, height: Float, depth: Float, profile: EnvironmentProfile, seed: UInt64
    ) -> Entity {
        makeJaggedShardCluster(
            width: width, height: height, depth: depth,
            coreCount: 3,
            sidesRange: 5...7,
            jitterRange: 0.24...0.4,
            heightVariance: 0.92...1.14,
            leanRange: -0.14...0.14,
            seed: seed
        ) { _, variance in
            EnvironmentMaterials.wallBody(
                tint: profile.palette.wallTint,
                emissive: profile.palette.wallEmissive,
                opacity: profile.palette.wallOpacity,
                emissiveIntensity: profile.palette.wallEmissiveIntensity * (0.65 + variance * 0.75)
            )
        }
    }

    // MARK: - Summit Step — layered rock outcrop

    static func makeSummitOutcrop(
        width: Float, height: Float, depth: Float, profile: EnvironmentProfile, seed: UInt64
    ) -> Entity {
        makeJaggedShardCluster(
            width: width, height: height, depth: depth,
            coreCount: 3,
            sidesRange: 4...5,
            jitterRange: 0.1...0.2,
            heightVariance: 0.86...1.05,
            leanRange: -0.07...0.07,
            seed: seed
        ) { _, variance in
            EnvironmentMaterials.wallBody(
                tint: profile.palette.wallTint,
                emissive: profile.palette.wallEmissive,
                opacity: profile.palette.wallOpacity,
                emissiveIntensity: profile.palette.wallEmissiveIntensity * (0.8 + variance * 0.5)
            )
        }
    }

    // MARK: - Storm Pass — levitating charged debris

    static func makeStormDebrisCluster(
        width: Float, height: Float, depth: Float, profile: EnvironmentProfile, seed: UInt64
    ) -> Entity {
        let root = makeJaggedShardCluster(
            width: width, height: height, depth: depth,
            coreCount: 3,
            sidesRange: 5...6,
            jitterRange: 0.2...0.34,
            heightVariance: 0.82...1.18,
            leanRange: -0.28...0.28,
            seed: seed
        ) { _, variance in
            EnvironmentMaterials.wallBody(
                tint: profile.palette.wallTint,
                emissive: profile.palette.wallEmissive,
                opacity: profile.palette.wallOpacity,
                emissiveIntensity: profile.palette.wallEmissiveIntensity * (0.7 + variance * 0.7)
            )
        }

        // Small static-charge sparks orbiting the cluster — storm flavor.
        var rng = SeededGenerator(seed: seed &+ 555)
        for _ in 0..<4 {
            let spark = ModelEntity(
                mesh: MeshResource.generateSphere(radius: Float.random(in: 0.012...0.02, using: &rng)),
                materials: [UnlitMaterial(color: GamePalette.neonCyanHot)]
            )
            spark.position = SIMD3(
                Float.random(in: -width * 0.5...width * 0.5, using: &rng),
                Float.random(in: -height * 0.45...height * 0.5, using: &rng),
                Float.random(in: -depth * 0.4...depth * 0.4, using: &rng)
            )
            root.addChild(spark)
        }
        return root
    }

    // MARK: - Low Crawl — alien rib lattice fence

    static func makeLowCrawlFence(
        width: Float, height: Float, depth: Float, profile: EnvironmentProfile, seed: UInt64
    ) -> Entity {
        let root = Entity()
        root.name = "wallSlab"
        var rng = SeededGenerator(seed: seed)
        let material = EnvironmentMaterials.wallBody(
            tint: profile.palette.wallTint,
            emissive: profile.palette.wallEmissive,
            opacity: profile.palette.wallOpacity,
            emissiveIntensity: profile.palette.wallEmissiveIntensity
        )

        let ribCount = 5
        for i in 0..<ribCount {
            let t = ribCount > 1 ? Float(i) / Float(ribCount - 1) : 0.5
            let x = -width * 0.5 + t * width
            let bow = sin(t * Float.pi) * width * 0.12
            let radiusTop = Float.random(in: 0.02...0.032, using: &rng)
            let radiusBottom = radiusTop * 1.45

            let lowerHeight = height * 0.56
            let lower = ModelEntity(
                mesh: MeshResource.generateCylinder(height: lowerHeight, radius: radiusBottom),
                materials: [material]
            )
            lower.position = SIMD3(x + bow, -height * 0.5 + lowerHeight * 0.5, 0)
            root.addChild(lower)

            let upperHeight = height * 0.5
            let upper = ModelEntity(
                mesh: MeshResource.generateCylinder(height: upperHeight, radius: radiusTop),
                materials: [material]
            )
            upper.position = SIMD3(x + bow * 0.4, height * 0.5 - upperHeight * 0.5, 0)
            root.addChild(upper)
        }

        // Horizontal cross-struts tie the ribs together.
        for t: Float in [0.28, 0.6, 0.85] {
            let strut = ModelEntity(
                mesh: MeshResource.generateCylinder(height: width * 0.98, radius: 0.016),
                materials: [material]
            )
            strut.orientation = simd_quatf(angle: Float.pi / 2, axis: SIMD3(0, 0, 1))
            strut.position = SIMD3(0, -height * 0.5 + t * height, 0)
            root.addChild(strut)
        }

        // Faint membrane behind the ribs — guarantees a solid head-to-toe read
        // without hiding the lattice detail in front.
        let membrane = ModelEntity(
            mesh: MeshResource.generateBox(width: width * 0.94, height: height * 0.96, depth: max(0.02, depth * 0.18)),
            materials: [EnvironmentMaterials.wallBody(
                tint: profile.palette.wallTint,
                emissive: profile.palette.wallEmissive,
                opacity: min(0.4, profile.palette.wallOpacity),
                emissiveIntensity: profile.palette.wallEmissiveIntensity * 0.5
            )]
        )
        membrane.position = SIMD3(0, 0, -depth * 0.3)
        root.addChild(membrane)

        return root
    }

    // MARK: - Crystal Cave — geode spire cluster

    static func makeCrystalSpireCluster(
        width: Float, height: Float, depth: Float, profile: EnvironmentProfile, seed: UInt64
    ) -> Entity {
        let root = Entity()
        root.name = "wallSlab"
        var rng = SeededGenerator(seed: seed)
        let spireCount = 3
        let slotWidth = width / Float(spireCount)
        let opacity = max(0.5, profile.palette.wallOpacity)

        for i in 0..<spireCount {
            let radius = slotWidth * Float.random(in: 0.4...0.56, using: &rng)
            let totalHeight = height * Float.random(in: 0.95...1.18, using: &rng)
            let topFrac = Float.random(in: 0.55...0.72, using: &rng)
            let sides = Int.random(in: 5...7, using: &rng)
            guard let mesh = try? ProceduralGeometry.bipyramid(
                sides: sides,
                radius: radius,
                topHeight: totalHeight * topFrac,
                bottomHeight: totalHeight * (1 - topFrac),
                jitter: 0.16,
                seed: seed &+ UInt64(i) &+ 61
            ) else { continue }

            let material = EnvironmentMaterials.crystalSpire(tint: profile.palette.wallEmissive, opacity: opacity)
            let spire = ModelEntity(mesh: mesh, materials: [material])
            let slotCenter = -width * 0.5 + (Float(i) + 0.5) * slotWidth
            let x = slotCenter + Float.random(in: -slotWidth * 0.1...slotWidth * 0.1, using: &rng)
            let waistY = -height * 0.5 + totalHeight * (1 - topFrac) * 0.7
            spire.position = SIMD3(x, waistY, Float.random(in: -depth * 0.15...depth * 0.15, using: &rng))
            spire.orientation = simd_quatf(angle: Float.random(in: -0.25...0.25, using: &rng), axis: SIMD3(0, 1, 0))
            root.addChild(spire)
        }

        for i in 0..<3 {
            let radius = Float.random(in: 0.03...0.06, using: &rng)
            guard let mesh = try? ProceduralGeometry.bipyramid(
                sides: 5,
                radius: radius,
                topHeight: radius * 2.2,
                bottomHeight: radius * 1.1,
                jitter: 0.2,
                seed: seed &+ UInt64(i) &+ 900
            ) else { continue }
            let material = EnvironmentMaterials.crystalSpire(tint: profile.palette.wallEmissive, opacity: min(1, opacity + 0.15))
            let shard = ModelEntity(mesh: mesh, materials: [material])
            shard.position = SIMD3(
                Float.random(in: -width * 0.45...width * 0.45, using: &rng),
                -height * 0.5 + radius,
                Float.random(in: -depth * 0.3...depth * 0.3, using: &rng)
            )
            shard.orientation = simd_quatf(angle: Float.random(in: 0...(2 * Float.pi), using: &rng), axis: SIMD3(0, 0, 1))
            root.addChild(shard)
        }

        return root
    }

    // MARK: - Ghost Glass — jagged shatter pane

    static func makeGhostShatterPane(
        width: Float, height: Float, depth: Float, opacity: Float, seed: UInt64
    ) -> Entity {
        let root = Entity()
        root.name = "wallSlab"
        let material = EnvironmentMaterials.ghostWallBody(opacity: opacity)

        let noise = ProceduralGeometry.RadialNoise(seed: seed, octaves: 5)
        let outline = ProceduralGeometry.jaggedOutline(
            sides: 14, radiusX: width * 0.52, radiusY: height * 0.52,
            jitter: 0.1, noise: noise, minScale: 0.85
        )
        if let mesh = try? ProceduralGeometry.extrudedPolygon(points: outline, depth: depth) {
            root.addChild(ModelEntity(mesh: mesh, materials: [material]))
        } else {
            let mesh = MeshResource.generateBox(width: width, height: height, depth: depth)
            root.addChild(ModelEntity(mesh: mesh, materials: [material]))
        }

        // A few small floating fragments — a "still shattering" cue.
        var rng = SeededGenerator(seed: seed &+ 3)
        let axes: [SIMD3<Float>] = [SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)]
        for i in 0..<3 {
            let fragOutline = ProceduralGeometry.jaggedOutline(
                sides: Int.random(in: 4...6, using: &rng),
                radiusX: Float.random(in: 0.06...0.14, using: &rng),
                radiusY: Float.random(in: 0.06...0.14, using: &rng),
                jitter: 0.3,
                noise: ProceduralGeometry.RadialNoise(seed: seed &+ UInt64(i) &+ 91, octaves: 2)
            )
            guard let fragMesh = try? ProceduralGeometry.extrudedPolygon(points: fragOutline, depth: 0.02) else { continue }
            let frag = ModelEntity(mesh: fragMesh, materials: [material])
            frag.position = SIMD3(
                Float.random(in: -width * 0.6...width * 0.6, using: &rng),
                Float.random(in: -height * 0.5...height * 0.5, using: &rng),
                Float.random(in: 0.1...0.3, using: &rng)
            )
            frag.orientation = simd_quatf(
                angle: Float.random(in: 0...(2 * Float.pi), using: &rng),
                axis: axes[Int.random(in: 0...2, using: &rng)]
            )
            root.addChild(frag)
        }
        return root
    }

    // MARK: - Low Crawl duck hazard — hanging tendril curtain

    static func makeDuckTendrilCurtain(width: Float, height: Float, depth: Float, seed: UInt64) -> Entity {
        let root = Entity()
        root.name = "duckSlab"
        var rng = SeededGenerator(seed: seed)
        let material = EnvironmentMaterials.wallBody(
            tint: TintColor(r: 0.15, g: 0.55, b: 0.95, a: 0.85),
            emissive: TintColor(r: 0.2, g: 0.7, b: 1.0, a: 1),
            opacity: 0.85,
            emissiveIntensity: 0.7
        )

        // Base membrane keeps the "must duck under this" silhouette solid
        // between tendrils.
        let membrane = ModelEntity(
            mesh: MeshResource.generateBox(width: width * 0.92, height: height * 0.8, depth: max(0.02, depth * 0.35)),
            materials: [material]
        )
        root.addChild(membrane)

        let strandCount = 9
        for i in 0..<strandCount {
            let t = strandCount > 1 ? Float(i) / Float(strandCount - 1) : 0.5
            let x = -width * 0.5 + t * width + Float.random(in: -0.04...0.04, using: &rng)
            let beadCount = Int.random(in: 3...4, using: &rng)
            var y: Float = height * 0.5
            var radius = Float.random(in: 0.045...0.065, using: &rng)
            for _ in 0..<beadCount {
                let beadHeight = height / Float(beadCount) * Float.random(in: 0.85...1.1, using: &rng)
                let bead = ModelEntity(
                    mesh: MeshResource.generateCylinder(height: beadHeight, radius: radius),
                    materials: [material]
                )
                bead.position = SIMD3(x, y - beadHeight * 0.5, Float.random(in: -depth * 0.1...depth * 0.1, using: &rng))
                root.addChild(bead)
                y -= beadHeight
                radius *= 0.82
            }
            let tip = ModelEntity(
                mesh: MeshResource.generateSphere(radius: max(0.01, radius * 1.3)),
                materials: [material]
            )
            tip.position = SIMD3(x, y, 0)
            root.addChild(tip)
        }
        return root
    }

    // MARK: - Summit Step jump hazard — spike ridge

    static func makeSummitSpikeRidge(width: Float, height: Float, depth: Float, seed: UInt64) -> Entity {
        let root = Entity()
        root.name = "jumpSlab"
        var rng = SeededGenerator(seed: seed)
        let material = EnvironmentMaterials.wallBody(
            tint: TintColor(r: 0.95, g: 0.55, b: 0.18, a: 0.85),
            emissive: TintColor(r: 1.0, g: 0.7, b: 0.25, a: 1),
            opacity: 0.85,
            emissiveIntensity: 0.7
        )

        // Jump collision only checks headset rise across the Z band (see
        // WallCollision.pointHitsJumpBarrier) — visual height is purely
        // cosmetic, so the ridge can read taller/spikier than the old flat bar.
        let base = ModelEntity(
            mesh: MeshResource.generateBox(width: width * 0.96, height: height * 0.6, depth: depth * 0.85),
            materials: [material]
        )
        root.addChild(base)

        let spikeCount = 10
        for i in 0..<spikeCount {
            let t = spikeCount > 1 ? Float(i) / Float(spikeCount - 1) : 0.5
            let x = -width * 0.5 + t * width + Float.random(in: -0.03...0.03, using: &rng)
            let spikeHeight = height * Float.random(in: 1.4...2.4, using: &rng)
            let spikeRadius = Float.random(in: 0.035...0.06, using: &rng)
            let spike = ModelEntity(
                mesh: MeshResource.generateCone(height: spikeHeight, radius: spikeRadius),
                materials: [material]
            )
            spike.position = SIMD3(x, height * 0.3 + spikeHeight * 0.5, Float.random(in: -depth * 0.2...depth * 0.2, using: &rng))
            root.addChild(spike)
        }
        return root
    }
}
