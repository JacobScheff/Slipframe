//
//  GameWorld.swift
//  Endless Runner
//
//  Minimal single-environment endless runner:
//  - Playfield sits on the real floor and locks pose when a run starts
//  - Tiled track ribbon recycles for an endless corridor
//  - World scrolls toward the player
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
    private static let spawnZ: Float = -12
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
    /// Distance traveled between obstacle / coin patterns.
    private static let spawnGapMin: Float = 4.2
    private static let spawnGapMax: Float = 5.6
    private static let coinPoints = 10
    /// HUD sits above the corridor, further down the track, clear of the play volume.
    private static let hudPosition = SIMD3<Float>(0, 2.45, -4.0)
    /// World scale for the SwiftUI attachment (attachments are small by default).
    private static let hudScale: Float = 3.0

    // Endless track tiles — recycled as they pass behind the player.
    private static let trackWidth: Float = 3.2
    private static let trackSegmentLength: Float = 4.0
    private static let trackSegmentCount = 12
    /// When a segment center passes this Z, snap it to the far end of the ribbon.
    private static let trackRecycleZ: Float = 2.2
    /// First segment sits slightly behind the stand line so the ribbon covers your feet.
    private static let trackFirstCenterZ: Float = trackSegmentLength * 0.2
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
    private let hudAnchor = Entity()
    private let trackRoot = Entity()

    private weak var gameModel: GameModel?
    private var walls: [WallItem] = []
    private var coins: [CoinItem] = []
    private var trackSegments: [Entity] = []
    private var speed: Float = GameWorld.baseSpeed
    /// First pattern arrives almost immediately after Start.
    private var distanceUntilSpawn: Float = 0.15
    private var distanceAccumulator: Float = 0
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
        isPlayfieldLocked = false

        if updateSubscription == nil {
            updateSubscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
                self?.tick(deltaTime: Float(event.deltaTime))
            }
        }

        buildStaticEnvironment()
        ensureHUDAnchor()
        startHandTracking()
        // Warm audio before the first coin so setActive does not hitch mid-run.
        GameSFX.shared.prepare()
        snapPlayfieldToPlayer()
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
        clearDynamicContent()
        trackSegments.removeAll()
        for child in hudAnchor.children {
            child.removeFromParent()
        }
        for child in trackRoot.children {
            child.removeFromParent()
        }
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
        // Tiled corridor ribbon (placeholder for Ember Run) + fixed stand marker.
        if trackRoot.parent === root, !trackSegments.isEmpty { return }

        trackRoot.name = "trackRoot"
        if trackRoot.parent !== root {
            root.addChild(trackRoot)
        }

        trackSegments.removeAll()
        for child in trackRoot.children {
            child.removeFromParent()
        }

        for index in 0..<GameWorld.trackSegmentCount {
            let segment = makeTrackSegment()
            segment.position = SIMD3(
                0,
                0,
                GameWorld.trackFirstCenterZ - Float(index) * GameWorld.trackSegmentLength
            )
            trackRoot.addChild(segment)
            trackSegments.append(segment)
        }

        buildStartMarker()
    }

    private func makeTrackSegment() -> Entity {
        let segment = Entity()
        segment.name = "trackSegment"

        // Slight overlap avoids hairline gaps between recycled tiles.
        let depth = GameWorld.trackSegmentLength + 0.02
        let floorMesh = MeshResource.generateBox(
            width: GameWorld.trackWidth,
            height: 0.02,
            depth: depth
        )
        let floorMaterial = SimpleMaterial(
            color: UIColor(red: 0.45, green: 0.28, blue: 0.12, alpha: 1),
            roughness: 0.85,
            isMetallic: false
        )
        let floor = ModelEntity(mesh: floorMesh, materials: [floorMaterial])
        floor.name = "floor"
        segment.addChild(floor)

        let stripeMaterial = SimpleMaterial(
            color: UIColor(red: 1.0, green: 0.72, blue: 0.25, alpha: 0.9),
            roughness: 0.7,
            isMetallic: false
        )
        for lane in Lane.allCases {
            let stripeMesh = MeshResource.generateBox(width: 0.08, height: 0.025, depth: depth)
            let stripe = ModelEntity(mesh: stripeMesh, materials: [stripeMaterial])
            stripe.position = SIMD3(lane.x, 0.02, 0)
            segment.addChild(stripe)
        }

        return segment
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
        // Final snap to feet / facing / real floor, then freeze world pose for the run.
        snapPlayfieldToPlayer()
        isPlayfieldLocked = true
        clearDynamicContent()
        resetTrackLayout()
        speed = GameWorld.baseSpeed
        distanceUntilSpawn = 0.15
        distanceAccumulator = 0
        GameSFX.shared.prepare()
    }

    // MARK: - Playfield pose

    /// Places the playfield on the real floor under the player, facing their look direction.
    private func snapPlayfieldToPlayer() {
        let headWorld = headAnchor.position(relativeTo: nil)
        let headRotation = headAnchor.orientation(relativeTo: nil)

        let floorY: Float
        if floorAnchor.isAnchored {
            floorY = floorAnchor.position(relativeTo: nil).y
        } else {
            floorY = headWorld.y - GameWorld.fallbackEyeHeight
        }

        // Flatten head forward onto the floor plane (track runs along local −Z).
        let forwardWorld = headRotation.act(SIMD3<Float>(0, 0, -1))
        var flatForward = SIMD3<Float>(forwardWorld.x, 0, forwardWorld.z)
        let forwardLength = length(flatForward)
        if forwardLength < 0.05 {
            flatForward = SIMD3(0, 0, -1)
        } else {
            flatForward /= forwardLength
        }

        let yaw = atan2(-flatForward.x, -flatForward.z)
        let position = SIMD3<Float>(headWorld.x, floorY, headWorld.z)
        root.setPosition(position, relativeTo: nil)
        root.setOrientation(simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0)), relativeTo: nil)
    }

    private func resetTrackLayout() {
        for (index, segment) in trackSegments.enumerated() {
            segment.position = SIMD3(
                0,
                0,
                GameWorld.trackFirstCenterZ - Float(index) * GameWorld.trackSegmentLength
            )
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
        // Before Start, keep the stand line under the player. After Start, pose is frozen
        // so walking forward/back does not drag the track.
        if !isPlayfieldLocked {
            snapPlayfieldToPlayer()
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
        advanceTrack(by: travel)
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

    private func advanceTrack(by travel: Float) {
        for segment in trackSegments {
            segment.position.z += travel
        }

        // Recycle any tiles that have slid behind the player to the far horizon.
        while let segment = trackSegments.first(where: { $0.position.z > GameWorld.trackRecycleZ }) {
            let farthestZ = trackSegments.map(\.position.z).min() ?? segment.position.z
            segment.position.z = farthestZ - GameWorld.trackSegmentLength
        }
    }

    // MARK: - Spawning

    private func spawnNextPattern() {
        // Random mix of wall / coin layouts so each run feels different.
        switch Int.random(in: 0..<6) {
        case 0:
            spawnWall(blocking: [.left])
        case 1:
            spawnCoin(in: .right)
        case 2:
            spawnWall(blocking: [.right])
        case 3:
            spawnCoin(in: .left)
        case 4:
            spawnWall(blocking: [.center])
            spawnCoin(in: .left)
        default:
            spawnWall(blocking: [.left, .right])
            spawnCoin(in: .center)
        }
    }

    private func spawnWall(blocking lanes: Set<Lane>) {
        let parent = Entity()
        parent.position = SIMD3(0, GameWorld.wallHeight * 0.5, GameWorld.spawnZ)
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
        coin.position = SIMD3(lane.x + outward, GameWorld.coinHeight, GameWorld.spawnZ)
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
