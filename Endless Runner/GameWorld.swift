//
//  GameWorld.swift
//  Endless Runner
//
//  Minimal single-environment endless runner:
//  - Playfield sits on the real floor and locks pose when a run starts
//  - Synth Riders-style portal window at the end of a fixed track
//  - Obstacles emerge from the portal into the real room
//  - Track is a static slab (does not scroll or recycle)
//  - Red walls block 1–2 lanes (head + hand collision)
//  - Gold coins collected by hand proximity
//  - Play / score HUD is fixed above the track
//  Placeholder meshes only (no art assets).
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
        /// Local X centers of each red slab (playfield / parent space).
        let slabXs: [Float]
        var hasResolvedHit = false

        init(entity: Entity, slabXs: [Float]) {
            self.entity = entity
            self.slabXs = slabXs
        }
    }

    private struct CoinItem {
        let entity: Entity
        var collected = false
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
    private static let coinPoints = 10
    /// HUD sits above the corridor, further down the track, clear of the play volume.
    private static let hudPosition = SIMD3<Float>(0, 2.45, -3.2)
    /// World scale for the SwiftUI attachment (attachments are small by default).
    private static let hudScale: Float = 3.0

    // Synth Riders-style portal aperture (always visible at the track end).
    private static let portalWidth: Float = 3.8
    private static let portalHeight: Float = 2.7
    private static let portalCornerRadius: Float = 1.15
    private static let portalRimThickness: Float = 0.14
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

    /// Simple glowing placeholder until real wall art is dropped in.
    private static let wallBodyMaterial: any RealityKit.Material = makeWallBodyMaterial()

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

    private weak var gameModel: GameModel?
    private var walls: [WallItem] = []
    private var coins: [CoinItem] = []
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

    /// ARKit hand tracking — AnchorEntity(.hand) transforms are privacy-locked
    /// unless a SpatialTrackingSession is running (visionOS 2+), so we read
    /// joint positions from HandTrackingProvider instead.
    private let arSession = ARKitSession()
    private let handTracking = HandTrackingProvider()
    private var handTask: Task<Void, Never>?
    /// World-space contact points (wrist + fingertips) for each hand.
    private var leftHandContactsWorld: [SIMD3<Float>] = []
    private var rightHandContactsWorld: [SIMD3<Float>] = []

    func attach(to content: RealityViewContent, gameModel: GameModel) {
        self.gameModel = gameModel
        content.add(root)
        content.add(headAnchor)
        content.add(floorAnchor)
        content.add(wallAnchor)
        isPlayfieldLocked = false

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
        guard gameModel.isPlaying, gameModel.runID != activeRunID else { return }
        beginRun(runID: gameModel.runID)
    }

    func teardown() {
        handTask?.cancel()
        handTask = nil
        leftHandContactsWorld = []
        rightHandContactsWorld = []
        updateSubscription = nil
        isPlayfieldLocked = false
        portalZ = GameWorld.defaultPortalZ
        activeSpawnZ = GameWorld.defaultPortalZ + GameWorld.spawnInFrontOfPortal
        lastBuiltPortalZ = .greatestFiniteMagnitude
        clearDynamicContent()
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

        let floorMesh = MeshResource.generateBox(
            width: GameWorld.trackWidth,
            height: 0.02,
            depth: depth
        )
        let floorMaterial = SimpleMaterial(
            color: UIColor(red: 0.12, green: 0.1, blue: 0.16, alpha: 1),
            roughness: 0.85,
            isMetallic: false
        )
        let floor = ModelEntity(mesh: floorMesh, materials: [floorMaterial])
        floor.name = "floor"
        floor.position = SIMD3(0, 0, centerZ)
        trackRoot.addChild(floor)

        let stripeMaterial = UnlitMaterial(
            color: UIColor(red: 0.35, green: 0.95, blue: 1.0, alpha: 0.85)
        )
        for lane in Lane.allCases {
            let stripeMesh = MeshResource.generateBox(width: 0.07, height: 0.025, depth: depth)
            let stripe = ModelEntity(mesh: stripeMesh, materials: [stripeMaterial])
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

        // Also register the world at the RealityView root level via portalRoot parenting.
        layoutPortal()
    }

    private func buildPortalRim() {
        if portalRoot.children.contains(where: { $0.name == "portalRim" }) { return }

        let rim = Entity()
        rim.name = "portalRim"
        let t = GameWorld.portalRimThickness
        let outerW = GameWorld.portalWidth + t * 2
        let outerH = GameWorld.portalHeight + t * 2
        let cyan = UnlitMaterial(color: UIColor(red: 0.25, green: 0.95, blue: 1.0, alpha: 1))
        let magenta = UnlitMaterial(color: UIColor(red: 1.0, green: 0.25, blue: 0.75, alpha: 1))

        func addBar(width: Float, height: Float, x: Float, y: Float, material: UnlitMaterial) {
            let mesh = MeshResource.generateBox(width: width, height: height, depth: 0.08)
            let bar = ModelEntity(mesh: mesh, materials: [material])
            bar.position = SIMD3(x, y, 0.04)
            rim.addChild(bar)
        }

        // Rounded look approximated with thick neon bars + corner blocks.
        addBar(width: outerW, height: t, x: 0, y: (GameWorld.portalHeight + t) * 0.5, material: cyan)
        addBar(width: outerW, height: t, x: 0, y: -(GameWorld.portalHeight + t) * 0.5, material: magenta)
        addBar(width: t, height: GameWorld.portalHeight, x: (GameWorld.portalWidth + t) * 0.5, y: 0, material: cyan)
        addBar(width: t, height: GameWorld.portalHeight, x: -(GameWorld.portalWidth + t) * 0.5, y: 0, material: magenta)

        // Soft outer glow plates (slightly larger, behind the rim).
        let glowMesh = MeshResource.generatePlane(
            width: outerW + 0.25,
            height: outerH + 0.25,
            cornerRadius: GameWorld.portalCornerRadius + 0.15
        )
        let glowMaterial = UnlitMaterial(color: UIColor(red: 0.4, green: 0.2, blue: 0.9, alpha: 0.35))
        let glow = ModelEntity(mesh: glowMesh, materials: [glowMaterial])
        glow.position = SIMD3(0, 0, -0.02)
        rim.addChild(glow)

        portalRoot.addChild(rim)
    }

    /// Neon tunnel visible only through the portal — blocks passthrough like Synth Riders.
    private func buildPortalInterior() {
        for child in portalWorld.children {
            child.removeFromParent()
        }

        let interior = Entity()
        interior.name = "portalInterior"
        // Behind the portal plane (away from the player).
        interior.position = SIMD3(0, 0, -0.08)

        let deep = UnlitMaterial(color: UIColor(red: 0.04, green: 0.02, blue: 0.1, alpha: 1))
        let cyan = UnlitMaterial(color: UIColor(red: 0.2, green: 0.95, blue: 1.0, alpha: 1))
        let magenta = UnlitMaterial(color: UIColor(red: 1.0, green: 0.2, blue: 0.7, alpha: 1))

        // Inward-facing sky dome so the aperture always reads as a solid other-world.
        let dome = ModelEntity(
            mesh: MeshResource.generateSphere(radius: 9),
            materials: [deep]
        )
        dome.scale = SIMD3(-1, 1, 1)
        dome.position = SIMD3(0, 0, -4)
        interior.addChild(dome)

        let floor = ModelEntity(
            mesh: MeshResource.generateBox(width: 5, height: 0.05, depth: 12),
            materials: [UnlitMaterial(color: UIColor(red: 0.08, green: 0.05, blue: 0.16, alpha: 1))]
        )
        floor.position = SIMD3(0, -GameWorld.portalHeight * 0.5 + 0.02, -6)
        interior.addChild(floor)

        // Receding neon frames (open rectangles) for depth, Synth Riders-style.
        for i in 0..<5 {
            let z = Float(-1.0 - Float(i) * 1.6)
            let scale = 1.0 - Float(i) * 0.06
            let w = GameWorld.portalWidth * scale
            let h = GameWorld.portalHeight * scale
            let mat = i % 2 == 0 ? cyan : magenta
            let frame = Entity()
            frame.position = SIMD3(0, 0, z)

            let top = ModelEntity(
                mesh: MeshResource.generateBox(width: w, height: 0.05, depth: 0.05),
                materials: [mat]
            )
            top.position = SIMD3(0, h * 0.5, 0)
            frame.addChild(top)

            let bottom = ModelEntity(
                mesh: MeshResource.generateBox(width: w, height: 0.05, depth: 0.05),
                materials: [mat]
            )
            bottom.position = SIMD3(0, -h * 0.5, 0)
            frame.addChild(bottom)

            for sign: Float in [-1, 1] {
                let side = ModelEntity(
                    mesh: MeshResource.generateBox(width: 0.05, height: h, depth: 0.05),
                    materials: [mat]
                )
                side.position = SIMD3(sign * w * 0.5, 0, 0)
                frame.addChild(side)
            }
            interior.addChild(frame)
        }

        for sign: Float in [-1, 1] {
            let rail = ModelEntity(
                mesh: MeshResource.generateBox(width: 0.06, height: 0.06, depth: 12),
                materials: [sign < 0 ? cyan : magenta]
            )
            rail.position = SIMD3(sign * 1.55, -GameWorld.portalHeight * 0.35, -6)
            interior.addChild(rail)
        }

        portalWorld.addChild(interior)
    }

    private func layoutPortal() {
        // Center the aperture at standing height, flush with the portal depth.
        portalRoot.position = SIMD3(0, GameWorld.portalHeight * 0.5, portalZ)
        activeSpawnZ = portalZ + GameWorld.spawnInFrontOfPortal
    }

    /// Minimal stand line at the player's start — easy to find, quiet otherwise.
    private func buildStartMarker() {
        if root.children.contains(where: { $0.name == "startMarker" }) { return }

        let marker = Entity()
        marker.name = "startMarker"
        // Fixed in world space at z = 0 (does not scroll with the ribbon).
        marker.position = SIMD3(0, 0.03, 0)

        let lineMesh = MeshResource.generateBox(width: 2.35, height: 0.008, depth: 0.028)
        let lineMaterial = UnlitMaterial(
            color: UIColor(red: 0.98, green: 0.93, blue: 0.82, alpha: 0.75)
        )
        let line = ModelEntity(mesh: lineMesh, materials: [lineMaterial])
        marker.addChild(line)

        // Small center tick so the midline is findable at a glance.
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
        // Final snap toward wall (if any) / feet / facing, then freeze pose for the run.
        snapPlayfieldToPlayer()
        updatePortalAndTrack()
        isPlayfieldLocked = true
        clearDynamicContent()
        rebuildFixedTrack(force: true)
        layoutPortal()
        speed = GameWorld.baseSpeed
        distanceUntilSpawn = 0
        distanceAccumulator = 0
        GameSFX.shared.prepare()
    }

    // MARK: - Playfield pose

    /// Places the playfield on the real floor. Faces a nearby wall when one is found;
    /// otherwise faces the player's look direction. Portal stays at the track end either way.
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

    /// Horizontal unit vector from the player toward a wall in the accepted distance band.
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

    /// Portal is always shown. Snap it onto a wall when one is in range; otherwise use default depth.
    private func updatePortalAndTrack() {
        let playerPosition = root.position(relativeTo: nil)

        if wallAnchor.isAnchored,
           suitableWallForward(from: playerPosition) != nil {
            let wallInRoot = root.convert(position: wallAnchor.position(relativeTo: nil), from: nil)
            // Sit the aperture on / just in front of the real wall.
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
        walls.removeAll()
        coins.removeAll()
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
                        case .left: leftHandContactsWorld = []
                        case .right: rightHandContactsWorld = []
                        @unknown default: break
                        }
                        continue
                    }
                    let contacts = Self.contactPoints(from: anchor)
                    switch anchor.chirality {
                    case .left:
                        leftHandContactsWorld = contacts
                    case .right:
                        rightHandContactsWorld = contacts
                    @unknown default:
                        break
                    }
                }
            } catch {
                // Hand tracking is optional for dodge; walls still work via head.
                print("Hand tracking failed: \(error)")
            }
        }
    }

    /// Wrist / palm origin plus fingertips — better "touch" than wrist alone.
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

    // MARK: - Loop

    private func tick(deltaTime: Float) {
        // Before Start, keep the stand line under the player and refresh portal depth.
        // After Start, pose / portal / track are frozen — only obstacles move.
        if !isPlayfieldLocked {
            snapPlayfieldToPlayer()
            updatePortalAndTrack()
        }

        guard let gameModel, gameModel.isPlaying, !gameModel.isGameOver else { return }
        guard deltaTime > 0, deltaTime < 0.25 else { return }

        let travel = speed * deltaTime
        speed = min(GameWorld.maxSpeed, speed + GameWorld.speedRampPerSecond * deltaTime)

        // Distance score: +1 per meter traveled.
        distanceAccumulator += travel
        if distanceAccumulator >= 1 {
            let gained = Int(distanceAccumulator)
            distanceAccumulator -= Float(gained)
            gameModel.addScore(gained)
        }

        advanceEntities(by: travel)
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
    }

    // MARK: - Spawning

    private func spawnNextPattern() {
        // Always spawn a wall so there are no empty obstacle gaps.
        let blocking = Self.randomWallLanes()
        spawnWall(blocking: blocking)

        // Often place a coin in a safe lane for reach variety.
        let safeLanes = Lane.allCases.filter { !blocking.contains($0) }
        if let coinLane = safeLanes.randomElement(), Float.random(in: 0...1) < 0.7 {
            spawnCoin(in: coinLane)
        }
    }

    /// Random 1–2 lane blocks (never all three — always a dodge path).
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

    private func spawnWall(blocking lanes: Set<Lane>) {
        let parent = Entity()
        parent.position = SIMD3(0, GameWorld.wallHeight * 0.5, activeSpawnZ)
        parent.name = "wall"

        var slabXs: [Float] = []
        for lane in lanes {
            let slab = makeWallSlab()
            slab.position = SIMD3(lane.x, 0, 0)
            parent.addChild(slab)
            slabXs.append(lane.x)
        }

        root.addChild(parent)
        walls.append(WallItem(entity: parent, slabXs: slabXs))
    }

    /// Thick translucent placeholder slab (swap for a real model later).
    private func makeWallSlab() -> Entity {
        let bodyMesh = MeshResource.generateBox(
            width: GameWorld.wallWidth,
            height: GameWorld.wallHeight,
            depth: GameWorld.wallThickness
        )
        let body = ModelEntity(mesh: bodyMesh, materials: [GameWorld.wallBodyMaterial])
        body.name = "wallSlab"
        return body
    }

    private static func makeWallBodyMaterial() -> any RealityKit.Material {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: 0.95, green: 0.12, blue: 0.1, alpha: 0.42))
        material.roughness = .init(floatLiteral: 0.35)
        material.metallic = .init(floatLiteral: 0.05)
        material.emissiveColor = .init(color: UIColor(red: 1.0, green: 0.18, blue: 0.12, alpha: 1.0))
        material.emissiveIntensity = 0.55
        material.blending = .transparent(opacity: .init(floatLiteral: 0.42))
        return material
    }

    private func spawnCoin(in lane: Lane) {
        let mesh = MeshResource.generateSphere(radius: GameWorld.coinRadius)
        let material = SimpleMaterial(
            color: UIColor(red: 1, green: 0.84, blue: 0.2, alpha: 1),
            isMetallic: true
        )
        let coin = ModelEntity(mesh: mesh, materials: [material])
        // Mild outward offset — still a reach, but easier to snag mid-dodge.
        let outward: Float = lane == .center ? 0 : (lane.x > 0 ? GameWorld.coinOutwardOffset : -GameWorld.coinOutwardOffset)
        coin.position = SIMD3(lane.x + outward, GameWorld.coinHeight, activeSpawnZ)
        coin.name = "coin"
        root.addChild(coin)
        coins.append(CoinItem(entity: coin))
    }

    // MARK: - Collisions

    private func resolveCollisions(gameModel: GameModel) {
        let head = headAnchor.position(relativeTo: root)
        // ARKit hand joints are world-space; convert into the locked playfield.
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

        for wall in walls {
            guard !wall.hasResolvedHit else { continue }
            let wallZ = wall.entity.position.z

            let headHit = WallCollision.pointHitsSlabs(
                point: head,
                wallZ: wallZ,
                slabXs: wall.slabXs,
                halfWidth: halfWidth,
                halfDepth: halfDepth,
                minY: GameWorld.headHitMinY,
                maxY: GameWorld.headHitMaxY
            )
            let handHit = hands.contains { hand in
                WallCollision.pointHitsSlabs(
                    point: hand,
                    wallZ: wallZ,
                    slabXs: wall.slabXs,
                    halfWidth: handHalfWidth,
                    halfDepth: handHalfDepth,
                    minY: GameWorld.handHitMinY,
                    maxY: GameWorld.handHitMaxY
                )
            }

            if headHit || handHit {
                wall.hasResolvedHit = true
                GameSFX.shared.playWallHit()
                gameModel.endRun()
                return
            }

            // Keep testing while any contact (including a forward-reaching hand)
            // could still overlap the slab.
            let farthestContactZ = hands.map(\.z).min().map { min($0, head.z) } ?? head.z
            if WallCollision.hasPassedContact(
                wallZ: wallZ,
                contactZ: farthestContactZ,
                halfDepth: handHalfDepth
            ) {
                wall.hasResolvedHit = true
            }
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
    }
}
