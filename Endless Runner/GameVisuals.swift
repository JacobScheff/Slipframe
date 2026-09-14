//
//  GameVisuals.swift
//  Slipframe
//
//  Shared palette, materials, and polished procedural mesh builders.
//  See ASSET_SPEC.md for authored USDZ swap guidance.
//

import RealityKit
import UIKit
import simd

/// Tags a small ambient "rift dust" mote so `GameWorld.animateRiftMotes` can
/// drift it around a stable anchor without needing per-entity stored state
/// outside the ECS component system. Lives in this file (always compiled into
/// the app target) rather than the geometry toolkit so registration and mote
/// animation never lose the type to a missing source-file membership.
struct RiftMoteComponent: Component, Codable {
    var basePosition: SIMD3<Float>
    var phase: Float
    var radius: Float
}

// MARK: - Coin biome tint

/// Spawn-time Data Token colors per biome. Ember Run keeps the polished gold;
/// other biomes shift to `EnvironmentPalette.coinTint`.
enum GameCoinTint {
    struct Colors: Equatable {
        var base: TintColor
        var hot: TintColor
        /// Ember keeps an unmultiplied face texture; other biomes tint the face.
        var tintsFaceTexture: Bool
    }

    /// Base + hot emissive colors for a coin spawned under `profile`.
    static func colors(for profile: EnvironmentProfile) -> (base: UIColor, hot: UIColor, tintsFaceTexture: Bool) {
        let tints = tintColors(for: profile)
        return (
            EnvironmentMaterials.uiColor(tints.base),
            EnvironmentMaterials.uiColor(tints.hot),
            tints.tintsFaceTexture
        )
    }

    /// TintColor form for unit tests and callers that avoid UIKit.
    static func tintColors(for profile: EnvironmentProfile) -> Colors {
        // Ember keeps GamePalette gold (slightly different from palette.coinTint).
        if profile.id == .emberRun {
            return Colors(
                base: TintColor(r: 1.0, g: 0.78, b: 0.22, a: 1),
                hot: TintColor(r: 1.0, g: 0.92, b: 0.55, a: 1),
                tintsFaceTexture: false
            )
        }
        let base = profile.palette.coinTint
        let hot = base.mixed(toward: TintColor(r: 1, g: 1, b: 1, a: 1), t: 0.4)
        return Colors(base: base, hot: hot, tintsFaceTexture: true)
    }
}

// MARK: - Palette

enum GamePalette {
    /// Deep ink under the track — reads against passthrough without going pure black.
    static let trackInk = UIColor(red: 0.06, green: 0.07, blue: 0.11, alpha: 1)
    /// Cool cyan neon — primary guide / portal accent.
    static let neonCyan = UIColor(red: 0.28, green: 0.93, blue: 1.0, alpha: 1)
    static let neonCyanSoft = UIColor(red: 0.28, green: 0.93, blue: 1.0, alpha: 0.55)
    static let neonCyanHot = UIColor(red: 0.75, green: 0.98, blue: 1.0, alpha: 1)
    /// Danger red for walls.
    static let hazardRed = UIColor(red: 0.98, green: 0.16, blue: 0.14, alpha: 1)
    static let hazardRedSoft = UIColor(red: 0.98, green: 0.22, blue: 0.18, alpha: 0.38)
    static let hazardEdge = UIColor(red: 1.0, green: 0.55, blue: 0.42, alpha: 1)
    /// Coin gold.
    static let coinGold = UIColor(red: 1.0, green: 0.78, blue: 0.22, alpha: 1)
    static let coinGoldHot = UIColor(red: 1.0, green: 0.92, blue: 0.55, alpha: 1)
    /// Stand-line warm cream.
    static let standCream = UIColor(red: 0.98, green: 0.93, blue: 0.78, alpha: 1)
    static let standAmber = UIColor(red: 1.0, green: 0.82, blue: 0.38, alpha: 1)
    /// Portal tunnel void.
    static let voidInk = UIColor(red: 0.02, green: 0.03, blue: 0.06, alpha: 1)
    static let tunnelAccent = UIColor(red: 0.12, green: 0.45, blue: 0.62, alpha: 1)
    /// Alien/synthetic accent — rift chrome, HUD frame details, gem facets.
    static let alienViolet = UIColor(red: 0.62, green: 0.34, blue: 1.0, alpha: 1)
    static let alienVioletSoft = UIColor(red: 0.62, green: 0.34, blue: 1.0, alpha: 0.4)
    static let alienMagentaHot = UIColor(red: 0.92, green: 0.55, blue: 1.0, alpha: 1)
}

// MARK: - Materials

enum GameMaterials {
    private static var didWarmTextures = false
    private static var trackFloorTexture: TextureResource?
    private static var coinFaceTexture: TextureResource?
    private static var portalGlowTexture: TextureResource?
    private static var laneStripeTexture: TextureResource?
    private static var startPadTexture: TextureResource?

    /// Generate every surface texture once at runtime — no shipped raster
    /// assets. Falls back to solid colors below if bitmap generation ever fails.
    static func warmTextures() {
        guard !didWarmTextures else { return }
        didWarmTextures = true
        trackFloorTexture = ProceduralTextures.trackFloor()
        coinFaceTexture = ProceduralTextures.coinFace()
        portalGlowTexture = ProceduralTextures.portalGlow()
        laneStripeTexture = ProceduralTextures.laneStripe()
        startPadTexture = ProceduralTextures.startPad()
    }

    /// `tint` lets biome switches recolor the etched-plating texture in place
    /// (see `GameWorld.applyPalette`) instead of discarding it for a flat fill.
    static func trackFloor(tint: UIColor = GamePalette.trackInk, emissive: UIColor? = nil) -> any RealityKit.Material {
        warmTextures()
        if let texture = trackFloorTexture {
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: tint, texture: .init(texture))
            material.roughness = .init(floatLiteral: 0.78)
            material.metallic = .init(floatLiteral: 0.12)
            material.emissiveColor = .init(
                color: emissive ?? EnvironmentMaterials.lerpColor(tint, .black, 0.4),
                texture: .init(texture)
            )
            material.emissiveIntensity = 0.22
            return material
        }
        return SimpleMaterial(color: tint, roughness: 0.85, isMetallic: false)
    }

    /// `tint` lets biome switches recolor the energized-conduit texture in
    /// place (see `GameWorld.applyPalette`) instead of discarding it.
    static func laneCore(tint: UIColor = GamePalette.neonCyan) -> UnlitMaterial {
        warmTextures()
        var material = UnlitMaterial(color: tint)
        if let texture = laneStripeTexture {
            material.color = .init(tint: tint, texture: .init(texture))
        }
        return material
    }

    static func laneGlow() -> any RealityKit.Material {
        // Soft under-glow — alpha on tint handles transparency on visionOS 1.x.
        UnlitMaterial(color: GamePalette.neonCyanSoft)
    }

    static func railNeon() -> UnlitMaterial {
        UnlitMaterial(color: GamePalette.neonCyan)
    }

    static func railDark() -> SimpleMaterial {
        SimpleMaterial(
            color: UIColor(red: 0.1, green: 0.12, blue: 0.16, alpha: 1),
            roughness: 0.7,
            isMetallic: true
        )
    }

    /// Glowing Data Token body — faceted gem, not a metallic coin disc.
    static func coinMetal(
        tint: UIColor = GamePalette.coinGold,
        hot: UIColor = GamePalette.coinGoldHot,
        tintsFaceTexture: Bool = false
    ) -> any RealityKit.Material {
        _ = tintsFaceTexture
        warmTextures()
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: tint.withAlphaComponent(0.55))
        material.emissiveColor = .init(color: hot)
        material.emissiveIntensity = 1.15
        material.roughness = .init(floatLiteral: 0.12)
        material.metallic = .init(floatLiteral: 0.35)
        material.clearcoat = .init(floatLiteral: 0.9)
        material.clearcoatRoughness = .init(floatLiteral: 0.08)
        material.blending = .transparent(opacity: .init(floatLiteral: 0.72))
        material.faceCulling = .none
        return material
    }

    static func coinCore(hot: UIColor = GamePalette.coinGoldHot) -> UnlitMaterial {
        UnlitMaterial(color: hot)
    }

    /// Soft holographic bloom around a Data Token.
    static func coinAura(
        tint: UIColor = GamePalette.coinGold,
        hot: UIColor = GamePalette.coinGoldHot,
        tintsFaceTexture: Bool = false
    ) -> any RealityKit.Material {
        _ = tintsFaceTexture
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: tint.withAlphaComponent(0.18))
        material.emissiveColor = .init(color: hot)
        material.emissiveIntensity = 0.55
        material.roughness = .init(floatLiteral: 1.0)
        material.metallic = .init(floatLiteral: 0.0)
        material.blending = .transparent(opacity: .init(floatLiteral: 0.18))
        material.faceCulling = .none
        return material
    }

    /// Neon edge stroke for Data Token wireframe facets.
    static func dataTokenEdge(hot: UIColor) -> UnlitMaterial {
        UnlitMaterial(color: hot)
    }

    static func portalRimHot() -> UnlitMaterial {
        UnlitMaterial(color: GamePalette.neonCyanHot)
    }

    static func portalRimMid() -> UnlitMaterial {
        UnlitMaterial(color: GamePalette.neonCyan)
    }

    static func portalRimBloom(tint: UIColor = .white) -> any RealityKit.Material {
        warmTextures()
        if let texture = portalGlowTexture {
            var material = UnlitMaterial(color: tint)
            material.color = .init(tint: tint, texture: .init(texture))
            return material
        }
        return UnlitMaterial(color: tint == .white ? GamePalette.neonCyanSoft : tint)
    }

    /// Torn-edge debris fringing the rift — per-shard gradient between cyan and
    /// the alien-violet accent so the fringe reads as varied, hand-cut shards.
    static func riftShard(brightness: Float) -> UnlitMaterial {
        UnlitMaterial(color: EnvironmentMaterials.lerpColor(GamePalette.neonCyan, GamePalette.alienViolet, brightness))
    }

    /// Crackling energy tendril segment — darker violet at the root, hot near the tip.
    static func riftTendrilEnergy(t: Float) -> UnlitMaterial {
        UnlitMaterial(color: EnvironmentMaterials.lerpColor(GamePalette.alienVioletSoft, GamePalette.neonCyanHot, t))
    }

    /// Distant silhouette structure inside the infinite void behind the rift.
    static func riftMonolith() -> any RealityKit.Material {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: 0.05, green: 0.02, blue: 0.09, alpha: 0.55))
        material.emissiveColor = .init(color: UIColor(red: 0.3, green: 0.1, blue: 0.42, alpha: 1))
        material.emissiveIntensity = 0.14
        material.roughness = .init(floatLiteral: 1.0)
        material.metallic = .init(floatLiteral: 0.0)
        material.blending = .transparent(opacity: .init(floatLiteral: 0.55))
        material.faceCulling = .none
        return material
    }

    /// Slow-drifting mote leaking out of the rift into the void / real room.
    static func riftMote(hot: Bool) -> UnlitMaterial {
        UnlitMaterial(color: hot ? GamePalette.alienMagentaHot : GamePalette.neonCyanHot)
    }

    static func portalVoid() -> UnlitMaterial {
        UnlitMaterial(color: GamePalette.voidInk)
    }

    static func portalRail() -> UnlitMaterial {
        UnlitMaterial(color: GamePalette.neonCyan)
    }

    static func portalAccent() -> UnlitMaterial {
        UnlitMaterial(color: GamePalette.tunnelAccent)
    }

    static func portalRing() -> any RealityKit.Material {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: 0.2, green: 0.7, blue: 0.9, alpha: 0.45))
        material.emissiveColor = .init(color: UIColor(red: 0.25, green: 0.75, blue: 0.95, alpha: 1))
        material.emissiveIntensity = 0.5
        material.roughness = .init(floatLiteral: 1.0)
        material.metallic = .init(floatLiteral: 0.0)
        material.blending = .transparent(opacity: .init(floatLiteral: 0.45))
        return material
    }

    static func startLine() -> UnlitMaterial {
        UnlitMaterial(color: GamePalette.standCream)
    }

    static func startAccent() -> UnlitMaterial {
        UnlitMaterial(color: GamePalette.standAmber)
    }

    static func startPad() -> any RealityKit.Material {
        warmTextures()
        if let texture = startPadTexture {
            var material = UnlitMaterial(color: .white)
            material.color = .init(tint: .white, texture: .init(texture))
            return material
        }
        return UnlitMaterial(color: UIColor(red: 1, green: 0.9, blue: 0.7, alpha: 0.55))
    }

    static func hitFlash() -> any RealityKit.Material {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: 1.0, green: 0.15, blue: 0.12, alpha: 0.45))
        material.emissiveColor = .init(color: GamePalette.hazardRed)
        material.emissiveIntensity = 0.8
        material.roughness = .init(floatLiteral: 1.0)
        material.metallic = .init(floatLiteral: 0.0)
        material.blending = .transparent(opacity: .init(floatLiteral: 0.45))
        return material
    }

    static func spark(color: UIColor) -> UnlitMaterial {
        UnlitMaterial(color: color)
    }
}

// MARK: - Builders

enum GameVisualBuilders {
    /// Glowing geometric **Data Token** (Validation Packet) — octahedron /
    /// diamond collectible with neon facet edges, pulsing core, and soft aura.
    /// Spins / bobs via `GameWorld.animateCoins`. Entity name stays `"coin"` so
    /// gameplay / FX plumbing stays unchanged; only the silhouette is new.
    /// Pass biome tints from `GameCoinTint` so non-Ember environments shift color at spawn.
    static func makeCoin(
        radius: Float,
        tint: UIColor = GamePalette.coinGold,
        hot: UIColor = GamePalette.coinGoldHot,
        tintsFaceTexture: Bool = false
    ) -> Entity {
        let root = Entity()
        root.name = "coin"

        // Slightly stretched octahedron — reads as a floating diamond / data node.
        let gemSeed: UInt64 = 0xDA7A_700E_5001
        let gemMesh = (try? ProceduralGeometry.bipyramid(
            sides: 4,
            radius: radius * 0.92,
            topHeight: radius * 1.45,
            bottomHeight: radius * 1.45,
            jitter: 0.04,
            seed: gemSeed
        )) ?? MeshResource.generateSphere(radius: radius)

        let gem = ModelEntity(
            mesh: gemMesh,
            materials: [GameMaterials.coinMetal(tint: tint, hot: hot, tintsFaceTexture: tintsFaceTexture)]
        )
        gem.name = "coinDisc" // retained name: animateCoins / lighting still find the body
        root.addChild(gem)

        // Neon facet wireframe — same hologram language as the obstacles.
        let edge = GameMaterials.dataTokenEdge(hot: hot)
        root.addChild(ProceduralGeometry.hologramBipyramidWireframe(
            sides: 4,
            radius: radius * 0.92,
            topHeight: radius * 1.45,
            bottomHeight: radius * 1.45,
            jitter: 0.04,
            seed: gemSeed,
            edgeRadius: max(0.004, radius * 0.07),
            material: edge
        ))

        let core = ModelEntity(
            mesh: MeshResource.generateSphere(radius: radius * 0.28),
            materials: [GameMaterials.coinCore(hot: hot)]
        )
        core.name = "coinCore"
        root.addChild(core)

        let aura = ModelEntity(
            mesh: MeshResource.generateSphere(radius: radius * 1.45),
            materials: [GameMaterials.coinAura(tint: tint, hot: hot, tintsFaceTexture: tintsFaceTexture)]
        )
        aura.name = "coinAura"
        root.addChild(aura)

        // Tiny orbiting data mote.
        let spark = ModelEntity(
            mesh: MeshResource.generateSphere(radius: radius * 0.11),
            materials: [UnlitMaterial(color: hot)]
        )
        spark.name = "coinSpark"
        spark.position = SIMD3(radius * 0.95, radius * 0.15, 0)
        root.addChild(spark)

        return root
    }

    /// Fixed track slab with neon lane guides and side rails.
    static func makeTrack(width: Float, depth: Float, laneXs: [Float]) -> Entity {
        let root = Entity()
        root.name = "trackAssembly"

        let floor = ModelEntity(
            mesh: MeshResource.generateBox(width: width, height: 0.025, depth: depth),
            materials: [GameMaterials.trackFloor()]
        )
        floor.name = "floor"
        floor.position = SIMD3(0, 0, 0)
        root.addChild(floor)

        // Soft under-glow strips under each lane.
        for x in laneXs {
            let glow = ModelEntity(
                mesh: MeshResource.generateBox(width: 0.16, height: 0.01, depth: depth),
                materials: [GameMaterials.laneGlow()]
            )
            glow.position = SIMD3(x, 0.014, 0)
            root.addChild(glow)

            let core = ModelEntity(
                mesh: MeshResource.generateBox(width: 0.05, height: 0.018, depth: depth),
                materials: [GameMaterials.laneCore()]
            )
            core.name = "laneStripe"
            core.position = SIMD3(x, 0.022, 0)
            root.addChild(core)
        }

        // Side rails — segmented alien conduit (faceted vertebra plates
        // strung on a continuous neon spine) instead of a plain metal bar.
        for sign: Float in [-1, 1] {
            let railX = sign * (width * 0.5 - 0.04)
            let rail = makeConduitRail(depth: depth)
            rail.position = SIMD3(railX, 0, 0)
            root.addChild(rail)
        }

        // Distance tick marks along the center for motion parallax.
        let tickCount = max(4, Int(depth / 1.4))
        let halfDepth = depth * 0.5
        for i in 0..<tickCount {
            let t = Float(i) / Float(max(tickCount - 1, 1))
            let z = halfDepth - t * depth
            let tick = ModelEntity(
                mesh: MeshResource.generateBox(width: 0.22, height: 0.012, depth: 0.03),
                materials: [UnlitMaterial(color: UIColor(red: 0.35, green: 0.75, blue: 0.9, alpha: 0.55))]
            )
            tick.position = SIMD3(0, 0.03, z)
            root.addChild(tick)
        }

        return root
    }

    private static let railVertebraSeed: UInt64 = 0x7A11_5E17_1234_5678

    /// A chain of faceted "vertebra" plates strung along a continuous neon
    /// spine — reads as a machined alien conduit rather than a plastic guide
    /// bar, while keeping an unbroken bright line for peripheral guidance.
    private static func makeConduitRail(depth: Float) -> Entity {
        let root = Entity()
        root.name = "trackRail"

        let spine = ModelEntity(
            mesh: MeshResource.generateBox(width: 0.018, height: 0.018, depth: depth),
            materials: [GameMaterials.railNeon()]
        )
        spine.position = SIMD3(0, 0.05, 0)
        root.addChild(spine)

        let segmentLength: Float = 0.32
        let gap: Float = 0.06
        let stride = segmentLength + gap
        let count = max(1, Int(depth / stride))
        var z = depth * 0.5 - segmentLength * 0.5

        for i in 0..<count {
            let outline = ProceduralGeometry.jaggedOutline(
                sides: 6,
                radiusX: 0.075,
                radiusY: 0.045,
                jitter: 0.18,
                noise: ProceduralGeometry.RadialNoise(seed: railVertebraSeed &+ UInt64(i), octaves: 3)
            )
            if let mesh = try? ProceduralGeometry.extrudedPolygon(points: outline, depth: segmentLength) {
                let vertebra = ModelEntity(mesh: mesh, materials: [GameMaterials.railDark()])
                vertebra.position = SIMD3(0, 0.05, z)
                root.addChild(vertebra)
            }

            if i.isMultiple(of: 2) {
                let node = ModelEntity(
                    mesh: MeshResource.generateSphere(radius: 0.024),
                    materials: [GameMaterials.railNeon()]
                )
                node.position = SIMD3(0, 0.08, z)
                root.addChild(node)
            }

            z -= stride
        }

        return root
    }

    /// Seed shared by every jagged silhouette tied to the rift's actual aperture
    /// hole (rim hot edge, the aperture mesh itself in `GameWorld.buildPortal`)
    /// so those layers stay concentric instead of drifting apart.
    static let riftApertureSeed: UInt64 = 0x5211_7A17_0F1D_5EED

    /// Shared "torn reality" outline generator — one jagged-polygon language
    /// reused by the rift aperture, its rim layers, and (with different seeds)
    /// obstacle silhouettes so the whole game reads as one material world.
    static func riftOutline(
        width: Float,
        height: Float,
        jitter: Float,
        sides: Int = 40,
        seed: UInt64,
        angleOffset: Float = 0,
        minScale: Float = 0.6
    ) -> [SIMD2<Float>] {
        let noise = ProceduralGeometry.RadialNoise(seed: seed, octaves: 5)
        return ProceduralGeometry.jaggedOutline(
            sides: sides,
            radiusX: width * 0.5,
            radiusY: height * 0.5,
            jitter: jitter,
            noise: noise,
            angleOffset: angleOffset,
            minScale: minScale
        )
    }

    /// A tear in reality: irregular bloom/mid/hot rim bands hugging the jagged
    /// aperture, fringed with broken-off shard debris and a few crackling
    /// energy tendrils arcing a short distance out into the real room.
    static func makePortalRim(width: Float, height: Float, cornerRadius: Float, thickness: Float) -> Entity {
        _ = cornerRadius
        let rim = Entity()
        rim.name = "portalRim"
        let seed = riftApertureSeed

        // Soft outer bloom — largest, most irregular silhouette.
        let bloomPoints = riftOutline(width: width * 1.5, height: height * 1.5, jitter: 0.34, seed: seed &+ 101, angleOffset: 0.6)
        if let bloomMesh = try? ProceduralGeometry.filledPolygon(points: bloomPoints) {
            let bloom = ModelEntity(mesh: bloomMesh, materials: [GameMaterials.portalRimBloom()])
            bloom.name = "portalBloom"
            bloom.position = SIMD3(0, 0, -0.05)
            rim.addChild(bloom)
        }

        // Mid neon halo.
        let midPoints = riftOutline(width: width * 1.18, height: height * 1.18, jitter: 0.26, seed: seed &+ 202, angleOffset: 1.1)
        if let midMesh = try? ProceduralGeometry.filledPolygon(points: midPoints) {
            let mid = ModelEntity(mesh: midMesh, materials: [GameMaterials.portalRimMid()])
            mid.name = "portalMid"
            mid.position = SIMD3(0, 0, -0.025)
            rim.addChild(mid)
        }

        // Hot inner edge — same noise/seed as the true aperture, just dilated,
        // so it hugs the actual hole concentrically.
        let hotPoints = riftOutline(width: width * 1.08, height: height * 1.08, jitter: 0.14, seed: seed)
        if let hotMesh = try? ProceduralGeometry.filledPolygon(points: hotPoints) {
            let hot = ModelEntity(mesh: hotMesh, materials: [GameMaterials.portalRimHot()])
            hot.name = "portalHot"
            hot.position = SIMD3(0, 0, -0.01)
            rim.addChild(hot)
        }

        // Torn-edge shard fringe — irregular fragments still falling off the wound.
        let shardNoise = ProceduralGeometry.RadialNoise(seed: seed &+ 303, octaves: 6)
        var shardRNG = SeededGenerator(seed: seed &+ 404)
        let shardCount = 28
        let rX = width * 0.5
        let rY = height * 0.5
        for i in 0..<shardCount {
            guard Float.random(in: 0...1, using: &shardRNG) < 0.55 else { continue }
            let theta0 = Float(i) / Float(shardCount) * 2 * Float.pi
            let theta1 = Float(i + 1) / Float(shardCount) * 2 * Float.pi
            let s0 = max(0.6, 1 + shardNoise.value(at: theta0) * 0.3)
            let s1 = max(0.6, 1 + shardNoise.value(at: theta1) * 0.3)
            let p0 = SIMD2(cos(theta0) * rX * s0 * 1.05, sin(theta0) * rY * s0 * 1.05)
            let p1 = SIMD2(cos(theta1) * rX * s1 * 1.05, sin(theta1) * rY * s1 * 1.05)
            let outset = Float.random(in: 0.05...0.24, using: &shardRNG)
            let thick = Float.random(in: 0.015...0.05, using: &shardRNG)
            guard let mesh = try? ProceduralGeometry.edgeShard(p0: p0, p1: p1, outset: outset, thickness: thick) else { continue }
            let shard = ModelEntity(
                mesh: mesh,
                materials: [GameMaterials.riftShard(brightness: Float.random(in: 0...1, using: &shardRNG))]
            )
            shard.name = "riftShard"
            shard.position = SIMD3(0, 0, Float.random(in: -0.04...0.09, using: &shardRNG))
            shard.orientation = simd_quatf(angle: Float.random(in: -0.3...0.3, using: &shardRNG), axis: SIMD3(0, 0, 1))
            rim.addChild(shard)
        }

        // Crackling energy tendrils arcing a short distance out into the room —
        // the effect literally leaking through the tear.
        var tendrilRNG = SeededGenerator(seed: seed &+ 505)
        for i in 0..<7 {
            let theta = (Float(i) + Float.random(in: 0.2...0.8, using: &tendrilRNG)) / 7 * 2 * Float.pi
            let anchor = SIMD3<Float>(cos(theta) * rX * 0.95, sin(theta) * rY * 0.95, 0)
            let radial = SIMD2(anchor.x, anchor.y)
            let radialLen = simd_length(radial)
            let radialDir = radialLen > 0.0001 ? radial / radialLen : SIMD2<Float>(0, 1)
            let outward = normalize(SIMD3(radialDir.x * 0.55, radialDir.y * 0.55, 0.8))
            let tendril = makeRiftTendril(seed: seed &+ 900 + UInt64(i))
            tendril.name = "riftTendril"
            tendril.position = anchor
            tendril.orientation = simd_quatf(from: SIMD3(0, 1, 0), to: outward)
            rim.addChild(tendril)
        }

        return rim
    }

    /// A short jointed chain of shrinking energy segments — used to fringe the
    /// rift with crackling discharge reaching into the real room.
    private static func makeRiftTendril(seed: UInt64) -> Entity {
        let root = Entity()
        var rng = SeededGenerator(seed: seed)
        let segments = Int.random(in: 3...5, using: &rng)
        var radius = Float.random(in: 0.016...0.026, using: &rng)
        var parent: Entity = root
        for i in 0..<segments {
            let segLength = Float.random(in: 0.055...0.1, using: &rng)
            let bend = Float.random(in: -0.35...0.35, using: &rng)
            let twist = Float.random(in: -0.35...0.35, using: &rng)
            let joint = Entity()
            joint.orientation = simd_quatf(angle: bend, axis: SIMD3(1, 0, 0))
                * simd_quatf(angle: twist, axis: SIMD3(0, 0, 1))
            parent.addChild(joint)

            let segment = ModelEntity(
                mesh: MeshResource.generateCylinder(height: segLength, radius: radius),
                materials: [GameMaterials.riftTendrilEnergy(t: Float(i) / Float(max(1, segments - 1)))]
            )
            segment.position = SIMD3(0, segLength * 0.5, 0)
            joint.addChild(segment)

            let tipAnchor = Entity()
            tipAnchor.position = SIMD3(0, segLength, 0)
            joint.addChild(tipAnchor)
            parent = tipAnchor
            radius *= 0.7
        }
        let tip = ModelEntity(
            mesh: MeshResource.generateSphere(radius: max(0.01, radius * 1.7)),
            materials: [GameMaterials.riftTendrilEnergy(t: 1)]
        )
        parent.addChild(tip)
        return root
    }

    /// Dark tunnel visible through the portal — rings + rails + far glow for depth.
    static func makePortalInterior(portalHeight: Float) -> Entity {
        let interior = Entity()
        interior.name = "portalInterior"
        interior.position = SIMD3(0, 0, -0.05)

        let voidMat = GameMaterials.portalVoid()
        let railMat = GameMaterials.portalRail()
        let accentMat = GameMaterials.portalAccent()
        let ringMat = GameMaterials.portalRing()

        let tunnelW: Float = 4.4
        let tunnelH = portalHeight + 0.4
        // Pushed much deeper than the old 12 m box so the track-world reads as
        // expanding toward infinity behind the tear rather than hitting a wall.
        let tunnelDepth: Float = 26

        let floor = ModelEntity(
            mesh: MeshResource.generateBox(width: tunnelW, height: 0.06, depth: tunnelDepth),
            materials: [voidMat]
        )
        floor.name = "portalFloor"
        floor.position = SIMD3(0, -tunnelH * 0.5, -tunnelDepth * 0.5)
        interior.addChild(floor)

        let ceiling = ModelEntity(
            mesh: MeshResource.generateBox(width: tunnelW, height: 0.06, depth: tunnelDepth),
            materials: [voidMat]
        )
        ceiling.name = "portalCeiling"
        ceiling.position = SIMD3(0, tunnelH * 0.5, -tunnelDepth * 0.5)
        interior.addChild(ceiling)

        for sign: Float in [-1, 1] {
            let wall = ModelEntity(
                mesh: MeshResource.generateBox(width: 0.06, height: tunnelH, depth: tunnelDepth),
                materials: [voidMat]
            )
            wall.name = "portalSide"
            wall.position = SIMD3(sign * tunnelW * 0.5, 0, -tunnelDepth * 0.5)
            interior.addChild(wall)
        }

        let back = ModelEntity(
            mesh: MeshResource.generateBox(width: tunnelW, height: tunnelH, depth: 0.08),
            materials: [voidMat]
        )
        back.name = "portalBack"
        back.position = SIMD3(0, 0, -tunnelDepth)
        interior.addChild(back)

        // Receding jagged rift echoes — irregular translucent plates (not clean
        // rounded rects) shrinking into the depth, echoing the aperture shape.
        for i in 0..<12 {
            let t = Float(i) / 11.0
            let z = -1.3 - t * (tunnelDepth - 3.2)
            let scale = 1.0 - t * 0.62
            let points = GameVisualBuilders.riftOutline(
                width: tunnelW * 0.8 * scale,
                height: tunnelH * 0.88 * scale,
                jitter: 0.22,
                sides: 22,
                seed: GameVisualBuilders.riftApertureSeed &+ 1200 &+ UInt64(i),
                angleOffset: Float(i) * 0.37
            )
            guard let mesh = try? ProceduralGeometry.filledPolygon(points: points) else { continue }
            let ring = ModelEntity(mesh: mesh, materials: [ringMat])
            ring.name = "portalRing"
            ring.position = SIMD3(0, 0, z)
            interior.addChild(ring)
        }

        // Floor rails.
        for sign: Float in [-1, 1] {
            let rail = ModelEntity(
                mesh: MeshResource.generateBox(width: 0.05, height: 0.05, depth: tunnelDepth - 0.5),
                materials: [railMat]
            )
            rail.name = "portalRail"
            rail.position = SIMD3(sign * 1.35, -tunnelH * 0.5 + 0.08, -tunnelDepth * 0.5)
            interior.addChild(rail)
        }

        // Chevron arrows on the tunnel floor pointing toward the player
        // (emergence) — named "portalAccent" so biome switches retint them.
        for i in 0..<5 {
            let z = -2.0 - Float(i) * 1.8
            let chevron = makeFloorChevron(material: accentMat)
            chevron.name = "portalAccent"
            chevron.position = SIMD3(0, -tunnelH * 0.5 + 0.05, z)
            interior.addChild(chevron)
        }

        // Distant alien monolith silhouettes — cheap parallax hinting the
        // track-world keeps expanding far past what the tunnel box shows.
        var monolithRNG = SeededGenerator(seed: GameVisualBuilders.riftApertureSeed &+ 7700)
        for i in 0..<5 {
            let points = GameVisualBuilders.riftOutline(
                width: Float.random(in: 2.2...4.4, using: &monolithRNG),
                height: Float.random(in: 3.4...7.0, using: &monolithRNG),
                jitter: 0.32,
                sides: 11,
                seed: GameVisualBuilders.riftApertureSeed &+ 7800 &+ UInt64(i),
                minScale: 0.5
            )
            guard let mesh = try? ProceduralGeometry.filledPolygon(points: points) else { continue }
            let monolith = ModelEntity(mesh: mesh, materials: [GameMaterials.riftMonolith()])
            monolith.name = "riftMonolith"
            monolith.position = SIMD3(
                Float.random(in: -3.4...3.4, using: &monolithRNG),
                Float.random(in: -0.5...1.8, using: &monolithRNG),
                -tunnelDepth * Float.random(in: 0.7...0.96, using: &monolithRNG)
            )
            monolith.orientation = simd_quatf(angle: Float.random(in: -0.2...0.2, using: &monolithRNG), axis: SIMD3(0, 0, 1))
            interior.addChild(monolith)
        }

        // Ambient rift dust — small motes drifting out of the tear, animated
        // continuously in `GameWorld.animateRiftMotes`.
        var moteRNG = SeededGenerator(seed: GameVisualBuilders.riftApertureSeed &+ 9999)
        for _ in 0..<18 {
            let base = SIMD3<Float>(
                Float.random(in: -tunnelW * 0.42...tunnelW * 0.42, using: &moteRNG),
                Float.random(in: -tunnelH * 0.4...tunnelH * 0.45, using: &moteRNG),
                Float.random(in: -(tunnelDepth - 1.5)...(-0.6), using: &moteRNG)
            )
            let radius = Float.random(in: 0.008...0.02, using: &moteRNG)
            let mote = ModelEntity(
                mesh: MeshResource.generateSphere(radius: radius),
                materials: [GameMaterials.riftMote(hot: Bool.random(using: &moteRNG))]
            )
            mote.name = "riftMote"
            mote.position = base
            mote.components.set(RiftMoteComponent(
                basePosition: base,
                phase: Float.random(in: 0...(2 * Float.pi), using: &moteRNG),
                radius: Float.random(in: 0.08...0.22, using: &moteRNG)
            ))
            interior.addChild(mote)
        }

        // Layered far glow — hot core + soft bloom, pushed to the new depth.
        let farCore = ModelEntity(
            mesh: MeshResource.generateSphere(radius: 0.35),
            materials: [UnlitMaterial(color: GamePalette.neonCyanHot)]
        )
        farCore.name = "farCore"
        farCore.position = SIMD3(0, -0.1, -tunnelDepth + 1.4)
        interior.addChild(farCore)

        var bloomMat = PhysicallyBasedMaterial()
        bloomMat.baseColor = .init(tint: UIColor(red: 0.2, green: 0.65, blue: 0.95, alpha: 0.3))
        bloomMat.emissiveColor = .init(color: UIColor(red: 0.2, green: 0.65, blue: 0.95, alpha: 1))
        bloomMat.emissiveIntensity = 0.55
        bloomMat.roughness = .init(floatLiteral: 1.0)
        bloomMat.metallic = .init(floatLiteral: 0.0)
        bloomMat.blending = .transparent(opacity: .init(floatLiteral: 0.3))
        let farBloom = ModelEntity(
            mesh: MeshResource.generateSphere(radius: 0.95),
            materials: [bloomMat]
        )
        farBloom.position = SIMD3(0, -0.1, -tunnelDepth + 1.4)
        interior.addChild(farBloom)

        return interior
    }

    private static func makeFloorChevron(material: UnlitMaterial) -> Entity {
        let root = Entity()
        // Two angled bars form a simple > chevron pointing +Z (toward player / out of portal).
        for sign: Float in [-1, 1] {
            let bar = ModelEntity(
                mesh: MeshResource.generateBox(width: 0.35, height: 0.02, depth: 0.05),
                materials: [material]
            )
            bar.position = SIMD3(sign * 0.14, 0, 0)
            bar.orientation = simd_quatf(angle: sign * 0.55, axis: SIMD3(0, 1, 0))
            root.addChild(bar)
        }
        return root
    }

    /// Wordless destination gate used by Normal-mode junctions. A clean aperture and
    /// biome-colored motif identify the destination; 1–3 warning diamonds show
    /// difficulty, while the lower icon shows the modifier.
    static func makeJunctionPortal(option: RiftPortalOption, seed: UInt64) -> Entity {
        let root = Entity()
        root.name = "junctionPortal"
        let profile = EnvironmentCatalog.profile(for: option.environment)
        let rimColor = EnvironmentMaterials.uiColor(profile.palette.portalRim)
        let hotColor = EnvironmentMaterials.uiColor(profile.palette.portalAccent)
        let voidColor = EnvironmentMaterials.uiColor(profile.palette.portalVoid)

        // A single restrained halo replaces the overlapping filled silhouettes.
        // Discrete nodes keep the opening readable at a distance and preserve the
        // distinctive torn-rift language without becoming a spinning blob.
        let haloOutline = riftOutline(
            width: 0.98, height: 2.08, jitter: 0.07, sides: 30,
            seed: seed &+ 0x511
        )
        if let mesh = try? ProceduralGeometry.filledPolygon(points: haloOutline) {
            let halo = ModelEntity(
                mesh: mesh,
                materials: [UnlitMaterial(color: rimColor.withAlphaComponent(0.2))]
            )
            halo.position.z = -0.025
            root.addChild(halo)
        }
        let innerOutline = riftOutline(
            width: 0.87, height: 1.96, jitter: 0.055, sides: 30,
            seed: seed &+ 0x719
        )
        if let mesh = try? ProceduralGeometry.filledPolygon(points: innerOutline) {
            let innerRim = ModelEntity(
                mesh: mesh,
                materials: [UnlitMaterial(color: hotColor.withAlphaComponent(0.82))]
            )
            innerRim.name = "junctionInnerRim"
            innerRim.position.z = 0.002
            root.addChild(innerRim)
        }

        let rimNodes = Entity()
        rimNodes.name = "junctionRimNodes"
        for index in 0..<18 {
            let angle = Float(index) / 18 * .pi * 2
            let node = ModelEntity(
                mesh: MeshResource.generateSphere(radius: index.isMultiple(of: 3) ? 0.038 : 0.026),
                materials: [UnlitMaterial(color: rimColor.withAlphaComponent(0.92))]
            )
            node.position = SIMD3(cos(angle) * 0.45, sin(angle) * 0.96, 0.012)
            rimNodes.addChild(node)
        }
        root.addChild(rimNodes)

        let apertureOutline = riftOutline(
            width: 0.75,
            height: 1.76,
            jitter: 0.045,
            sides: 30,
            seed: seed &+ 0xA93
        )
        if let mesh = try? ProceduralGeometry.filledPolygon(points: apertureOutline) {
            let aperture = ModelEntity(
                mesh: mesh,
                materials: [UnlitMaterial(color: voidColor.withAlphaComponent(0.97))]
            )
            aperture.name = "junctionAperture"
            aperture.position.z = 0.015
            root.addChild(aperture)
        }

        // Enabled only during the committed crossing. At headset distance this
        // briefly fills the view with the portal void while the destination swaps.
        let crossingVeil = ModelEntity(
            mesh: MeshResource.generatePlane(width: 2.7, height: 2.15),
            materials: [UnlitMaterial(color: UIColor.black.withAlphaComponent(0.985))]
        )
        crossingVeil.name = "junctionCrossingVeil"
        crossingVeil.position.z = 0.09
        crossingVeil.isEnabled = false
        root.addChild(crossingVeil)

        addBiomeSignature(
            option.environment,
            to: root,
            color: hotColor,
            seed: seed &+ 0xB10
        )
        addDifficultyMarkers(option.risk, to: root)
        addModifierGlyph(option.modifier, to: root, color: rimColor, seed: seed &+ 0xC41)
        return root
    }

    /// One/two/three warning diamonds are ordered and universally countable.
    private static func addDifficultyMarkers(
        _ risk: RiftRisk,
        to root: Entity
    ) {
        let markers = Entity()
        markers.name = "junctionDifficultyMarkers"
        markers.position = SIMD3(0, 1.12, 0.07)
        let color: UIColor
        switch risk {
        case .stable:
            color = UIColor(red: 0.3, green: 1, blue: 0.72, alpha: 1)
        case .charged:
            color = UIColor(red: 1, green: 0.75, blue: 0.18, alpha: 1)
        case .unstable:
            color = UIColor(red: 1, green: 0.25, blue: 0.2, alpha: 1)
        }
        for index in 0..<risk.difficultyMarkerCount {
            let marker = ModelEntity(
                mesh: MeshResource.generateBox(width: 0.09, height: 0.09, depth: 0.025),
                materials: [UnlitMaterial(color: color.withAlphaComponent(0.98))]
            )
            marker.position.x = (Float(index) - Float(risk.difficultyMarkerCount - 1) * 0.5) * 0.14
            marker.orientation = simd_quatf(angle: .pi / 4, axis: SIMD3(0, 0, 1))
            markers.addChild(marker)
        }
        root.addChild(markers)
    }

    private static func addBiomeSignature(
        _ id: EnvironmentID,
        to root: Entity,
        color: UIColor,
        seed: UInt64
    ) {
        let signature = Entity()
        signature.name = "junctionBiomeSignature"
        signature.position.z = 0.04
        let material = UnlitMaterial(color: color.withAlphaComponent(0.9))
        switch id {
        case .emberRun:
            for index in 0..<5 {
                let flame = ModelEntity(
                    mesh: (try? ProceduralGeometry.bipyramid(
                        sides: 4, radius: 0.055, topHeight: 0.24, bottomHeight: 0.05,
                        jitter: 0.16, seed: seed &+ UInt64(index)
                    )) ?? MeshResource.generateSphere(radius: 0.06),
                    materials: [material]
                )
                flame.position = SIMD3(Float(index - 2) * 0.13, -0.16 + Float(index % 2) * 0.1, 0)
                signature.addChild(flame)
            }
        case .summitStep:
            for index in 0..<3 {
                let peak = ModelEntity(
                    mesh: (try? ProceduralGeometry.bipyramid(
                        sides: 3, radius: 0.16 - Float(index) * 0.025,
                        topHeight: 0.42 + Float(index) * 0.08, bottomHeight: 0.02,
                        jitter: 0.08, seed: seed &+ UInt64(index)
                    )) ?? MeshResource.generateSphere(radius: 0.12),
                    materials: [material]
                )
                peak.position = SIMD3(Float(index - 1) * 0.2, -0.18, 0)
                signature.addChild(peak)
            }
        case .ghostGlass:
            for index in 0..<5 {
                let pane = ModelEntity(
                    mesh: MeshResource.generateBox(width: 0.12, height: 0.46, depth: 0.012),
                    materials: [UnlitMaterial(color: color.withAlphaComponent(0.48))]
                )
                pane.position = SIMD3(Float(index - 2) * 0.135, Float(index % 3 - 1) * 0.2, 0)
                pane.orientation = simd_quatf(angle: Float(index - 2) * 0.11, axis: SIMD3(0, 0, 1))
                signature.addChild(pane)
            }
        case .lowCrawl:
            for index in 0..<6 {
                let rib = ModelEntity(
                    mesh: MeshResource.generateBox(width: 0.045, height: 0.58, depth: 0.035),
                    materials: [material]
                )
                rib.position = SIMD3(Float(index) * 0.13 - 0.325, 0.18 - Float(index % 2) * 0.1, 0)
                signature.addChild(rib)
            }
        case .stormPass:
            for index in 0..<5 {
                let streak = ModelEntity(
                    mesh: MeshResource.generateBox(width: 0.5, height: 0.025, depth: 0.025),
                    materials: [material]
                )
                streak.position = SIMD3(Float(index % 2) * 0.12 - 0.06, Float(index - 2) * 0.17, 0)
                streak.orientation = simd_quatf(angle: -0.3, axis: SIMD3(0, 0, 1))
                signature.addChild(streak)
            }
        case .crystalCave:
            for index in 0..<5 {
                let crystal = ModelEntity(
                    mesh: (try? ProceduralGeometry.bipyramid(
                        sides: 6, radius: 0.065, topHeight: 0.18, bottomHeight: 0.12,
                        jitter: 0.05, seed: seed &+ UInt64(index)
                    )) ?? MeshResource.generateSphere(radius: 0.065),
                    materials: [material]
                )
                let angle = Float(index) / 5 * .pi * 2
                crystal.position = SIMD3(cos(angle) * 0.25, sin(angle) * 0.34, 0)
                signature.addChild(crystal)
            }
        }
        root.addChild(signature)
    }

    /// Small, consistent lower-aperture symbol. It is intentionally geometric and unlabeled.
    private static func addModifierGlyph(
        _ modifier: RiftModifier,
        to root: Entity,
        color: UIColor,
        seed: UInt64
    ) {
        let glyph = Entity()
        glyph.name = "junctionModifierGlyph"
        glyph.position = SIMD3(0, -0.72, 0.065)
        let material = UnlitMaterial(color: color.withAlphaComponent(0.95))
        switch modifier {
        case .tokenSurge:
            for sign: Float in [-1, 0, 1] {
                let node = ModelEntity(
                    mesh: (try? ProceduralGeometry.bipyramid(
                        sides: 4, radius: 0.05, topHeight: 0.075, bottomHeight: 0.075,
                        seed: seed &+ UInt64((sign + 1) * 10)
                    )) ?? MeshResource.generateSphere(radius: 0.05),
                    materials: [material]
                )
                node.position.x = sign * 0.13
                glyph.addChild(node)
            }
        case .aegis:
            let points = [
                SIMD2<Float>(-0.13, 0.09), SIMD2<Float>(0, 0.15),
                SIMD2<Float>(0.13, 0.09), SIMD2<Float>(0.1, -0.08),
                SIMD2<Float>(0, -0.17), SIMD2<Float>(-0.1, -0.08)
            ]
            if let mesh = try? ProceduralGeometry.filledPolygon(points: points) {
                glyph.addChild(ModelEntity(mesh: mesh, materials: [material]))
            }
        case .overdrive:
            let points = [
                SIMD2<Float>(0.02, 0.18), SIMD2<Float>(-0.13, 0.01),
                SIMD2<Float>(-0.025, 0.01), SIMD2<Float>(-0.075, -0.18),
                SIMD2<Float>(0.15, 0.055), SIMD2<Float>(0.045, 0.055)
            ]
            if let mesh = try? ProceduralGeometry.filledPolygon(points: points) {
                glyph.addChild(ModelEntity(mesh: mesh, materials: [material]))
            }
        case .magnet:
            // Chunky, high-contrast U silhouette built entirely from RealityKit
            // geometry; it does not depend on the UI/SF Symbols magnet asset.
            for sign: Float in [-1, 1] {
                let arm = ModelEntity(
                    mesh: MeshResource.generateBox(width: 0.06, height: 0.23, depth: 0.04),
                    materials: [material]
                )
                arm.position = SIMD3(sign * 0.11, 0.025, 0)
                glyph.addChild(arm)
                let pole = ModelEntity(
                    mesh: MeshResource.generateBox(width: 0.1, height: 0.055, depth: 0.05),
                    materials: [material]
                )
                pole.position = SIMD3(sign * 0.11, 0.16, 0.01)
                glyph.addChild(pole)
            }
            let bridge = ModelEntity(
                mesh: MeshResource.generateBox(width: 0.28, height: 0.07, depth: 0.04),
                materials: [material]
            )
            bridge.position.y = -0.105
            glyph.addChild(bridge)
        case .closeCall:
            let core = ModelEntity(
                mesh: MeshResource.generateSphere(radius: 0.035),
                materials: [material]
            )
            glyph.addChild(core)
            for angle: Float in [0, .pi / 2, .pi, .pi * 1.5] {
                let tick = ModelEntity(
                    mesh: MeshResource.generateBox(width: 0.09, height: 0.025, depth: 0.025),
                    materials: [material]
                )
                tick.position = SIMD3(cos(angle) * 0.13, sin(angle) * 0.13, 0)
                tick.orientation = simd_quatf(angle: angle, axis: SIMD3(0, 0, 1))
                glyph.addChild(tick)
            }
        case .bonusBank:
            let body = ModelEntity(
                mesh: MeshResource.generateBox(width: 0.22, height: 0.15, depth: 0.03),
                materials: [material]
            )
            body.position.y = -0.055
            glyph.addChild(body)
            for sign: Float in [-1, 1] {
                let shackle = ModelEntity(
                    mesh: MeshResource.generateBox(width: 0.035, height: 0.11, depth: 0.025),
                    materials: [material]
                )
                shackle.position = SIMD3(sign * 0.065, 0.075, 0)
                glyph.addChild(shackle)
            }
            let crown = ModelEntity(
                mesh: MeshResource.generateBox(width: 0.16, height: 0.035, depth: 0.025),
                materials: [material]
            )
            crown.position.y = 0.13
            glyph.addChild(crown)
        }
        root.addChild(glyph)
    }

    /// Stand zone: soft pad, crisp line, forward chevrons, center tick.
    static func makeStartMarker() -> Entity {
        let marker = Entity()
        marker.name = "startMarker"
        marker.position = SIMD3(0, 0.03, 0)

        // Jagged calibration glyph instead of a plain rounded rectangle —
        // reads as an etched alien floor sigil, not a landing-strip decal.
        let padOutline = riftOutline(
            width: 2.6, height: 0.9, jitter: 0.1, sides: 22,
            seed: riftApertureSeed &+ 0x5741_5344
        )
        let padMesh = (try? ProceduralGeometry.filledPolygon(points: padOutline))
            ?? MeshResource.generatePlane(width: 2.6, height: 0.55)
        let pad = ModelEntity(mesh: padMesh, materials: [GameMaterials.startPad()])
        // Mesh is authored flat in XY (facing +Z); lay it down on the floor (facing +Y).
        pad.orientation = simd_quatf(angle: -.pi / 2, axis: SIMD3(1, 0, 0))
        pad.position = SIMD3(0, 0.002, 0.05)
        marker.addChild(pad)

        // Slightly raised inner glyph layer, same silhouette family, so the
        // sigil reads as etched/layered rather than a single flat decal.
        let ringOutline = riftOutline(
            width: 2.44, height: 0.78, jitter: 0.1, sides: 22,
            seed: riftApertureSeed &+ 0x5741_5344
        )
        if let ringMesh = try? ProceduralGeometry.extrudedPolygon(points: ringOutline, depth: 0.006) {
            let etch = ModelEntity(mesh: ringMesh, materials: [GameMaterials.startAccent()])
            etch.position = SIMD3(0, 0.005, 0.05)
            marker.addChild(etch)
        }

        let line = ModelEntity(
            mesh: MeshResource.generateBox(width: 2.4, height: 0.01, depth: 0.032),
            materials: [GameMaterials.startLine()]
        )
        line.position = SIMD3(0, 0.008, 0)
        marker.addChild(line)

        let tick = ModelEntity(
            mesh: MeshResource.generateBox(width: 0.12, height: 0.014, depth: 0.12),
            materials: [GameMaterials.startAccent()]
        )
        tick.position = SIMD3(0, 0.012, 0)
        marker.addChild(tick)

        // Three forward chevrons pointing toward the portal (−Z).
        for i in 0..<3 {
            let chevron = makeWorldChevron()
            chevron.position = SIMD3(0, 0.01, -0.22 - Float(i) * 0.18)
            let s = 1.0 - Float(i) * 0.12
            chevron.scale = SIMD3(repeating: s)
            marker.addChild(chevron)
        }

        return marker
    }

    private static func makeWorldChevron() -> Entity {
        let root = Entity()
        let mat = GameMaterials.startAccent()
        for sign: Float in [-1, 1] {
            let bar = ModelEntity(
                mesh: MeshResource.generateBox(width: 0.22, height: 0.012, depth: 0.04),
                materials: [mat]
            )
            bar.position = SIMD3(sign * 0.09, 0, 0)
            // Angle so the V opens toward +Z and points toward −Z (portal).
            bar.orientation = simd_quatf(angle: sign * (-0.6), axis: SIMD3(0, 1, 0))
            root.addChild(bar)
        }
        return root
    }

    /// Brief full-field red flash for wall hits.
    static func makeHitFlash(width: Float = 3.5, height: Float = 2.4) -> ModelEntity {
        let mesh = MeshResource.generatePlane(width: width, height: height, cornerRadius: 0.2)
        let flash = ModelEntity(mesh: mesh, materials: [GameMaterials.hitFlash()])
        flash.name = "hitFlash"
        return flash
    }

    /// One collect-burst spark mesh. Prefer `VisualFXController` pooling at runtime —
    /// mesh generation mid-tick hitchs the runner and freezes obstacle motion.
    static func makeCollectSpark(color: UIColor, radius: Float, colorIndex: Int = 0) -> ModelEntity {
        let sphere = ModelEntity(
            mesh: MeshResource.generateSphere(radius: radius),
            materials: [GameMaterials.spark(color: color)]
        )
        sphere.name = "collectSpark.\(colorIndex)"
        sphere.isEnabled = false
        return sphere
    }
}

// MARK: - Lightweight VFX state

struct BurstSpark {
    let entity: Entity
    var velocity: SIMD3<Float>
    var age: Float
    let lifetime: Float
}

/// Kinematics for a single collect-burst spark (pure; shared by pool spawn + tests).
enum CollectBurstMotion {
    static let sparkCount = 10
    static let lifetime: Float = 0.35
    static let colors: [UIColor] = [
        GamePalette.coinGoldHot,
        GamePalette.coinGold,
        GamePalette.neonCyanHot
    ]

    static func velocity(index: Int) -> SIMD3<Float> {
        let angle = Float(index) / Float(sparkCount) * (.pi * 2) + Float.random(in: -0.2...0.2)
        let speed = Float.random(in: 0.9...1.6)
        return SIMD3<Float>(
            cos(angle) * speed,
            Float.random(in: 0.4...1.2),
            sin(angle) * speed * 0.35
        )
    }
}

@MainActor
final class VisualFXController {
    /// Enough for several overlapping collects without allocating meshes mid-run.
    private static let poolCapacityPerColor = CollectBurstMotion.sparkCount * 3

    private var sparks: [BurstSpark] = []
    /// Color-segregated idle sparks, permanently parented under `fxRoot`.
    private var sparkPools: [[ModelEntity]] = Array(
        repeating: [],
        count: CollectBurstMotion.colors.count
    )
    private var didWarmSparkPool = false
    private let fxRoot = Entity()
    private var hitFlash: Entity?
    private var hitFlashAge: Float = 0
    private let hitFlashLifetime: Float = 0.28
    private weak var parent: Entity?

    func attach(to parent: Entity) {
        self.parent = parent
        fxRoot.name = "visualFX"
        if fxRoot.parent !== parent {
            parent.addChild(fxRoot)
        }
        warmSparkPoolIfNeeded()
    }

    /// Pre-build spark meshes/materials so the first coin collect stays hitch-free.
    func prepare() {
        warmSparkPoolIfNeeded()
    }

    func clear() {
        for spark in sparks {
            recycleSpark(spark.entity)
        }
        sparks.removeAll()
        hitFlash?.removeFromParent()
        hitFlash = nil
        hitFlashAge = 0
    }

    func spawnCoinBurst(at position: SIMD3<Float>) {
        warmSparkPoolIfNeeded()

        for i in 0..<CollectBurstMotion.sparkCount {
            let colorIndex = i % CollectBurstMotion.colors.count
            let sphere = acquireSpark(colorIndex: colorIndex)
            // Same local space as gameplay root (fxRoot sits at identity under root).
            sphere.position = position
            sphere.scale = SIMD3(repeating: 1)
            sphere.isEnabled = true

            sparks.append(
                BurstSpark(
                    entity: sphere,
                    velocity: CollectBurstMotion.velocity(index: i),
                    age: 0,
                    lifetime: CollectBurstMotion.lifetime
                )
            )
        }
    }

    func spawnHitFlash(near position: SIMD3<Float>) {
        guard let parent else { return }
        hitFlash?.removeFromParent()
        let flash = GameVisualBuilders.makeHitFlash()
        flash.position = SIMD3(position.x, max(1.2, position.y), position.z - 0.35)
        parent.addChild(flash)
        hitFlash = flash
        hitFlashAge = 0
    }

    func tick(deltaTime: Float) {
        // Sparks.
        var alive: [BurstSpark] = []
        alive.reserveCapacity(sparks.count)
        for var spark in sparks {
            spark.age += deltaTime
            if spark.age >= spark.lifetime {
                recycleSpark(spark.entity)
                continue
            }
            spark.velocity.y -= 2.8 * deltaTime
            spark.entity.position += spark.velocity * deltaTime
            let life = 1.0 - spark.age / spark.lifetime
            spark.entity.scale = SIMD3(repeating: max(0.05, life))
            alive.append(spark)
        }
        sparks = alive

        // Hit flash fade.
        if let flash = hitFlash {
            hitFlashAge += deltaTime
            let t = hitFlashAge / hitFlashLifetime
            if t >= 1 {
                flash.removeFromParent()
                hitFlash = nil
            } else {
                let fade = 1.0 - t
                flash.scale = SIMD3(1 + t * 0.15, 1 + t * 0.15, 1)
                // Approximate fade via scale + opacity isn't trivial on UnlitMaterial; shrink & drop.
                flash.position.z += deltaTime * 0.2
                _ = fade
            }
        }
    }

    private func warmSparkPoolIfNeeded() {
        guard !didWarmSparkPool else { return }
        didWarmSparkPool = true
        for colorIndex in CollectBurstMotion.colors.indices {
            sparkPools[colorIndex].reserveCapacity(Self.poolCapacityPerColor)
            let color = CollectBurstMotion.colors[colorIndex]
            for _ in 0..<Self.poolCapacityPerColor {
                let radius = Float.random(in: 0.012...0.028)
                let spark = GameVisualBuilders.makeCollectSpark(
                    color: color,
                    radius: radius,
                    colorIndex: colorIndex
                )
                fxRoot.addChild(spark)
                sparkPools[colorIndex].append(spark)
            }
        }
    }

    private func acquireSpark(colorIndex: Int) -> ModelEntity {
        if let pooled = sparkPools[colorIndex].popLast() {
            return pooled
        }
        // Fallback keeps full burst visuals if overlapping collects exhaust the pool.
        let color = CollectBurstMotion.colors[colorIndex]
        let spark = GameVisualBuilders.makeCollectSpark(
            color: color,
            radius: Float.random(in: 0.012...0.028),
            colorIndex: colorIndex
        )
        fxRoot.addChild(spark)
        return spark
    }

    private func recycleSpark(_ entity: Entity) {
        entity.isEnabled = false
        entity.scale = SIMD3(repeating: 1)
        // Stay parented under fxRoot — no scene-graph remove/add on the collect hot path.
        guard let model = entity as? ModelEntity else { return }
        let colorIndex = sparkColorIndex(for: model)
        sparkPools[colorIndex].append(model)
    }

    private func sparkColorIndex(for model: ModelEntity) -> Int {
        // Materials were assigned at warm/fallback time; recover index from name tag if present.
        if let raw = model.name.split(separator: ".").last, let idx = Int(raw),
           sparkPools.indices.contains(idx) {
            return idx
        }
        return 0
    }
}
