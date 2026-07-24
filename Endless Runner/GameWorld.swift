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

    private struct WallItem {
        let entity: Entity
        let blockedLanes: Set<Int>
        var hasResolvedHit = false
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
    private static let spawnZ: Float = -8
    private static let despawnZ: Float = 1.5
    /// Hit test at the stand line (playfield z = 0), matching visual pass-through.
    private static let hitZWindow: Float = wallThickness * 0.5 + 0.12
    /// Mild shrink so grazing a lane edge is less punishing.
    private static let hitXInset: Float = 0.1
    private static let collectDistance: Float = 0.24
    private static let baseSpeed: Float = 2.2
    private static let maxSpeed: Float = 5.5
    private static let speedRampPerSecond: Float = 0.04
    /// Distance traveled between obstacle / coin patterns.
    private static let spawnGapMin: Float = 3.6
    private static let spawnGapMax: Float = 5.2
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
    private var distanceUntilSpawn: Float = 1.5
    private var distanceAccumulator: Float = 0
    private var patternIndex = 0
    private var updateSubscription: EventSubscription?
    private var activeRunID: Int = -1
    /// After Start, playfield pose no longer follows the player.
    private var isPlayfieldLocked = false

    private let arSession = ARKitSession()
    private let handTracking = HandTrackingProvider()
    private var handTask: Task<Void, Never>?

    private var leftHandPosition: SIMD3<Float>?
    private var rightHandPosition: SIMD3<Float>?

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
        distanceUntilSpawn = 1.0
        distanceAccumulator = 0
        patternIndex = 0
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
                    guard anchor.isTracked else { continue }
                    let position = SIMD3<Float>(
                        anchor.originFromAnchorTransform.columns.3.x,
                        anchor.originFromAnchorTransform.columns.3.y,
                        anchor.originFromAnchorTransform.columns.3.z
                    )
                    switch anchor.chirality {
                    case .left:
                        leftHandPosition = position
                    case .right:
                        rightHandPosition = position
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
        // Simple repeating warm-up patterns for the first base environment.
        switch patternIndex % 6 {
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
            // Gate with an open center — left+center was punishing the stand-line
            // pose (center) even when dodging clear of the side slab.
            spawnWall(blocking: [.left, .right])
            spawnCoin(in: .center)
        }
        patternIndex += 1
    }

    private func spawnWall(blocking lanes: Set<Lane>) {
        let parent = Entity()
        parent.position = SIMD3(0, GameWorld.wallHeight * 0.5, GameWorld.spawnZ)
        parent.name = "wall"

        for lane in lanes {
            let slab = makeWallSlab()
            slab.position = SIMD3(lane.x, 0, 0)
            parent.addChild(slab)
        }

        root.addChild(parent)
        walls.append(WallItem(entity: parent, blockedLanes: Set(lanes.map(\.rawValue))))
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
        let handsWorld = [leftHandPosition, rightHandPosition].compactMap { $0 }

        for index in walls.indices {
            guard !walls[index].hasResolvedHit else { continue }
            let wallZ = walls[index].entity.position.z
            // Resolve once at the stand line — not against head depth (walking
            // forward was making distant walls register as hits).
            guard abs(wallZ) <= GameWorld.hitZWindow else { continue }

            walls[index].hasResolvedHit = true
            if headHitsBlockedSlab(blockedLanes: walls[index].blockedLanes, headX: head.x) {
                GameSFX.shared.playWallHit()
                gameModel.endRun()
                return
            }
        }

        guard !handsWorld.isEmpty else { return }

        for index in coins.indices {
            guard !coins[index].collected else { continue }
            let coinPos = coins[index].entity.position(relativeTo: nil)
            for hand in handsWorld {
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

    /// Head-only check against the real slab widths (restored full-size hit box).
    private func headHitsBlockedSlab(blockedLanes: Set<Int>, headX: Float) -> Bool {
        let halfWidth = max(0.05, GameWorld.wallWidth * 0.5 - GameWorld.hitXInset)
        for laneValue in blockedLanes {
            let laneX = Float(laneValue) * GameWorld.laneSpacing
            if headX >= laneX - halfWidth, headX <= laneX + halfWidth {
                return true
            }
        }
        return false
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
