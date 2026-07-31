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
//  Visuals: polished procedural meshes + catalog textures (see ASSET_SPEC.md).
//

import ARKit
import QuartzCore
import RealityKit
import SwiftUI
import UIKit

/// Frame timing helpers for the runner tick.
enum GameTiming {
    /// Cap hitch frames so obstacles keep advancing instead of freezing.
    static let maxGameplayDeltaTime: Float = 1.0 / 15.0

    /// Returns nil when the frame should be ignored; otherwise a hitch-clamped delta.
    static func clampedGameplayDelta(_ deltaTime: Float) -> Float? {
        guard deltaTime > 0, deltaTime.isFinite else { return nil }
        return min(deltaTime, maxGameplayDeltaTime)
    }
}

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
        /// Adjacent double-lane walls seal the visual gap between slabs (collision only).
        let sealsBetweenSlabs: Bool
        var hasResolvedHit = false
        /// Prior-frame Z for swept head/hand collision (prevents tunneling).
        var previousZ: Float

        init(
            entity: Entity,
            localSlabXs: [Float],
            kind: WallKind,
            sealsBetweenSlabs: Bool = false
        ) {
            self.entity = entity
            self.localSlabXs = localSlabXs
            self.kind = kind
            self.sealsBetweenSlabs = sealsBetweenSlabs
            self.previousZ = entity.position.z
        }

        func worldSlabXs() -> [Float] {
            localSlabXs.map { $0 + entity.position.x }
        }
    }

    private struct CoinItem {
        let entity: Entity
        let baseY: Float
        var phase: Float
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
        /// True once a non-open (fist / closed) grip is seen; opening the hand drops it.
        var confirmedGrip: Bool = false
        /// Seconds since grab — still-open hands drop after `crystalGrabConfirmWindow`.
        var timeSinceGrab: Float = 0
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
    /// Obstacles stay visible this far past the stand line (+Z) before cleanup.
    private static let despawnZ: Float = 3.0
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
    /// Crystal halves use a generous grab radius so fist + reach stays fair.
    private static let crystalCollectDistance: Float = 0.45
    private static let baseSpeed: Float = 3.0
    private static let maxSpeed: Float = 7.0
    private static let speedRampPerSecond: Float = 0.055
    /// Continuous obstacle stream with a bit of breathing room between beats.
    private static let spawnGapMin: Float = 2.2
    private static let spawnGapMax: Float = 2.9
    /// Ember Run gets a touch more room than the denser biomes.
    private static let emberSpawnGapMin: Float = 2.55
    private static let emberSpawnGapMax: Float = 3.25
    /// Low Crawl needs extra reaction time for duck gates.
    private static let lowCrawlSpawnGapMin: Float = 3.3
    private static let lowCrawlSpawnGapMax: Float = 4.2
    /// Nudge adjacent double-lane slabs slightly farther apart (meters each side).
    private static let adjacentPairSpread: Float = 0.09
    /// Extra Z gap when consecutive adjacent doubles open on opposite outer lanes (left↔right).
    private static let oppositeOpenLaneSpacingBonus: Float = 0.35
    /// HUD sits above the corridor, further down the track, clear of the play volume.
    private static let hudPosition = SIMD3<Float>(0, 2.45, -3.2)
    /// World scale for the SwiftUI attachment (attachments are small by default).
    private static let hudScale: Float = 3.0

    // Duck hazard geometry (Low Crawl).
    /// Bottom of the hanging slab — stand through it = hit; duck under to clear.
    private static let duckClearanceY: Float = 1.0
    private static let duckSlabHeight: Float = 0.75
    private static let duckSlabWidth: Float = 2.5
    /// Duck gates use a deeper kill volume so fast approach cannot skip the head.
    private static let duckHitHalfDepth: Float = 0.4
    /// Coins paired with a duck ceiling sit under it; other Low Crawl coins stay normal height.
    private static let lowCrawlCoinHeight: Float = duckClearanceY * 0.65

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
    /// Track slab extends this far behind the stand line (+Z).
    private static let trackNearZ: Float = 1.1
    private static let trackPastPortal: Float = 0.35
    /// Used only when a floor plane has not been found yet.
    private static let fallbackEyeHeight: Float = 1.55

    // Storm Pass wind.
    private static let windMinInterval: Float = 2.4
    private static let windMaxInterval: Float = 4.8
    /// Visual/audio warning before boxes start drifting (expand then shrink).
    private static let windTelegraphSeconds: Float = 1.8
    /// How long the boxes take to finish the shove (slow = easy to correct).
    private static let windDuration: Float = 4.5
    private static let windMagnitude: Float = 0.55
    /// Only skip a shove when a wall is already in this near danger band.
    private static let windDangerMinZ: Float = -1.1
    private static let windDangerMaxZ: Float = 0.7
    /// Storm warning streak size / placement (unit-width mesh, scaled on X).
    private static let gustBarWidth: Float = 2.8
    private static let gustBarHeight: Float = 0.08
    private static let gustBarDepth: Float = 0.35
    private static let gustBarY: Float = 1.25
    private static let gustBarZ: Float = -1.4
    /// Fraction of the telegraph used to finish the expand; remainder shrinks back.
    private static let gustExpandFinishAt: Float = 0.42
    /// Coin bob amplitude / spin rates.
    private static let coinBobAmplitude: Float = 0.045
    private static let coinBobSpeed: Float = 2.6
    private static let coinSpinSpeed: Float = 1.8

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
    /// Holds the portal plane + neon rim in playfield space (always visible).
    private let portalRoot = Entity()
    private let portalEntity = Entity()
    private let portalWorld = Entity()
    private let visualFX = VisualFXController()

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
    /// Open outer lane raw of the last adjacent double wall (−1 / +1), if any.
    private var lastAdjacentDoubleOpenLaneRaw: Int?
    /// Extra depth for this beat when a left↔right open-lane flip needs more room.
    private var patternSpawnZOffset: Float = 0
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
    /// Seconds since attach — drives portal pulse / ambient motion.
    private var elapsedTime: Float = 0

    // Wind shove state (offsets obstacle boxes only).
    private var windCurrentX: Float = 0
    private var windFromX: Float = 0
    private var windToX: Float = 0
    private var windElapsed: Float = 0
    private var windDurationActive: Float = 0
    private var windTelegraphRemaining: Float = 0
    private var pendingWindDirection: Float = 0
    /// Discrete lane offset from start: -1, 0, or +1. Never stacks same-side shoves.
    private var windOffsetStep: Int = 0
    private var timeUntilWind: Float = GameWorld.windMinInterval
    private var gustEntity: Entity?

    /// ARKit providers — AnchorEntity(.head/.hand) transforms are privacy-locked
    /// on visionOS, so gameplay reads DeviceAnchor + HandTrackingProvider instead.
    private let arSession = ARKitSession()
    private let handTracking = HandTrackingProvider()
    private let worldTracking = WorldTrackingProvider()
    private var arTask: Task<Void, Never>?
    /// World-space contact points (wrist + fingertips) for each hand.
    private var leftHandContactsWorld: [SIMD3<Float>] = []
    private var rightHandContactsWorld: [SIMD3<Float>] = []
    /// World-space grip point (fingertip / palm center), not the wrist.
    private var leftHandGripWorld: SIMD3<Float>?
    private var rightHandGripWorld: SIMD3<Float>?
    private var leftIsOpen = false
    private var rightIsOpen = false
    /// After proximity grab, a still-open / flat hand drops quickly.
    /// A non-open hand (fist or closed) confirms immediately — no open→fist required.
    private static let crystalGrabConfirmWindow: Float = 0.12
    /// Crystal Cave half spawn chance per beat (was 0.2; +50%).
    private static let crystalHalfSpawnChance: Float = 0.3
    /// Held shards sit this far past the knuckle plane toward the fingertips (meters).
    private static let crystalGripFingerBias: Float = 0.04
    /// Lift shards slightly off the knuckle plane so they sit in/on the fingers.
    private static let crystalGripPalmLift: Float = 0.035

    func attach(to content: RealityViewContent, gameModel: GameModel) {
        self.gameModel = gameModel
        content.add(root)
        content.add(headAnchor)
        content.add(floorAnchor)
        content.add(wallAnchor)
        isPlayfieldLocked = false
        lastDebugMode = gameModel.environmentDebugMode
        elapsedTime = 0
        GameMaterials.warmTextures()
        visualFX.attach(to: root)
        // Pre-build collect-burst meshes so the first coin does not hitch the tick.
        visualFX.prepare()

        if updateSubscription == nil {
            updateSubscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
                self?.tick(deltaTime: Float(event.deltaTime))
            }
        }

        buildPortal()
        buildStaticEnvironment()
        ensureHUDAnchor()
        startARSession()
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
        arTask?.cancel()
        arTask = nil
        leftHandContactsWorld = []
        rightHandContactsWorld = []
        leftHandGripWorld = nil
        rightHandGripWorld = nil
        leftIsOpen = false
        rightIsOpen = false
        updateSubscription = nil
        isPlayfieldLocked = false
        elapsedTime = 0
        portalZ = GameWorld.defaultPortalZ
        activeSpawnZ = GameWorld.defaultPortalZ + GameWorld.spawnInFrontOfPortal
        lastBuiltPortalZ = .greatestFiniteMagnitude
        visualFX.clear()
        clearDynamicContent()
        dropHeldHalves()
        gameModel?.prefersRoomDimming = false
        GameMusic.shared.stop()
        for child in hudAnchor.children {
            child.removeFromParent()
        }
        for child in trackRoot.children {
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
        if trackRoot.parent !== root {
            root.addChild(trackRoot)
        }
        rebuildFixedTrack(force: true)
        buildStartMarker()
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

        let track = GameVisualBuilders.makeTrack(
            width: GameWorld.trackWidth,
            depth: depth,
            laneXs: Lane.allCases.map(\.x)
        )
        track.position = SIMD3(0, 0, centerZ)
        trackRoot.addChild(track)
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

        let rim = GameVisualBuilders.makePortalRim(
            width: GameWorld.portalWidth,
            height: GameWorld.portalHeight,
            cornerRadius: GameWorld.portalCornerRadius,
            thickness: GameWorld.portalRimThickness
        )
        portalRoot.addChild(rim)
    }

    /// Dark tunnel visible only through the portal — blocks passthrough cleanly.
    private func buildPortalInterior() {
        for child in portalWorld.children {
            child.removeFromParent()
        }
        portalWorld.addChild(GameVisualBuilders.makePortalInterior(portalHeight: GameWorld.portalHeight))
    }

    private func layoutPortal() {
        portalRoot.position = SIMD3(0, GameWorld.portalHeight * 0.5, portalZ)
        activeSpawnZ = portalZ + GameWorld.spawnInFrontOfPortal
    }

    /// Polished stand zone at the player's start — pad, line, forward chevrons.
    private func buildStartMarker() {
        if root.children.contains(where: { $0.name == "startMarker" }) { return }
        root.addChild(GameVisualBuilders.makeStartMarker())
    }

    private func beginRun(runID: Int) {
        activeRunID = runID
        snapPlayfieldToPlayer()
        updatePortalAndTrack()
        isPlayfieldLocked = true
        visualFX.clear()
        clearDynamicContent()
        dropHeldHalves()
        resetWind()
        environmentDirector.beginRun(debugMode: gameModel?.environmentDebugMode ?? .normal)
        activeSpawnProfile = environmentDirector.currentProfile
        if activeSpawnProfile.twist == .windShove {
            timeUntilWind = Float.random(in: 1.0...2.0)
        }
        rebuildFixedTrack(force: true)
        buildPortalRim()
        buildPortalInterior()
        applyPalette(environmentDirector.displayedPalette, telegraph: 0)
        layoutPortal()
        speed = GameWorld.baseSpeed
        distanceUntilSpawn = 0
        distanceAccumulator = 0
        lastAdjacentDoubleOpenLaneRaw = nil
        patternSpawnZOffset = 0
        visualFX.prepare()
        GameSFX.shared.prepare()
        GameMusic.shared.prepare()
    }

    // MARK: - Palette / room dimming

    private func applyPalette(_ palette: EnvironmentPalette, telegraph: Float) {
        // Polished track nests floor/stripes under trackAssembly.
        let trackNodes = trackRoot.children.flatMap { child -> [Entity] in
            if child.name == "trackAssembly" { return Array(child.children) }
            return [child]
        }
        for child in trackNodes {
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
                case "portalAccent", "farCore":
                    model.model?.materials = [EnvironmentMaterials.unlit(palette.portalAccent)]
                case "portalFloor", "portalCeiling", "portalSide", "portalBack":
                    model.model?.materials = [EnvironmentMaterials.unlit(palette.portalVoid)]
                default:
                    // Keep polished rings / chevrons / bloom on their neon materials.
                    continue
                }
            }
        }

        syncRoomDimming()
    }

    /// Fog Hollow dims the real room via preferredSurroundingsEffect (no fog geometry).
    private func syncRoomDimming() {
        guard let gameModel else { return }
        let wants = gameModel.isPlaying
            && !gameModel.isGameOver
            && activeSpawnProfile.twist == .fogVisibility
        if gameModel.prefersRoomDimming != wants {
            gameModel.prefersRoomDimming = wants
        }
    }

    // MARK: - Playfield pose

    private func snapPlayfieldToPlayer() {
        let headWorld: SIMD3<Float>
        let flatForward: SIMD3<Float>

        if worldTracking.state == .running,
           let device = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()),
           device.isTracked {
            let matrix = device.originFromAnchorTransform
            headWorld = SIMD3(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z)
            // Device forward is -Z in the device transform.
            let forwardWorld = SIMD3(-matrix.columns.2.x, 0, -matrix.columns.2.z)
            let forwardLength = length(forwardWorld)
            if forwardLength < 0.05 {
                flatForward = SIMD3(0, 0, -1)
            } else {
                flatForward = forwardWorld / forwardLength
            }
        } else {
            headWorld = headAnchor.position(relativeTo: nil)
            let headRotation = headAnchor.orientation(relativeTo: nil)
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

        let floorY: Float
        if floorAnchor.isAnchored {
            floorY = floorAnchor.position(relativeTo: nil).y
        } else {
            floorY = headWorld.y - GameWorld.fallbackEyeHeight
        }

        let position = SIMD3<Float>(headWorld.x, floorY, headWorld.z)
        let facing = suitableWallForward(from: position) ?? flatForward
        let yaw = atan2(-facing.x, -facing.z)
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
        lastAdjacentDoubleOpenLaneRaw = nil
        patternSpawnZOffset = 0
        gustEntity?.removeFromParent()
        gustEntity = nil
    }

    // MARK: - ARKit tracking

    private func startARSession() {
        guard arTask == nil else { return }
        arTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                var providers: [any DataProvider] = []
                var handsEnabled = false
                if WorldTrackingProvider.isSupported {
                    providers.append(worldTracking)
                }
                if HandTrackingProvider.isSupported {
                    let auth = await arSession.requestAuthorization(for: [.handTracking])
                    if auth[.handTracking] == .allowed {
                        providers.append(handTracking)
                        handsEnabled = true
                    }
                }
                guard !providers.isEmpty else { return }
                try await arSession.run(providers)

                guard handsEnabled else { return }

                for await update in handTracking.anchorUpdates {
                    guard !Task.isCancelled else { break }
                    let anchor = update.anchor
                    guard anchor.isTracked else {
                        switch anchor.chirality {
                        case .left:
                            leftHandContactsWorld = []
                            leftHandGripWorld = nil
                            leftIsOpen = false
                        case .right:
                            rightHandContactsWorld = []
                            rightHandGripWorld = nil
                            rightIsOpen = false
                        @unknown default: break
                        }
                        continue
                    }
                    let contacts = Self.contactPoints(from: anchor)
                    let grip = Self.gripPoint(from: anchor)
                    let isOpen = HandPose.isOpenPose(anchor: anchor)
                    switch anchor.chirality {
                    case .left:
                        leftHandContactsWorld = contacts
                        leftHandGripWorld = grip
                        leftIsOpen = isOpen
                    case .right:
                        rightHandContactsWorld = contacts
                        rightHandGripWorld = grip
                        rightIsOpen = isOpen
                    @unknown default:
                        break
                    }
                }
            } catch {
                print("ARKit session failed: \(error)")
            }
        }
    }

    /// Head/device position in playfield space. Prefer ARKit DeviceAnchor because
    /// AnchorEntity(.head) transforms are not readable for gameplay queries.
    private func playfieldHeadPosition() -> SIMD3<Float> {
        if worldTracking.state == .running,
           let device = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()),
           device.isTracked {
            let matrix = device.originFromAnchorTransform
            let world = SIMD3<Float>(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z)
            return root.convert(position: world, from: nil)
        }

        // Fallback if world tracking is unavailable.
        var head = headAnchor.position(relativeTo: root)
        if head.y < 0.9 {
            head.y = GameWorld.fallbackEyeHeight
        }
        return head
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

    /// Grip point on the fingers — knuckles + a bit toward the tips.
    /// Fingertip averages sit under a closed fist, which made shards hang below the hand.
    private static func gripPoint(from anchor: HandAnchor) -> SIMD3<Float> {
        let origin = anchor.originFromAnchorTransform
        let wrist = SIMD3<Float>(origin.columns.3.x, origin.columns.3.y, origin.columns.3.z)
        guard let skeleton = anchor.handSkeleton else {
            // No skeleton: nudge from wrist along the hand anchor's local finger axis.
            let alongFingers = SIMD3<Float>(-origin.columns.2.x, -origin.columns.2.y, -origin.columns.2.z)
            let palmUp = SIMD3<Float>(origin.columns.1.x, origin.columns.1.y, origin.columns.1.z)
            return wrist
                + alongFingers * (0.08 + GameWorld.crystalGripFingerBias)
                + palmUp * GameWorld.crystalGripPalmLift
        }

        let knuckleNames: [HandSkeleton.JointName] = [
            .indexFingerKnuckle, .middleFingerKnuckle, .ringFingerKnuckle
        ]
        var knuckleSum = SIMD3<Float>.zero
        var knuckleCount = 0
        for name in knuckleNames {
            let joint = skeleton.joint(name)
            guard joint.isTracked else { continue }
            let world = origin * joint.anchorFromJointTransform
            knuckleSum += SIMD3(world.columns.3.x, world.columns.3.y, world.columns.3.z)
            knuckleCount += 1
        }

        let intermediateNames: [HandSkeleton.JointName] = [
            .indexFingerIntermediateBase, .middleFingerIntermediateBase, .ringFingerIntermediateBase
        ]
        var midSum = SIMD3<Float>.zero
        var midCount = 0
        for name in intermediateNames {
            let joint = skeleton.joint(name)
            guard joint.isTracked else { continue }
            let world = origin * joint.anchorFromJointTransform
            midSum += SIMD3(world.columns.3.x, world.columns.3.y, world.columns.3.z)
            midCount += 1
        }

        if knuckleCount > 0 {
            let knuckles = knuckleSum / Float(knuckleCount)
            // Prefer mid-finger joints when available; otherwise push past knuckles toward tips.
            let alongFingers: SIMD3<Float>
            if midCount > 0 {
                let mids = midSum / Float(midCount)
                alongFingers = mids - knuckles
            } else {
                alongFingers = knuckles - wrist
            }
            let fingerDir = length(alongFingers) > 0.001
                ? normalize(alongFingers)
                : SIMD3<Float>(0, 0, 0)

            // Palm "up" ≈ wrist→knuckles cross a side finger, falling back to world up.
            var palmUp = SIMD3<Float>(0, 1, 0)
            if knuckleCount >= 2 {
                let index = skeleton.joint(.indexFingerKnuckle)
                let ring = skeleton.joint(.ringFingerKnuckle)
                if index.isTracked, ring.isTracked {
                    let iWorld = origin * index.anchorFromJointTransform
                    let rWorld = origin * ring.anchorFromJointTransform
                    let indexPos = SIMD3<Float>(iWorld.columns.3.x, iWorld.columns.3.y, iWorld.columns.3.z)
                    let ringPos = SIMD3<Float>(rWorld.columns.3.x, rWorld.columns.3.y, rWorld.columns.3.z)
                    let side = ringPos - indexPos
                    let candidate = cross(fingerDir, side)
                    if length(candidate) > 0.001 {
                        palmUp = normalize(candidate)
                        // Keep lift toward the back of the hand (away from the palm underside).
                        if palmUp.y < 0 { palmUp = -palmUp }
                    }
                }
            }

            let base = midCount > 0 ? (midSum / Float(midCount)) : knuckles
            return base
                + fingerDir * GameWorld.crystalGripFingerBias
                + palmUp * GameWorld.crystalGripPalmLift
        }

        // Fallback: fingertip blend, still lifted so it doesn't hang under the fist.
        let tipNames: [HandSkeleton.JointName] = [
            .indexFingerTip, .middleFingerTip, .ringFingerTip
        ]
        var tipSum = SIMD3<Float>.zero
        var tipCount = 0
        for name in tipNames {
            let joint = skeleton.joint(name)
            guard joint.isTracked else { continue }
            let world = origin * joint.anchorFromJointTransform
            tipSum += SIMD3(world.columns.3.x, world.columns.3.y, world.columns.3.z)
            tipCount += 1
        }
        if tipCount > 0 {
            let tips = tipSum / Float(tipCount)
            return mix(wrist, tips, t: 0.9) + SIMD3<Float>(0, GameWorld.crystalGripPalmLift, 0)
        }

        return wrist + SIMD3<Float>(0, 0.08, 0)
    }

    // MARK: - Loop

    private func tick(deltaTime: Float) {
        elapsedTime += deltaTime
        animatePortal(deltaTime: deltaTime)
        animateCoins(deltaTime: deltaTime)
        visualFX.tick(deltaTime: deltaTime)

        // Before Start, keep the stand line under the player and refresh portal depth.
        // After Start, pose / portal / track are frozen — only obstacles move.
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
            syncRoomDimming()
        }

        guard gameModel.isPlaying, !gameModel.isGameOver else {
            if gameModel.prefersRoomDimming {
                gameModel.prefersRoomDimming = false
            }
            return
        }
        // Clamp hitch frames instead of skipping them — a discarded tick freezes walls.
        guard let dt = GameTiming.clampedGameplayDelta(deltaTime) else { return }

        let frame = environmentDirector.update(deltaTime: dt)
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

        let travel = speed * dt
        speed = min(GameWorld.maxSpeed, speed + GameWorld.speedRampPerSecond * dt)

        distanceAccumulator += travel
        if distanceAccumulator >= 1 {
            let gained = Int(distanceAccumulator)
            distanceAccumulator -= Float(gained)
            gameModel.addScore(gained)
        }

        advanceEntities(by: travel)
        updateWind(deltaTime: dt)
        // Grab before hold-update so a newly closed hand can pick up this frame.
        if activeSpawnProfile.twist == .crystalHalves {
            tryGrabHalves()
        }
        updateHeldHalves(deltaTime: dt)

        distanceUntilSpawn -= travel
        if distanceUntilSpawn <= 0 {
            patternSpawnZOffset = 0
            spawnNextPattern()
            // Preserve spacing to the following beat when this one was pushed deeper.
            distanceUntilSpawn = Self.spawnGap(for: activeSpawnProfile) + patternSpawnZOffset
        }

        resolveCollisions(gameModel: gameModel)
        pruneEntities()
    }

    private static func spawnGap(for profile: EnvironmentProfile) -> Float {
        switch profile.twist {
        case .lowCrawl:
            return Float.random(in: lowCrawlSpawnGapMin...lowCrawlSpawnGapMax)
        case .baseline:
            return Float.random(in: emberSpawnGapMin...emberSpawnGapMax)
        default:
            return Float.random(in: spawnGapMin...spawnGapMax)
        }
    }

    private func animatePortal(deltaTime: Float) {
        _ = deltaTime
        guard let rim = portalRoot.children.first(where: { $0.name == "portalRim" }) else { return }
        let pulse = 1.0 + 0.035 * sin(elapsedTime * 2.2)
        rim.scale = SIMD3(pulse, pulse, 1)

        if let bloom = rim.children.first(where: { $0.name == "portalBloom" }) {
            let bloomPulse = 1.0 + 0.06 * sin(elapsedTime * 1.6 + 0.4)
            bloom.scale = SIMD3(bloomPulse, bloomPulse, 1)
        }

        // Subtle far-glow breathe inside the tunnel.
        if let interior = portalWorld.children.first(where: { $0.name == "portalInterior" }),
           let farCore = interior.children.first(where: { $0.name == "farCore" }) {
            let glow = 1.0 + 0.12 * sin(elapsedTime * 1.8)
            farCore.scale = SIMD3(repeating: glow)
        }
    }

    private func animateCoins(deltaTime: Float) {
        for index in coins.indices {
            guard !coins[index].collected else { continue }
            coins[index].phase += deltaTime
            let phase = coins[index].phase
            let bob = sin(phase * GameWorld.coinBobSpeed) * GameWorld.coinBobAmplitude
            coins[index].entity.position.y = coins[index].baseY + bob
            coins[index].entity.orientation = simd_quatf(
                angle: phase * GameWorld.coinSpinSpeed,
                axis: SIMD3(0, 1, 0)
            )

            if let spark = coins[index].entity.children.first(where: { $0.name == "coinSpark" }) {
                let orbit = phase * 3.2
                let r = GameWorld.coinRadius * 0.9
                spark.position = SIMD3(cos(orbit) * r, sin(orbit * 0.7) * r * 0.35, sin(orbit) * r * 0.2)
            }
            if let aura = coins[index].entity.children.first(where: { $0.name == "coinAura" }) {
                let s = 1.0 + 0.08 * sin(phase * 3.5)
                aura.scale = SIMD3(repeating: s)
            }
        }
    }

    private func advanceEntities(by travel: Float) {
        for wall in walls {
            wall.previousZ = wall.entity.position.z
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
        windTelegraphRemaining = 0
        pendingWindDirection = 0
        windOffsetStep = 0
        timeUntilWind = Float.random(in: GameWorld.windMinInterval...GameWorld.windMaxInterval)
        gustEntity?.removeFromParent()
        gustEntity = nil
    }

    private func updateWind(deltaTime: Float) {
        guard activeSpawnProfile.twist == .windShove else { return }

        // Warning phase: expand then shrink the other way; shove starts the instant the line is gone.
        if windTelegraphRemaining > 0 {
            windTelegraphRemaining = max(0, windTelegraphRemaining - deltaTime)
            let warnProgress = 1 - (windTelegraphRemaining / GameWorld.windTelegraphSeconds)
            updateGustVisual(progress: warnProgress)
            if StormWind.gustLineDidDisappear(
                progress: warnProgress,
                expandFinishAt: GameWorld.gustExpandFinishAt
            ) || windTelegraphRemaining <= 0 {
                windTelegraphRemaining = 0
                startWindDrift()
            }
            return
        }

        if windDurationActive > 0 {
            windElapsed += deltaTime
            let t = min(1, windElapsed / windDurationActive)
            // Smoothstep for non-sudden box motion.
            let smooth = t * t * (3 - 2 * t)
            let newX = windFromX + (windToX - windFromX) * smooth
            let deltaX = newX - windCurrentX
            windCurrentX = newX
            shiftDynamicBoxes(by: deltaX)
            if t >= 1 {
                windDurationActive = 0
                windOffsetStep = StormWind.applyStep(
                    offsetStep: windOffsetStep,
                    direction: pendingWindDirection
                )
                pendingWindDirection = 0
                timeUntilWind = Float.random(in: GameWorld.windMinInterval...GameWorld.windMaxInterval)
            }
            return
        }

        timeUntilWind -= deltaTime
        if timeUntilWind <= 0 {
            beginWindTelegraph()
        }
    }

    private func beginWindTelegraph() {
        // Only defer when a wall is already in the near hit band (not merely "on screen").
        let imminent = walls.contains {
            $0.entity.position.z > GameWorld.windDangerMinZ
                && $0.entity.position.z < GameWorld.windDangerMaxZ
        }
        if imminent {
            timeUntilWind = 0.35
            return
        }

        pendingWindDirection = nextWindDirection()
        windTelegraphRemaining = GameWorld.windTelegraphSeconds
        spawnGustVisual(direction: pendingWindDirection)
        GameSFX.shared.playWindWhoosh()
    }

    private func startWindDrift() {
        // Warning line is gone — begin the slow shove with no leftover bar.
        gustEntity?.removeFromParent()
        gustEntity = nil
        windFromX = windCurrentX
        windToX = windCurrentX + pendingWindDirection * GameWorld.windMagnitude
        windElapsed = 0
        windDurationActive = GameWorld.windDuration
    }

    /// From center: left or right. From ±1: must return toward center (no left→left).
    private func nextWindDirection() -> Float {
        let preferred: Float?
        if windOffsetStep == 0 {
            preferred = windDirectionPreferringSafeGap()
        } else {
            preferred = nil
        }
        return StormWind.nextDirection(offsetStep: windOffsetStep, preferredFromGap: preferred)
    }

    private func windDirectionPreferringSafeGap() -> Float {
        // Look at the nearest upcoming wall and shove away from its blocked center when possible.
        let ahead = walls
            .filter { $0.entity.position.z < -1.2 && $0.kind != .duck }
            .sorted { $0.entity.position.z > $1.entity.position.z }
        if let nearest = ahead.first {
            let xs = nearest.worldSlabXs()
            let blockedCenter = xs.reduce(0, +) / Float(xs.count)
            if abs(blockedCenter) > 0.05 {
                return blockedCenter > 0 ? -1 : 1
            }
        }
        return Bool.random() ? 1 : -1
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
        gust.position = SIMD3(0, GameWorld.gustBarY, GameWorld.gustBarZ)

        // Unit-width bar; X scale + offset grow/shrink along the shove axis.
        let mesh = MeshResource.generateBox(
            width: 1,
            height: GameWorld.gustBarHeight,
            depth: GameWorld.gustBarDepth
        )
        let mat = UnlitMaterial(color: UIColor(red: 0.55, green: 0.75, blue: 1.0, alpha: 0.2))
        let model = ModelEntity(mesh: mesh, materials: [mat])
        model.name = "windGustBar"
        gust.addChild(model)
        root.addChild(gust)
        gustEntity = gust
        layoutGustBar(progress: 0, direction: direction)
    }

    private func updateGustVisual(progress: Float) {
        layoutGustBar(progress: progress, direction: pendingWindDirection)
    }

    /// Expands toward the shove, then shrinks the other way (wipes onward in shove direction).
    private func layoutGustBar(progress: Float, direction: Float) {
        guard let model = gustEntity?.children.first as? ModelEntity else { return }

        let layout = StormWind.gustBarLayout(
            progress: progress,
            expandFinishAt: GameWorld.gustExpandFinishAt,
            direction: direction,
            fullWidth: GameWorld.gustBarWidth
        )

        // Hide completely once collapsed so disappearance and shove share the same frame.
        let visible = layout.width > 0.001
        model.isEnabled = visible
        if visible {
            model.scale = SIMD3(layout.width, 1, 1)
            model.position = SIMD3(layout.centerX, 0, 0)
        }

        let settle = CGFloat(min(1, layout.width / max(0.001, GameWorld.gustBarWidth)))
        let pulse = 0.5 + 0.5 * sin(Double(progress) * .pi * 4)
        let alpha = visible ? ((0.2 + 0.4 * settle) + 0.2 * pulse * settle) : 0
        model.model?.materials = [
            UnlitMaterial(color: UIColor(red: 0.55, green: 0.8, blue: 1.0, alpha: alpha))
        ]
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
        case .windShove:
            spawnStormPattern(profile: profile)
        case .fogVisibility, .baseline:
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

    /// Storm Pass: never spawn a wall in the lane the wind is shoving toward.
    private func spawnStormPattern(profile: EnvironmentProfile) {
        let rawPatterns = Self.stormWallLaneRawPatterns()
        let chosen = StormWind.chooseWallLanes(
            from: rawPatterns,
            offsetStep: windOffsetStep,
            pendingDirection: pendingWindDirection
        )
        let blocking = Set(chosen.compactMap { Lane(rawValue: $0) })
        spawnWall(blocking: blocking, kind: .standard, profile: profile)

        let safeLanes = Lane.allCases.filter { !blocking.contains($0) }
        if let coinLane = safeLanes.randomElement(), Float.random(in: 0...1) < 0.7 {
            spawnCoin(in: coinLane)
        }
    }

    private func spawnGhostGlassPattern(profile: EnvironmentProfile) {
        let blocking = Self.randomWallLanes()
        // Every Ghost Glass wall is the white transparent ghost variant.
        spawnWall(blocking: blocking, kind: .ghost, profile: profile)

        let safeLanes = Lane.allCases.filter { !blocking.contains($0) }
        if let coinLane = safeLanes.randomElement(), Float.random(in: 0...1) < 0.7 {
            spawnCoin(in: coinLane)
        }
    }

    private func spawnLowCrawlPattern(profile: EnvironmentProfile) {
        if environmentDirector.isTeachingLowCrawl {
            spawnDuckWall()
            environmentDirector.noteDuckGateSpawned()
            // Coin under the hanging ceiling — lowered so ducking still rewards grabs.
            if Float.random(in: 0...1) < 0.7, let lane = Lane.allCases.randomElement() {
                spawnCoin(in: lane, underCeiling: true)
            }
            return
        }

        if Float.random(in: 0...1) < profile.duckHazardChance {
            // Occasional duck + simple single side wall, otherwise duck alone.
            var blocked: Set<Lane> = []
            if Float.random(in: 0...1) < 0.35 {
                let side: Set<Lane> = Bool.random() ? [.left] : [.right]
                blocked = side
                spawnWall(blocking: side, kind: .standard, profile: profile)
            }
            spawnDuckWall()
            let coinLanes = Lane.allCases.filter { !blocked.contains($0) }
            if Float.random(in: 0...1) < 0.7, let lane = coinLanes.randomElement() {
                spawnCoin(in: lane, underCeiling: true)
            }
        } else {
            // No ceiling on this beat — normal standing coin height.
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
        if let lane = safeLanes.randomElement(),
           Float.random(in: 0...1) < GameWorld.crystalHalfSpawnChance {
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

    /// Lane raw patterns for Storm (-1 left, 0 center, +1 right).
    private static func stormWallLaneRawPatterns() -> [[Int]] {
        [
            [-1], [0], [1],
            [-1], [0], [1],
            [-1], [1],
            [-1, 0], [0, 1], [-1, 1],
            [-1, 1], [-1, 0], [0, 1]
        ]
    }

    private func spawnWall(blocking lanes: Set<Lane>, kind: WallKind, profile: EnvironmentProfile) {
        let openLaneRaw = ObstacleLayout.adjacentDoubleOpenLaneRaw(
            blockingLaneRaws: Set(lanes.map(\.rawValue))
        )
        if ObstacleLayout.requiresOppositeOpenLaneSpacing(
            previousOpenLaneRaw: lastAdjacentDoubleOpenLaneRaw,
            nextOpenLaneRaw: openLaneRaw
        ) {
            patternSpawnZOffset = Self.oppositeOpenLaneSpacingBonus
        }
        lastAdjacentDoubleOpenLaneRaw = openLaneRaw

        let parent = Entity()
        parent.position = SIMD3(windCurrentX, GameWorld.wallHeight * 0.5, patternSpawnZ)
        parent.name = kind == .ghost ? "wallGhost" : "wall"

        var slabXs: [Float] = []
        for lane in lanes {
            let x = Self.slabX(for: lane, blocking: lanes)
            let slab = makeWallSlab(kind: kind, profile: profile)
            slab.position = SIMD3(x, 0, 0)
            parent.addChild(slab)
            slabXs.append(x)
        }

        // Adjacent doubles are spread for readability, which leaves a squeezable gap
        // between kill boxes. Seal that span in collision only — no extra mesh.
        let sealsGap = ObstacleLayout.isAdjacentDouble(
            blockingLaneRaws: Set(lanes.map(\.rawValue))
        )

        root.addChild(parent)
        walls.append(
            WallItem(
                entity: parent,
                localSlabXs: slabXs,
                kind: kind,
                sealsBetweenSlabs: sealsGap
            )
        )
    }

    /// Spawn depth for the current beat (deeper when an opposite-open double needs room).
    private var patternSpawnZ: Float {
        activeSpawnZ - patternSpawnZOffset
    }

    /// Adjacent double-lane blocks get a slight extra gap so they don't read as one slab.
    private static func slabX(for lane: Lane, blocking: Set<Lane>) -> Float {
        ObstacleLayout.slabLocalX(
            laneRaw: lane.rawValue,
            blockingLaneRaws: Set(blocking.map(\.rawValue)),
            laneSpacing: laneSpacing,
            adjacentSpread: adjacentPairSpread
        )
    }

    private func spawnDuckWall() {
        // Duck gates break adjacent-double open-lane chaining.
        lastAdjacentDoubleOpenLaneRaw = nil
        let parent = Entity()
        // Center the hanging slab in the upper corridor band.
        let centerY = GameWorld.duckClearanceY + GameWorld.duckSlabHeight * 0.5
        parent.position = SIMD3(windCurrentX, centerY, patternSpawnZ)
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

        let material: PhysicallyBasedMaterial
        switch kind {
        case .ghost:
            // No Unlit rim — UnlitMaterial ignores alpha and was painting a solid white shell.
            material = EnvironmentMaterials.ghostWallBody(opacity: profile.ghostWallOpacity)
        case .standard, .duck:
            material = EnvironmentMaterials.wallBody(
                tint: profile.palette.wallTint,
                emissive: profile.palette.wallEmissive,
                opacity: profile.palette.wallOpacity,
                emissiveIntensity: profile.palette.wallEmissiveIntensity
            )
        }

        let body = ModelEntity(mesh: bodyMesh, materials: [material])
        body.name = "wallSlab"
        return body
    }

    private func spawnCoin(in lane: Lane, underCeiling: Bool = false) {
        // Spawn-time biome tint only (no live retint on switch) — Ember keeps polished gold.
        let coinColors = GameCoinTint.colors(for: activeSpawnProfile)
        let coin = GameVisualBuilders.makeCoin(
            radius: GameWorld.coinRadius,
            tint: coinColors.base,
            hot: coinColors.hot,
            tintsFaceTexture: coinColors.tintsFaceTexture
        )
        // Mild outward offset — still a reach, but easier to snag mid-dodge.
        let outward: Float = lane == .center ? 0 : (lane.x > 0 ? GameWorld.coinOutwardOffset : -GameWorld.coinOutwardOffset)
        let baseY = underCeiling ? GameWorld.lowCrawlCoinHeight : GameWorld.coinHeight
        coin.position = SIMD3(lane.x + outward + windCurrentX, baseY, patternSpawnZ)
        root.addChild(coin)
        coins.append(
            CoinItem(
                entity: coin,
                baseY: baseY,
                phase: Float.random(in: 0...(Float.pi * 2))
            )
        )
    }

    private func spawnHalfCrystal(in lane: Lane) {
        var rng = SystemRandomNumberGenerator()
        let roll = CrystalCombine.makeHalf(rng: &rng)
        let radius: Float = roll.charged ? 0.09 : 0.075
        let mesh = MeshResource.generateSphere(radius: radius)
        let material = EnvironmentMaterials.crystalHalf(type: roll.type, charged: roll.charged)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        let outward: Float = lane == .center ? 0 : (lane.x > 0 ? GameWorld.coinOutwardOffset : -GameWorld.coinOutwardOffset)
        entity.position = SIMD3(lane.x + outward + windCurrentX, GameWorld.coinHeight, patternSpawnZ)
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

    private func updateHeldHalves(deltaTime: Float) {
        // Non-open hands confirm immediately. Open/flat hands get a brief window, then drop.
        // After confirm, only a clear open palm releases — no open→fist transition required.
        if var held = heldLeft {
            held.timeSinceGrab += deltaTime
            let tracked = leftHandGripWorld != nil || !leftHandContactsWorld.isEmpty
            if !leftIsOpen {
                held.confirmedGrip = true
            }

            let mustDrop: Bool
            if !tracked {
                mustDrop = true
            } else if held.confirmedGrip {
                mustDrop = leftIsOpen
            } else {
                mustDrop = held.timeSinceGrab >= GameWorld.crystalGrabConfirmWindow
            }

            if mustDrop {
                held.entity.removeFromParent()
                heldLeft = nil
            } else {
                if let grip = leftHandGripWorld {
                    held.entity.position = root.convert(position: grip, from: nil)
                } else if let tip = leftHandContactsWorld.last {
                    held.entity.position = root.convert(position: tip, from: nil)
                }
                heldLeft = held
            }
        }
        if var held = heldRight {
            held.timeSinceGrab += deltaTime
            let tracked = rightHandGripWorld != nil || !rightHandContactsWorld.isEmpty
            if !rightIsOpen {
                held.confirmedGrip = true
            }

            let mustDrop: Bool
            if !tracked {
                mustDrop = true
            } else if held.confirmedGrip {
                mustDrop = rightIsOpen
            } else {
                mustDrop = held.timeSinceGrab >= GameWorld.crystalGrabConfirmWindow
            }

            if mustDrop {
                held.entity.removeFromParent()
                heldRight = nil
            } else {
                if let grip = rightHandGripWorld {
                    held.entity.position = root.convert(position: grip, from: nil)
                } else if let tip = rightHandContactsWorld.last {
                    held.entity.position = root.convert(position: tip, from: nil)
                }
                heldRight = held
            }
        }

        guard let left = heldLeft, let right = heldRight else { return }
        guard CrystalCombine.canMerge(left: left.type, right: right.type) else { return }

        let leftPos = left.entity.position
        let rightPos = right.entity.position
        if distance(leftPos, rightPos) <= CrystalCombine.combineDistance {
            let coins = CrystalCombine.mergeCoinAward(
                leftCharged: left.charged,
                rightCharged: right.charged
            )
            left.entity.removeFromParent()
            right.entity.removeFromParent()
            heldLeft = nil
            heldRight = nil
            GameSFX.shared.playCoinCollect()
            let model = self.gameModel
            DispatchQueue.main.async {
                model?.collectCoin(count: coins)
            }
        }
    }

    private func tryGrabHalves() {
        guard activeSpawnProfile.twist == .crystalHalves else { return }

        // Proximity pickup. Already-closed hands keep it; still-open hands drop after the window.
        if heldLeft == nil {
            let points = handPointsInRoot(leftHandContactsWorld, gripWorld: leftHandGripWorld)
            if let index = nearestHalfIndex(toAnyOf: points) {
                grabHalf(at: index, left: true)
            }
        }
        if heldRight == nil {
            let points = handPointsInRoot(rightHandContactsWorld, gripWorld: rightHandGripWorld)
            if let index = nearestHalfIndex(toAnyOf: points) {
                grabHalf(at: index, left: false)
            }
        }
    }

    private func handPointsInRoot(
        _ contactsWorld: [SIMD3<Float>],
        gripWorld: SIMD3<Float>?
    ) -> [SIMD3<Float>] {
        var points = contactsWorld.map { root.convert(position: $0, from: nil) }
        if let gripWorld {
            let grip = root.convert(position: gripWorld, from: nil)
            if !points.contains(where: { distance($0, grip) < 0.01 }) {
                points.append(grip)
            }
        }
        return points
    }

    private func nearestHalfIndex(toAnyOf points: [SIMD3<Float>]) -> Int? {
        guard !points.isEmpty else { return nil }
        var bestIndex: Int?
        var bestDistance = GameWorld.crystalCollectDistance
        for (index, half) in halves.enumerated() {
            guard !half.collected else { continue }
            let halfPos = half.entity.position(relativeTo: root)
            for point in points {
                let d = distance(point, halfPos)
                if d <= bestDistance {
                    bestDistance = d
                    bestIndex = index
                }
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
        var held = HeldHalf(type: source.type, charged: source.charged, entity: heldEntity)
        if left {
            // Fist / closed / unknown all count — only a flat open hand needs the confirm window.
            if !leftIsOpen {
                held.confirmedGrip = true
            }
            if let grip = leftHandGripWorld {
                held.entity.position = root.convert(position: grip, from: nil)
            }
            heldLeft = held
        } else {
            if !rightIsOpen {
                held.confirmedGrip = true
            }
            if let grip = rightHandGripWorld {
                held.entity.position = root.convert(position: grip, from: nil)
            }
            heldRight = held
        }
    }

    // MARK: - Collisions

    private func resolveCollisions(gameModel: GameModel) {
        let head = playfieldHeadPosition()
        // Also test a slightly lower "chin/neck" sample so tall duck slabs are harder to skim.
        let headSamples = [
            head,
            SIMD3<Float>(head.x, head.y - 0.12, head.z)
        ]
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
        let duckHalfWidth = GameWorld.duckSlabWidth * 0.5 - 0.05

        for wall in walls {
            guard !wall.hasResolvedHit else { continue }
            let wallZ = wall.entity.position.z
            let previousZ = wall.previousZ

            let hit: Bool
            if wall.kind == .duck {
                let centerX = wall.entity.position.x
                let headHit = headSamples.contains { sample in
                    WallCollision.pointHitsDuckBarrier(
                        point: sample,
                        wallZ: wallZ,
                        previousWallZ: previousZ,
                        centerX: centerX,
                        halfWidth: duckHalfWidth,
                        halfDepth: GameWorld.duckHitHalfDepth,
                        clearanceY: GameWorld.duckClearanceY,
                        maxY: GameWorld.headHitMaxY
                    )
                }
                let handHit = hands.contains { hand in
                    WallCollision.pointHitsDuckBarrier(
                        point: hand,
                        wallZ: wallZ,
                        previousWallZ: previousZ,
                        centerX: centerX,
                        halfWidth: duckHalfWidth + GameWorld.handHitRadius,
                        halfDepth: GameWorld.duckHitHalfDepth + GameWorld.handHitRadius,
                        clearanceY: GameWorld.duckClearanceY,
                        maxY: GameWorld.handHitMaxY
                    )
                }
                hit = headHit || handHit
            } else {
                let slabXs = wall.worldSlabXs()
                let seal = wall.sealsBetweenSlabs
                let headHit = headSamples.contains { sample in
                    WallCollision.pointHitsSlabs(
                        point: sample,
                        wallZ: wallZ,
                        previousWallZ: previousZ,
                        slabXs: slabXs,
                        halfWidth: halfWidth,
                        halfDepth: halfDepth,
                        minY: GameWorld.headHitMinY,
                        maxY: GameWorld.headHitMaxY,
                        sealBetweenSlabs: seal
                    )
                }
                let handHit = hands.contains { hand in
                    WallCollision.pointHitsSlabs(
                        point: hand,
                        wallZ: wallZ,
                        previousWallZ: previousZ,
                        slabXs: slabXs,
                        halfWidth: handHalfWidth,
                        halfDepth: handHalfDepth,
                        minY: GameWorld.handHitMinY,
                        maxY: GameWorld.handHitMaxY,
                        sealBetweenSlabs: seal
                    )
                }
                hit = headHit || handHit
            }

            if hit {
                wall.hasResolvedHit = true
                visualFX.spawnHitFlash(near: SIMD3(head.x, head.y, wall.entity.position.z))
                // Quick squash so the hit reads before game-over UI.
                wall.entity.scale = SIMD3(1.08, 0.92, 1.15)
                GameSFX.shared.playWallHit()
                dropHeldHalves()
                gameModel.endRun()
                return
            }

            // Retire only after the slab clears the head. Using a forward hand Z here
            // used to mark walls "passed" before the head could collide (bad for duck gates).
            if WallCollision.hasPassedContact(
                wallZ: wallZ,
                contactZ: head.z,
                halfDepth: handHalfDepth
            ) {
                wall.hasResolvedHit = true
            }
        }

        // Crystal grabs run in tick(); coins only apply outside Crystal Cave.
        if activeSpawnProfile.twist == .crystalHalves {
            return
        }

        guard !hands.isEmpty else { return }

        for index in coins.indices {
            guard !coins[index].collected else { continue }
            let coinPos = coins[index].entity.position(relativeTo: root)
            for hand in hands {
                if distance(hand, coinPos) <= GameWorld.collectDistance {
                    coins[index].collected = true
                    visualFX.spawnCoinBurst(at: coinPos)
                    // Hide now; removeFromParent happens in prune. HUD/SFX after this tick.
                    coins[index].entity.isEnabled = false
                    let model = gameModel
                    GameSFX.shared.playCoinCollect()
                    DispatchQueue.main.async {
                        model.collectCoin()
                    }
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
            if item.collected {
                item.entity.removeFromParent()
                return true
            }
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
