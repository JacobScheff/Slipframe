//
//  GameWorld.swift
//  Endless Runner
//
//  Minimal single-environment endless runner:
//  - World scrolls toward the player
//  - Red walls block 1–2 lanes (head X collision)
//  - Gold coins collected by hand proximity
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
    private static let wallThickness: Float = 0.12
    private static let wallWidth: Float = 0.7
    private static let coinRadius: Float = 0.07
    private static let coinHeight: Float = 1.25
    private static let spawnZ: Float = -8
    private static let despawnZ: Float = 1.5
    private static let hitZWindow: Float = 0.35
    private static let collectDistance: Float = 0.18
    private static let baseSpeed: Float = 2.2
    private static let maxSpeed: Float = 5.5
    private static let speedRampPerSecond: Float = 0.04
    private static let spawnGapMin: Float = 2.4
    private static let spawnGapMax: Float = 3.6
    private static let coinPoints = 10

    let root = Entity()
    private let headAnchor = AnchorEntity(.head)

    private weak var gameModel: GameModel?
    private var walls: [WallItem] = []
    private var coins: [CoinItem] = []
    private var speed: Float = GameWorld.baseSpeed
    private var distanceUntilSpawn: Float = 1.5
    private var distanceAccumulator: Float = 0
    private var patternIndex = 0
    private var updateSubscription: EventSubscription?
    private var activeRunID: Int = -1

    private let arSession = ARKitSession()
    private let handTracking = HandTrackingProvider()
    private var handTask: Task<Void, Never>?

    private var leftHandPosition: SIMD3<Float>?
    private var rightHandPosition: SIMD3<Float>?

    func attach(to content: RealityViewContent, gameModel: GameModel) {
        self.gameModel = gameModel
        content.add(root)
        content.add(headAnchor)

        if updateSubscription == nil {
            updateSubscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
                self?.tick(deltaTime: Float(event.deltaTime))
            }
        }

        buildStaticEnvironment()
        startHandTracking()
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
        clearDynamicContent()
        for child in root.children {
            child.removeFromParent()
        }
    }

    // MARK: - Setup

    private func buildStaticEnvironment() {
        // One static warm corridor (placeholder for Ember Run).
        guard root.children.isEmpty else { return }

        let floorMesh = MeshResource.generateBox(width: 3.2, height: 0.02, depth: 24)
        let floorMaterial = SimpleMaterial(
            color: UIColor(red: 0.45, green: 0.28, blue: 0.12, alpha: 1),
            roughness: 0.85,
            isMetallic: false
        )
        let floor = ModelEntity(mesh: floorMesh, materials: [floorMaterial])
        floor.position = SIMD3(0, 0, -8)
        root.addChild(floor)

        for lane in Lane.allCases {
            let stripeMesh = MeshResource.generateBox(width: 0.08, height: 0.025, depth: 24)
            let stripeMaterial = SimpleMaterial(
                color: UIColor(red: 1.0, green: 0.72, blue: 0.25, alpha: 0.9),
                roughness: 0.7,
                isMetallic: false
            )
            let stripe = ModelEntity(mesh: stripeMesh, materials: [stripeMaterial])
            stripe.position = SIMD3(lane.x, 0.02, -8)
            root.addChild(stripe)
        }
    }

    private func beginRun(runID: Int) {
        activeRunID = runID
        clearDynamicContent()
        speed = GameWorld.baseSpeed
        distanceUntilSpawn = 1.0
        distanceAccumulator = 0
        patternIndex = 0
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
            spawnWall(blocking: [.left, .center])
            spawnCoin(in: .right)
        }
        patternIndex += 1
    }

    private func spawnWall(blocking lanes: Set<Lane>) {
        let parent = Entity()
        parent.position = SIMD3(0, GameWorld.wallHeight * 0.5, GameWorld.spawnZ)
        parent.name = "wall"

        let red = SimpleMaterial(
            color: UIColor(red: 1, green: 0.15, blue: 0.12, alpha: 0.45),
            roughness: 0.4,
            isMetallic: false
        )

        for lane in lanes {
            let mesh = MeshResource.generateBox(
                width: GameWorld.wallWidth,
                height: GameWorld.wallHeight,
                depth: GameWorld.wallThickness
            )
            let slab = ModelEntity(mesh: mesh, materials: [red])
            slab.position = SIMD3(lane.x, 0, 0)
            parent.addChild(slab)
        }

        root.addChild(parent)
        walls.append(WallItem(entity: parent, blockedLanes: Set(lanes.map(\.rawValue))))
    }

    private func spawnCoin(in lane: Lane) {
        let mesh = MeshResource.generateSphere(radius: GameWorld.coinRadius)
        let material = SimpleMaterial(
            color: UIColor(red: 1, green: 0.84, blue: 0.2, alpha: 1),
            isMetallic: true
        )
        let coin = ModelEntity(mesh: mesh, materials: [material])
        // Offset slightly outward so collecting requires a reach.
        let outward: Float = lane == .center ? 0 : (lane.x > 0 ? 0.2 : -0.2)
        coin.position = SIMD3(lane.x + outward, GameWorld.coinHeight, GameWorld.spawnZ)
        coin.name = "coin"
        root.addChild(coin)
        coins.append(CoinItem(entity: coin))
    }

    // MARK: - Collisions

    private func resolveCollisions(gameModel: GameModel) {
        let head = headAnchor.position(relativeTo: root)

        for index in walls.indices {
            guard !walls[index].hasResolvedHit else { continue }
            let z = walls[index].entity.position.z
            guard abs(z) <= GameWorld.hitZWindow else { continue }

            walls[index].hasResolvedHit = true
            let playerLane = lane(for: head.x)
            if walls[index].blockedLanes.contains(playerLane) {
                gameModel.endRun()
                return
            }
        }

        let hands = [leftHandPosition, rightHandPosition].compactMap { $0 }
        guard !hands.isEmpty else { return }

        for index in coins.indices {
            guard !coins[index].collected else { continue }
            let coinPos = coins[index].entity.position(relativeTo: nil)
            for hand in hands {
                if distance(hand, coinPos) <= GameWorld.collectDistance {
                    coins[index].collected = true
                    coins[index].entity.removeFromParent()
                    gameModel.addScore(GameWorld.coinPoints)
                    break
                }
            }
        }
    }

    private func lane(for x: Float) -> Int {
        if x < -GameWorld.laneSpacing * 0.5 { return Lane.left.rawValue }
        if x > GameWorld.laneSpacing * 0.5 { return Lane.right.rawValue }
        return Lane.center.rawValue
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
