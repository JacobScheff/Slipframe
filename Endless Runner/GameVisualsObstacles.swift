//
//  GameVisualsObstacles.swift
//  Slipframe
//
//  Per-biome obstacle "species" — every environment gets its own irregular
//  silhouette instead of one shared rectangular slab. Collision stays a plain
//  AABB (see WallCollision.swift), fully decoupled from these visuals, so the
//  shapes below are free to be as jagged as the art direction wants without
//  ever changing gameplay fairness.
//
//  Visual language: digital holograms — highly transparent volume fills with
//  bright biome-colored neon wireframe edges / internal scanline grids. Not
//  solid translucent "glass boxes." Ghost Glass pushes this further: almost
//  no fill, barely-there cool wireframe.
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

    // MARK: - Shared hologram shard cluster

    /// Builds `coreCount` full-height jagged hologram prisms that collectively
    /// span the whole width (so there's no visual gap to be mistaken for a
    /// duck-under), plus smaller accent shards. Each prism is a near-invisible
    /// fill wrapped in a neon wireframe cage tinted by the biome emissive.
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
        fillFactory: (Float) -> any RealityKit.Material,
        edgeFactory: (Float) -> UnlitMaterial,
        edgeRadius: Float = 0.012,
        scanlineCount: Int = 2
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

            let shard = Entity()
            shard.name = "hologramShard"
            let fill = ModelEntity(mesh: mesh, materials: [fillFactory(variance)])
            fill.name = "hologramFill"
            shard.addChild(fill)
            let wire = ProceduralGeometry.hologramWireframeCage(
                points: outline,
                depth: shardHeight,
                edgeRadius: edgeRadius,
                material: edgeFactory(variance),
                scanlineCount: scanlineCount
            )
            shard.addChild(wire)

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

            let accent = Entity()
            accent.name = "hologramAccent"
            accent.addChild(ModelEntity(mesh: mesh, materials: [fillFactory(variance)]))
            accent.addChild(ProceduralGeometry.hologramWireframeCage(
                points: outline,
                depth: accentHeight,
                edgeRadius: edgeRadius * 0.85,
                material: edgeFactory(variance),
                scanlineCount: max(0, scanlineCount - 1)
            ))

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

    /// Standard biome hologram materials — transparent fill + neon edge from palette.
    private static func biomeHologramFactories(
        profile: EnvironmentProfile
    ) -> (
        fill: (Float) -> any RealityKit.Material,
        edge: (Float) -> UnlitMaterial
    ) {
        let tint = profile.palette.wallTint
        let emissive = profile.palette.wallEmissive
        let baseIntensity = profile.palette.wallEmissiveIntensity
        return (
            fill: { variance in
                EnvironmentMaterials.hologramFill(
                    tint: tint,
                    emissive: emissive,
                    opacity: 0.045 + variance * 0.025,
                    emissiveIntensity: 0.18 + baseIntensity * 0.2 * variance
                )
            },
            edge: { variance in
                // Hotter edges for brighter shards; stays fully opaque neon.
                let hot = TintColor(
                    r: min(1, emissive.r + 0.08 * variance),
                    g: min(1, emissive.g + 0.05 * variance),
                    b: min(1, emissive.b + 0.05 * variance),
                    a: 1
                )
                return EnvironmentMaterials.hologramEdge(emissive: hot, alpha: 1)
            }
        )
    }

    // MARK: - Ember Run — magma hologram shard cluster

    static func makeEmberShardCluster(
        width: Float, height: Float, depth: Float, profile: EnvironmentProfile, seed: UInt64
    ) -> Entity {
        let mats = biomeHologramFactories(profile: profile)
        return makeJaggedShardCluster(
            width: width, height: height, depth: depth,
            coreCount: 3,
            sidesRange: 5...7,
            jitterRange: 0.24...0.4,
            heightVariance: 0.92...1.14,
            leanRange: -0.14...0.14,
            seed: seed,
            fillFactory: mats.fill,
            edgeFactory: mats.edge,
            edgeRadius: 0.014,
            scanlineCount: 2
        )
    }

    // MARK: - Summit Step — layered hologram outcrop

    static func makeSummitOutcrop(
        width: Float, height: Float, depth: Float, profile: EnvironmentProfile, seed: UInt64
    ) -> Entity {
        let mats = biomeHologramFactories(profile: profile)
        return makeJaggedShardCluster(
            width: width, height: height, depth: depth,
            coreCount: 3,
            sidesRange: 4...5,
            jitterRange: 0.1...0.2,
            heightVariance: 0.86...1.05,
            leanRange: -0.07...0.07,
            seed: seed,
            fillFactory: mats.fill,
            edgeFactory: mats.edge,
            edgeRadius: 0.013,
            scanlineCount: 2
        )
    }

    // MARK: - Storm Pass — levitating charged hologram debris

    static func makeStormDebrisCluster(
        width: Float, height: Float, depth: Float, profile: EnvironmentProfile, seed: UInt64
    ) -> Entity {
        let mats = biomeHologramFactories(profile: profile)
        let root = makeJaggedShardCluster(
            width: width, height: height, depth: depth,
            coreCount: 3,
            sidesRange: 5...6,
            jitterRange: 0.2...0.34,
            heightVariance: 0.82...1.18,
            leanRange: -0.28...0.28,
            seed: seed,
            fillFactory: mats.fill,
            edgeFactory: mats.edge,
            edgeRadius: 0.012,
            scanlineCount: 3
        )

        // Small static-charge sparks orbiting the cluster — storm flavor.
        var rng = SeededGenerator(seed: seed &+ 555)
        let sparkMat = EnvironmentMaterials.hologramEdge(emissive: profile.palette.wallEmissive, alpha: 1)
        for _ in 0..<4 {
            let spark = ModelEntity(
                mesh: MeshResource.generateSphere(radius: Float.random(in: 0.012...0.02, using: &rng)),
                materials: [sparkMat]
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

    // MARK: - Low Crawl — neon rib lattice hologram fence

    static func makeLowCrawlFence(
        width: Float, height: Float, depth: Float, profile: EnvironmentProfile, seed: UInt64
    ) -> Entity {
        let root = Entity()
        root.name = "wallSlab"
        var rng = SeededGenerator(seed: seed)
        let edge = EnvironmentMaterials.hologramEdge(emissive: profile.palette.wallEmissive, alpha: 1)
        let fill = EnvironmentMaterials.hologramFill(
            tint: profile.palette.wallTint,
            emissive: profile.palette.wallEmissive,
            opacity: 0.04,
            emissiveIntensity: 0.2
        )

        let ribCount = 5
        for i in 0..<ribCount {
            let t = ribCount > 1 ? Float(i) / Float(ribCount - 1) : 0.5
            let x = -width * 0.5 + t * width
            let bow = sin(t * Float.pi) * width * 0.12
            let radiusTop = Float.random(in: 0.014...0.022, using: &rng)
            let radiusBottom = radiusTop * 1.35

            let lowerHeight = height * 0.56
            let lower = ModelEntity(
                mesh: MeshResource.generateCylinder(height: lowerHeight, radius: radiusBottom),
                materials: [edge]
            )
            lower.position = SIMD3(x + bow, -height * 0.5 + lowerHeight * 0.5, 0)
            root.addChild(lower)

            let upperHeight = height * 0.5
            let upper = ModelEntity(
                mesh: MeshResource.generateCylinder(height: upperHeight, radius: radiusTop),
                materials: [edge]
            )
            upper.position = SIMD3(x + bow * 0.4, height * 0.5 - upperHeight * 0.5, 0)
            root.addChild(upper)
        }

        // Horizontal neon cross-struts.
        for t: Float in [0.28, 0.6, 0.85] {
            let strut = ModelEntity(
                mesh: MeshResource.generateCylinder(height: width * 0.98, radius: 0.011),
                materials: [edge]
            )
            strut.orientation = simd_quatf(angle: Float.pi / 2, axis: SIMD3(0, 0, 1))
            strut.position = SIMD3(0, -height * 0.5 + t * height, 0)
            root.addChild(strut)
        }

        // Barely-there membrane so the gate still reads head-to-toe without
        // looking like a solid glass panel.
        let membrane = ModelEntity(
            mesh: MeshResource.generateBox(width: width * 0.94, height: height * 0.96, depth: max(0.015, depth * 0.12)),
            materials: [fill]
        )
        membrane.position = SIMD3(0, 0, -depth * 0.3)
        root.addChild(membrane)

        // Vertical scanline accents on the membrane for the hologram grid read.
        for i in 0..<6 {
            let t = Float(i) / 5.0
            let x = -width * 0.45 + t * width * 0.9
            if let seg = ProceduralGeometry.neonSegment(
                from: SIMD3(x, -height * 0.46, -depth * 0.28),
                to: SIMD3(x, height * 0.46, -depth * 0.28),
                radius: 0.006,
                material: edge
            ) {
                root.addChild(seg)
            }
        }

        return root
    }

    // MARK: - Crystal Cave — hologram geode spire cluster

    static func makeCrystalSpireCluster(
        width: Float, height: Float, depth: Float, profile: EnvironmentProfile, seed: UInt64
    ) -> Entity {
        let root = Entity()
        root.name = "wallSlab"
        var rng = SeededGenerator(seed: seed)
        let spireCount = 3
        let slotWidth = width / Float(spireCount)
        let fill = EnvironmentMaterials.crystalSpire(tint: profile.palette.wallEmissive, opacity: profile.palette.wallOpacity)
        let edge = EnvironmentMaterials.hologramEdge(emissive: profile.palette.wallEmissive, alpha: 1)

        for i in 0..<spireCount {
            let radius = slotWidth * Float.random(in: 0.4...0.56, using: &rng)
            let totalHeight = height * Float.random(in: 0.95...1.18, using: &rng)
            let topFrac = Float.random(in: 0.55...0.72, using: &rng)
            let sides = Int.random(in: 5...7, using: &rng)
            let topHeight = totalHeight * topFrac
            let bottomHeight = totalHeight * (1 - topFrac)
            let gemSeed = seed &+ UInt64(i) &+ 61
            guard let mesh = try? ProceduralGeometry.bipyramid(
                sides: sides,
                radius: radius,
                topHeight: topHeight,
                bottomHeight: bottomHeight,
                jitter: 0.16,
                seed: gemSeed
            ) else { continue }

            let spire = Entity()
            spire.name = "hologramSpire"
            spire.addChild(ModelEntity(mesh: mesh, materials: [fill]))
            spire.addChild(ProceduralGeometry.hologramBipyramidWireframe(
                sides: sides,
                radius: radius,
                topHeight: topHeight,
                bottomHeight: bottomHeight,
                jitter: 0.16,
                seed: gemSeed,
                edgeRadius: 0.01,
                material: edge
            ))

            let slotCenter = -width * 0.5 + (Float(i) + 0.5) * slotWidth
            let x = slotCenter + Float.random(in: -slotWidth * 0.1...slotWidth * 0.1, using: &rng)
            let waistY = -height * 0.5 + bottomHeight * 0.7
            spire.position = SIMD3(x, waistY, Float.random(in: -depth * 0.15...depth * 0.15, using: &rng))
            spire.orientation = simd_quatf(angle: Float.random(in: -0.25...0.25, using: &rng), axis: SIMD3(0, 1, 0))
            root.addChild(spire)
        }

        for i in 0..<3 {
            let radius = Float.random(in: 0.03...0.06, using: &rng)
            let gemSeed = seed &+ UInt64(i) &+ 900
            guard let mesh = try? ProceduralGeometry.bipyramid(
                sides: 5,
                radius: radius,
                topHeight: radius * 2.2,
                bottomHeight: radius * 1.1,
                jitter: 0.2,
                seed: gemSeed
            ) else { continue }
            let shard = Entity()
            shard.addChild(ModelEntity(mesh: mesh, materials: [fill]))
            shard.addChild(ProceduralGeometry.hologramBipyramidWireframe(
                sides: 5,
                radius: radius,
                topHeight: radius * 2.2,
                bottomHeight: radius * 1.1,
                jitter: 0.2,
                seed: gemSeed,
                edgeRadius: 0.006,
                material: edge
            ))
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

    // MARK: - Ghost Glass — nearly invisible hologram shatter pane

    static func makeGhostShatterPane(
        width: Float, height: Float, depth: Float, opacity: Float, seed: UInt64
    ) -> Entity {
        let root = Entity()
        root.name = "wallSlab"
        let fill = EnvironmentMaterials.ghostWallBody(opacity: opacity)
        let edge = EnvironmentMaterials.ghostHologramEdge()

        let noise = ProceduralGeometry.RadialNoise(seed: seed, octaves: 5)
        let outline = ProceduralGeometry.jaggedOutline(
            sides: 14, radiusX: width * 0.52, radiusY: height * 0.52,
            jitter: 0.1, noise: noise, minScale: 0.85
        )
        if let mesh = try? ProceduralGeometry.extrudedPolygon(points: outline, depth: depth) {
            // Keep a whisper of fill so occlusion/depth still exists, but the
            // readable silhouette is the faint wireframe only.
            root.addChild(ModelEntity(mesh: mesh, materials: [fill]))
            root.addChild(ProceduralGeometry.hologramWireframeCage(
                points: outline,
                depth: depth,
                edgeRadius: 0.006,
                material: edge,
                scanlineCount: 1
            ))
        } else {
            let mesh = MeshResource.generateBox(width: width, height: height, depth: depth)
            root.addChild(ModelEntity(mesh: mesh, materials: [fill]))
        }

        // Tiny floating fragments — wireframe chips, not milky glass shards.
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
            let frag = Entity()
            if let fragMesh = try? ProceduralGeometry.extrudedPolygon(points: fragOutline, depth: 0.015) {
                frag.addChild(ModelEntity(mesh: fragMesh, materials: [fill]))
            }
            frag.addChild(ProceduralGeometry.hologramWireframeCage(
                points: fragOutline,
                depth: 0.015,
                edgeRadius: 0.004,
                material: edge,
                scanlineCount: 0
            ))
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

    // MARK: - Low Crawl duck hazard — hologram tendril curtain

    static func makeDuckTendrilCurtain(width: Float, height: Float, depth: Float, seed: UInt64) -> Entity {
        let root = Entity()
        root.name = "duckSlab"
        var rng = SeededGenerator(seed: seed)
        let emissive = TintColor(r: 0.2, g: 0.7, b: 1.0, a: 1)
        let tint = TintColor(r: 0.15, g: 0.55, b: 0.95, a: 1)
        let fill = EnvironmentMaterials.hologramFill(tint: tint, emissive: emissive, opacity: 0.05, emissiveIntensity: 0.22)
        let edge = EnvironmentMaterials.hologramEdge(emissive: emissive, alpha: 1)

        // Barely-there membrane + neon frame so the "must duck" band reads
        // without becoming a solid cyan glass bar.
        let membrane = ModelEntity(
            mesh: MeshResource.generateBox(width: width * 0.92, height: height * 0.8, depth: max(0.015, depth * 0.25)),
            materials: [fill]
        )
        root.addChild(membrane)

        let frameOutline: [SIMD2<Float>] = [
            SIMD2(-width * 0.46, -height * 0.4),
            SIMD2(width * 0.46, -height * 0.4),
            SIMD2(width * 0.46, height * 0.4),
            SIMD2(-width * 0.46, height * 0.4)
        ]
        root.addChild(ProceduralGeometry.hologramWireframeCage(
            points: frameOutline,
            depth: max(0.02, depth * 0.3),
            edgeRadius: 0.01,
            material: edge,
            scanlineCount: 2
        ))

        let strandCount = 9
        for i in 0..<strandCount {
            let t = strandCount > 1 ? Float(i) / Float(strandCount - 1) : 0.5
            let x = -width * 0.5 + t * width + Float.random(in: -0.04...0.04, using: &rng)
            let top = SIMD3<Float>(x, height * 0.5, 0)
            let bottom = SIMD3<Float>(x, -height * 0.35, Float.random(in: -depth * 0.08...depth * 0.08, using: &rng))
            if let strand = ProceduralGeometry.neonSegment(
                from: top,
                to: bottom,
                radius: Float.random(in: 0.008...0.014, using: &rng),
                material: edge
            ) {
                root.addChild(strand)
            }
            let tip = ModelEntity(
                mesh: MeshResource.generateSphere(radius: 0.016),
                materials: [edge]
            )
            tip.position = bottom
            root.addChild(tip)
        }
        return root
    }

    // MARK: - Summit Step jump hazard — hologram spike ridge

    static func makeSummitSpikeRidge(width: Float, height: Float, depth: Float, seed: UInt64) -> Entity {
        let root = Entity()
        root.name = "jumpSlab"
        var rng = SeededGenerator(seed: seed)
        let emissive = TintColor(r: 1.0, g: 0.7, b: 0.25, a: 1)
        let tint = TintColor(r: 0.95, g: 0.55, b: 0.18, a: 1)
        let fill = EnvironmentMaterials.hologramFill(tint: tint, emissive: emissive, opacity: 0.05, emissiveIntensity: 0.22)
        let edge = EnvironmentMaterials.hologramEdge(emissive: emissive, alpha: 1)

        // Jump collision only checks headset rise across the Z band (see
        // WallCollision.pointHitsJumpBarrier) — visual height is purely cosmetic.
        let baseW = width * 0.96
        let baseH = height * 0.55
        let baseD = depth * 0.7
        let base = ModelEntity(
            mesh: MeshResource.generateBox(width: baseW, height: baseH, depth: baseD),
            materials: [fill]
        )
        root.addChild(base)

        // Neon box edges in world-aligned slab space (no mesh-space reorientation).
        let hx = baseW * 0.5, hy = baseH * 0.5, hz = baseD * 0.5
        let corners: [SIMD3<Float>] = [
            SIMD3(-hx, -hy, -hz), SIMD3(hx, -hy, -hz), SIMD3(hx, -hy, hz), SIMD3(-hx, -hy, hz),
            SIMD3(-hx, hy, -hz), SIMD3(hx, hy, -hz), SIMD3(hx, hy, hz), SIMD3(-hx, hy, hz)
        ]
        let edges: [(Int, Int)] = [
            (0, 1), (1, 2), (2, 3), (3, 0),
            (4, 5), (5, 6), (6, 7), (7, 4),
            (0, 4), (1, 5), (2, 6), (3, 7)
        ]
        for (a, b) in edges {
            if let seg = ProceduralGeometry.neonSegment(
                from: corners[a], to: corners[b], radius: 0.01, material: edge
            ) {
                root.addChild(seg)
            }
        }
        // One mid-height scanline ring for the hologram grid cue.
        let midY: Float = 0
        let midRing: [SIMD3<Float>] = [
            SIMD3(-hx * 0.92, midY, -hz * 0.92),
            SIMD3(hx * 0.92, midY, -hz * 0.92),
            SIMD3(hx * 0.92, midY, hz * 0.92),
            SIMD3(-hx * 0.92, midY, hz * 0.92)
        ]
        for i in 0..<midRing.count {
            if let seg = ProceduralGeometry.neonSegment(
                from: midRing[i], to: midRing[(i + 1) % midRing.count], radius: 0.007, material: edge
            ) {
                root.addChild(seg)
            }
        }

        let spikeCount = 10
        for i in 0..<spikeCount {
            let t = spikeCount > 1 ? Float(i) / Float(spikeCount - 1) : 0.5
            let x = -width * 0.5 + t * width + Float.random(in: -0.03...0.03, using: &rng)
            let spikeHeight = height * Float.random(in: 1.4...2.4, using: &rng)
            let spikeRadius = Float.random(in: 0.012...0.02, using: &rng)
            let baseY = height * 0.25
            let tip = SIMD3<Float>(x, baseY + spikeHeight, Float.random(in: -depth * 0.15...depth * 0.15, using: &rng))
            let foot = SIMD3<Float>(x, baseY, tip.z)
            if let spike = ProceduralGeometry.neonSegment(from: foot, to: tip, radius: spikeRadius, material: edge) {
                root.addChild(spike)
            }
            let tipOrb = ModelEntity(
                mesh: MeshResource.generateSphere(radius: spikeRadius * 1.2),
                materials: [edge]
            )
            tipOrb.position = tip
            root.addChild(tipOrb)
        }
        return root
    }
}
