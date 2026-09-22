// Blender-authored visuals. Editable source: Art/Blender/Slipframe_ArtSource.blend.
import RealityKit
import UIKit
import simd

struct RiftMoteComponent: Component, Codable {
    var basePosition: SIMD3<Float>
    var phase: Float
    var radius: Float
    var falling: Bool = false

    func sample(at time: Float) -> (offset: SIMD3<Float>, opacity: Float) {
        if falling {
            let cycle = (time * 0.55 + phase).truncatingRemainder(dividingBy: 1)
            // Fade out at the wrap so a raindrop never visibly jumps upward.
            let opacity = min(1, min(cycle, 1 - cycle) * 8) * 0.7
            return (SIMD3(cycle * 0.24, 0.6 - cycle * 1.2, 0), opacity)
        }
        let t = time * 0.5 + phase
        return (SIMD3(sin(t) * radius, cos(t * 0.7) * radius * 0.6,
                      sin(t * 0.5) * radius * 0.4), 1)
    }
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


enum GameMaterials {
    static func laneCore(tint: UIColor = GamePalette.neonCyan) -> UnlitMaterial {
        UnlitMaterial(color: tint)
    }
    static func hitFlash() -> any RealityKit.Material {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: GamePalette.hazardRed)
        material.emissiveColor = .init(color: GamePalette.hazardRed)
        material.emissiveIntensity = 0.65
        material.blending = .transparent(opacity: .init(floatLiteral: 0.3))
        return material
    }
}

@MainActor
enum GameVisualBuilders {
    static func makeCoin(radius: Float, tint: UIColor = GamePalette.coinGold,
                         hot: UIColor = GamePalette.coinGoldHot, tintsFaceTexture: Bool = false) -> Entity {
        let root = Entity()
        root.name = "coin"
        if let visual = BiomeAssetCatalog.clone("token") {
            visual.scale = SIMD3(repeating: radius / 0.07)
            if tintsFaceTexture { BiomeAssetCatalog.tint(visual, role: "tint_pickup", color: tint) }
            BiomeAssetCatalog.tint(visual, role: "tint_hot", color: hot)
            root.addChild(visual)
        } else {
            root.addChild(ModelEntity(mesh: .generateSphere(radius: radius),
                                      materials: [UnlitMaterial(color: hot)]))
        }
        return root
    }

    /// Arrange authored one-meter modules; shorten only the final segment.
    static func makeTrack(width: Float, depth: Float, laneXs: [Float],
                          biome: EnvironmentID = .emberRun) -> Entity {
        let root = Entity()
        root.name = "trackAssembly"
        let count = max(1, Int(ceil(depth)))
        for index in 0..<count {
            let length = min(1, depth - Float(index))
            let z = -depth * 0.5 + Float(index) + length * 0.5
            if let tile = BiomeAssetCatalog.clone("track_segment") {
                tile.scale = SIMD3(width / 3.2, 1, length)
                tile.position.z = z
                root.addChild(tile)
            } else {
                let tile = ModelEntity(mesh: .generateBox(width: width, height: 0.025, depth: length),
                    materials: [SimpleMaterial(color: GamePalette.trackInk, roughness: 0.8, isMetallic: false)])
                tile.position = SIMD3(0, -0.013, z)
                root.addChild(tile)
            }
            if let insert = BiomeAssetCatalog.clone("floor_\(biome.rawValue)") {
                insert.scale = SIMD3(width / 3.2, 1, length)
                insert.position.z = z
                root.addChild(insert)
            }
            for sign: Float in [-1, 1] {
                if let rail = BiomeAssetCatalog.clone("rail_segment") {
                    rail.position = SIMD3(sign * width * 0.5, 0.05, z)
                    rail.scale.z = length
                    root.addChild(rail)
                }
            }
        }
        for sign: Float in [-1, 1] {
            if let endcap = BiomeAssetCatalog.clone("track_endcap") {
                endcap.position = SIMD3(0, 0, sign * max(0, depth * 0.5 - 0.06))
                endcap.scale.x = width / 3.2
                root.addChild(endcap)
            }
        }
        return root
    }

    static func makePortalRim(width: Float, height: Float, cornerRadius: Float, thickness: Float) -> Entity {
        let root = Entity()
        root.name = "portalRim"
        if let visual = BiomeAssetCatalog.clone("rift_frame") {
            visual.scale = SIMD3(width / 3.6, height / 2.5, 1)
            root.addChild(visual)
        }
        addPortalEnergy(to: root, name: "riftEnergyOuter", radii: SIMD2(width * 0.536, height * 0.542), z: 0.30)
        addPortalEnergy(to: root, name: "riftEnergyInner", radii: SIMD2(width * 0.515, height * 0.517), z: 0.23)
        return root
    }

    private static func addPortalEnergy(to root: Entity, name: String, radii: SIMD2<Float>, z: Float) {
        guard let ring = BiomeAssetCatalog.clone("rift_energy") else { return }
        let ellipse = Entity()
        ellipse.name = name
        ellipse.scale = SIMD3(radii.x, radii.y, 1)
        ellipse.position.z = z
        ellipse.addChild(ring)
        root.addChild(ellipse)
    }

    static func animatePortalEnergy(in root: Entity, name: String, time: Float, speed: Float) {
        guard let ellipse = root.children.first(where: { $0.name == name }),
              let ring = ellipse.children.first else { return }
        ring.orientation = simd_quatf(angle: time * speed, axis: SIMD3(0, 0, 1))
        ring.components.set(OpacityComponent(opacity: 0.78 + 0.12 * sin(time * 1.4)))
    }

    static func makePortalInterior(portalHeight: Float, biome: EnvironmentID = .emberRun,
                                   scenerySeed: UInt64 = 0) -> Entity {
        let root = Entity()
        root.name = "portalInterior"
        if let environment = BiomeAssetCatalog.clone("environment_\(biome.rawValue)") {
            environment.position.y = -(portalHeight - 2.5) * 0.5
            root.addChild(environment)
        }
        for (index, placement) in SceneryVariation.placements(biome: biome, seed: scenerySeed).enumerated() {
            guard let prop = BiomeAssetCatalog.clone(BiomeAssetID.prop(biome, variant: placement.variant)) else { continue }
            prop.name = "sceneryVariation_\(index)"
            prop.scale = placement.scale
            let yaw = simd_quatf(angle: placement.yaw, axis: SIMD3(0, 1, 0))
            let lean = simd_quatf(angle: placement.lean, axis: SIMD3(0, 0, 1))
            prop.orientation = yaw * lean
            prop.position = placement.position
            root.addChild(prop)
            // Tilt around the foot, then ground the actual imported mesh bounds.
            // These are decorative clones only; no collision components are added.
            prop.position.y += -portalHeight * 0.5 - prop.visualBounds(relativeTo: root).min.y
        }
        // Sparse peripheral flecks share the imported collect-shard geometry.
        if let mesh = BiomeAssetCatalog.mesh("fx_shard") {
            let palette = EnvironmentCatalog.profile(for: biome).palette
            for index in 0..<12 {
                let side: Float = index.isMultiple(of: 2) ? -1 : 1
                let mote = ModelEntity(mesh: mesh, materials: [EnvironmentMaterials.unlit(palette.portalAccent)])
                mote.name = "riftMote"
                let size: Float = biome == .ghostGlass ? 0.008 : 0.016
                mote.scale = SIMD3(size, biome == .stormPass ? size * 5 : size, size)
                let base = SIMD3<Float>(side * (1.85 + Float(index % 3) * 0.22),
                                       0.2 + Float(index % 4) * 0.55, -2 - Float(index) * 1.5)
                mote.position = base
                mote.components.set(RiftMoteComponent(basePosition: base, phase: Float(index) * 2.399,
                                                      radius: 0.09, falling: biome == .stormPass))
                root.addChild(mote)
            }
        }
        return root
    }

    static func makeStartMarker() -> Entity {
        let root = Entity()
        root.name = "startMarker"
        if let visual = BiomeAssetCatalog.clone("start_pad") { root.addChild(visual) }
        root.position.y = 0.03
        return root
    }

    static func makeJunctionPortal(option: RiftPortalOption, seed: UInt64) -> Entity {
        let root = Entity()
        root.name = "junctionPortal"
        let palette = EnvironmentCatalog.profile(for: option.environment).palette
        let color = EnvironmentMaterials.uiColor(palette.portalRim)
        if let frame = BiomeAssetCatalog.clone("junction_frame") {
            BiomeAssetCatalog.tint(frame, role: "tint_rim", color: color)
            root.addChild(frame)
        }
        // Each choice is an actual window into its destination, sharing cached
        // geometry with the main world while retaining its own portal target.
        let destination = Entity()
        destination.name = "junctionDestinationWorld"
        destination.components.set(WorldComponent())
        destination.addChild(makePortalInterior(portalHeight: 1.86, biome: option.environment, scenerySeed: seed))
        let previewWall = makeBiomeObstacle(biome: option.environment, width: 0.7, height: 1.8, depth: 0.7,
                                            profile: EnvironmentCatalog.profile(for: option.environment), seed: seed)
        previewWall.position = SIMD3(-0.75, -0.03, -5)
        destination.addChild(previewWall)
        let aperture = ModelEntity(mesh: BiomeAssetCatalog.mesh("junction_aperture")
            ?? .generatePlane(width: 0.76, height: 1.86), materials: [PortalMaterial()])
        aperture.name = "junctionAperture"
        aperture.components.set(PortalComponent(target: destination,
            clippingMode: .plane(.positiveZ), crossingMode: .plane(.positiveZ)))
        root.addChild(destination)
        root.addChild(aperture)
        addPortalEnergy(to: root, name: "junctionEnergy", radii: SIMD2(0.422, 0.985), z: 0.22)
        BiomeAssetCatalog.tint(root, role: "tint_rim", color: color)
        BiomeAssetCatalog.tint(root, role: "tint_hot", color: EnvironmentMaterials.lerpColor(color, .white, 0.4))
        let veil = ModelEntity(mesh: .generatePlane(width: 2.7, height: 2.15),
                               materials: [UnlitMaterial(color: .black)])
        veil.name = "junctionCrossingVeil"
        veil.position.z = 0.10
        veil.isEnabled = false
        root.addChild(veil)
        let markers = Entity()
        markers.name = "junctionDifficultyMarkers"
        markers.position = SIMD3(0, 1.15, 0.12)
        let riskColor: UIColor = option.risk == .stable ? .systemMint
            : (option.risk == .charged ? .systemOrange : .systemRed)
        for index in 0..<option.risk.difficultyMarkerCount {
            if let glyph = BiomeAssetCatalog.clone("glyph_risk") {
                glyph.scale = SIMD3(repeating: 0.09)
                glyph.position.x = (Float(index) - Float(option.risk.difficultyMarkerCount - 1) * 0.5) * 0.14
                BiomeAssetCatalog.tint(glyph, role: "tint_glyph", color: riskColor)
                markers.addChild(glyph)
            }
        }
        root.addChild(markers)
        if let modifier = option.modifier {
            let holder = Entity()
            holder.name = "junctionModifierGlyph"
            holder.position = SIMD3(0, -0.74, 0.25)
            let id: String
            switch modifier {
            case .tokenSurge: id = "token"
            case .aegis: id = "glyph_aegis"
            case .overdrive: id = "glyph_overdrive"
            case .magnet: id = "glyph_magnet"
            case .closeCall: id = "glyph_precision"
            case .bonusBank: id = "glyph_lock"
            }
            if let glyph = BiomeAssetCatalog.clone(id) {
                glyph.scale = SIMD3(repeating: modifier == .tokenSurge ? 1.4 : 0.25)
                BiomeAssetCatalog.tint(glyph, role: "tint_glyph", color: color)
                holder.addChild(glyph)
            }
            root.addChild(holder)
        }
        return root
    }

    // Effect planes are runtime infrastructure, not authored scenery.
    static func makeHitFlash(width: Float = 3.5, height: Float = 2.4) -> ModelEntity {
        let flash = ModelEntity(mesh: .generatePlane(width: width, height: height, cornerRadius: 0.2),
                                materials: [GameMaterials.hitFlash()])
        flash.name = "hitFlash"
        return flash
    }

    static func makeCollectSpark(color: UIColor, radius: Float, colorIndex: Int = 0) -> ModelEntity {
        let root = ModelEntity()
        let mesh = BiomeAssetCatalog.mesh("fx_shard") ?? .generateSphere(radius: 1)
        let shard = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: color)])
        shard.scale = SIMD3(repeating: radius)
        root.addChild(shard)
        root.name = "collectSpark.\(colorIndex)"
        root.isEnabled = false
        return root
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
    private var mergeCrystal: Entity?
    private var mergeAge: Float = 0
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
        mergeCrystal?.removeFromParent()
        mergeCrystal = nil
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

    func spawnCrystalMerge(at position: SIMD3<Float>) {
        spawnCoinBurst(at: position)
        mergeCrystal?.removeFromParent()
        if let crystal = BiomeAssetCatalog.clone("crystal_combined") {
            crystal.position = position
            fxRoot.addChild(crystal)
            mergeCrystal = crystal
            mergeAge = 0
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
        if let crystal = mergeCrystal {
            mergeAge += deltaTime
            let t = min(1, mergeAge / 0.55)
            crystal.scale = SIMD3(repeating: 0.75 + sin(t * .pi) * 0.4)
            crystal.orientation = simd_quatf(angle: t * .pi, axis: SIMD3(0, 1, 0))
            crystal.components.set(OpacityComponent(opacity: 1 - t))
            if t >= 1 {
                crystal.removeFromParent()
                mergeCrystal = nil
            }
        }
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
                flash.components.set(OpacityComponent(opacity: fade))
                flash.position.z += deltaTime * 0.2
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
