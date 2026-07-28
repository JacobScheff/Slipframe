//
//  GameWorld.swift
//  Endless Runner
//
//  Mixed-immersive endless runner with rotating biome environments:
//  - Playfield sits on the real floor and locks pose when a run starts
//  - Synth Riders-style portal window at the end of a fixed track
//  - Obstacles emerge from the portal into the real room
//  - Biomes tint ambience / walls / coins (ready for custom assets later)
//  - Each biome applies one gameplay twist via EnvironmentDirector
//

import ARKit
import RealityKit
import SwiftUI
import UIKit

@MainActor
final class GameWorld {
    private enum Lane: Int, CaseIterable {
        case left = -1
        case center = 0
        case right = 1

        var x: Float {
            Float(rawValue) * GameWorld.laneSpacing
        }
    }

    private final class WallItem {
        let entity: Entity
        /// Local X centers of each slab relative to the wall parent.
        let localSlabXs: [Float]
        let kind: WallKind
        var hasResolvedHit = false

        init(entity: Entity, localSlabXs: [Float], kind: WallKind) {
            self.entity = entity
            self.localSlabXs = localSlabXs
            self.kind = kind
        }

        func worldSlabXs() -> [Float] {
            localSlabXs.map { $0 + entity.position.x }
        }
    }

    private struct CoinItem {
        let entity: Entity
        var collected = false
    }

    private final class HalfCrystalItem {
        let entity: Entity
        let type: CrystalHalfType
        let charged: Bool
        var collected = false

        init(entity: Entity, type: CrystalHalfType, charged: Bool) {
            self.entity = entity
            self.type = type
            self.charged = charged
        }
    }

    private struct HeldHalf {
        let type: CrystalHalfType
        let charged: Bool
        let entity: Entity
    }

    // Layout
    private static let laneSpacing: Float = 0.75
    private static let wallHeight: Float = 1.8
    /// Depth along the track so slabs read as thick volumes, not paper-thin panels.
    private static let wallThickness: Float = 0.7
    private static let wallWidth: Float = 0.7
    private static let coinRadius: Float = 0.07
    private static let coinHeight: Float = 1.2
    /// How far side-lane coins sit outside the lane center (smaller = easier reach).
    private static let coinOutwardOffset: Float = 0.12
    /// Portal / spawn depth when no wall plane is available.
    private static let defaultPortalZ: Float = -8
    private static let despawnZ: Float = 1.5
    /// Kill-box depth pad beyond the thinned collision half-depth.
    private static let hitZPad: Float = 0.02
    /// Shrink the slab's X kill box so grazing a lane edge is less punishing.
    private static let hitXInset: Float = 0.12
    /// Hands must be inside the slab height — ignore floor/ceiling noise.
    private static let handHitMinY: Float = 0.05
    private static let handHitMaxY: Float = wallHeight + 0.15
    /// Expand around tracked joints so a real hand volume can touch a slab.
    private static let handHitRadius: Float = 0.12
    /// Head stays within the standing eye band for wall tests.
    private static let headHitMinY: Float = 0.4
    private static let headHitMaxY: Float = wallHeight + 0.35
    private static let collectDistance: Float = 0.24
    private static let baseSpeed: Float = 3.0
    private static let maxSpeed: Float = 7.0
    private static let speedRampPerSecond: Float = 0.055
    /// Continuous obstacle stream with a bit of breathing room between beats.
    private static let spawnGapMin: Float = 2.2
    private static let spawnGapMax: Float = 2.9
    private static let coinPoints = CrystalCombine.baseCoinPoints
    /// HUD sits above the corridor, further down the track, clear of the play volume.
    private static let hudPosition = SIMD3<Float>(0, 2.45, -3.2)
    /// World scale for the SwiftUI attachment (attachments are small by default).
    private static let hudScale: Float = 3.0

    // Duck hazard geometry (Low Crawl).
    private static let duckClearanceY: Float = 1.05
    private static let duckSlabHeight: Float = 0.55
    private static let duckSlabWidth: Float = 2.4

    // Synth Riders-style portal aperture (always visible at the track end).
    private static let portalWidth: Float = 3.6
    private static let portalHeight: Float = 2.5
    private static let portalCornerRadius: Float = 0.85
    /// Neon halo that peeks out around the portal mesh.
    private static let portalRimThickness: Float = 0.11
    /// Prefer snapping the portal onto a real wall in this band.
    private static let portalMinDistance: Float = 3.5
    private static let portalMaxDistance: Float = 10.0
    /// Obstacles appear just in front of the portal mouth (toward the player).
    private static let spawnInFrontOfPortal: Float = 0.35
    private static let wallMinimumBounds = SIMD2<Float>(0.8, 1.5)

    // Fixed track slab from the stand line to just behind the portal.
    private static let trackWidth: Float = 3.2
    private static let trackNearZ: Float = 0.55
    private static let trackPastPortal: Float = 0.35
    /// Used only when a floor plane has not been found yet.
    private static let fallbackEyeHeight: Float = 1.55

    // Storm Pass wind.
    private static let windMinInterval: Float = 3.5
    private static let windMaxInterval: Float = 6.5
    private static let windDuration: Float = 0.85
    private static let windMagnitude: Float = 0.42
    private static let windSafeDistance: Float = 2.2

    /// Playfield origin: floor at y=0, stand line at z=0, track extends along −Z.
    let root = Entity()
    private let headAnchor = AnchorEntity(.head)
    private let floorAnchor = AnchorEntity(
        .plane(
            .horizontal,
            classification: .floor,
            minimumBounds: SIMD2<Float>(0.5, 0.5)
        )
    )
    /// First matching vertical wall — portal attaches here when in range.
    private let wallAnchor = AnchorEntity(
        .plane(
            .vertical,
            classification: .wall,
            minimumBounds: GameWorld.wallMinimumBounds
        )
    )
    private let hudAnchor = Entity()
    private let trackRoot = Entity()
    private let fogRoot = Entity()
    /// Holds the portal plane + neon rim in playfield space (always visible).
    private let portalRoot = Entity()
    private let portalEntity = Entity()
    private let portalWorld = Entity()

    private weak var gameModel: GameModel?
    private let environmentDirector = EnvironmentDirector()
    private var lastDebugMode: EnvironmentDebugMode = .normal
    private var activeSpawnProfile: EnvironmentProfile = EnvironmentCatalog.profile(for: .emberRun)

    private var walls: [WallItem] = []
    private var coins: [CoinItem] = []
    private var halves: [HalfCrystalItem] = []
    private var heldLeft: HeldHalf?
    private var heldRight: HeldHalf?

    private var speed: Float = GameWorld.baseSpeed
    /// First obstacle spawns on the opening tick of a run.
    private var distanceUntilSpawn: Float = 0
    private var distanceAccumulator: Float = 0
    /// Portal plane depth along playfield −Z.
    private var portalZ: Float = GameWorld.defaultPortalZ
    /// Where obstacles / coins appear (just in front of the portal).
    private var activeSpawnZ: Float = GameWorld.defaultPortalZ + GameWorld.spawnInFrontOfPortal
    private var lastBuiltPortalZ: Float = .greatestFiniteMagnitude
    private var updateSubscription: EventSubscription?
    private var activeRunID: Int = -1
    /// After Start, playfield pose no longer follows the player.
    private var isPlayfieldLocked = false

    // Wind shove state (offsets obstacle boxes only).
    private var windCurrentX: Float = 0
    private var windFromX: Float = 0
    private var windToX: Float = 0
    private var windElapsed: Float = 0
    private var windDurationActive: Float = 0
    private var timeUntilWind: Float = GameWorld.windMinInterval
    private var gustEntity: Entity?

    /// ARKit hand tracking — AnchorEntity(.hand) transforms are privacy-locked
    /// unless a SpatialTrackingSession is running (visionOS 2+), so we read
    /// joint positions from HandTrackingProvider instead.
    private let arSession = ARKitSession()
    private let handTracking = HandTrackingProvider()
    private var handTask: Task<Void, Never>?
    /// World-space contact points (wrist + fingertips) for each hand.
    private var leftHandContactsWorld: [SIMD3<Float>] = []
    private var rightHandContactsWorld: [SIMD3<Float>] = []
    private var leftHandPalmWorld: SIMD3<Float>?
    private var rightHandPalmWorld: SIMD3<Float>?
    private var leftIsFist = false
    private var rightIsFist = false

    func attach(to content: RealityViewContent, gameModel: GameModel) {
        self.gameModel = gameModel
        content.add(root)
        content.add(headAnchor)
        content.add(floorAnchor)
        content.add(wallAnchor)
        isPlayfieldLocked = false
        lastDebugMode = gameModel.environmentDebugMode

        if updateSubscription == nil {
            updateSubscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
                self?.tick(deltaTime: Float(event.deltaTime))
            }
        }

        buildPortal()
        buildStaticEnvironment()
        ensureHUDAnchor()
        startHandTracking()
        // Warm audio before the first coin so setActive does not hitch mid-run.
        GameSFX.shared.prepare()
        GameMusic.shared.prepare()
        applyPalette(environmentDirector.displayedPalette, telegraph: 0)
        snapPlayfieldToPlayer()
        updatePortalAndTrack()
    }

    /// Parents the SwiftUI play/score attachment so it stays fixed with the track.
    func attachHUD(_ hudEntity: Entity) {
        ensureHUDAnchor()
        // Attachments face +Z by default; player looks down −Z, so identity faces you.
        // (A 180° yaw shows the panel mirrored from behind.)
        hudEntity.orientation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        hudEntity.scale = SIMD3(repeating: GameWorld.hudScale)
        guard hudEntity.parent !== hudAnchor else { return }
        hudEntity.removeFromParent()
        hudAnchor.addChild(hudEntity)
    }

    func syncRun(with gameModel: GameModel) {
        self.gameModel = gameModel
        if gameModel.environmentDebugMode != lastDebugMode {
            lastDebugMode = gameModel.environmentDebugMode
            environmentDirector.applyDebugMode(gameModel.environmentDebugMode)
            activeSpawnProfile = environmentDirector.currentProfile
            if gameModel.environmentDebugMode != .normal || gameModel.isPlaying {
                dropHeldHalves()
            }
        }
        guard gameModel.isPlaying, gameModel.runID != activeRunID else { return }
        beginRun(runID: gameModel.runID)
    }

    func teardown() {
        handTask?.cancel()
        handTask = nil
        leftHandContactsWorld = []
        rightHandContactsWorld = []
        leftHandPalmWorld = nil
        rightHandPalmWorld = nil
        leftIsFist = false
        rightIsFist = false
        updateSubscription = nil
        isPlayfieldLocked = false
        portalZ = GameWorld.defaultPortalZ
        activeSpawnZ = GameWorld.defaultPortalZ + GameWorld.spawnInFrontOfPortal
        lastBuiltPortalZ = .greatestFiniteMagnitude
        clearDynamicContent()
        dropHeldHalves()
        GameMusic.shared.stop()
        for child in hudAnchor.children {
            child.removeFromParent()
        }
        for child in trackRoot.children {
            child.removeFromParent()
        }
        for child in fogRoot.children {
            child.removeFromParent()
        }
        for child in portalRoot.children {
            child.removeFromParent()
        }
        for child in portalWorld.children {
            child.removeFromParent()
        }
        portalRoot.removeFromParent()
        portalWorld.removeFromParent()
        fogRoot.removeFromParent()
        for child in root.children {
            child.removeFromParent()
        }
    }

    private func ensureHUDAnchor() {
        hudAnchor.name = "playHUD"
        hudAnchor.position = GameWorld.hudPosition
        if hudAnchor.parent !== root {
            root.addChild(hudAnchor)
        }
    }

    // MARK: - Setup

    private func buildStaticEnvironment() {
        trackRoot.name = "trackRoot"
        fogRoot.name = "fogRoot"
        if trackRoot.parent !== root {
            root.addChild(trackRoot)
        }
        if fogRoot.parent !== root {
            root.addChild(fogRoot)
        }
        rebuildFixedTrack(force: true)
        buildStartMarker()
        rebuildFogVolumes(density: 0, color: .clear)
    }

    /// One static floor slab from the stand line to the portal — never scrolls.
    private func rebuildFixedTrack(force: Bool = false) {
        if !force, abs(portalZ - lastBuiltPortalZ) < 0.05, !trackRoot.children.isEmpty {
            return
        }
        lastBuiltPortalZ = portalZ

        for child in trackRoot.children {
            child.removeFromParent()
        }

        let farZ = portalZ - GameWorld.trackPastPortal
        let nearZ = GameWorld.trackNearZ
        let depth = max(1.0, nearZ - farZ)
        let centerZ = (nearZ + farZ) * 0.5
        let palette = environmentDirector.displayedPalette

        let floorMesh = MeshResource.generateBox(
            width: GameWorld.trackWidth,
            height: 0.02,
            depth: depth
        )
        let floor = ModelEntity(
            mesh: floorMesh,
            materials: [EnvironmentMaterials.simple(palette.floor, roughness: 0.85)]
        )
        floor.name = "floor"
        floor.position = SIMD3(0, 0, centerZ)
        trackRoot.addChild(floor)

        for lane in Lane.allCases {
            let stripeMesh = MeshResource.generateBox(width: 0.07, height: 0.025, depth: depth)
            let stripe = ModelEntity(
                mesh: stripeMesh,
                materials: [EnvironmentMaterials.unlit(palette.laneStripe)]
            )
            stripe.name = "laneStripe"
            stripe.position = SIMD3(lane.x, 0.02, centerZ)
            trackRoot.addChild(stripe)
        }
    }

    /// Always-on Synth Riders-style aperture at the end of the track.
    private func buildPortal() {
        portalRoot.name = "portalRoot"
        portalEntity.name = "portal"
        portalWorld.name = "portalWorld"
        portalWorld.components.set(WorldComponent())

        let portalMesh = MeshResource.generatePlane(
            width: GameWorld.portalWidth,
            height: GameWorld.portalHeight,
            cornerRadius: GameWorld.portalCornerRadius
        )
        // Plane faces +Z (toward the player looking down −Z).
        portalEntity.components.set(
            ModelComponent(mesh: portalMesh, materials: [PortalMaterial()])
        )
        portalEntity.components.set(PortalComponent(target: portalWorld))

        buildPortalRim()
        buildPortalInterior()

        if portalEntity.parent !== portalRoot {
            portalRoot.addChild(portalEntity)
        }
        // World must live in the scene graph; keep it under portalRoot so it moves with the aperture.
        if portalWorld.parent !== portalRoot {
            portalRoot.addChild(portalWorld)
        }
        if portalRoot.parent !== root {
            root.addChild(portalRoot)
        }

        layoutPortal()
    }

    private func buildPortalRim() {
        if let existing = portalRoot.children.first(where: { $0.name == "portalRim" }) {
            existing.removeFromParent()
        }

        let rim = Entity()
        rim.name = "portalRim"
        let t = GameWorld.portalRimThickness
        let palette = environmentDirector.displayedPalette

        let haloMesh = MeshResource.generatePlane(
            width: GameWorld.portalWidth + t * 2,
            height: GameWorld.portalHeight + t * 2,
            cornerRadius: GameWorld.portalCornerRadius + t * 0.4
        )
        let halo = ModelEntity(
            mesh: haloMesh,
            materials: [EnvironmentMaterials.unlit(palette.portalRim)]
        )
        halo.name = "portalRimHalo"
        halo.position = SIMD3(0, 0, -0.015)
        rim.addChild(halo)

        portalRoot.addChild(rim)
    }

    /// Dark tunnel visible only through the portal — blocks passthrough cleanly.
    private func buildPortalInterior() {
        for child in portalWorld.children {
            child.removeFromParent()
        }

        let interior = Entity()
        interior.name = "portalInterior"
        interior.position = SIMD3(0, 0, -0.05)
        let palette = environmentDirector.displayedPalette

        let voidMat = EnvironmentMaterials.unlit(palette.portalVoid)
        let railMat = EnvironmentMaterials.unlit(palette.portalRail)
        let accentMat = EnvironmentMaterials.unlit(palette.portalAccent)

        let tunnelW: Float = 4.4
        let tunnelH = GameWorld.portalHeight + 0.4
        let tunnelDepth: Float = 10

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

        for sign: Float in [-1, 1] {
            let rail = ModelEntity(
                mesh: MeshResource.generateBox(width: 0.05, height: 0.05, depth: tunnelDepth - 0.5),
                materials: [railMat]
            )
            rail.name = "portalRail"
            rail.position = SIMD3(sign * 1.35, -tunnelH * 0.5 + 0.08, -tunnelDepth * 0.5)
            interior.addChild(rail)
        }

        let farGlow = ModelEntity(
            mesh: MeshResource.generateSphere(radius: 0.45),
            materials: [accentMat]
        )
        farGlow.name = "portalAccent"
        farGlow.position = SIMD3(0, -0.15, -tunnelDepth + 1.2)
        interior.addChild(farGlow)

        portalWorld.addChild(interior)
    }

    private func layoutPortal() {
        portalRoot.position = SIMD3(0, GameWorld.portalHeight * 0.5, portalZ)
        activeSpawnZ = portalZ + GameWorld.spawnInFrontOfPortal
    }

    /// Minimal stand line at the player's start — easy to find, quiet otherwise.
    private func buildStartMarker() {
        if root.children.contains(where: { $0.name == "startMarker" }) { return }

        let marker = Entity()
        marker.name = "startMarker"
        marker.position = SIMD3(0, 0.03, 0)

        let lineMesh = MeshResource.generateBox(width: 2.35, height: 0.008, depth: 0.028)
        let lineMaterial = UnlitMaterial(
            color: UIColor(red: 0.98, green: 0.93, blue: 0.82, alpha: 0.75)
        )
        let line = ModelEntity(mesh: lineMesh, materials: [lineMaterial])
        marker.addChild(line)

        let tickMesh = MeshResource.generateBox(width: 0.1, height: 0.01, depth: 0.1)
        let tickMaterial = UnlitMaterial(
            color: UIColor(red: 1.0, green: 0.86, blue: 0.45, alpha: 0.9)
        )
        let tick = ModelEntity(mesh: tickMesh, materials: [tickMaterial])
        tick.position = SIMD3(0, 0.004, 0)
        marker.addChild(tick)

        root.addChild(marker)
    }

    private func beginRun(runID: Int) {
        activeRunID = runID
        snapPlayfieldToPlayer()
        updatePortalAndTrack()
        isPlayfieldLocked = true
        clearDynamicContent()
        dropHeldHalves()
        resetWind()
        environmentDirector.beginRun(debugMode: gameModel?.environmentDebugMode ?? .normal)
        activeSpawnProfile = environmentDirector.currentProfile
        rebuildFixedTrack(force: true)
        buildPortalRim()
        buildPortalInterior()
        applyPalette(environmentDirector.displayedPalette, telegraph: 0)
        layoutPortal()
        speed = GameWorld.baseSpeed
        distanceUntilSpawn = 0
        distanceAccumulator = 0
        GameSFX.shared.prepare()
        GameMusic.shared.prepare()
    }

    // MARK: - Palette / fog

    private func applyPalette(_ palette: EnvironmentPalette, telegraph: Float) {
        for child in trackRoot.children {
            guard let model = child as? ModelEntity else { continue }
            if child.name == "floor" {
                model.model?.materials = [EnvironmentMaterials.simple(palette.floor, roughness: 0.85)]
            } else if child.name == "laneStripe" {
                model.model?.materials = [EnvironmentMaterials.unlit(palette.laneStripe)]
            }
        }

        if let rim = portalRoot.children.first(where: { $0.name == "portalRim" }) {
            for child in rim.children {
                guard let model = child as? ModelEntity else { continue }
                // Brief rim pulse on biome switch — no full-screen wash in front of the player.
                var rimTint = palette.portalRim
                if telegraph > 0.01 {
                    let boost = 0.35 * telegraph
                    rimTint = TintColor(
                        r: min(1, rimTint.r + boost),
                        g: min(1, rimTint.g + boost),
                        b: min(1, rimTint.b + boost),
                        a: rimTint.a
                    )
                }
                model.model?.materials = [EnvironmentMaterials.unlit(rimTint)]
            }
        }

        if let interior = portalWorld.children.first(where: { $0.name == "portalInterior" }) {
            for child in interior.children {
                guard let model = child as? ModelEntity else { continue }
                switch child.name {
                case "portalRail":
                    model.model?.materials = [EnvironmentMaterials.unlit(palette.portalRail)]
                case "portalAccent":
                    model.model?.materials = [EnvironmentMaterials.unlit(palette.portalAccent)]
                default:
                    model.model?.materials = [EnvironmentMaterials.unlit(palette.portalVoid)]
                }
            }
        }

        rebuildFogVolumes(density: palette.fogDensity, color: palette.fogColor)
    }

    /// Soft mist for Fog Hollow only. Kept mid-track → portal so the stand line stays clear.
    private func rebuildFogVolumes(density: Float, color: TintColor) {
        for child in fogRoot.children {
            child.removeFromParent()
        }
        guard density > 0.02 else { return }

        // Keep the first ~2.5 m of play space open; haze builds toward the portal.
        let clearUntilZ: Float = -2.5
        let endZ = min(portalZ + 0.4, -3.0)
        guard endZ < clearUntilZ - 0.5 else { return }

        let layerCount = max(3, Int(ceil(Double(density * 6))))
        for index in 0..<layerCount {
            let t = Float(index) / Float(max(1, layerCount - 1))
            let z = clearUntilZ + (endZ - clearUntilZ) * t
            // Farther layers are denser; near layers stay wispy.
            let alpha = min(0.14, 0.03 + density * 0.08 * (0.35 + 0.65 * t))
            let mist = TintColor(
                r: color.r,
                g: color.g,
                b: color.b,
                a: alpha
            )
            // Thin depth slabs read as volume haze better than flat face-on cards.
            let width: Float = 3.4 + t * 0.4
            let height: Float = 2.1 + t * 0.3
            let depth: Float = 0.55
            let mesh = MeshResource.generateBox(width: width, height: height, depth: depth)
            let volume = ModelEntity(
                mesh: mesh,
                materials: [EnvironmentMaterials.fogVolume(mist)]
            )
            volume.name = "fogVolume"
            volume.position = SIMD3(0, 1.15, z)
            fogRoot.addChild(volume)
        }
    }

    // MARK: - Playfield pose

    private func snapPlayfieldToPlayer() {
        let headWorld = headAnchor.position(relativeTo: nil)
        let headRotation = headAnchor.orientation(relativeTo: nil)

        let floorY: Float
        if floorAnchor.isAnchored {
            floorY = floorAnchor.position(relativeTo: nil).y
        } else {
            floorY = headWorld.y - GameWorld.fallbackEyeHeight
        }

        let position = SIMD3<Float>(headWorld.x, floorY, headWorld.z)
        let flatForward: SIMD3<Float>

        if let towardWall = suitableWallForward(from: position) {
            flatForward = towardWall
        } else {
            let forwardWorld = headRotation.act(SIMD3<Float>(0, 0, -1))
            var flattened = SIMD3<Float>(forwardWorld.x, 0, forwardWorld.z)
            let forwardLength = length(flattened)
            if forwardLength < 0.05 {
                flattened = SIMD3(0, 0, -1)
            } else {
                flattened /= forwardLength
            }
            flatForward = flattened
        }

        let yaw = atan2(-flatForward.x, -flatForward.z)
        root.setPosition(position, relativeTo: nil)
        root.setOrientation(simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0)), relativeTo: nil)
    }

    private func suitableWallForward(from playerPosition: SIMD3<Float>) -> SIMD3<Float>? {
        guard wallAnchor.isAnchored else { return nil }

        let wallWorld = wallAnchor.position(relativeTo: nil)
        var toWall = SIMD3<Float>(
            wallWorld.x - playerPosition.x,
            0,
            wallWorld.z - playerPosition.z
        )
        let distance = length(toWall)
        guard distance >= GameWorld.portalMinDistance,
              distance <= GameWorld.portalMaxDistance
        else { return nil }

        toWall /= distance
        return toWall
    }

    private func updatePortalAndTrack() {
        let playerPosition = root.position(relativeTo: nil)

        if wallAnchor.isAnchored,
           suitableWallForward(from: playerPosition) != nil {
            let wallInRoot = root.convert(position: wallAnchor.position(relativeTo: nil), from: nil)
            portalZ = min(-GameWorld.portalMinDistance, wallInRoot.z + 0.05)
        } else {
            portalZ = GameWorld.defaultPortalZ
        }

        layoutPortal()
        if !isPlayfieldLocked {
            rebuildFixedTrack()
        }
    }

    private func clearDynamicContent() {
        for wall in walls {
            wall.entity.removeFromParent()
        }
        for coin in coins {
            coin.entity.removeFromParent()
        }
        for half in halves {
            half.entity.removeFromParent()
        }
        walls.removeAll()
        coins.removeAll()
        halves.removeAll()
        gustEntity?.removeFromParent()
        gustEntity = nil
    }

    // MARK: - Hand tracking

    private func startHandTracking() {
        guard handTask == nil else { return }
        handTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard HandTrackingProvider.isSupported else { return }

            do {
                let auth = await arSession.requestAuthorization(for: [.handTracking])
                guard auth[.handTracking] == .allowed else { return }
                try await arSession.run([handTracking])

                for await update in handTracking.anchorUpdates {
                    guard !Task.isCancelled else { break }
                    let anchor = update.anchor
                    guard anchor.isTracked else {
                        switch anchor.chirality {
                        case .left:
                            leftHandContactsWorld = []
                            leftHandPalmWorld = nil
                            leftIsFist = false
                        case .right:
                            rightHandContactsWorld = []
                            rightHandPalmWorld = nil
                            rightIsFist = false
                        @unknown default: break
                        }
                        continue
                    }
                    let contacts = Self.contactPoints(from: anchor)
                    let palm = Self.palmPoint(from: anchor)
                    let fist = HandPose.isFist(anchor: anchor)
                    switch anchor.chirality {
                    case .left:
                        leftHandContactsWorld = contacts
                        leftHandPalmWorld = palm
                        leftIsFist = fist
                    case .right:
                        rightHandContactsWorld = contacts
                        rightHandPalmWorld = palm
                        rightIsFist = fist
                    @unknown default:
                        break
                    }
                }
            } catch {
                print("Hand tracking failed: \(error)")
            }
        }
    }

    private static func contactPoints(from anchor: HandAnchor) -> [SIMD3<Float>] {
        let origin = anchor.originFromAnchorTransform
        var points: [SIMD3<Float>] = [
            SIMD3(origin.columns.3.x, origin.columns.3.y, origin.columns.3.z)
        ]

        guard let skeleton = anchor.handSkeleton else { return points }
        let tips: [HandSkeleton.JointName] = [
            .indexFingerTip,
            .middleFingerTip,
            .thumbTip
        ]
        for name in tips {
            let joint = skeleton.joint(name)
            guard joint.isTracked else { continue }
            let world = origin * joint.anchorFromJointTransform
            points.append(SIMD3(world.columns.3.x, world.columns.3.y, world.columns.3.z))
        }
        return points
    }

    private static func palmPoint(from anchor: HandAnchor) -> SIMD3<Float> {
        let origin = anchor.originFromAnchorTransform
        return SIMD3(origin.columns.3.x, origin.columns.3.y, origin.columns.3.z)
    }

    // MARK: - Loop

    private func tick(deltaTime: Float) {
        if !isPlayfieldLocked {
            snapPlayfieldToPlayer()
            updatePortalAndTrack()
        }

        guard let gameModel else { return }

        if gameModel.environmentDebugMode != lastDebugMode {
            lastDebugMode = gameModel.environmentDebugMode
            environmentDirector.applyDebugMode(gameModel.environmentDebugMode)
            activeSpawnProfile = environmentDirector.currentProfile
            dropHeldHalves()
        }

        guard gameModel.isPlaying, !gameModel.isGameOver else { return }
        guard deltaTime > 0, deltaTime < 0.25 else { return }

        let frame = environmentDirector.update(deltaTime: deltaTime)
        if frame.didEnterEnvironment {
            activeSpawnProfile = frame.profile
            dropHeldHalves()
            if frame.profile.twist != .windShove {
                resetWind()
            } else {
                timeUntilWind = Float.random(in: 1.2...2.5)
            }
        }
        applyPalette(frame.displayedPalette, telegraph: frame.telegraphStrength)

        let travel = speed * deltaTime
        speed = min(GameWorld.maxSpeed, speed + GameWorld.speedRampPerSecond * deltaTime)

        distanceAccumulator += travel
        if distanceAccumulator >= 1 {
            let gained = Int(distanceAccumulator)
            distanceAccumulator -= Float(gained)
            gameModel.addScore(gained)
        }

        advanceEntities(by: travel)
        updateWind(deltaTime: deltaTime)
        updateHeldHalves()

        distanceUntilSpawn -= travel
        if distanceUntilSpawn <= 0 {
            spawnNextPattern()
            distanceUntilSpawn = Float.random(in: GameWorld.spawnGapMin...GameWorld.spawnGapMax)
        }

        resolveCollisions(gameModel: gameModel)
        pruneEntities()
    }

    private func advanceEntities(by travel: Float) {
        for wall in walls {
            wall.entity.position.z += travel
        }
        for coin in coins {
            coin.entity.position.z += travel
        }
        for half in halves {
            half.entity.position.z += travel
        }
    }

    // MARK: - Wind (Storm Pass)

    private func resetWind() {
        windCurrentX = 0
        windFromX = 0
        windToX = 0
        windElapsed = 0
        windDurationActive = 0
        timeUntilWind = Float.random(in: GameWorld.windMinInterval...GameWorld.windMaxInterval)
        gustEntity?.removeFromParent()
        gustEntity = nil
    }

    private func updateWind(deltaTime: Float) {
        guard activeSpawnProfile.twist == .windShove else { return }

        if windDurationActive > 0 {
            windElapsed += deltaTime
            let t = min(1, windElapsed / windDurationActive)
            // Smoothstep for non-sudden box motion.
            let smooth = t * t * (3 - 2 * t)
            let newX = windFromX + (windToX - windFromX) * smooth
            let deltaX = newX - windCurrentX
            windCurrentX = newX
            shiftDynamicBoxes(by: deltaX)
            updateGustVisual(progress: t)
            if t >= 1 {
                windDurationActive = 0
                gustEntity?.removeFromParent()
                gustEntity = nil
                timeUntilWind = Float.random(in: GameWorld.windMinInterval...GameWorld.windMaxInterval)
            }
            return
        }

        timeUntilWind -= deltaTime
        if timeUntilWind <= 0 {
            beginWindShove()
        }
    }

    private func beginWindShove() {
        // Don't shove when a wall is already on top of the player.
        let imminent = walls.contains { abs($0.entity.position.z) < GameWorld.windSafeDistance }
        if imminent {
            timeUntilWind = 0.75
            return
        }

        let direction: Float = Bool.random() ? 1 : -1
        windFromX = windCurrentX
        windToX = windCurrentX + direction * GameWorld.windMagnitude
        windElapsed = 0
        windDurationActive = GameWorld.windDuration
        spawnGustVisual(direction: direction)
        GameSFX.shared.playWindWhoosh()
    }

    private func shiftDynamicBoxes(by deltaX: Float) {
        guard abs(deltaX) > 0.0001 else { return }
        for wall in walls {
            wall.entity.position.x += deltaX
        }
        for coin in coins {
            coin.entity.position.x += deltaX
        }
        for half in halves {
            half.entity.position.x += deltaX
        }
    }

    private func spawnGustVisual(direction: Float) {
        gustEntity?.removeFromParent()
        let gust = Entity()
        gust.name = "windGust"
        let mesh = MeshResource.generateBox(width: 2.8, height: 0.08, depth: 0.35)
        let mat = UnlitMaterial(color: UIColor(red: 0.55, green: 0.75, blue: 1.0, alpha: 0.35))
        let model = ModelEntity(mesh: mesh, materials: [mat])
        model.position = SIMD3(direction * 0.2, 1.2, -1.5)
        gust.addChild(model)
        root.addChild(gust)
        gustEntity = gust
    }

    private func updateGustVisual(progress: Float) {
        guard let gust = gustEntity else { return }
        let fade = max(0, 1 - abs(progress - 0.45) * 2)
        gust.position.z += speed * 0.016
        if let model = gust.children.first as? ModelEntity {
            model.model?.materials = [
                UnlitMaterial(color: UIColor(red: 0.55, green: 0.75, blue: 1.0, alpha: CGFloat(0.15 + 0.35 * fade)))
            ]
        }
    }

    // MARK: - Spawning

    private func spawnNextPattern() {
        let profile = activeSpawnProfile

        switch profile.twist {
        case .lowCrawl:
            spawnLowCrawlPattern(profile: profile)
        case .crystalHalves:
            spawnCrystalCavePattern()
        case .ghostWalls:
            spawnGhostGlassPattern(profile: profile)
        case .fogVisibility, .baseline, .windShove:
            spawnStandardPattern(preferFairFog: profile.twist == .fogVisibility)
        }
    }

    private func spawnStandardPattern(preferFairFog: Bool) {
        let blocking = preferFairFog ? Self.fairFogWallLanes() : Self.randomWallLanes()
        spawnWall(blocking: blocking, kind: .standard, profile: activeSpawnProfile)

        let safeLanes = Lane.allCases.filter { !blocking.contains($0) }
        if let coinLane = safeLanes.randomElement(), Float.random(in: 0...1) < 0.7 {
            spawnCoin(in: coinLane)
        }
    }

    private func spawnGhostGlassPattern(profile: EnvironmentProfile) {
        let blocking = Self.randomWallLanes()
        let kind: WallKind = Float.random(in: 0...1) < profile.ghostWallChance ? .ghost : .standard
        spawnWall(blocking: blocking, kind: kind, profile: profile)

        let safeLanes = Lane.allCases.filter { !blocking.contains($0) }
        if let coinLane = safeLanes.randomElement(), Float.random(in: 0...1) < 0.7 {
            spawnCoin(in: coinLane)
        }
    }

    private func spawnLowCrawlPattern(profile: EnvironmentProfile) {
        if environmentDirector.isTeachingLowCrawl {
            spawnDuckWall()
            environmentDirector.noteDuckGateSpawned()
            return
        }

        if Float.random(in: 0...1) < profile.duckHazardChance {
            // Occasional duck + simple single side wall, otherwise duck alone.
            if Float.random(in: 0...1) < 0.35 {
                let side: Set<Lane> = Bool.random() ? [.left] : [.right]
                spawnWall(blocking: side, kind: .standard, profile: profile)
            }
            spawnDuckWall()
        } else {
            spawnStandardPattern(preferFairFog: false)
        }
    }

    private func spawnCrystalCavePattern() {
        // Prefer simpler / fewer walls while halves are in play.
        let patterns: [Set<Lane>] = [
            [.left], [.center], [.right],
            [.left], [.right],
            [.left, .right]
        ]
        let blocking = patterns.randomElement() ?? [.center]
        spawnWall(blocking: blocking, kind: .standard, profile: activeSpawnProfile)

        let safeLanes = Lane.allCases.filter { !blocking.contains($0) }
        if let lane = safeLanes.randomElement(), Float.random(in: 0...1) < 0.8 {
            spawnHalfCrystal(in: lane)
        }
    }

    /// Avoid surprise double-blocks while Fog Hollow walls are harder to read.
    private static func fairFogWallLanes() -> Set<Lane> {
        let patterns: [Set<Lane>] = [
            [.left], [.center], [.right],
            [.left], [.center], [.right],
            [.left, .right]
        ]
        return patterns.randomElement() ?? [.center]
    }

    private static func randomWallLanes() -> Set<Lane> {
        let patterns: [Set<Lane>] = [
            [.left], [.center], [.right],
            [.left], [.center], [.right],
            [.left], [.right],
            [.left, .center], [.center, .right], [.left, .right],
            [.left, .right], [.left, .center], [.center, .right]
        ]
        return patterns.randomElement() ?? [.center]
    }

    private func spawnWall(blocking lanes: Set<Lane>, kind: WallKind, profile: EnvironmentProfile) {
        let parent = Entity()
        parent.position = SIMD3(windCurrentX, GameWorld.wallHeight * 0.5, activeSpawnZ)
        parent.name = kind == .ghost ? "wallGhost" : "wall"

        var slabXs: [Float] = []
        for lane in lanes {
            let slab = makeWallSlab(kind: kind, profile: profile)
            slab.position = SIMD3(lane.x, 0, 0)
            parent.addChild(slab)
            slabXs.append(lane.x)
        }

        root.addChild(parent)
        walls.append(WallItem(entity: parent, localSlabXs: slabXs, kind: kind))
    }

    private func spawnDuckWall() {
        let parent = Entity()
        // Center the hanging slab in the upper corridor band.
        let centerY = GameWorld.duckClearanceY + GameWorld.duckSlabHeight * 0.5
        parent.position = SIMD3(windCurrentX, centerY, activeSpawnZ)
        parent.name = "wallDuck"

        let mesh = MeshResource.generateBox(
            width: GameWorld.duckSlabWidth,
            height: GameWorld.duckSlabHeight,
            depth: GameWorld.wallThickness * 0.85
        )
        let profile = activeSpawnProfile
        let material = EnvironmentMaterials.wallBody(
            tint: TintColor(r: 0.15, g: 0.55, b: 0.95, a: profile.palette.wallOpacity),
            emissive: TintColor(r: 0.2, g: 0.7, b: 1.0, a: 1),
            opacity: max(0.35, profile.palette.wallOpacity),
            emissiveIntensity: 0.7
        )
        let body = ModelEntity(mesh: mesh, materials: [material])
        body.name = "duckSlab"
        parent.addChild(body)

        root.addChild(parent)
        walls.append(WallItem(entity: parent, localSlabXs: [0], kind: .duck))
    }

    private func makeWallSlab(kind: WallKind, profile: EnvironmentProfile) -> Entity {
        let bodyMesh = MeshResource.generateBox(
            width: GameWorld.wallWidth,
            height: GameWorld.wallHeight,
            depth: GameWorld.wallThickness
        )

        let opacity: Float
        let emissiveIntensity: Float
        switch kind {
        case .ghost:
            opacity = profile.ghostWallOpacity
            emissiveIntensity = max(0.15, profile.palette.wallEmissiveIntensity * 0.35)
        case .standard, .duck:
            opacity = profile.palette.wallOpacity
            emissiveIntensity = profile.palette.wallEmissiveIntensity
        }

        let body = ModelEntity(
            mesh: bodyMesh,
            materials: [
                EnvironmentMaterials.wallBody(
                    tint: profile.palette.wallTint,
                    emissive: profile.palette.wallEmissive,
                    opacity: opacity,
                    emissiveIntensity: emissiveIntensity
                )
            ]
        )
        body.name = "wallSlab"

        if kind == .ghost {
            // Faint edge shimmer so skilled players can still learn to spot ghosts.
            let edgeMesh = MeshResource.generateBox(
                width: GameWorld.wallWidth + 0.04,
                height: GameWorld.wallHeight + 0.04,
                depth: GameWorld.wallThickness + 0.04
            )
            let edgeTint = TintColor(
                r: profile.palette.wallEmissive.r,
                g: profile.palette.wallEmissive.g,
                b: profile.palette.wallEmissive.b,
                a: 0.12
            )
            let edge = ModelEntity(mesh: edgeMesh, materials: [EnvironmentMaterials.unlit(edgeTint)])
            edge.name = "ghostEdge"
            body.addChild(edge)
        }

        return body
    }

    private func spawnCoin(in lane: Lane) {
        let mesh = MeshResource.generateSphere(radius: GameWorld.coinRadius)
        let material = EnvironmentMaterials.coin(activeSpawnProfile.palette.coinTint)
        let coin = ModelEntity(mesh: mesh, materials: [material])
        let outward: Float = lane == .center ? 0 : (lane.x > 0 ? GameWorld.coinOutwardOffset : -GameWorld.coinOutwardOffset)
        coin.position = SIMD3(lane.x + outward + windCurrentX, GameWorld.coinHeight, activeSpawnZ)
        coin.name = "coin"
        root.addChild(coin)
        coins.append(CoinItem(entity: coin))
    }

    private func spawnHalfCrystal(in lane: Lane) {
        var rng = SystemRandomNumberGenerator()
        let roll = CrystalCombine.makeHalf(rng: &rng)
        let radius: Float = roll.charged ? 0.09 : 0.075
        let mesh = MeshResource.generateSphere(radius: radius)
        let material = EnvironmentMaterials.crystalHalf(type: roll.type, charged: roll.charged)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        let outward: Float = lane == .center ? 0 : (lane.x > 0 ? GameWorld.coinOutwardOffset : -GameWorld.coinOutwardOffset)
        entity.position = SIMD3(lane.x + outward + windCurrentX, GameWorld.coinHeight, activeSpawnZ)
        entity.name = roll.charged ? "halfCrystalCharged" : "halfCrystal"
        root.addChild(entity)
        halves.append(HalfCrystalItem(entity: entity, type: roll.type, charged: roll.charged))
    }

    // MARK: - Crystal hold / merge

    private func dropHeldHalves() {
        heldLeft?.entity.removeFromParent()
        heldRight?.entity.removeFromParent()
        heldLeft = nil
        heldRight = nil
    }

    private func updateHeldHalves() {
        if let held = heldLeft {
            if !leftIsFist {
                held.entity.removeFromParent()
                heldLeft = nil
            } else if let palm = leftHandPalmWorld {
                held.entity.position = root.convert(position: palm, from: nil)
            }
        }
        if let held = heldRight {
            if !rightIsFist {
                held.entity.removeFromParent()
                heldRight = nil
            } else if let palm = rightHandPalmWorld {
                held.entity.position = root.convert(position: palm, from: nil)
            }
        }

        guard let left = heldLeft, let right = heldRight else { return }
        guard CrystalCombine.canMerge(left: left.type, right: right.type) else { return }

        let leftPos = left.entity.position
        let rightPos = right.entity.position
        if distance(leftPos, rightPos) <= CrystalCombine.combineDistance {
            let payout = CrystalCombine.mergePayout(
                leftCharged: left.charged,
                rightCharged: right.charged
            )
            left.entity.removeFromParent()
            right.entity.removeFromParent()
            heldLeft = nil
            heldRight = nil
            gameModel?.collectCoin(points: payout)
            GameSFX.shared.playCoinCollect()
        }
    }

    private func tryGrabHalves() {
        guard activeSpawnProfile.twist == .crystalHalves else { return }

        if heldLeft == nil, leftIsFist, let palmWorld = leftHandPalmWorld {
            let palm = root.convert(position: palmWorld, from: nil)
            if let index = nearestHalfIndex(to: palm) {
                grabHalf(at: index, left: true)
            }
        }
        if heldRight == nil, rightIsFist, let palmWorld = rightHandPalmWorld {
            let palm = root.convert(position: palmWorld, from: nil)
            if let index = nearestHalfIndex(to: palm) {
                grabHalf(at: index, left: false)
            }
        }
    }

    private func nearestHalfIndex(to point: SIMD3<Float>) -> Int? {
        var bestIndex: Int?
        var bestDistance = GameWorld.collectDistance
        for (index, half) in halves.enumerated() {
            guard !half.collected else { continue }
            let d = distance(point, half.entity.position(relativeTo: root))
            if d <= bestDistance {
                bestDistance = d
                bestIndex = index
            }
        }
        return bestIndex
    }

    private func grabHalf(at index: Int, left: Bool) {
        guard halves.indices.contains(index), !halves[index].collected else { return }
        halves[index].collected = true
        let source = halves[index]
        source.entity.removeFromParent()

        let mesh = MeshResource.generateSphere(radius: source.charged ? 0.08 : 0.065)
        let heldEntity = ModelEntity(
            mesh: mesh,
            materials: [EnvironmentMaterials.crystalHalf(type: source.type, charged: source.charged)]
        )
        heldEntity.name = "heldHalf"
        root.addChild(heldEntity)
        let held = HeldHalf(type: source.type, charged: source.charged, entity: heldEntity)
        if left {
            heldLeft = held
        } else {
            heldRight = held
        }
    }

    // MARK: - Collisions

    private func resolveCollisions(gameModel: GameModel) {
        let head = headAnchor.position(relativeTo: root)
        let handsWorld = leftHandContactsWorld + rightHandContactsWorld
        let hands = handsWorld.map { root.convert(position: $0, from: nil) }

        let halfDepth = WallCollision.halfDepth(
            visualThickness: GameWorld.wallThickness,
            pad: GameWorld.hitZPad
        )
        let halfWidth = WallCollision.halfWidth(
            visualWidth: GameWorld.wallWidth,
            inset: GameWorld.hitXInset
        )
        let handHalfDepth = halfDepth + GameWorld.handHitRadius
        let handHalfWidth = halfWidth + GameWorld.handHitRadius
        let duckHalfWidth = GameWorld.duckSlabWidth * 0.5 - 0.08

        for wall in walls {
            guard !wall.hasResolvedHit else { continue }
            let wallZ = wall.entity.position.z

            let hit: Bool
            if wall.kind == .duck {
                let centerX = wall.entity.position.x
                let headHit = WallCollision.pointHitsDuckBarrier(
                    point: head,
                    wallZ: wallZ,
                    centerX: centerX,
                    halfWidth: duckHalfWidth,
                    halfDepth: halfDepth,
                    clearanceY: GameWorld.duckClearanceY,
                    maxY: GameWorld.headHitMaxY
                )
                let handHit = hands.contains { hand in
                    WallCollision.pointHitsDuckBarrier(
                        point: hand,
                        wallZ: wallZ,
                        centerX: centerX,
                        halfWidth: duckHalfWidth + GameWorld.handHitRadius,
                        halfDepth: handHalfDepth,
                        clearanceY: GameWorld.duckClearanceY,
                        maxY: GameWorld.handHitMaxY
                    )
                }
                hit = headHit || handHit
            } else {
                let slabXs = wall.worldSlabXs()
                let headHit = WallCollision.pointHitsSlabs(
                    point: head,
                    wallZ: wallZ,
                    slabXs: slabXs,
                    halfWidth: halfWidth,
                    halfDepth: halfDepth,
                    minY: GameWorld.headHitMinY,
                    maxY: GameWorld.headHitMaxY
                )
                let handHit = hands.contains { hand in
                    WallCollision.pointHitsSlabs(
                        point: hand,
                        wallZ: wallZ,
                        slabXs: slabXs,
                        halfWidth: handHalfWidth,
                        halfDepth: handHalfDepth,
                        minY: GameWorld.handHitMinY,
                        maxY: GameWorld.handHitMaxY
                    )
                }
                hit = headHit || handHit
            }

            if hit {
                wall.hasResolvedHit = true
                GameSFX.shared.playWallHit()
                dropHeldHalves()
                gameModel.endRun()
                return
            }

            let farthestContactZ = hands.map(\.z).min().map { min($0, head.z) } ?? head.z
            if WallCollision.hasPassedContact(
                wallZ: wallZ,
                contactZ: farthestContactZ,
                halfDepth: handHalfDepth
            ) {
                wall.hasResolvedHit = true
            }
        }

        if activeSpawnProfile.twist == .crystalHalves {
            tryGrabHalves()
            return
        }

        guard !hands.isEmpty else { return }

        for index in coins.indices {
            guard !coins[index].collected else { continue }
            let coinPos = coins[index].entity.position(relativeTo: root)
            for hand in hands {
                if distance(hand, coinPos) <= GameWorld.collectDistance {
                    coins[index].collected = true
                    coins[index].entity.removeFromParent()
                    gameModel.collectCoin(points: GameWorld.coinPoints)
                    GameSFX.shared.playCoinCollect()
                    break
                }
            }
        }
    }

    private func pruneEntities() {
        walls.removeAll { item in
            if item.entity.position.z > GameWorld.despawnZ {
                item.entity.removeFromParent()
                return true
            }
            return false
        }
        coins.removeAll { item in
            if item.collected { return true }
            if item.entity.position.z > GameWorld.despawnZ {
                item.entity.removeFromParent()
                return true
            }
            return false
        }
        halves.removeAll { item in
            if item.collected { return true }
            if item.entity.position.z > GameWorld.despawnZ {
                item.entity.removeFromParent()
                return true
            }
            return false
        }
    }
}
