//
//  GameWorld.swift
//  Slipframe
//
//  Mixed-immersive endless runner with rotating biome environments:
//  - Playfield sits on the real floor and locks pose when a run starts
//  - Synth Riders-style portal window at the end of a fixed track
//  - Obstacles emerge from the portal into the real room
//  - Biomes tint ambience / walls / coins
//  - Each biome applies one gameplay twist via EnvironmentDirector
//  Visuals: cached Blender-authored USDZ models (see ASSET_SPEC.md).
//

import ARKit
import QuartzCore
import RealityKit
import simd
import SwiftUI
import UIKit

enum FoundryForceSteering {
    /// A 15 cm wrist movement covers a 75 cm lane; full cross-door moves need about 30 cm.
    static let translationGain: Float = 5.0
    static let maxSpeed: Float = 3.8

    static func target(grabShape: SIMD2<Float>, handDelta: SIMD2<Float>) -> SIMD2<Float> {
        let requested = grabShape + handDelta * translationGain
        return SIMD2(min(1.55, max(-1.55, requested.x)),
                     min(2.05, max(0.52, requested.y)))
    }

    static func advance(position: SIMD2<Float>, velocity: SIMD2<Float>,
                        target: SIMD2<Float>, deltaTime: Float)
        -> (position: SIMD2<Float>, velocity: SIMD2<Float>) {
        var desiredVelocity = (target - position) * 10
        let desiredSpeed = simd_length(desiredVelocity)
        if desiredSpeed > maxSpeed { desiredVelocity *= maxSpeed / desiredSpeed }
        var nextVelocity = velocity
            + (desiredVelocity - velocity) * min(1, deltaTime * 20)
        let speed = simd_length(nextVelocity)
        if speed > maxSpeed { nextVelocity *= maxSpeed / speed }
        return (position + nextVelocity * deltaTime, nextVelocity)
    }
}

/// Once acquired, a lock depends only on wrist position, never on hand orientation.
struct FoundryForceLock {
    static let trackingLossGrace: Float = 2.0
    private var grabHand: SIMD2<Float>
    private var grabShape: SIMD2<Float>
    private(set) var target: SIMD2<Float>
    private(set) var trackingLossSeconds: Float = 0

    init(hand: SIMD3<Float>, shape: SIMD2<Float>) {
        grabHand = SIMD2(hand.x, hand.y)
        grabShape = shape
        target = shape
    }

    /// False only after sustained loss. Fast movement and wrist rotation never release.
    mutating func update(hand: SIMD3<Float>?, deltaTime: Float) -> Bool {
        guard let hand else {
            trackingLossSeconds += deltaTime
            return trackingLossSeconds <= Self.trackingLossGrace
        }
        let handXY = SIMD2(hand.x, hand.y)
        if trackingLossSeconds > 0 {
            // Rebase after occlusion so a corrected tracking pose cannot jump the object.
            grabHand = handXY
            grabShape = target
        }
        trackingLossSeconds = 0
        target = FoundryForceSteering.target(grabShape: grabShape, handDelta: handXY - grabHand)
        return true
    }
}

enum FoundryForceSelection {
    static let aimDot: Float = 0.94

    static func score(head: SIMD3<Float>, hand: SIMD3<Float>, target: SIMD3<Float>,
                      basis: HandPose.ForceBasis?) -> Float? {
        let ray = hand - head
        let toward = target - head
        guard ray.z < -0.12, simd_length(ray) > 0.15, toward.z < -0.4 else { return nil }
        let sight = simd_normalize(ray)
        // Eligibility uses the original headset-through-hand sight line. Joint occlusion
        // or a turned palm must never prevent a tracked hand from acquiring a shape.
        let sightScore = simd_dot(sight, simd_normalize(toward))
        guard sightScore > aimDot else { return nil }
        guard let basis else { return sightScore }
        let fromHand = target - hand
        guard simd_length(fromHand) > 0.001 else { return sightScore }
        let direction = simd_normalize(fromHand)
        let alignment = max(simd_dot(basis.finger, direction), simd_dot(basis.palm, direction))
        guard alignment.isFinite else { return sightScore }
        // Rotation is a small ranking preference between eligible shapes, not a gate.
        return sightScore + min(1, max(0, alignment)) * 0.025
    }

    /// Assign distinct available shapes together so update order cannot favor one hand.
    /// Nil scores mean unavailable, already owned, or outside that hand's acquisition cone.
    static func assign(left: [Float?], right: [Float?]) -> (left: Int?, right: Int?) {
        let leftOptions: [Int?] = [nil] + left.indices.filter { left[$0] != nil }.map { Optional($0) }
        let rightOptions: [Int?] = [nil] + right.indices.filter { right[$0] != nil }.map { Optional($0) }
        var best: (left: Int?, right: Int?) = (nil, nil)
        var bestCount = 0
        var bestScore: Float = -1
        for l in leftOptions {
            for r in rightOptions {
                if let l, let r, l == r { continue }
                let count = (l == nil ? 0 : 1) + (r == nil ? 0 : 1)
                let score = (l.flatMap { left[$0] } ?? 0) + (r.flatMap { right[$0] } ?? 0)
                if count > bestCount || (count == bestCount && score > bestScore) {
                    best = (l, r)
                    bestCount = count
                    bestScore = score
                }
            }
        }
        return best
    }
}

enum FoundryPatternRules {
    static func shapeCountPool(for risk: RiftRisk) -> [Int] {
        switch risk {
        case .stable: return [1, 2, 2]
        case .charged: return [1, 2, 2, 3]
        case .unstable: return [2, 2, 3]
        }
    }
}

enum OrbitGateGeometry {
    static func patternIndex(spawnCount: Int) -> Int {
        spawnCount < 2 ? 0 : (spawnCount - 1) % 3
    }

    /// Positive clearance is inside the visible radial wedge.
    static func timedGapClearance(localX: Float, localY: Float) -> Float {
        let radial = simd_length(SIMD2(localX, localY))
        let angle = atan2(localY, localX)
        return min(min(radial - 0.30, 0.90 - radial),
                   (0.52 - abs(angle)) * 0.6)
    }
}

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

/// Resolves playfield floor Y before / after a real floor plane is available.
enum PlayfieldPlacement {
    /// Used only when a floor plane has not been found yet.
    static let fallbackEyeHeight: Float = 1.55
    /// Headset world Y below this is treated as "pose not ready" (origin / untracked).
    static let minPlausibleHeadWorldY: Float = 0.9

    /// World-space Y for the playfield origin (floor at y=0 in playfield space).
    ///
    /// Prefers a detected floor plane. Otherwise subtracts standing eye height
    /// from a plausible headset Y. If the headset pose is still at the origin
    /// (typical on first immersive-space open), keep Y at 0 — the immersive
    /// origin sits on the real floor — instead of `0 - eyeHeight`, which buries
    /// the track underground until the app is reopened.
    static func floorY(headWorldY: Float, anchoredFloorY: Float?) -> Float {
        if let anchoredFloorY {
            return anchoredFloorY
        }
        if headWorldY >= minPlausibleHeadWorldY {
            return headWorldY - fallbackEyeHeight
        }
        return 0
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
        /// Prior-frame playfield Z for swept head/hand collision (prevents tunneling).
        var previousZ: Float
        /// Logical stream depth in playfield space (advances with travel every frame).
        var playfieldZ: Float
        /// Elapsed emerge time while still inside `portalWorld`; nil once in the room.
        var emergeElapsed: Float?
        /// Resting playfield-space center Y (walls stay portal-parented; Y is converted each frame).
        let emergePlayfieldY: Float
        /// Last applied lighting weight — avoid rewriting the component every tick.
        var lastLightingWeight: Float = -1

        var isEmerging: Bool { emergeElapsed != nil }
        /// Floor-sitting walls grow from the portal lip; duck gates keep a fixed center.
        var anchorsEmergeToFloor: Bool { kind != .duck }

        init(
            entity: Entity,
            localSlabXs: [Float],
            kind: WallKind,
            sealsBetweenSlabs: Bool = false,
            playfieldZ: Float,
            emergePlayfieldY: Float
        ) {
            self.entity = entity
            self.localSlabXs = localSlabXs
            self.kind = kind
            self.sealsBetweenSlabs = sealsBetweenSlabs
            self.playfieldZ = playfieldZ
            self.emergePlayfieldY = emergePlayfieldY
            self.emergeElapsed = 0
            self.previousZ = playfieldZ
        }

        func worldSlabXs() -> [Float] {
            localSlabXs.map { $0 + entity.position.x }
        }
    }

    private struct CoinItem {
        let entity: Entity
        let baseY: Float
        /// Logical stream depth — matches wall spawn lead so coins do not sit inside walls.
        var playfieldZ: Float
        var phase: Float
        var collected = false
        var lastLightingWeight: Float = -1
    }

    private final class HalfCrystalItem {
        let entity: Entity
        let type: CrystalHalfType
        let charged: Bool
        let visualSeed: UInt64
        /// Logical stream depth — matches wall spawn lead.
        var playfieldZ: Float
        var collected = false
        var lastLightingWeight: Float = -1
        /// Airborne spin phase — Crystal Cave halves tumble until grabbed.
        var spinPhase: Float = 0

        init(
            entity: Entity,
            type: CrystalHalfType,
            charged: Bool,
            playfieldZ: Float,
            visualSeed: UInt64
        ) {
            self.entity = entity
            self.type = type
            self.charged = charged
            self.playfieldZ = playfieldZ
            self.visualSeed = visualSeed
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

    private enum FoundryShapeKind: CaseIterable {
        case sphere, cube, diamond

        var assetID: String {
            switch self {
            case .sphere: return "foundry_shape_sphere"
            case .cube: return "foundry_shape_cube"
            case .diamond: return "foundry_shape_diamond"
            }
        }

        var color: UIColor {
            switch self {
            case .sphere: return .systemCyan
            case .cube: return .systemOrange
            case .diamond: return .systemPurple
            }
        }
    }

    private final class FoundryShape {
        let body: Entity
        let core: Entity
        let glow: Entity
        let slot: Entity
        let targetX: Float
        let targetY: Float
        let phase: Float
        var x: Float
        var y: Float
        var target = SIMD2<Float>.zero
        var velocity = SIMD2<Float>.zero
        var heldBy: HandAnchor.Chirality?
        var forceLock: FoundryForceLock?
        var inserting = false
        var insertionProgress: Float = 0
        var resolved = false
        var lightingWeight: Float = -1

        init(body: Entity, core: Entity, glow: Entity, slot: Entity,
             x: Float, y: Float, targetX: Float, targetY: Float, phase: Float) {
            self.body = body
            self.core = core
            self.glow = glow
            self.slot = slot
            self.x = x
            self.y = y
            self.target = SIMD2(x, y)
            self.targetX = targetX
            self.targetY = targetY
            self.phase = phase
        }
    }

    private final class FoundryItem {
        let root: Entity
        let leftPanel: Entity
        let rightPanel: Entity
        let shapes: [FoundryShape]
        let speed: Float
        var z: Float
        var previousZ: Float
        var opening: Float = 0
        var resolved = false
        var lightingWeight: Float = -1

        init(root: Entity, leftPanel: Entity, rightPanel: Entity,
             shapes: [FoundryShape], z: Float, speed: Float) {
            self.root = root
            self.leftPanel = leftPanel
            self.rightPanel = rightPanel
            self.shapes = shapes
            self.z = z
            self.previousZ = z
            self.speed = speed
        }
    }

    private enum OrbitRingStyle {
        case hoop
        case timedGap
    }

    private final class OrbitRing {
        let entity: Entity
        let offsetZ: Float
        let style: OrbitRingStyle
        let axis: SIMD3<Float>
        let phase: Float
        let spin: Float
        let baseRotation: Float
        let swing: Float
        var previousHeadPlaneZ: Float?
        var resolved = false

        init(entity: Entity, offsetZ: Float, style: OrbitRingStyle,
             axis: SIMD3<Float>, phase: Float, spin: Float,
             baseRotation: Float = 0, swing: Float = 0.48) {
            self.entity = entity
            self.offsetZ = offsetZ
            self.style = style
            self.axis = axis
            self.phase = phase
            self.spin = spin
            self.baseRotation = baseRotation
            self.swing = swing
        }
    }

    private final class OrbitItem {
        let root: Entity
        let rings: [OrbitRing]
        var z: Float
        var lightingWeight: Float = -1

        init(root: Entity, rings: [OrbitRing], z: Float) {
            self.root = root
            self.rings = rings
            self.z = z
        }
    }

    private final class JunctionState {
        let root: Entity
        let gates: [Entity]
        let guide: ModelEntity
        let options: [RiftPortalOption]
        var elapsed: Float = 0
        var selectedIndex: Int?
        var didSwapDestinationVisuals = false

        init(root: Entity, gates: [Entity], guide: ModelEntity, options: [RiftPortalOption]) {
            self.root = root
            self.gates = gates
            self.guide = guide
            self.options = options
        }
    }

    /// One authored beat inside a short obstacle phrase. Phrases preserve rhythm
    /// across several spawns while still allowing seeded/random mirroring.
    private struct PhraseBeat {
        var blocking: Set<Lane>
        var reward: Lane?
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
    /// Crystal halves require a close hand touch (fingertips + grip only; never wrist/arm).
    /// Kept tight so distant hands do not grab or trigger the open-hand drop window.
    private static let crystalCollectDistance: Float = 0.16
    /// Constant for every stage and risk tier. Challenge comes from composition, not velocity.
    private static let runSpeed: Float = 3.0
    /// Continuous obstacle stream with a bit of breathing room between beats.
    private static let spawnGapMin: Float = 2.2
    private static let spawnGapMax: Float = 2.9
    /// Ember Run gets a touch more room than the denser biomes.
    private static let emberSpawnGapMin: Float = 2.55
    private static let emberSpawnGapMax: Float = 3.25
    /// Low Crawl / Summit Step need extra reaction time for vertical gates.
    private static let lowCrawlSpawnGapMin: Float = 3.3
    private static let lowCrawlSpawnGapMax: Float = 4.2
    private static let summitStepSpawnGapMin: Float = 3.3
    private static let summitStepSpawnGapMax: Float = 4.2
    /// Nudge adjacent double-lane slabs slightly farther apart (meters each side).
    private static let adjacentPairSpread: Float = 0.09
    /// Extra Z gap when consecutive adjacent doubles open on opposite outer lanes (left↔right).
    private static let oppositeOpenLaneSpacingBonus: Float = 0.35
    /// HUD sits above the corridor, further down the track, clear of the play volume.
    private static let hudPosition = SIMD3<Float>(0, 2.35, -2.7)
    /// Coaching card sits just under the center HUD band.
    private static let tutorialOverlayHUDDrop: Float = 0.28
    /// World scale for the SwiftUI attachment (attachments are small by default).
    private static let hudScale: Float = 2.7
    /// Centered command console (Play / Scores / Settings) at comfortable reach.
    private static let menuConsolePosition = SIMD3<Float>(0, 1.42, -1.9)
    private static let menuConsoleScale: Float = 2.05
    /// Pause after a crash before walls start dissolving.
    private static let gameOverClearDelay: Float = 2.2
    /// Duration of the post-game wall sink / squash animation.
    private static let gameOverClearDuration: Float = 0.9

    // Duck hazard geometry (Low Crawl).
    /// Bottom of the hanging slab — stand through it = hit; duck under to clear.
    private static let duckClearanceY: Float = 1.0
    private static let duckSlabHeight: Float = 0.75
    private static let duckSlabWidth: Float = 2.5
    /// Duck gates use a deeper kill volume so fast approach cannot skip the head.
    private static let duckHitHalfDepth: Float = 0.4
    /// Coins paired with a duck ceiling sit under it; other Low Crawl coins stay normal height.
    private static let lowCrawlCoinHeight: Float = duckClearanceY * 0.65

    // Jump hazard geometry (Summit Step) — Low Crawl's vertical twin.
    /// Very small headset rise above standing eye height that clears a hurdle.
    private static let jumpMinRise: Float = 0.04
    /// Visual hurdle height (short — reads as a step, not a wall).
    private static let jumpSlabHeight: Float = 0.14
    private static let jumpSlabWidth: Float = 2.5
    /// Thin along the track (toward the portal) so the step is a narrow strip.
    private static let jumpSlabDepth: Float = 0.22
    private static let jumpHitHalfDepth: Float = 0.16

    // Synth Riders-style portal aperture (always visible at the track end).
    private static let portalWidth: Float = 3.6
    private static let portalHeight: Float = 2.5
    private static let portalCornerRadius: Float = 0.85
    /// Neon halo that peeks out around the portal mesh.
    private static let portalRimThickness: Float = 0.11
    /// Choice gates fan wider than gameplay lanes so all three worlds remain distinct.
    private static let junctionFanSpacing: Float = 1.02
    /// Prefer snapping the portal onto a real wall in this band.
    private static let portalMinDistance: Float = 3.5
    private static let portalMaxDistance: Float = 10.0
    /// Stream pose just in front of the portal mouth (toward the player) after emerge.
    private static let spawnInFrontOfPortal: Float = 0.35
    private static let wallMinimumBounds = SIMD2<Float>(0.8, 1.5)

    // Fixed track slab from the stand line to just behind the portal.
    private static let trackWidth: Float = 3.2
    /// Scene kit currently displayed; may lead gameplay during a portal crossing.
    private var visualEnvironmentID: EnvironmentID?
    private var lastArtPalette: EnvironmentPalette?
    private var lastArtTelegraph: Int = -1
    private var portalMotions: [AuthoredMotion] = []
    private var junctionMotions: [AuthoredMotion] = []
    /// Track slab extends this far behind the stand line (+Z).
    private static let trackNearZ: Float = 1.1
    /// End the track this far in front of the portal so the slab cannot occlude emerging walls.
    private static let trackEndBeforePortal: Float = 0.12
    /// Used only when a floor plane has not been found yet.
    private static let fallbackEyeHeight: Float = PlayfieldPlacement.fallbackEyeHeight

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
    /// Data Token bob / tumble rates.
    private static let coinBobAmplitude: Float = 0.045
    private static let coinBobSpeed: Float = 2.6
    private static let coinSpinSpeed: Float = 1.8
    private static let coinTumbleSpeed: Float = 1.15
    /// Crystal half airborne spin (Crystal Cave pickups).
    private static let crystalHalfSpinSpeed: Float = 2.4
    private static let foundryShapeDepth: Float = 0.72
    private static let foundryAimDwell: Float = 0.28
    private static let orbitOpeningRadius: Float = 0.67

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
    private let menuConsoleAnchor = Entity()
    private let tutorialOverlayAnchor = Entity()
    private let trackRoot = Entity()
    /// Holds the portal plane + neon rim in playfield space (always visible).
    private let portalRoot = Entity()
    private let portalEntity = Entity()
    private let portalWorld = Entity()
    private let visualFX = VisualFXController()
    private var aegisAura: Entity?

    private weak var gameModel: GameModel?
    private let environmentDirector = EnvironmentDirector()
    private let tutorialDirector = TutorialDirector()
    private var lastPreviewMode: PlayMode?
    private var activeSpawnProfile: EnvironmentProfile = EnvironmentCatalog.profile(for: .emberRun)
    private var lazyLockPose: LazyLockPose?
    private var tutorialHitCooldown: Float = 0
    private var tutorialSpeedMultiplier: Float = 1
    private var tutorialPortalPulse: Float = 0
    private var tutorialSpawningEnabled = true
    private var biomeHintRemaining: Float = 0
    /// nil = settled at rest poses; otherwise seconds into the post-tutorial menu rise.
    private var menuRevealElapsed: Float?
    private static let menuRevealDuration: Float = 1.25
    private static let menuRevealRise: Float = 0.7

    private var walls: [WallItem] = []
    private var coins: [CoinItem] = []
    private var halves: [HalfCrystalItem] = []
    private var foundryItems: [FoundryItem] = []
    private var foundrySpawnCount = 0
    private var orbitItems: [OrbitItem] = []
    private var orbitSpawnCount = 0
    private var heldLeft: HeldHalf?
    private var heldRight: HeldHalf?
    private var leftFoundryHover: FoundryShape?
    private var rightFoundryHover: FoundryShape?
    private var leftFoundryHoverSeconds: Float = 0
    private var rightFoundryHoverSeconds: Float = 0
    private var leftFoundryPositionWorld: SIMD3<Float>?
    private var rightFoundryPositionWorld: SIMD3<Float>?
    private var leftFoundryBasisWorld: HandPose.ForceBasis?
    private var rightFoundryBasisWorld: HandPose.ForceBasis?

    private var speed: Float = GameWorld.runSpeed
    /// 1 while the player is on the play volume; eases to 0 when they step off.
    private var streamFlow = StreamFlow()
    /// First obstacle spawns on the opening tick of a run.
    private var distanceUntilSpawn: Float = 0
    /// Open outer lane raw of the last adjacent double wall (−1 / +1), if any.
    private var lastAdjacentDoubleOpenLaneRaw: Int?
    /// Extra depth for this beat when a left↔right open-lane flip needs more room.
    private var patternSpawnZOffset: Float = 0
    private var phraseQueue: [PhraseBeat] = []
    private var pendingPhraseReward: Lane?
    private var distanceAccumulator: Float = 0
    private var flowDecayAccumulator: Float = 0
    private var junctionQueued = false
    private var junction: JunctionState?
    /// Portal plane depth along playfield −Z.
    private var portalZ: Float = GameWorld.defaultPortalZ
    /// Where obstacles / coins appear (just in front of the portal).
    private var activeSpawnZ: Float = GameWorld.defaultPortalZ + GameWorld.spawnInFrontOfPortal
    private var lastBuiltPortalZ: Float = .greatestFiniteMagnitude
    private var updateSubscription: EventSubscription?
    private var activeRunID: Int = -1
    /// After the initial placement (or an explicit recenter), pose stays fixed.
    private var isPlayfieldLocked = false
    /// True once we've placed using a tracked WorldTracking device anchor.
    private var didSnapWithWorldTracking = false
    /// True once we've placed using a detected floor plane (not eye-height fallback).
    private var didSnapWithFloor = false
    /// True after the playfield has been placed on a real floor plane.
    var hasSnappedToFloor: Bool { didSnapWithFloor }
    /// Standing eye height in playfield space — median of idle headset samples.
    private var standingEyeHeight: Float = GameWorld.fallbackEyeHeight
    /// Rolling headset-Y samples gathered while idle (menu / game over).
    private var standingHeightSamples: [Float] = []
    private var timeUntilStandingSample: Float = 0
    /// Sample standing height every few seconds while not in a run.
    private static let standingSampleInterval: Float = 2.5
    /// Cap the rolling buffer so calibration stays bounded in memory.
    private static let standingSampleCapacity: Int = 100
    /// Seconds since attach — drives portal pulse / ambient motion.
    private var elapsedTime: Float = 0
    /// Elapsed time while game-over clear is armed; nil when inactive.
    private var gameOverClearElapsed: Float?
    private var gameOverClearFinished = false
    /// Snapshotted wall poses at the start of the dissolve animation.
    private var gameOverWallBases: [(entity: Entity, position: SIMD3<Float>, scale: SIMD3<Float>)] = []
    /// Daily-only spawn/wind stream (nil → unseeded SystemRandom for other modes).
    private var gameplayRNG: SeededGenerator?
    /// Purely cosmetic per-instance seed for authored obstacle variants —
    /// deliberately separate from `gameplayRNG` so shape variety never shifts
    /// the deterministic daily-challenge spawn/wind sequence.
    private var visualSeedCounter: UInt64 = 0
    private var sceneryRunSeed: UInt64 = UInt64.random(in: .min ... .max)
    private var sceneryVisit: UInt64 = 0

    private func nextVisualSeed() -> UInt64 {
        visualSeedCounter &+= 0x9E37_79B9_7F4A_7C15
        return visualSeedCounter
    }

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
    /// Crystal Cave half spawn chance per beat.
    private static let crystalHalfSpawnChance: Float = 0.6
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
        didSnapWithWorldTracking = false
        didSnapWithFloor = false
        lastPreviewMode = gameModel.resolvedPlayMode
        elapsedTime = 0
        visualEnvironmentID = nil
        lastArtPalette = nil
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
        ensureMenuConsoleAnchor()
        setTrackVisible(gameModel.showsTrack)
        startARSession()
        // Warm audio before the first coin so setActive does not hitch mid-run.
        GameSFX.shared.prepare()
        GameMusic.shared.prepare()
        applyPalette(environmentDirector.displayedPalette, telegraph: 0)
        // Place once from the current headset pose; do not follow afterward.
        placePlayfield()
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

    func attachMenuConsole(_ entity: Entity) {
        ensureMenuConsoleAnchor()
        entity.orientation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        entity.scale = SIMD3(repeating: GameWorld.menuConsoleScale)
        guard entity.parent !== menuConsoleAnchor else { return }
        entity.removeFromParent()
        menuConsoleAnchor.addChild(entity)
    }

    func attachTutorialOverlay(_ entity: Entity) {
        ensureTutorialOverlayAnchor()
        entity.orientation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        entity.scale = SIMD3(repeating: 1.35)
        guard entity.parent !== tutorialOverlayAnchor else { return }
        entity.removeFromParent()
        tutorialOverlayAnchor.addChild(entity)
    }

    /// Show / hide Ready-state chrome (center console + HUD).
    /// When becoming visible after a tutorial, plays a rise-and-scale reveal.
    func setMenuChromeVisible(_ visible: Bool) {
        ensureHUDAnchor()
        ensureMenuConsoleAnchor()
        menuConsoleAnchor.isEnabled = visible
        hudAnchor.isEnabled = true

        if visible, gameModel?.pendingMenuReveal == true {
            gameModel?.consumeMenuReveal()
            beginMenuReveal()
        } else if !visible {
            menuRevealElapsed = nil
            applyMenuRevealPose(progress: 1)
        } else if menuRevealElapsed == nil {
            applyMenuRevealPose(progress: 1)
        }
    }

    func setTrackVisible(_ visible: Bool) {
        trackRoot.isEnabled = visible
    }

    func setTutorialOverlayVisible(_ visible: Bool) {
        tutorialOverlayAnchor.isEnabled = visible
    }

    /// Idle palette preview when the level-select draft changes.
    func previewPlayMode(_ mode: PlayMode) {
        guard gameModel?.isPlaying != true else { return }
        guard mode != lastPreviewMode else { return }
        lastPreviewMode = mode
        environmentDirector.previewMode(mode)
        activeSpawnProfile = environmentDirector.currentProfile
        applyPalette(environmentDirector.displayedPalette, telegraph: 0)
        syncRoomDimming()
    }

    func syncRun(with gameModel: GameModel) {
        self.gameModel = gameModel
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
        leftFoundryHover = nil
        rightFoundryHover = nil
        leftFoundryHoverSeconds = 0
        rightFoundryHoverSeconds = 0
        leftFoundryPositionWorld = nil
        rightFoundryPositionWorld = nil
        leftFoundryBasisWorld = nil
        rightFoundryBasisWorld = nil
        updateSubscription = nil
        isPlayfieldLocked = false
        didSnapWithWorldTracking = false
        didSnapWithFloor = false
        elapsedTime = 0
        portalZ = GameWorld.defaultPortalZ
        activeSpawnZ = GameWorld.defaultPortalZ + GameWorld.spawnInFrontOfPortal
        lastBuiltPortalZ = .greatestFiniteMagnitude
        visualFX.clear()
        aegisAura?.removeFromParent()
        aegisAura = nil
        resetGameOverClear()
        clearJunction()
        portalMotions.removeAll()
        clearDynamicContent()
        dropHeldHalves()
        foundrySpawnCount = 0
        orbitSpawnCount = 0
        gameplayRNG = nil
        gameModel?.prefersRoomDimming = false
        gameModel?.clearTutorialOverlay()
        tutorialDirector.stop()
        GameMusic.shared.stop()
        for child in hudAnchor.children {
            child.removeFromParent()
        }
        for child in menuConsoleAnchor.children {
            child.removeFromParent()
        }
        for child in tutorialOverlayAnchor.children {
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
        // Don't stomp an in-flight post-tutorial reveal pose.
        if menuRevealElapsed == nil {
            hudAnchor.position = GameWorld.hudPosition
            hudAnchor.scale = SIMD3(repeating: 1)
        }
        if hudAnchor.parent !== root {
            root.addChild(hudAnchor)
        }
    }

    private func ensureMenuConsoleAnchor() {
        menuConsoleAnchor.name = "menuConsole"
        if menuRevealElapsed == nil {
            menuConsoleAnchor.position = GameWorld.menuConsolePosition
            menuConsoleAnchor.scale = SIMD3(repeating: 1)
        }
        if menuConsoleAnchor.parent !== root {
            root.addChild(menuConsoleAnchor)
        }
    }

    private func ensureTutorialOverlayAnchor() {
        tutorialOverlayAnchor.name = "tutorialOverlay"
        // Seed under the HUD; lazy-lock retargets XZ while active.
        if tutorialOverlayAnchor.parent !== root {
            tutorialOverlayAnchor.position = SIMD3(
                0,
                GameWorld.hudPosition.y - GameWorld.tutorialOverlayHUDDrop,
                -1.8
            )
            root.addChild(tutorialOverlayAnchor)
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

        // Stop short of the aperture — a track that crosses the portal lip hides wall bottoms.
        let farZ = portalZ + GameWorld.trackEndBeforePortal
        let nearZ = GameWorld.trackNearZ
        let depth = max(1.0, nearZ - farZ)
        let centerZ = (nearZ + farZ) * 0.5

        let track = GameVisualBuilders.makeTrack(
            width: GameWorld.trackWidth,
            depth: depth,
            laneXs: Lane.allCases.map(\.x),
            biome: visualEnvironmentID ?? environmentDirector.currentID
        )
        track.position = SIMD3(0, 0, centerZ)
        trackRoot.addChild(track)
        lastArtPalette = nil
    }

    /// Always-on Synth Riders-style aperture at the end of the track.
    private func buildPortal() {
        portalRoot.name = "portalRoot"
        portalEntity.name = "portal"
        portalWorld.name = "portalWorld"
        portalWorld.components.set(WorldComponent())

        // Exported mask matches the authored frame and has baked Y-up vertices.
        let portalMesh = BiomeAssetCatalog.mesh("rift_aperture") ?? MeshResource.generatePlane(
            width: GameWorld.portalWidth,
            height: GameWorld.portalHeight,
            cornerRadius: GameWorld.portalCornerRadius
        )
        // Plane faces +Z (toward the player looking down −Z).
        portalEntity.components.set(
            ModelComponent(mesh: portalMesh, materials: [PortalMaterial()])
        )
        // Clipping keeps tunnel content inside the aperture; crossing lets thick
        // walls exit into the room without z-fighting / flicker at the plane.
        portalEntity.components.set(
            PortalComponent(
                target: portalWorld,
                clippingMode: .plane(.positiveZ),
                crossingMode: .plane(.positiveZ)
            )
        )

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
        lastArtPalette = nil
    }

    /// Dark tunnel visible only through the portal — blocks passthrough cleanly.
    private func buildPortalInterior() {
        // Only replace the tunnel mesh — emerging walls are also parented under portalWorld.
        if let existing = portalWorld.children.first(where: { $0.name == "portalInterior" }) {
            existing.removeFromParent()
        }
        let interior = GameVisualBuilders.makePortalInterior(
            portalHeight: GameWorld.portalHeight,
            biome: visualEnvironmentID ?? environmentDirector.currentID,
            scenerySeed: sceneryRunSeed ^ (sceneryVisit &* 0x9E37_79B9_7F4A_7C15)
        )
        portalWorld.addChild(interior)
        portalMotions = BiomeAssetCatalog.motionBindings(in: interior)
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
        // Restart must not move the track — pose stays from session start / last recenter.
        if !isPlayfieldLocked {
            placePlayfield()
        }
        visualFX.clear()
        aegisAura?.removeFromParent()
        aegisAura = nil
        resetGameOverClear()
        clearJunction()
        clearDynamicContent()
        dropHeldHalves()
        leftFoundryHover = nil
        rightFoundryHover = nil
        leftFoundryHoverSeconds = 0
        rightFoundryHoverSeconds = 0
        leftFoundryPositionWorld = nil
        rightFoundryPositionWorld = nil
        leftFoundryBasisWorld = nil
        rightFoundryBasisWorld = nil
        foundrySpawnCount = 0
        orbitSpawnCount = 0
        let mode = gameModel?.resolvedPlayMode ?? .normal
        configureGameplayRNG(for: mode)
        resetWind()
        lastPreviewMode = mode
        environmentDirector.beginRun(mode: mode)
        activeSpawnProfile = environmentDirector.currentProfile
        updateBiomeHint()
        if activeSpawnProfile.twist == .windShove {
            timeUntilWind = nextFloat(in: 1.0...2.0)
        }
        buildPortalRim()
        applyPalette(environmentDirector.displayedPalette, telegraph: 0)
        layoutPortal()
        tutorialHitCooldown = 0
        tutorialSpeedMultiplier = 1
        tutorialPortalPulse = 0
        tutorialSpawningEnabled = true
        lazyLockPose = nil
        streamFlow.reset()
        GameMusic.shared.resetPlaybackFlow()
        if mode == .tutorial {
            tutorialDirector.begin()
            let first = tutorialDirector.currentSection
            tutorialSpeedMultiplier = first.speedMultiplier
            if let environment = first.environment {
                environmentDirector.forceEnvironment(environment, telegraph: false)
                activeSpawnProfile = environmentDirector.currentProfile
            }
            GameMusic.shared.prepare()
            _ = GameMusic.shared.playFromStart(TutorialMusic.cue, loop: false)
            gameModel?.applyTutorialOverlay(
                title: first.title,
                body: first.body,
                opacity: 1,
                banner: nil
            )
            setTutorialOverlayVisible(true)
            // Brief empty beat so the first wall isn't on top of the player.
            distanceUntilSpawn = 1.6
        } else {
            tutorialDirector.stop()
            gameModel?.clearTutorialOverlay()
            setTutorialOverlayVisible(false)
            distanceUntilSpawn = 0
            GameMusic.shared.prepare()
        }
        speed = GameWorld.runSpeed * tutorialSpeedMultiplier
        distanceAccumulator = 0
        flowDecayAccumulator = 0
        junctionQueued = false
        lastAdjacentDoubleOpenLaneRaw = nil
        patternSpawnZOffset = 0
        phraseQueue.removeAll()
        pendingPhraseReward = nil
        visualFX.prepare()
        GameSFX.shared.prepare()
    }

    // MARK: - Normal-mode physical junctions

    private func beginJunction() {
        guard junction == nil, junctionQueued else { return }
        junctionQueued = false
        dropHeldHalves()
        resetWind()
        // The recovery window is intentionally silent. The next biome track starts
        // only after the player has physically passed through the chosen gate.
        GameMusic.shared.stop()

        let options: [RiftPortalOption]
        var rng = SystemRandomNumberGenerator()
        options = RiftJunctionRules.makeOptions(
            excluding: environmentDirector.currentID,
            rng: &rng
        )

        let junctionRoot = Entity()
        junctionRoot.name = "riftJunction"
        let guideDepth = max(1, -portalZ)
        let guide = ModelEntity(
            mesh: MeshResource.generateBox(width: 0.075, height: 0.014, depth: guideDepth),
            materials: [GameMaterials.laneCore()]
        )
        guide.name = "junctionSelectionGuide"
        guide.position = SIMD3(0, 0.045, portalZ * 0.5)
        junctionRoot.addChild(guide)
        var gates: [Entity] = []
        for index in options.indices {
            let gate = GameVisualBuilders.makeJunctionPortal(
                option: options[index],
                seed: nextVisualSeed()
            )
            gate.position = SIMD3(
                Float(index - 1) * GameWorld.junctionFanSpacing,
                GameWorld.portalHeight * 0.5,
                portalZ + 0.08
            )
            junctionRoot.addChild(gate)
            gates.append(gate)
        }
        root.addChild(junctionRoot)
        junction = JunctionState(root: junctionRoot, gates: gates, guide: guide, options: options)
        junctionMotions = BiomeAssetCatalog.motionBindings(in: junctionRoot)
        gameModel?.isChoosingPortal = true
        GameSFX.shared.playJunctionOpen()
    }

    private func updateJunction(deltaTime: Float, head: SIMD3<Float>, gameModel: GameModel) {
        guard let junction else { return }
        junction.elapsed += max(0, deltaTime)
        let choiceDuration = RiftJunctionRules.choiceSeconds
        let commitTime = choiceDuration - RiftJunctionRules.commitLeadSeconds

        // Keep the source rift alive while its three destinations travel outward.
        // A small synchronized pulse reads as a temporary branching state without
        // replacing or hiding the landmark at the end of the track.
        let sourcePulse: Float = 1.0 + 0.035 * sin(junction.elapsed * 2.4)
        portalRoot.scale = SIMD3(repeating: sourcePulse)

        if junction.selectedIndex == nil {
            let t: Float = min(1, junction.elapsed / choiceDuration)
            // Linear travel is deliberate: the gates always drift toward the player
            // and never appear to park before a separate teleport animation.
            let approachZ = portalZ + 0.08 + (head.z - 0.18 - portalZ) * t
            let hovered = RiftJunctionRules.nearestOptionIndex(
                headX: head.x,
                laneSpacing: GameWorld.laneSpacing
            )
            let guideX = Float(hovered - 1) * GameWorld.laneSpacing
            junction.guide.position.x += (guideX - junction.guide.position.x) * min(1, deltaTime * 9)
            let guideTint = EnvironmentCatalog.profile(
                for: junction.options[hovered].environment
            ).palette.laneStripe
            junction.guide.model?.materials = [
                GameMaterials.laneCore(tint: EnvironmentMaterials.uiColor(guideTint))
            ]
            let guidePulse: Float = 1 + 0.18 * sin(elapsedTime * 4)
            junction.guide.scale = SIMD3(guidePulse, 1, 1)

            for index in junction.gates.indices {
                let gate = junction.gates[index]
                GameVisualBuilders.animatePortalEnergy(in: gate, name: "junctionEnergy", time: elapsedTime + Float(index), speed: 0.22)
                gate.position.z = approachZ
                let highlighted = index == hovered
                let breathe: Float = 1 + 0.018 * sin(elapsedTime * 2.1 + Float(index))
                let emphasis: Float = highlighted && t > 0.35 ? 1.1 : 1
                let targetScale = SIMD3<Float>(repeating: breathe * emphasis)
                gate.scale += (targetScale - gate.scale) * min(1, deltaTime * 8)

                if let world = gate.children.first(where: { $0.name == "junctionDestinationWorld" }),
                   let interior = world.children.first(where: { $0.name == "portalInterior" }) {
                    animateRiftMotes(in: interior)
                }
                if let markers = gate.children.first(where: { $0.name == "junctionDifficultyMarkers" }) {
                    let pulse: Float = 1 + 0.055 * sin(elapsedTime * 3 + Float(index))
                    markers.scale = SIMD3<Float>(repeating: pulse)
                }
                if let glyph = gate.children.first(where: { $0.name == "junctionModifierGlyph" }) {
                    let pulse: Float = 1 + 0.045 * sin(elapsedTime * 2.7 + Float(index))
                    glyph.scale = SIMD3<Float>(repeating: pulse)
                }
            }

            if junction.elapsed >= commitTime {
                junction.selectedIndex = hovered
                GameSFX.shared.playJunctionCommit(
                    risk: junction.options[hovered].risk,
                    laneIndex: hovered
                )
            }
            return
        }

        guard let selected = junction.selectedIndex else { return }
        let crossingElapsed = junction.elapsed - commitTime
        let t: Float = min(1, crossingElapsed / RiftJunctionRules.crossingSeconds)
        let option = junction.options[selected]

        // The selected aperture is already directly in front of the player here.
        // Swap the distant rift while it is occluded, then hold the destination
        // palette behind the crossing so its reveal feels instantaneous.
        if !junction.didSwapDestinationVisuals {
            environmentDirector.revealNormalDestinationPalette(option.environment)
            junction.didSwapDestinationVisuals = true
        }
        applyPalette(EnvironmentCatalog.profile(for: option.environment).palette, telegraph: 0)

        for index in junction.gates.indices {
            let gate = junction.gates[index]
            // Continue the same forward velocity after commitment. Passing the
            // aperture is the transition; there is no scale-up or camera engulf.
            gate.position.z = head.z - 0.28 + t * 0.48
            if index == selected {
                gate.position.x += (head.x - gate.position.x) * min(1, deltaTime * 7)
                let crossingPulse: Float = 1.1 + 0.07 * sin(t * Float.pi)
                gate.scale = SIMD3<Float>(repeating: crossingPulse)
                gate.children.first(where: { $0.name == "junctionCrossingVeil" })?.isEnabled = true
            } else {
                let direction: Float = index < selected ? -1 : 1
                gate.position.x += direction * deltaTime * 1.5
                gate.scale = SIMD3<Float>(repeating: 0.96)
            }
        }

        guard t >= 1 else { return }
        junction.root.removeFromParent()
        self.junction = nil
        junctionMotions.removeAll()
        portalRoot.scale = SIMD3(repeating: 1)
        gameModel.isChoosingPortal = false
        environmentDirector.chooseNormalEnvironment(option.environment)
        activeSpawnProfile = environmentDirector.currentProfile
        updateBiomeHint()
        gameModel.configureStage(risk: option.risk, modifier: option.modifier)
        gameModel.recordPortalCrossing()
        phraseQueue.removeAll()
        pendingPhraseReward = nil
        if activeSpawnProfile.twist == .windShove {
            timeUntilWind = nextFloat(in: 1.2...2.5)
        }
        applyPalette(environmentDirector.displayedPalette, telegraph: 0)
        distanceUntilSpawn = 2.2
        GameMusic.shared.resetPlaybackFlow()
    }

    /// Re-snap the track to the current headset pose (use after the user recenters their origin).
    func recalibratePlayfield() {
        placePlayfield()
    }

    // MARK: - Palette / room dimming

    private func applyPalette(_ palette: EnvironmentPalette, telegraph: Float) {
        let destination: EnvironmentID
        if let junction, junction.didSwapDestinationVisuals, let selected = junction.selectedIndex {
            destination = junction.options[selected].environment
        } else {
            destination = environmentDirector.currentID
        }
        if visualEnvironmentID != destination {
            visualEnvironmentID = destination
            sceneryVisit &+= 1
            buildPortalInterior()
            rebuildFixedTrack(force: true)
            lastArtPalette = nil
        }

        // Avoid traversing imported hierarchies or allocating new materials every
        // frame once the palette settles. Quantize only the brief switch pulse.
        let pulseStep = Int(min(1, max(0, telegraph)) * 16)
        if lastArtPalette != palette || lastArtTelegraph != pulseStep {
            lastArtPalette = palette
            lastArtTelegraph = pulseStep
            BiomeAssetCatalog.tint(trackRoot, role: "tint_lane",
                                   color: EnvironmentMaterials.uiColor(palette.laneStripe))
            if let rim = portalRoot.children.first(where: { $0.name == "portalRim" }) {
                let color = EnvironmentMaterials.uiColor(palette.portalRim)
                let hot = EnvironmentMaterials.lerpColor(color, .white, 0.35 + Float(pulseStep) / 40)
                BiomeAssetCatalog.tint(rim, role: "tint_rim", color: color)
                BiomeAssetCatalog.tint(rim, role: "tint_hot", color: hot)
            }
        }
        syncRoomDimming()
    }

    /// Room dimming is unused by the current biome roster; keep passthrough clear.
    private func syncRoomDimming() {
        guard let gameModel else { return }
        if gameModel.prefersRoomDimming {
            gameModel.prefersRoomDimming = false
        }
    }

    // MARK: - Playfield pose

    private var hasTrackedDeviceAnchor: Bool {
        worldTracking.state == .running
            && worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime())?.isTracked == true
    }

    /// Places the playfield from the current headset pose and locks it in place.
    private func placePlayfield() {
        let usedWorldTracking = hasTrackedDeviceAnchor
        let usedFloor = floorAnchor.isAnchored
        snapPlayfieldToPlayer()
        // Seed standing-height calibration from the placement pose.
        standingHeightSamples.removeAll()
        standingEyeHeight = PlayfieldPlacement.fallbackEyeHeight
        recordStandingHeightSample(playfieldHeadPosition().y)
        timeUntilStandingSample = GameWorld.standingSampleInterval
        updatePortalAndTrack()
        rebuildFixedTrack(force: true)
        isPlayfieldLocked = true
        didSnapWithWorldTracking = usedWorldTracking
        didSnapWithFloor = usedFloor
    }

    /// While idle, sample headset height every few seconds and use the median
    /// as standing eye height so Summit Step jumps aren't calibrated off a bob.
    private func updateStandingHeightCalibration(deltaTime: Float) {
        timeUntilStandingSample -= deltaTime
        guard timeUntilStandingSample <= 0 else { return }
        timeUntilStandingSample = GameWorld.standingSampleInterval
        recordStandingHeightSample(playfieldHeadPosition().y)
    }

    private func recordStandingHeightSample(_ headY: Float) {
        guard JumpHeightDetection.isPlausibleStandingHeight(headY) else { return }
        standingHeightSamples.append(headY)
        if standingHeightSamples.count > GameWorld.standingSampleCapacity {
            standingHeightSamples.removeFirst(
                standingHeightSamples.count - GameWorld.standingSampleCapacity
            )
        }
        if let median = JumpHeightDetection.medianHeight(of: standingHeightSamples) {
            standingEyeHeight = median
        }
    }

    /// One-time upgrades after the initial placement:
    /// - head-anchor fallback → WorldTracking once the device is tracked
    /// - eye-height fallback → real floor once a floor plane is anchored
    /// Idle: full re-place. Mid-run: only lift/drop onto the floor so XZ/yaw stay put.
    private func upgradePlayfieldIfNeeded() {
        guard isPlayfieldLocked else { return }

        let needsWorldTrackingUpgrade = !didSnapWithWorldTracking && hasTrackedDeviceAnchor
        let needsFloorUpgrade = !didSnapWithFloor && floorAnchor.isAnchored
        guard needsWorldTrackingUpgrade || needsFloorUpgrade else { return }

        if gameModel?.isPlaying == true {
            if needsFloorUpgrade {
                snapPlayfieldToFloorY()
            }
            return
        }

        placePlayfield()
    }

    /// Mid-run floor correction: keep XZ/yaw, move only Y onto the detected plane.
    private func snapPlayfieldToFloorY() {
        guard floorAnchor.isAnchored else { return }
        let floorY = floorAnchor.position(relativeTo: nil).y
        var position = root.position(relativeTo: nil)
        if abs(position.y - floorY) > 0.01 {
            position.y = floorY
            root.setPosition(position, relativeTo: nil)
            standingHeightSamples.removeAll()
            standingEyeHeight = PlayfieldPlacement.fallbackEyeHeight
            recordStandingHeightSample(playfieldHeadPosition().y)
            timeUntilStandingSample = GameWorld.standingSampleInterval
        }
        didSnapWithFloor = true
    }

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

        let anchoredFloorY: Float? = floorAnchor.isAnchored
            ? floorAnchor.position(relativeTo: nil).y
            : nil
        let floorY = PlayfieldPlacement.floorY(
            headWorldY: headWorld.y,
            anchoredFloorY: anchoredFloorY
        )

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
        for item in foundryItems {
            item.root.removeFromParent()
            for shape in item.shapes { shape.body.removeFromParent() }
        }
        for item in orbitItems {
            item.root.removeFromParent()
        }
        walls.removeAll()
        coins.removeAll()
        halves.removeAll()
        foundryItems.removeAll()
        orbitItems.removeAll()
        gameOverWallBases = []
        lastAdjacentDoubleOpenLaneRaw = nil
        patternSpawnZOffset = 0
        gustEntity?.removeFromParent()
        gustEntity = nil
    }

    private func clearJunction() {
        junction?.root.removeFromParent()
        junction = nil
        junctionMotions.removeAll()
        junctionQueued = false
        portalRoot.isEnabled = true
        portalRoot.scale = SIMD3(repeating: 1)
        gameModel?.isChoosingPortal = false
    }

    private func resetGameOverClear() {
        gameOverClearElapsed = nil
        gameOverClearFinished = false
        gameOverWallBases = []
    }

    /// After a crash, hold for a beat, then squash/sink walls away and clear the field.
    private func tickGameOverClear(deltaTime: Float) {
        guard !gameOverClearFinished else { return }
        if gameOverClearElapsed == nil {
            gameOverClearElapsed = 0
        }
        gameOverClearElapsed! += max(0, deltaTime)
        let elapsed = gameOverClearElapsed!

        guard elapsed >= GameWorld.gameOverClearDelay else { return }

        let animT = elapsed - GameWorld.gameOverClearDelay
        if gameOverWallBases.isEmpty, !walls.isEmpty {
            // Finish any in-flight emerges before capturing dissolve bases.
            for wall in walls where wall.isEmerging {
                finishWallEmerge(wall)
            }
            gameOverWallBases = walls.map { wall in
                (wall.entity, wall.entity.position, wall.entity.scale)
            }
        }

        if animT >= GameWorld.gameOverClearDuration || walls.isEmpty {
            clearDynamicContent()
            gameOverClearFinished = true
            // Tutorial skip reuses this dissolve, then hands back to the ready menu.
            if gameModel?.isTutorialRun == true {
                gameModel?.finalizeTutorialSkip()
            } else {
                // Publishing this state starts the existing rise/scale console reveal.
                gameModel?.revealGameOverMenu()
            }
            return
        }

        let u = min(1, animT / GameWorld.gameOverClearDuration)
        // Smoothstep ease-in-out.
        let ease = u * u * (3 - 2 * u)
        for base in gameOverWallBases {
            let scaleY = max(0.02, 1 - ease)
            base.entity.scale = SIMD3(
                base.scale.x * (1 + ease * 0.2),
                base.scale.y * scaleY,
                base.scale.z * (1 + ease * 0.12)
            )
            var position = base.position
            position.y -= ease * 1.5
            base.entity.position = position
        }

        // Soften leftover pickups in the same window.
        let pickupScale = max(0.02, 1 - ease)
        for coin in coins {
            coin.entity.scale = SIMD3(repeating: pickupScale)
        }
        for half in halves where !half.collected {
            half.entity.scale = SIMD3(repeating: pickupScale)
        }
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
                            leftFoundryPositionWorld = nil
                            leftFoundryBasisWorld = nil
                        case .right:
                            rightHandContactsWorld = []
                            rightHandGripWorld = nil
                            rightIsOpen = false
                            rightFoundryPositionWorld = nil
                            rightFoundryBasisWorld = nil
                        @unknown default: break
                        }
                        continue
                    }
                    let contacts = Self.contactPoints(from: anchor)
                    let grip = Self.gripPoint(from: anchor)
                    let pose = HandPose.classify(anchor: anchor)
                    let forceBasis = HandPose.forceBasis(anchor: anchor)
                    switch anchor.chirality {
                    case .left:
                        leftHandContactsWorld = contacts
                        leftHandGripWorld = grip
                        leftIsOpen = pose == .open
                        leftFoundryPositionWorld = HandPose.forcePosition(anchor: anchor)
                        leftFoundryBasisWorld = forceBasis
                    case .right:
                        rightHandContactsWorld = contacts
                        rightHandGripWorld = grip
                        rightIsOpen = pose == .open
                        rightFoundryPositionWorld = HandPose.forcePosition(anchor: anchor)
                        rightFoundryBasisWorld = forceBasis
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
        animateHalves(deltaTime: deltaTime)
        visualFX.tick(deltaTime: deltaTime)

        // Pose is fixed after the initial placement. Allow one-time upgrades
        // from head-anchor / eye-height fallbacks once WorldTracking or a
        // floor plane becomes available (full re-place while idle; Y-only
        // during a run so a late floor detection can un-bury the track).
        upgradePlayfieldIfNeeded()

        guard let gameModel else { return }
        syncAegisAura(gameModel: gameModel)

        // Calibrate standing height on the menu / after a run — freeze during play
        // so a jump cannot raise the baseline mid-hurdle.
        if !gameModel.isPlaying {
            updateStandingHeightCalibration(deltaTime: deltaTime)
        }

        guard gameModel.isPlaying, !gameModel.isGameOver else {
            if gameModel.prefersRoomDimming {
                gameModel.prefersRoomDimming = false
            }
            if tutorialDirector.isActive {
                // Interrupted exit (skip / dismiss). Natural finish already stopped the director.
                tutorialDirector.stop()
                tutorialPortalPulse = 0
                tutorialSpeedMultiplier = 1
                tutorialSpawningEnabled = true
                lazyLockPose = nil
                setTutorialOverlayVisible(false)
                gameModel.clearTutorialOverlay()
            }
            // Keep animating the post-tutorial menu rise while idle.
            tickMenuReveal(deltaTime: deltaTime)
            if gameModel.isGameOver {
                tickGameOverClear(deltaTime: deltaTime)
            } else {
                resetGameOverClear()
            }
            if streamFlow.scale < 1 {
                streamFlow.reset()
                GameMusic.shared.resetPlaybackFlow()
            }
            return
        }
        // Clamp hitch frames instead of skipping them — a discarded tick freezes walls.
        guard let dt = GameTiming.clampedGameplayDelta(deltaTime) else { return }

        let inBounds = PlayfieldVolume.containsHead(playfieldHeadPosition())
        if gameModel.isOffPlayfield == inBounds {
            gameModel.isOffPlayfield = !inBounds
        }
        streamFlow.update(inBounds: inBounds, deltaTime: dt)
        let motion = streamFlow.motionScale
        GameMusic.shared.setPlaybackFlow(motion)
        let simDt = dt * motion

        if gameModel.isTutorialRun {
            tickTutorial(gameModel: gameModel, deltaTime: simDt)
            // Outro may finish the run mid-frame.
            guard gameModel.isPlaying else { return }
        }

        let frame = environmentDirector.update(deltaTime: simDt)
        if frame.requestsJunction {
            // Finish the currently readable beat before presenting the restful choice.
            junctionQueued = true
            distanceUntilSpawn = .greatestFiniteMagnitude
        }
        if frame.didEnterEnvironment {
            activeSpawnProfile = frame.profile
            updateBiomeHint()
            dropHeldHalves()
            for item in foundryItems {
                for shape in item.shapes { shape.heldBy = nil }
            }
            leftFoundryHover = nil
            rightFoundryHover = nil
            leftFoundryHoverSeconds = 0
            rightFoundryHoverSeconds = 0
            leftFoundryPositionWorld = nil
            rightFoundryPositionWorld = nil
            leftFoundryBasisWorld = nil
            rightFoundryBasisWorld = nil
            foundrySpawnCount = 0
            orbitSpawnCount = 0
            if frame.profile.twist != .windShove {
                resetWind()
            } else {
                timeUntilWind = nextFloat(in: 1.2...2.5)
            }
        }
        let telegraph = max(frame.telegraphStrength, tutorialPortalPulse)
        applyPalette(frame.displayedPalette, telegraph: telegraph)
        if biomeHintRemaining > 0 {
            biomeHintRemaining = max(0, biomeHintRemaining - simDt)
            if biomeHintRemaining == 0 { gameModel.biomeHint = nil }
        }

        if junction != nil {
            updateJunction(deltaTime: dt, head: playfieldHeadPosition(), gameModel: gameModel)
            return
        }

        if tutorialHitCooldown > 0 {
            tutorialHitCooldown = max(0, tutorialHitCooldown - simDt)
        }

        // Never ramp with elapsed time or chosen risk. Tutorial may temporarily slow it.
        let travel = speed * simDt
        speed = GameWorld.runSpeed * tutorialSpeedMultiplier

        distanceAccumulator += travel
        if distanceAccumulator >= 1 {
            let gained = Int(distanceAccumulator)
            distanceAccumulator -= Float(gained)
            gameModel.addScore(gained)
        }

        flowDecayAccumulator += simDt
        let scoreBonusDecayInterval = gameModel.stats.modifier?.scoreBonusDecayInterval ?? 0.75
        if flowDecayAccumulator >= scoreBonusDecayInterval {
            gameModel.decayFlow()
            flowDecayAccumulator -= scoreBonusDecayInterval
        }

        advanceEntities(by: travel, deltaTime: simDt)
        updateFoundry(deltaTime: simDt, gameModel: gameModel)
        updateOrbitGates(deltaTime: simDt, gameModel: gameModel)
        updateWind(deltaTime: simDt)
        // Grab before hold-update so a newly closed hand can pick up this frame.
        if activeSpawnProfile.twist == .crystalHalves {
            tryGrabHalves()
        }
        updateHeldHalves(deltaTime: dt)

        distanceUntilSpawn -= travel
        if !junctionQueued, tutorialSpawningEnabled, motion > StreamFlow.stopThreshold, distanceUntilSpawn <= 0 {
            patternSpawnZOffset = 0
            spawnNextPattern()
            // Preserve spacing to the following beat when this one was pushed deeper.
            distanceUntilSpawn = spawnGap(for: activeSpawnProfile) + patternSpawnZOffset
        }

        resolveCollisions(gameModel: gameModel)
        pruneEntities()
        if junctionQueued, environmentDirector.hasReachedNormalMusicEnd {
            // Spawning stopped one full travel time ago. Clear anything already
            // behind the player on the exact audio boundary and enter recovery.
            clearDynamicContent()
            beginJunction()
        }
    }

    private func tickTutorial(gameModel: GameModel, deltaTime: Float) {
        let frame = tutorialDirector.update(deltaTime: deltaTime)
        updateLazyLockedTutorialOverlay(deltaTime: deltaTime)
        setTutorialOverlayVisible(true)

        if frame.didEnterSection {
            tutorialSpeedMultiplier = max(0.01, frame.section.speedMultiplier)
            speed = GameWorld.runSpeed * tutorialSpeedMultiplier
            if let environment = frame.section.environment {
                environmentDirector.forceEnvironment(environment, telegraph: true)
                activeSpawnProfile = environmentDirector.currentProfile
                dropHeldHalves()
                if activeSpawnProfile.twist == .windShove {
                    timeUntilWind = nextFloat(in: 0.8...1.6)
                } else {
                    resetWind()
                }
                applyPalette(environmentDirector.displayedPalette, telegraph: 1)
                // Breathing room between teaching verbs.
                distanceUntilSpawn = max(distanceUntilSpawn, 2.2)
            }
            if frame.section.isOutro {
                tutorialSpawningEnabled = false
                clearDynamicContent()
                dropHeldHalves()
                resetWind()
            }
            if frame.section.portalOverdrive {
                // Kick a visible surge as coaching UI dissolves.
                distanceUntilSpawn = min(distanceUntilSpawn, 0.8)
            }
        }

        tutorialPortalPulse = frame.portalPulse
        gameModel.applyTutorialOverlay(
            title: frame.section.title,
            body: frame.section.body,
            opacity: frame.overlayOpacity,
            banner: frame.successBanner
        )

        if frame.shouldFinish {
            // Leave the master track alone — it already hard-cuts to silence in-file.
            tutorialDirector.stop()
            tutorialPortalPulse = 0
            tutorialSpeedMultiplier = 1
            tutorialSpawningEnabled = true
            setTutorialOverlayVisible(false)
            gameModel.finishTutorial(markCompleted: true, revealMenu: true)
        }
    }

    private func beginMenuReveal() {
        menuRevealElapsed = 0
        applyMenuRevealPose(progress: 0)
        menuConsoleAnchor.isEnabled = true
        hudAnchor.isEnabled = true
    }

    private func tickMenuReveal(deltaTime: Float) {
        guard var elapsed = menuRevealElapsed else { return }
        elapsed += deltaTime
        let t = min(1, elapsed / GameWorld.menuRevealDuration)
        applyMenuRevealPose(progress: easeOutBack(t))
        if t >= 1 {
            menuRevealElapsed = nil
            applyMenuRevealPose(progress: 1)
        } else {
            menuRevealElapsed = elapsed
        }
    }

    /// `progress` 0 = hidden below / tiny, 1 = rest pose.
    private func applyMenuRevealPose(progress: Float) {
        let p = max(0, min(1, progress))
        let rise = GameWorld.menuRevealRise * (1 - p)
        let scaleFactor = max(0.04, p)

        hudAnchor.position = SIMD3(
            GameWorld.hudPosition.x,
            GameWorld.hudPosition.y - rise,
            GameWorld.hudPosition.z
        )
        // Attachment scale is applied on the child; nudge the anchor for the grow.
        hudAnchor.scale = SIMD3(repeating: scaleFactor)

        menuConsoleAnchor.position = SIMD3(
            GameWorld.menuConsolePosition.x,
            GameWorld.menuConsolePosition.y - rise * 1.15,
            GameWorld.menuConsolePosition.z
        )
        menuConsoleAnchor.scale = SIMD3(repeating: scaleFactor)
    }

    private func easeOutBack(_ t: Float) -> Float {
        let c1: Float = 1.70158
        let c3 = c1 + 1
        let u = t - 1
        return 1 + c3 * u * u * u + c1 * u * u
    }

    private func updateLazyLockedTutorialOverlay(deltaTime: Float) {
        ensureTutorialOverlayAnchor()
        let head = playfieldHeadPosition()
        let forward = playfieldFlatForward()
        // Match HUD height (slightly below) so coaching copy sits under the score panel.
        var desired = LazyLock.desiredPose(
            headPosition: head,
            flatForward: forward,
            distance: 1.85,
            drop: 0
        )
        desired.position.y = GameWorld.hudPosition.y - GameWorld.tutorialOverlayHUDDrop
        let next = LazyLock.step(current: lazyLockPose, desired: desired, deltaTime: deltaTime)
        var seated = next
        seated.position.y = desired.position.y
        lazyLockPose = seated
        tutorialOverlayAnchor.position = seated.position
        tutorialOverlayAnchor.orientation = simd_quatf(angle: seated.yaw, axis: SIMD3(0, 1, 0))
    }

    /// Horizontal look direction in playfield space for lazy-lock seating.
    private func playfieldFlatForward() -> SIMD3<Float> {
        if worldTracking.state == .running,
           let device = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()),
           device.isTracked {
            let matrix = device.originFromAnchorTransform
            let headWorld = SIMD3<Float>(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z)
            let forwardWorld = SIMD3<Float>(-matrix.columns.2.x, 0, -matrix.columns.2.z)
            let headLocal = root.convert(position: headWorld, from: nil)
            let aheadLocal = root.convert(position: headWorld + forwardWorld, from: nil)
            var flat = SIMD3<Float>(aheadLocal.x - headLocal.x, 0, aheadLocal.z - headLocal.z)
            let len = length(flat)
            if len < 0.05 { return SIMD3(0, 0, -1) }
            return flat / len
        }

        let headRotation = headAnchor.orientation(relativeTo: root)
        let forward = headRotation.act(SIMD3<Float>(0, 0, -1))
        var flat = SIMD3<Float>(forward.x, 0, forward.z)
        let len = length(flat)
        if len < 0.05 { return SIMD3(0, 0, -1) }
        return flat / len
    }

    // MARK: - Gameplay RNG (Daily seed)

    private func configureGameplayRNG(for mode: PlayMode) {
        switch mode {
        case .daily:
            gameplayRNG = DailyChallenge.makeGameplayGenerator(dayKey: DailyChallenge.dayKey())
            sceneryRunSeed = DailyChallenge.seed(for: DailyChallenge.dayKey())
        case .normal, .solo, .playlist, .tutorial:
            gameplayRNG = nil
            sceneryRunSeed = UInt64.random(in: .min ... .max)
        }
        visualSeedCounter = sceneryRunSeed
        sceneryVisit = 0
        visualEnvironmentID = nil
    }

    private func nextFloat(in range: ClosedRange<Float>) -> Float {
        guard var rng = gameplayRNG else {
            return Float.random(in: range)
        }
        let value = Float.random(in: range, using: &rng)
        gameplayRNG = rng
        return value
    }

    private func nextUnitFloat() -> Float {
        nextFloat(in: 0...1)
    }

    private func nextBool() -> Bool {
        guard var rng = gameplayRNG else {
            return Bool.random()
        }
        let value = Bool.random(using: &rng)
        gameplayRNG = rng
        return value
    }

    private func nextElement<T>(_ items: [T]) -> T? {
        guard !items.isEmpty else { return nil }
        guard var rng = gameplayRNG else {
            return items.randomElement()
        }
        let value = items.randomElement(using: &rng)
        gameplayRNG = rng
        return value
    }

    private func spawnGap(for profile: EnvironmentProfile) -> Float {
        let base: Float
        switch profile.twist {
        case .lowCrawl:
            base = nextFloat(in: GameWorld.lowCrawlSpawnGapMin...GameWorld.lowCrawlSpawnGapMax)
        case .summitStep:
            base = nextFloat(in: GameWorld.summitStepSpawnGapMin...GameWorld.summitStepSpawnGapMax)
        case .telekinesis:
            base = nextFloat(in: 19...21)
        case .orbitGate:
            base = nextFloat(in: 6.0...7.0)
        case .baseline:
            base = nextFloat(in: GameWorld.emberSpawnGapMin...GameWorld.emberSpawnGapMax)
        default:
            base = nextFloat(in: GameWorld.spawnGapMin...GameWorld.spawnGapMax)
        }
        if case .normal? = gameModel?.resolvedPlayMode {
            return base * (gameModel?.stats.risk.spawnGapScale ?? 1)
        }
        return base
    }

    private var collectibleChance: Float {
        guard case .normal? = gameModel?.resolvedPlayMode else { return 0.7 }
        let modifierBonus: Float = gameModel?.stats.modifier == .tokenSurge ? 0.16 : 0
        return min(0.98, 0.7 + (gameModel?.stats.risk.collectibleChanceBonus ?? 0) + modifierBonus)
    }

    private func biomeHazardChance(_ base: Float) -> Float {
        guard case .normal? = gameModel?.resolvedPlayMode else { return base }
        switch gameModel?.stats.risk ?? .stable {
        case .stable: return max(0.28, base - 0.22)
        case .charged: return base
        case .unstable: return min(0.88, base + 0.2)
        }
    }

    private func animatePortal(deltaTime: Float) {
        _ = deltaTime
        guard let rim = portalRoot.children.first(where: { $0.name == "portalRim" }) else { return }
        // The rigid frame and aperture stay aligned; only energy geometry moves.
        GameVisualBuilders.animatePortalEnergy(in: rim, name: "riftEnergyOuter", time: elapsedTime, speed: 0.15)
        GameVisualBuilders.animatePortalEnergy(in: rim, name: "riftEnergyInner", time: elapsedTime, speed: -0.10)
        for motion in portalMotions { motion.update(time: elapsedTime) }
        for motion in junctionMotions { motion.update(time: elapsedTime) }

        if let interior = portalWorld.children.first(where: { $0.name == "portalInterior" }) {
            animateRiftMotes(in: interior)
        }
    }

    /// Ambient dust motes drift in a small loop around their spawn anchor —
    /// the tear keeps leaking energy even when nothing is spawning.
    private func animateRiftMotes(in interior: Entity) {
        for child in interior.children {
            guard child.name == "riftMote",
                  let mote = child.components[RiftMoteComponent.self] else { continue }
            let sample = mote.sample(at: elapsedTime)
            child.position = mote.basePosition + sample.offset
            if mote.falling { child.components.set(OpacityComponent(opacity: sample.opacity)) }
        }
    }

    private func animateCoins(deltaTime: Float) {
        for index in coins.indices {
            guard !coins[index].collected else { continue }
            coins[index].phase += deltaTime
            let phase = coins[index].phase
            let bob = sin(phase * GameWorld.coinBobSpeed) * GameWorld.coinBobAmplitude
            // Data Tokens stay portal-parented — bob in playfield Y, convert to portal-local.
            coins[index].entity.position.y =
                coins[index].baseY + bob - GameWorld.portalHeight * 0.5
            // Multi-axis tumble so the octahedron reads as a floating diamond, not a spinning disc.
            let yaw = simd_quatf(angle: phase * GameWorld.coinSpinSpeed, axis: SIMD3(0, 1, 0))
            let pitch = simd_quatf(angle: phase * GameWorld.coinTumbleSpeed, axis: SIMD3(1, 0, 0))
            let roll = simd_quatf(angle: sin(phase * 0.7) * 0.35, axis: SIMD3(0, 0, 1))
            coins[index].entity.orientation = yaw * pitch * roll

            if let spark = coins[index].entity.children.first(where: { $0.name == "coinSpark" }) {
                let orbit = phase * 3.2
                let r = GameWorld.coinRadius * 0.95
                spark.position = SIMD3(cos(orbit) * r, sin(orbit * 0.7) * r * 0.35, sin(orbit) * r * 0.2)
            }
            if let aura = coins[index].entity.children.first(where: { $0.name == "coinAura" }) {
                let s = 1.0 + 0.12 * sin(phase * 3.5)
                aura.scale = SIMD3(repeating: s)
            }
            if let core = coins[index].entity.children.first(where: { $0.name == "coinCore" }) {
                let pulse = 1.0 + 0.18 * sin(phase * 4.2)
                core.scale = SIMD3(repeating: pulse)
            }
        }
    }

    /// Crystal Cave halves rotate in place until grabbed — sells them as live
    /// holographic shards rather than static props on the stream.
    private func animateHalves(deltaTime: Float) {
        for half in halves {
            guard !half.collected else { continue }
            half.spinPhase += deltaTime
            let spin = half.spinPhase * GameWorld.crystalHalfSpinSpeed
            // Tip slightly so the fracture face stays readable while yawing.
            let tip = simd_quatf(angle: 0.4, axis: SIMD3(1, 0, 0))
            let yaw = simd_quatf(angle: spin, axis: SIMD3(0, 1, 0))
            half.entity.orientation = yaw * tip
        }
    }

    private func advanceEntities(by travel: Float, deltaTime: Float) {
        for wall in walls {
            wall.previousZ = wall.playfieldZ
            wall.playfieldZ += travel
            if wall.isEmerging {
                tickWallEmerge(wall, deltaTime: deltaTime)
            } else {
                // Stay under portalWorld for life — crossing renders them in the room.
                applyPortalWallPose(wall, scale: 1)
                setWallLightingWeight(wall, weight: 1)
            }
        }
        for index in coins.indices {
            guard !coins[index].collected else { continue }
            coins[index].playfieldZ += travel
            coins[index].entity.position.z = coins[index].playfieldZ - portalZ
            setPickupLightingWeight(
                entity: coins[index].entity,
                playfieldZ: coins[index].playfieldZ,
                lastWeight: &coins[index].lastLightingWeight
            )
        }
        for half in halves {
            guard !half.collected else { continue }
            half.playfieldZ += travel
            half.entity.position.z = half.playfieldZ - portalZ
            setPickupLightingWeight(
                entity: half.entity,
                playfieldZ: half.playfieldZ,
                lastWeight: &half.lastLightingWeight
            )
        }
        for item in foundryItems {
            item.previousZ = item.z
            item.z += travel * item.speed / Self.runSpeed
        }
        for item in orbitItems {
            item.z += travel
        }
    }

    private func foundryCandidates() -> (left: FoundryShape?, right: FoundryShape?) {
        let head = playfieldHeadPosition()
        // Finish the nearer puzzle before acquiring shapes behind it.
        guard let door = foundryItems.first(where: {
            $0.z < head.z - 0.65 && $0.opening == 0
                && $0.shapes.contains(where: { !$0.resolved && !$0.inserting })
        }) else { return (nil, nil) }
        let shapes = door.shapes
        func scores(hand: HandAnchor.Chirality, position: SIMD3<Float>?,
                    basis: HandPose.ForceBasis?, hover: FoundryShape?) -> [Float?] {
            let unavailable = [Float?](repeating: nil, count: shapes.count)
            guard !foundryItems.contains(where: { item in
                item.shapes.contains { $0.heldBy == hand && !$0.resolved }
            }), let position else { return unavailable }
            let grip = root.convert(position: position, from: nil)
            let localBasis = foundryBasisInPlayfield(basis, gripWorld: position)
            return shapes.map { shape -> Float? in
                guard !shape.resolved, !shape.inserting, shape.heldBy == nil else { return nil }
                guard let score = FoundryForceSelection.score(
                    head: head, hand: grip,
                    target: SIMD3(shape.x, shape.y, door.z + Self.foundryShapeDepth),
                    basis: localBasis
                ) else { return nil }
                // Small hysteresis keeps a nearly tied target from resetting the dwell.
                return score + (shape === hover ? 0.008 : 0)
            }
        }
        let assignment = FoundryForceSelection.assign(
            left: scores(hand: .left, position: leftHandGripWorld ?? leftFoundryPositionWorld,
                         basis: leftFoundryBasisWorld, hover: leftFoundryHover),
            right: scores(hand: .right, position: rightHandGripWorld ?? rightFoundryPositionWorld,
                          basis: rightFoundryBasisWorld, hover: rightFoundryHover)
        )
        return (assignment.left.map { shapes[$0] }, assignment.right.map { shapes[$0] })
    }

    private func releaseFoundryShape(_ shape: FoundryShape) {
        shape.heldBy = nil
        shape.forceLock = nil
        shape.velocity = .zero
        shape.target = SIMD2(shape.x, shape.y)
        shape.glow.isEnabled = false
    }

    private func foundryBasisInPlayfield(_ basis: HandPose.ForceBasis?,
                                         gripWorld: SIMD3<Float>?) -> HandPose.ForceBasis? {
        guard let basis, let gripWorld else { return nil }
        let origin = root.convert(position: gripWorld, from: nil)
        let finger = root.convert(position: gripWorld + basis.finger, from: nil) - origin
        let palm = root.convert(position: gripWorld + basis.palm, from: nil) - origin
        guard length(finger) > 0.001, length(palm) > 0.001 else { return nil }
        return HandPose.ForceBasis(finger: normalize(finger), palm: normalize(palm))
    }

    private func controlFoundryHand(_ hand: HandAnchor.Chirality,
                                    positionWorld: SIMD3<Float>?, candidate: FoundryShape?,
                                    deltaTime: Float) {
        let grip = positionWorld.map { root.convert(position: $0, from: nil) }
        if let held = foundryItems.flatMap(\.shapes).first(where: { $0.heldBy == hand && !$0.resolved }),
           var lock = held.forceLock {
            guard lock.update(hand: grip, deltaTime: deltaTime) else {
                releaseFoundryShape(held)
                return
            }
            held.forceLock = lock
            held.target = lock.target
            return
        }

        if hand == .left {
            leftFoundryHoverSeconds = candidate === leftFoundryHover
                ? leftFoundryHoverSeconds + deltaTime : 0
            leftFoundryHover = candidate
            guard let candidate, let grip,
                  leftFoundryHoverSeconds >= Self.foundryAimDwell else { return }
            latchFoundryShape(candidate, hand: hand, grip: grip)
            leftFoundryHover = nil
            leftFoundryHoverSeconds = 0
        } else {
            rightFoundryHoverSeconds = candidate === rightFoundryHover
                ? rightFoundryHoverSeconds + deltaTime : 0
            rightFoundryHover = candidate
            guard let candidate, let grip,
                  rightFoundryHoverSeconds >= Self.foundryAimDwell else { return }
            latchFoundryShape(candidate, hand: hand, grip: grip)
            rightFoundryHover = nil
            rightFoundryHoverSeconds = 0
        }
    }

    private func latchFoundryShape(_ shape: FoundryShape,
                                   hand: HandAnchor.Chirality, grip: SIMD3<Float>) {
        guard shape.heldBy == nil, !shape.resolved, !shape.inserting else { return }
        shape.heldBy = hand
        shape.forceLock = FoundryForceLock(hand: grip, shape: SIMD2(shape.x, shape.y))
        shape.target = SIMD2(shape.x, shape.y)
        shape.velocity = .zero
        shape.glow.isEnabled = true
    }

    private func updateFoundry(deltaTime: Float, gameModel: GameModel) {
        if activeSpawnProfile.twist == .telekinesis {
            let candidates = foundryCandidates()
            controlFoundryHand(.left, positionWorld: leftFoundryPositionWorld,
                               candidate: candidates.left, deltaTime: deltaTime)
            controlFoundryHand(.right, positionWorld: rightFoundryPositionWorld,
                               candidate: candidates.right, deltaTime: deltaTime)
        }
        let head = playfieldHeadPosition()
        for door in foundryItems {
            door.root.position.z = door.z - portalZ
            setPickupLightingWeight(entity: door.root, playfieldZ: door.z,
                                    lastWeight: &door.lightingWeight)

            for shape in door.shapes where !shape.resolved {
                if shape.inserting {
                    shape.insertionProgress = min(1, shape.insertionProgress + deltaTime * 2)
                    let progress = shape.insertionProgress
                    shape.body.position = SIMD3(
                        shape.targetX,
                        shape.targetY - Self.portalHeight * 0.5,
                        door.z + Self.foundryShapeDepth * (1 - progress) + 0.13 * progress - portalZ
                    )
                    shape.core.scale = SIMD3(repeating: 1 - 0.2 * progress)
                    if progress >= 1 {
                        shape.resolved = true
                        shape.body.isEnabled = false
                        shape.glow.isEnabled = false
                        shape.slot.scale = SIMD3(repeating: 1.22)
                        visualFX.spawnCoinBurst(at: SIMD3(shape.targetX, shape.targetY, door.z))
                        GameSFX.shared.playCoinCollect()
                        gameModel.collectCoin()
                        gameModel.addScore(8)
                    }
                    continue
                }
                let motion = FoundryForceSteering.advance(
                    position: SIMD2(shape.x, shape.y), velocity: shape.velocity,
                    target: shape.target, deltaTime: deltaTime
                )
                shape.x = motion.position.x
                shape.y = motion.position.y
                shape.velocity = motion.velocity
                let t = elapsedTime + shape.phase
                shape.body.position = SIMD3(shape.x + 0.018 * sin(t * 1.4),
                                            shape.y - Self.portalHeight * 0.5 + 0.04 * sin(t * 1.9),
                                            door.z + Self.foundryShapeDepth - portalZ
                                                + 0.025 * sin(t * 1.1))
                shape.core.scale = SIMD3(repeating: 1 + 0.025 * sin(t * 2.6))
                shape.glow.isEnabled = shape.heldBy != nil
                if shape.glow.isEnabled {
                    shape.glow.components.set(OpacityComponent(opacity: 0.65 + 0.25 * sin(t * 4)))
                }
                shape.core.orientation = simd_quatf(angle: 0.08 * sin(t * 0.8), axis: SIMD3(0, 1, 0))
                    * simd_quatf(angle: 0.05 * sin(t * 0.7), axis: SIMD3(0, 0, 1))
                setPickupLightingWeight(entity: shape.body,
                                        playfieldZ: door.z + Self.foundryShapeDepth,
                                        lastWeight: &shape.lightingWeight)
                if abs(shape.x - shape.targetX) < 0.16 && abs(shape.y - shape.targetY) < 0.16 {
                    shape.inserting = true
                    shape.heldBy = nil
                    shape.forceLock = nil
                    shape.velocity = .zero
                    shape.glow.isEnabled = false
                }
            }

            let unlocked = door.shapes.allSatisfy(\.resolved)
            if unlocked { door.opening = min(1, door.opening + deltaTime * 1.25) }
            door.leftPanel.position.x = -0.79 - door.opening * 1.55
            door.rightPanel.position.x = 0.79 + door.opening * 1.55
            if unlocked {
                for shape in door.shapes { shape.slot.isEnabled = false }
            }

            guard !door.resolved,
                  door.z >= head.z - 0.16 && door.previousZ <= head.z + 0.16 else { continue }
            door.resolved = true
            if !unlocked {
                visualFX.spawnHitFlash(near: SIMD3(head.x, head.y, door.z))
                if gameModel.absorbHitIfPossible() {
                    GameSFX.shared.playShieldBreak()
                } else if !gameModel.isTutorialRun {
                    GameSFX.shared.playWallHit()
                    gameModel.endRun()
                    return
                }
            } else {
                gameModel.addFlow(8)
            }
        }
    }

    private func updateOrbitGates(deltaTime: Float, gameModel: GameModel) {
        _ = deltaTime
        let head = playfieldHeadPosition()
        for item in orbitItems {
            item.root.position.z = item.z - portalZ
            setPickupLightingWeight(entity: item.root, playfieldZ: item.z,
                                    lastWeight: &item.lightingWeight)
            for ring in item.rings {
                switch ring.style {
                case .hoop:
                    let tilt = ring.baseRotation + ring.swing * sin(elapsedTime * ring.spin + ring.phase)
                    ring.entity.orientation = simd_quatf(angle: tilt, axis: ring.axis)
                        * simd_quatf(angle: elapsedTime * ring.spin * 0.55,
                                     axis: SIMD3(0, 0, 1))
                case .timedGap:
                    let angle = ring.baseRotation + ring.swing * sin(elapsedTime * ring.spin + ring.phase)
                    ring.entity.orientation = simd_quatf(angle: angle, axis: SIMD3(0, 0, 1))
                }
                let ringZ = item.z + ring.offsetZ
                let localHead = ring.entity.convert(position: head, from: root)
                let previousPlaneZ = ring.previousHeadPlaneZ
                ring.previousHeadPlaneZ = localHead.z
                guard !ring.resolved, let previousPlaneZ,
                      previousPlaneZ >= 0 && localHead.z <= 0 else { continue }
                ring.resolved = true
                let radial = length(SIMD2(localHead.x, localHead.y))
                let safe: Bool
                let clearance: Float
                switch ring.style {
                case .hoop:
                    safe = radial <= Self.orbitOpeningRadius
                    clearance = Self.orbitOpeningRadius - radial
                case .timedGap:
                    clearance = OrbitGateGeometry.timedGapClearance(
                        localX: localHead.x, localY: localHead.y
                    )
                    safe = clearance >= 0
                }
                if !safe {
                    visualFX.spawnHitFlash(near: SIMD3(head.x, head.y, ringZ))
                    if gameModel.absorbHitIfPossible() {
                        GameSFX.shared.playShieldBreak()
                    } else if !gameModel.isTutorialRun {
                        GameSFX.shared.playWallHit()
                        gameModel.endRun()
                        return
                    }
                } else if clearance < (gameModel.stats.modifier?.nearMissRange ?? 0.2) {
                    gameModel.registerNearMiss()
                    GameSFX.shared.playNearMiss()
                } else {
                    gameModel.addFlow(2)
                }
            }
        }
    }

    /// Drive portal-local pose while a wall rushes from tunnel infinity to the mouth.
    private func tickWallEmerge(_ wall: WallItem, deltaTime: Float) {
        guard let elapsed = wall.emergeElapsed else { return }
        let nextElapsed = elapsed + deltaTime
        wall.emergeElapsed = nextElapsed
        let progress = WallEmerge.progress(elapsed: nextElapsed)
        let exitLocalZ = wall.playfieldZ - portalZ
        // After the rush finishes, track the stream pose in portal space.
        let localZ = progress >= 1
            ? exitLocalZ
            : WallEmerge.localZ(progress: progress, exitLocalZ: exitLocalZ)
        let scale = progress >= 1 ? 1 : WallEmerge.scale(progress: progress)
        let localY = WallEmerge.portalLocalY(
            playfieldCenterY: wall.emergePlayfieldY,
            scale: scale,
            portalHeight: GameWorld.portalHeight,
            floorAnchored: wall.anchorsEmergeToFloor
        )
        wall.entity.position = SIMD3(wall.entity.position.x, localY, localZ)
        wall.entity.scale = SIMD3(repeating: scale)

        let halfDepth = Self.emergeHalfDepth(for: wall.kind) * scale
        let lighting = WallEmerge.environmentLightingWeight(
            portalLocalZ: localZ,
            halfDepth: halfDepth
        )
        setWallLightingWeight(wall, weight: lighting)

        // Mark emerge done once fully clear — do NOT reparent (avoids a one-frame pop).
        if progress >= 1, wall.playfieldZ - halfDepth >= portalZ + 0.02 {
            finishWallEmerge(wall)
        }
    }

    /// Snap emerge animation complete while keeping the wall in `portalWorld`.
    private func finishWallEmerge(_ wall: WallItem) {
        guard wall.isEmerging else { return }
        wall.entity.scale = SIMD3(repeating: 1)
        applyPortalWallPose(wall, scale: 1)
        setWallLightingWeight(wall, weight: 1)
        wall.previousZ = wall.playfieldZ
        wall.emergeElapsed = nil
    }

    /// Portal-local pose matching the wall's playfield stream position.
    private func applyPortalWallPose(_ wall: WallItem, scale: Float) {
        let localY = WallEmerge.portalLocalY(
            playfieldCenterY: wall.emergePlayfieldY,
            scale: scale,
            portalHeight: GameWorld.portalHeight,
            floorAnchored: wall.anchorsEmergeToFloor
        )
        wall.entity.position = SIMD3(
            wall.entity.position.x,
            localY,
            wall.playfieldZ - portalZ
        )
    }

    /// Quantized lighting updates — rewriting the component every frame flickers.
    private func setWallLightingWeight(_ wall: WallItem, weight: Float) {
        let quantized = (min(1, max(0, weight)) * 8).rounded() / 8
        guard abs(quantized - wall.lastLightingWeight) > 0.001 else { return }
        wall.lastLightingWeight = quantized
        wall.entity.components.set(
            EnvironmentLightingConfigurationComponent(environmentLightingWeight: quantized)
        )
    }

    private func setPickupLightingWeight(
        entity: Entity,
        playfieldZ: Float,
        lastWeight: inout Float
    ) {
        let localZ = playfieldZ - portalZ
        let weight = WallEmerge.environmentLightingWeight(portalLocalZ: localZ, halfDepth: 0.12)
        let quantized = (weight * 8).rounded() / 8
        guard abs(quantized - lastWeight) > 0.001 else { return }
        lastWeight = quantized
        entity.components.set(
            EnvironmentLightingConfigurationComponent(environmentLightingWeight: quantized)
        )
    }

    /// Stream Z shared by walls / coins / halves on the current beat.
    private var patternStreamSpawnZ: Float {
        WallEmerge.spawnPlayfieldZ(mouthSpawnZ: patternSpawnZ)
    }

    /// Place a pickup in the portal stream so it stays aligned with led-back walls.
    private func attachPickupToPortalStream(
        _ entity: Entity,
        playfieldX: Float,
        playfieldY: Float,
        playfieldZ: Float
    ) {
        entity.position = SIMD3(
            playfieldX,
            playfieldY - GameWorld.portalHeight * 0.5,
            playfieldZ - portalZ
        )
        entity.components.set(PortalCrossingComponent())
        entity.components.set(
            EnvironmentLightingConfigurationComponent(environmentLightingWeight: 0)
        )
        portalWorld.addChild(entity)
    }

    /// Parent a newly built wall under the portal tunnel and start its emerge animation.
    private func beginWallEmerge(
        parent: Entity,
        playfieldY: Float,
        playfieldZ: Float,
        localSlabXs: [Float],
        kind: WallKind,
        sealsBetweenSlabs: Bool = false
    ) {
        // Start the stream pose further back so the emerge is visible sooner.
        let streamZ = WallEmerge.spawnPlayfieldZ(mouthSpawnZ: playfieldZ)
        let floorAnchored = kind != .duck
        let startY = WallEmerge.portalLocalY(
            playfieldCenterY: playfieldY,
            scale: WallEmerge.startScale,
            portalHeight: GameWorld.portalHeight,
            floorAnchored: floorAnchored
        )
        parent.scale = SIMD3(repeating: WallEmerge.startScale)
        parent.position = SIMD3(windCurrentX, startY, WallEmerge.startDepth)
        // Required for thick walls to render smoothly across the portal plane.
        parent.components.set(PortalCrossingComponent())
        parent.components.set(
            EnvironmentLightingConfigurationComponent(environmentLightingWeight: 0)
        )
        portalWorld.addChild(parent)
        let item = WallItem(
            entity: parent,
            localSlabXs: localSlabXs,
            kind: kind,
            sealsBetweenSlabs: sealsBetweenSlabs,
            playfieldZ: streamZ,
            emergePlayfieldY: playfieldY
        )
        item.lastLightingWeight = 0
        walls.append(item)
    }

    private static func emergeHalfDepth(for kind: WallKind) -> Float {
        switch kind {
        case .jump:
            return jumpSlabDepth * 0.5
        case .duck:
            return wallThickness * 0.85 * 0.5
        case .standard, .ghost:
            return wallThickness * 0.5
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
        timeUntilWind = nextFloat(in: GameWorld.windMinInterval...GameWorld.windMaxInterval)
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
                timeUntilWind = nextFloat(in: GameWorld.windMinInterval...GameWorld.windMaxInterval)
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
            $0.playfieldZ > GameWorld.windDangerMinZ
                && $0.playfieldZ < GameWorld.windDangerMaxZ
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
        if var rng = gameplayRNG {
            let value = StormWind.nextDirection(
                offsetStep: windOffsetStep,
                preferredFromGap: preferred,
                rng: &rng
            )
            gameplayRNG = rng
            return value
        }
        return StormWind.nextDirection(offsetStep: windOffsetStep, preferredFromGap: preferred)
    }

    private func windDirectionPreferringSafeGap() -> Float {
        // Look at the nearest upcoming wall and shove away from its blocked center when possible.
        let ahead = walls
            .filter { $0.playfieldZ < -1.2 && $0.kind != .duck }
            .sorted { $0.playfieldZ > $1.playfieldZ }
        if let nearest = ahead.first {
            let xs = nearest.worldSlabXs()
            let blockedCenter = xs.reduce(0, +) / Float(xs.count)
            if abs(blockedCenter) > 0.05 {
                return blockedCenter > 0 ? -1 : 1
            }
        }
        return nextBool() ? 1 : -1
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

        let model = BiomeAssetCatalog.clone("gust_ribbon") ?? Entity()
        model.name = "windGustBar"
        if direction < 0 {
            model.orientation = simd_quatf(angle: .pi, axis: SIMD3(0, 1, 0))
        }
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
        guard let model = gustEntity?.children.first else { return }

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
        model.components.set(OpacityComponent(opacity: Float(alpha)))
    }

    // MARK: - Spawning

    private func updateBiomeHint() {
        let hint: String?
        switch activeSpawnProfile.twist {
        case .telekinesis:
            hint = "Aim either hand to lock a shape · move each hand to guide"
        case .orbitGate:
            hint = "Pass through hoops · watch for the timed opening in flat rings"
        default:
            hint = nil
        }
        biomeHintRemaining = hint == nil ? 0
            : (activeSpawnProfile.twist == .telekinesis ? 15 : 10)
        if gameModel?.biomeHint != hint { gameModel?.biomeHint = hint }
    }

    private func spawnNextPattern() {
        let profile = activeSpawnProfile

        switch profile.twist {
        case .lowCrawl:
            spawnLowCrawlPattern(profile: profile)
        case .summitStep:
            spawnSummitStepPattern(profile: profile)
        case .crystalHalves:
            spawnCrystalCavePattern()
        case .telekinesis:
            spawnFoundryPattern()
        case .orbitGate:
            spawnOrbitGatePattern()
        case .ghostWalls:
            spawnGhostGlassPattern(profile: profile)
        case .windShove:
            spawnStormPattern(profile: profile)
        case .baseline:
            spawnStandardPattern()
        }
    }

    private func spawnStandardPattern() {
        let blocking = randomWallLanes()
        spawnWall(blocking: blocking, kind: .standard, profile: activeSpawnProfile)

        let safeLanes = Lane.allCases.filter { !blocking.contains($0) }
        if let coinLane = rewardLane(from: safeLanes), nextUnitFloat() < collectibleChance {
            spawnReward(in: coinLane)
        }
    }

    /// Storm Pass: never spawn a wall in the lane the wind is shoving toward.
    private func spawnStormPattern(profile: EnvironmentProfile) {
        let rawPatterns = Self.stormWallLaneRawPatterns()
        let chosen: [Int]
        if var rng = gameplayRNG {
            chosen = StormWind.chooseWallLanes(
                from: rawPatterns,
                offsetStep: windOffsetStep,
                pendingDirection: pendingWindDirection,
                rng: &rng
            )
            gameplayRNG = rng
        } else {
            chosen = StormWind.chooseWallLanes(
                from: rawPatterns,
                offsetStep: windOffsetStep,
                pendingDirection: pendingWindDirection
            )
        }
        let blocking = Set(chosen.compactMap { Lane(rawValue: $0) })
        spawnWall(blocking: blocking, kind: .standard, profile: profile)

        let safeLanes = Lane.allCases.filter { !blocking.contains($0) }
        if let coinLane = nextElement(safeLanes), nextUnitFloat() < collectibleChance {
            spawnReward(in: coinLane)
        }
    }

    private func spawnGhostGlassPattern(profile: EnvironmentProfile) {
        let blocking = randomWallLanes()
        let kind: WallKind = nextUnitFloat() < profile.ghostWallChance ? .ghost : .standard
        spawnWall(blocking: blocking, kind: kind, profile: profile)

        let safeLanes = Lane.allCases.filter { !blocking.contains($0) }
        if let coinLane = rewardLane(from: safeLanes), nextUnitFloat() < collectibleChance {
            spawnReward(in: coinLane)
        }
    }

    private func spawnLowCrawlPattern(profile: EnvironmentProfile) {
        if environmentDirector.isTeachingLowCrawl {
            spawnDuckWall()
            environmentDirector.noteDuckGateSpawned()
            // Coin under the hanging ceiling — lowered so ducking still rewards grabs.
            if nextUnitFloat() < collectibleChance, let lane = nextElement(Lane.allCases) {
                spawnReward(in: lane, underCeiling: true)
            }
            return
        }

        if nextUnitFloat() < biomeHazardChance(profile.duckHazardChance) {
            // Occasional duck + simple single side wall, otherwise duck alone.
            var blocked: Set<Lane> = []
            if nextUnitFloat() < 0.35 {
                let side: Set<Lane> = nextBool() ? [.left] : [.right]
                blocked = side
                spawnWall(blocking: side, kind: .standard, profile: profile)
            }
            spawnDuckWall()
            let coinLanes = Lane.allCases.filter { !blocked.contains($0) }
            if nextUnitFloat() < collectibleChance, let lane = nextElement(coinLanes) {
                spawnReward(in: lane, underCeiling: true)
            }
        } else {
            // No ceiling on this beat — normal standing coin height.
            spawnStandardPattern()
        }
    }

    private func spawnSummitStepPattern(profile: EnvironmentProfile) {
        if environmentDirector.isTeachingSummitStep {
            spawnJumpWall()
            environmentDirector.noteJumpGateSpawned()
            if nextUnitFloat() < collectibleChance, let lane = nextElement(Lane.allCases) {
                spawnReward(in: lane)
            }
            return
        }

        if nextUnitFloat() < biomeHazardChance(profile.jumpHazardChance) {
            // Occasional jump + simple single side wall, otherwise jump alone.
            var blocked: Set<Lane> = []
            if nextUnitFloat() < 0.35 {
                let side: Set<Lane> = nextBool() ? [.left] : [.right]
                blocked = side
                spawnWall(blocking: side, kind: .standard, profile: profile)
            }
            spawnJumpWall()
            let coinLanes = Lane.allCases.filter { !blocked.contains($0) }
            if nextUnitFloat() < collectibleChance, let lane = nextElement(coinLanes) {
                spawnReward(in: lane)
            }
        } else {
            spawnStandardPattern()
        }
    }

    private func spawnCrystalCavePattern() {
        // Prefer simpler / fewer walls while halves are in play.
        let patterns: [Set<Lane>] = [
            [.left], [.center], [.right],
            [.left], [.right],
            [.left, .right]
        ]
        let blocking = nextElement(patterns) ?? [.center]
        spawnWall(blocking: blocking, kind: .standard, profile: activeSpawnProfile)

        let safeLanes = Lane.allCases.filter { !blocking.contains($0) }
        let surgeBonus: Float = gameModel?.stats.modifier == .tokenSurge ? 0.28 : 0
        if let lane = nextElement(safeLanes),
           nextUnitFloat() < min(0.95, GameWorld.crystalHalfSpawnChance + surgeBonus) {
            spawnHalfCrystal(in: lane)
        }
    }

    private func spawnFoundryPattern() {
        lastAdjacentDoubleOpenLaneRaw = nil
        let z = patternStreamSpawnZ
        let risk = gameModel?.stats.risk ?? .stable
        let count = risk == .stable && foundrySpawnCount == 0
            ? 1 : (nextElement(FoundryPatternRules.shapeCountPool(for: risk)) ?? 2)
        let speed: Float
        switch risk {
        case .stable: speed = 0.9
        case .charged: speed = 1.08
        case .unstable: speed = 1.28
        }
        foundrySpawnCount += 1
        let root = Entity()
        root.name = "foundryDoor"
        func makePanel() -> Entity {
            if let authored = BiomeAssetCatalog.clone("foundry_door_panel") {
                return authored
            }
            let material = SimpleMaterial(color: .darkGray, roughness: 0.28, isMetallic: true)
            return ModelEntity(mesh: .generateBox(width: 1.57, height: 2.35, depth: 0.16),
                               materials: [material])
        }
        let leftPanel = makePanel()
        let rightPanel = makePanel()
        leftPanel.position.x = -0.79
        rightPanel.position.x = 0.79
        root.addChild(leftPanel)
        root.addChild(rightPanel)

        var available = FoundryShapeKind.allCases
        let targetXs: [Float] = count == 1 ? [0] : (count == 2 ? [-0.62, 0.62] : [-0.78, 0, 0.78])
        var shapes: [FoundryShape] = []
        for index in 0..<count {
            let kind = nextElement(available) ?? .sphere
            available.removeAll { $0 == kind }
            let targetX = targetXs[index]
            let targetY: Float = count == 1 ? 1.24 : (index.isMultiple(of: 2) ? 1.16 : 1.47)
            let startX: Float = count == 1
                ? (nextBool() ? -0.76 : 0.76)
                : targetXs[(index + 1) % count]
            let startY: Float = targetY + (nextBool() ? 0.14 : -0.14)

            let slot = makeFoundrySlot(kind: kind)
            slot.position = SIMD3(targetX, targetY - 1.18, 0.13)
            root.addChild(slot)
            let body = Entity()
            body.name = "forceShape"
            let core = Entity()
            core.name = "floatingCore"
            core.addChild(makeFoundryCore(kind: kind))
            body.addChild(core)
            let glow = Entity()
            glow.name = "forceGlow"
            for beadIndex in 0..<16 {
                let angle = Float(beadIndex) * Float.pi / 8
                let bead = ModelEntity(mesh: .generateSphere(radius: 0.032),
                                       materials: [UnlitMaterial(color: kind.color)])
                bead.position = SIMD3(cos(angle) * 0.23, sin(angle) * 0.23, 0.045)
                glow.addChild(bead)
            }
            glow.isEnabled = false
            body.addChild(glow)
            attachPickupToPortalStream(body, playfieldX: startX, playfieldY: startY,
                                       playfieldZ: z + Self.foundryShapeDepth)
            shapes.append(FoundryShape(body: body, core: core, glow: glow, slot: slot,
                                       x: startX, y: startY, targetX: targetX, targetY: targetY,
                                       phase: nextFloat(in: 0...(Float.pi * 2))))
        }
        attachPickupToPortalStream(root, playfieldX: 0, playfieldY: 1.18, playfieldZ: z)
        foundryItems.append(FoundryItem(root: root, leftPanel: leftPanel,
                                        rightPanel: rightPanel, shapes: shapes,
                                        z: z, speed: speed))
    }

    private func makeFoundryCore(kind: FoundryShapeKind) -> Entity {
        let entity = Entity()
        if let authored = BiomeAssetCatalog.clone(kind.assetID) {
            BiomeAssetCatalog.tint(authored, role: "tint_pickup", color: kind.color)
            entity.addChild(authored)
            return entity
        }
        let material = SimpleMaterial(color: kind.color, roughness: 0.16, isMetallic: true)
        let model: ModelEntity
        switch kind {
        case .sphere:
            model = ModelEntity(mesh: .generateSphere(radius: 0.15), materials: [material])
        case .cube:
            model = ModelEntity(mesh: .generateBox(width: 0.27, height: 0.27, depth: 0.27),
                                materials: [material])
        case .diamond:
            model = ModelEntity(mesh: .generateBox(width: 0.25, height: 0.25, depth: 0.25),
                                materials: [material])
            model.orientation = simd_quatf(angle: Float.pi / 4, axis: SIMD3(0, 0, 1))
                * simd_quatf(angle: 0.35, axis: SIMD3(1, 0, 0))
        }
        entity.addChild(model)
        return entity
    }

    private func makeFoundrySlot(kind: FoundryShapeKind) -> Entity {
        let slot = Entity()
        slot.name = "matchingSlot"
        let material = UnlitMaterial(color: kind.color)
        if kind == .sphere {
            for index in 0..<16 {
                let angle = Float(index) * Float.pi / 8
                let bead = ModelEntity(mesh: .generateSphere(radius: 0.026), materials: [material])
                bead.position = SIMD3(cos(angle) * 0.22, sin(angle) * 0.22, 0)
                slot.addChild(bead)
            }
        } else {
            for index in 0..<4 {
                let angle = Float(index) * Float.pi / 2 + (kind == .diamond ? Float.pi / 4 : 0)
                let edge = ModelEntity(mesh: .generateBox(width: 0.31, height: 0.035, depth: 0.035),
                                       materials: [material])
                edge.position = SIMD3(cos(angle) * 0.16, sin(angle) * 0.16, 0)
                edge.orientation = simd_quatf(angle: angle + Float.pi / 2,
                                               axis: SIMD3(0, 0, 1))
                slot.addChild(edge)
            }
        }
        return slot
    }

    private func spawnOrbitGatePattern() {
        lastAdjacentDoubleOpenLaneRaw = nil
        let z = patternStreamSpawnZ
        let root = Entity()
        let pattern = OrbitGateGeometry.patternIndex(spawnCount: orbitSpawnCount)
        root.name = pattern == 0 ? "threeOrbitRings"
            : (pattern == 1 ? "timedShutterRing" : "crossAxisRings")
        let axes: [SIMD3<Float>] = [
            normalize(SIMD3(1, 0.18, 0)),
            normalize(SIMD3(0.15, 1, 0)),
            normalize(SIMD3(0.8, -0.65, 0))
        ]
        let colors: [UIColor] = [.systemPink, .systemYellow, .systemCyan]
        let shift = nextBool() ? Float(1) : Float(-1)
        var rings: [OrbitRing] = []
        if pattern == 1 {
            let ring = makeTimedOrbitRing()
            ring.position = SIMD3(0, -0.12, 0)
            root.addChild(ring)
            rings.append(OrbitRing(entity: ring, offsetZ: 0, style: .timedGap,
                                   axis: SIMD3(0, 0, 1),
                                   phase: nextFloat(in: 0...(Float.pi * 2)),
                                   spin: nextFloat(in: 0.8...1.1),
                                   baseRotation: nextBool() ? 0 : Float.pi,
                                   swing: 0.85))
        } else {
            let count = pattern == 0 ? 3 : 2
            for index in 0..<count {
                let ring = makeOrbitHoop(color: colors[index])
                ring.name = "rotatingRing\(index + 1)"
                let centerX: Float
                let centerY: Float
                let offsetZ: Float
                let baseTilt: Float
                let swing: Float
                if pattern == 0 {
                    centerX = orbitSpawnCount < 2 ? 0 : shift * [0.0, 0.40, 0.75][index]
                    centerY = 1.46 + [0.0, 0.12, -0.10][index]
                    offsetZ = Float(index - 1) * 0.88
                    baseTilt = 0
                    swing = 0.48
                } else {
                    centerX = shift * (index == 0 ? 0.18 : 0.55)
                    centerY = index == 0 ? 1.54 : 1.38
                    offsetZ = index == 0 ? -0.75 : 0.75
                    baseTilt = index == 0 ? 0.46 : -0.52
                    swing = 0.38
                }
                ring.position = SIMD3(centerX, centerY - 1.46, offsetZ)
                root.addChild(ring)
                rings.append(OrbitRing(entity: ring, offsetZ: offsetZ, style: .hoop,
                                       axis: axes[(index + orbitSpawnCount) % 3],
                                       phase: nextFloat(in: 0...(Float.pi * 2)),
                                       spin: nextFloat(in: 0.65...1.05) * (index.isMultiple(of: 2) ? 1 : -1),
                                       baseRotation: baseTilt, swing: swing))
            }
        }
        attachPickupToPortalStream(root, playfieldX: 0, playfieldY: 1.46, playfieldZ: z)
        orbitSpawnCount += 1
        orbitItems.append(OrbitItem(root: root, rings: rings, z: z))
        if pattern != 1 && nextUnitFloat() < collectibleChance {
            spawnCoin(in: .center, streamOffset: -2.5)
        }
    }

    private func makeOrbitHoop(color: UIColor) -> Entity {
        let ring = Entity()
        let material = SimpleMaterial(color: color, roughness: 0.22, isMetallic: true)
        for segment in 0..<24 {
            let angle = Float(segment) * Float.pi / 12
            let bar: Entity
            if let authored = BiomeAssetCatalog.clone("orbit_hoop_segment") {
                BiomeAssetCatalog.tint(authored, role: "body", color: color)
                BiomeAssetCatalog.tint(authored, role: "accent", color: color)
                bar = authored
            } else {
                bar = ModelEntity(mesh: .generateBox(width: 0.22, height: 0.14, depth: 0.14),
                                  materials: [material])
            }
            bar.position = SIMD3(cos(angle) * 0.80, sin(angle) * 0.80, 0)
            bar.orientation = simd_quatf(angle: angle + Float.pi / 2,
                                          axis: SIMD3(0, 0, 1))
            ring.addChild(bar)
            if segment.isMultiple(of: 6) {
                let marker: Entity
                if let authored = BiomeAssetCatalog.clone("orbit_marker") {
                    BiomeAssetCatalog.tint(authored, role: "accent", color: color)
                    marker = authored
                } else {
                    marker = ModelEntity(mesh: .generateSphere(radius: 0.085),
                                         materials: [UnlitMaterial(color: color)])
                }
                marker.position = SIMD3(cos(angle) * 0.80, sin(angle) * 0.80, 0.10)
                ring.addChild(marker)
            }
        }
        return ring
    }

    /// A flat radial shutter with one clear wedge. The player must enter that
    /// moving wedge while the gate crosses the headset plane.
    private func makeTimedOrbitRing() -> Entity {
        let ring = Entity()
        let material = SimpleMaterial(color: .systemPink, roughness: 0.3, isMetallic: true)
        let hub: Entity = BiomeAssetCatalog.clone("orbit_shutter_hub")
            ?? ModelEntity(mesh: .generateSphere(radius: 0.29), materials: [material])
        ring.addChild(hub)
        for segment in 0..<24 {
            let angle = Float(segment) * Float.pi / 12
            let signedAngle = angle > Float.pi ? angle - 2 * Float.pi : angle
            if abs(signedAngle) <= 0.52 { continue }
            let blade: Entity = BiomeAssetCatalog.clone("orbit_shutter_blade")
                ?? ModelEntity(mesh: .generateBox(width: 0.72, height: 0.13, depth: 0.16),
                               materials: [material])
            blade.position = SIMD3(cos(angle) * 0.65, sin(angle) * 0.65, 0)
            blade.orientation = simd_quatf(angle: angle, axis: SIMD3(0, 0, 1))
            ring.addChild(blade)
            let band: Entity = BiomeAssetCatalog.clone("orbit_shutter_band")
                ?? ModelEntity(mesh: .generateBox(width: 0.21, height: 0.18, depth: 0.16),
                               materials: [material])
            band.position = SIMD3(cos(angle) * 0.65, sin(angle) * 0.65, 0.01)
            band.orientation = simd_quatf(angle: angle + Float.pi / 2,
                                           axis: SIMD3(0, 0, 1))
            ring.addChild(band)
            let rim: Entity = BiomeAssetCatalog.clone("orbit_shutter_rim")
                ?? ModelEntity(mesh: .generateBox(width: 0.25, height: 0.13, depth: 0.16),
                               materials: [UnlitMaterial(color: .systemYellow)])
            rim.position = SIMD3(cos(angle) * 1.02, sin(angle) * 1.02, 0.02)
            rim.orientation = simd_quatf(angle: angle + Float.pi / 2,
                                         axis: SIMD3(0, 0, 1))
            ring.addChild(rim)
        }
        for edgeAngle in [Float(-0.55), Float(0.55)] {
            let edge = ModelEntity(mesh: .generateBox(width: 0.72, height: 0.045, depth: 0.20),
                                   materials: [UnlitMaterial(color: .systemCyan)])
            edge.position = SIMD3(cos(edgeAngle) * 0.65, sin(edgeAngle) * 0.65, 0.11)
            edge.orientation = simd_quatf(angle: edgeAngle, axis: SIMD3(0, 0, 1))
            ring.addChild(edge)
        }
        return ring
    }

    private func randomWallLanes() -> Set<Lane> {
        if case .normal? = gameModel?.resolvedPlayMode {
            if phraseQueue.isEmpty { refillPhraseQueue() }
            if !phraseQueue.isEmpty {
                let beat = phraseQueue.removeFirst()
                pendingPhraseReward = beat.reward
                return beat.blocking
            }
        }
        let patterns: [Set<Lane>] = [
            [.left], [.center], [.right],
            [.left], [.center], [.right],
            [.left], [.right],
            [.left, .center], [.center, .right], [.left, .right],
            [.left, .right], [.left, .center], [.center, .right]
        ]
        return nextElement(patterns) ?? [.center]
    }

    /// A low peripheral floor orbit makes Aegis feel embodied without covering vision.
    private func syncAegisAura(gameModel: GameModel) {
        guard gameModel.isPlaying, gameModel.stats.shieldCharges > 0 else {
            aegisAura?.removeFromParent()
            aegisAura = nil
            return
        }

        if aegisAura == nil {
            let aura = Entity()
            aura.name = "aegisFloorAura"
            let material = UnlitMaterial(color: GamePalette.neonCyanHot.withAlphaComponent(0.86))
            for index in 0..<12 {
                let angle = Float(index) / 12 * .pi * 2
                let node = ModelEntity(mesh: BiomeAssetCatalog.mesh("fx_shard") ?? .generateSphere(radius: 1),
                                       materials: [material])
                node.scale = SIMD3(repeating: index.isMultiple(of: 3) ? 0.026 : 0.014)
                node.position = SIMD3(cos(angle) * 0.43, 0.055, sin(angle) * 0.43)
                aura.addChild(node)
            }
            root.addChild(aura)
            aegisAura = aura
        }

        let head = playfieldHeadPosition()
        aegisAura?.position = SIMD3(head.x, 0, head.z)
        aegisAura?.orientation = simd_quatf(
            angle: elapsedTime * 0.72,
            axis: SIMD3(0, 1, 0)
        )
    }

    /// Short readable choreographies rather than independent random rows.
    /// Stable phrases leave two routes; Charged links a weave; Unstable asks for
    /// a three-step reversal, with existing opposite-lane spacing protecting it.
    private func refillPhraseQueue() {
        let mirrored = nextBool()
        func lane(_ lane: Lane) -> Lane {
            guard mirrored else { return lane }
            switch lane {
            case .left: return .right
            case .right: return .left
            case .center: return .center
            }
        }
        func mapped(_ lanes: Set<Lane>) -> Set<Lane> {
            Set(lanes.map { lane($0) })
        }

        switch gameModel?.stats.risk ?? .stable {
        case .stable:
            let first: [PhraseBeat] = [
                PhraseBeat(blocking: [.left], reward: .center),
                PhraseBeat(blocking: [.right], reward: .center),
                PhraseBeat(blocking: [.center], reward: .left)
            ]
            phraseQueue = first.map {
                PhraseBeat(blocking: mapped($0.blocking), reward: $0.reward.map { lane($0) })
            }
        case .charged:
            let weave: [PhraseBeat] = [
                PhraseBeat(blocking: [.center, .right], reward: .left),
                PhraseBeat(blocking: [.left, .right], reward: .center),
                PhraseBeat(blocking: [.left], reward: .right),
                PhraseBeat(blocking: [.center], reward: .left)
            ]
            phraseQueue = weave.map {
                PhraseBeat(blocking: mapped($0.blocking), reward: $0.reward.map { lane($0) })
            }
        case .unstable:
            let reversal: [PhraseBeat] = [
                PhraseBeat(blocking: [.left, .center], reward: .right),
                PhraseBeat(blocking: [.left, .right], reward: .center),
                PhraseBeat(blocking: [.center, .right], reward: .left),
                PhraseBeat(blocking: [.left], reward: .right)
            ]
            phraseQueue = reversal.map {
                PhraseBeat(blocking: mapped($0.blocking), reward: $0.reward.map { lane($0) })
            }
        }
    }

    private func rewardLane(from safeLanes: [Lane]) -> Lane? {
        defer { pendingPhraseReward = nil }
        if let preferred = pendingPhraseReward, safeLanes.contains(preferred) {
            return preferred
        }
        return nextElement(safeLanes)
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

        beginWallEmerge(
            parent: parent,
            playfieldY: GameWorld.wallHeight * 0.5,
            playfieldZ: patternSpawnZ,
            localSlabXs: slabXs,
            kind: kind,
            sealsBetweenSlabs: sealsGap
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
        parent.name = "wallDuck"

        let body = GameVisualBuilders.makeDuckTendrilCurtain(
            width: GameWorld.duckSlabWidth,
            height: GameWorld.duckSlabHeight,
            depth: GameWorld.wallThickness * 0.85,
            seed: nextVisualSeed()
        )
        parent.addChild(body)

        beginWallEmerge(
            parent: parent,
            playfieldY: centerY,
            playfieldZ: patternSpawnZ,
            localSlabXs: [0],
            kind: .duck
        )
    }

    private func spawnJumpWall() {
        // Jump gates break adjacent-double open-lane chaining.
        lastAdjacentDoubleOpenLaneRaw = nil
        let parent = Entity()
        // Sit the hurdle on the floor band (center at half slab height).
        let centerY = GameWorld.jumpSlabHeight * 0.5
        parent.name = "wallJump"

        let body = GameVisualBuilders.makeSummitSpikeRidge(
            width: GameWorld.jumpSlabWidth,
            height: GameWorld.jumpSlabHeight,
            depth: GameWorld.jumpSlabDepth,
            seed: nextVisualSeed()
        )
        parent.addChild(body)

        beginWallEmerge(
            parent: parent,
            playfieldY: centerY,
            playfieldZ: patternSpawnZ,
            localSlabXs: [0],
            kind: .jump
        )
    }

    /// Every biome gets its own alien obstacle "species" instead of a shared
    /// rectangular slab — collision stays the plain AABB in `WallCollision`,
    /// so these can be as irregular as they like without touching fairness.
    private func makeWallSlab(kind: WallKind, profile: EnvironmentProfile) -> Entity {
        switch kind {
        case .ghost:
            return GameVisualBuilders.makeGhostShatterPane(
                width: GameWorld.wallWidth,
                height: GameWorld.wallHeight,
                depth: GameWorld.wallThickness,
                opacity: profile.ghostWallOpacity,
                seed: nextVisualSeed()
            )
        case .standard, .duck, .jump:
            return GameVisualBuilders.makeBiomeObstacle(
                biome: profile.id,
                width: GameWorld.wallWidth,
                height: GameWorld.wallHeight,
                depth: GameWorld.wallThickness,
                profile: profile,
                seed: nextVisualSeed()
            )
        }
    }

    private func spawnReward(in lane: Lane, underCeiling: Bool = false) {
        spawnCoin(in: lane, underCeiling: underCeiling)
        guard gameModel?.stats.modifier == .tokenSurge else { return }
        // A short depth chain creates a readable sweep without demanding a wider reach.
        spawnCoin(in: lane, underCeiling: underCeiling, streamOffset: -0.46)
        spawnCoin(in: lane, underCeiling: underCeiling, streamOffset: -0.92)
    }

    private func spawnCoin(
        in lane: Lane,
        underCeiling: Bool = false,
        streamOffset: Float = 0
    ) {
        // Spawn-time biome tint only (no live retint on switch) — Ember keeps polished gold.
        let coinColors = GameCoinTint.colors(for: activeSpawnProfile)
        let visualSeed = nextVisualSeed()
        let coin = GameVisualBuilders.makeCoin(
            radius: GameWorld.coinRadius,
            tint: coinColors.base,
            hot: coinColors.hot,
            tintsFaceTexture: coinColors.tintsFaceTexture,
            seed: visualSeed
        )
        // Mild outward offset — still a reach, but easier to snag mid-dodge.
        let outward: Float = lane == .center ? 0 : (lane.x > 0 ? GameWorld.coinOutwardOffset : -GameWorld.coinOutwardOffset)
        let baseY = underCeiling ? GameWorld.lowCrawlCoinHeight : GameWorld.coinHeight
        let streamZ = patternStreamSpawnZ + streamOffset
        attachPickupToPortalStream(
            coin,
            playfieldX: lane.x + outward + windCurrentX,
            playfieldY: baseY,
            playfieldZ: streamZ
        )
        coins.append(
            CoinItem(
                entity: coin,
                baseY: baseY,
                playfieldZ: streamZ,
                phase: nextFloat(in: 0...(Float.pi * 2)),
                lastLightingWeight: 0
            )
        )
    }

    private func spawnHalfCrystal(in lane: Lane) {
        let roll: (type: CrystalHalfType, charged: Bool)
        if var rng = gameplayRNG {
            roll = CrystalCombine.makeHalf(rng: &rng)
            gameplayRNG = rng
        } else {
            var rng = SystemRandomNumberGenerator()
            roll = CrystalCombine.makeHalf(rng: &rng)
        }
        let radius: Float = roll.charged ? 0.085 : 0.07
        let visualSeed = nextVisualSeed()
        let entity = BiomeAssetCatalog.crystal(type: roll.type, charged: roll.charged,
                                               radius: radius, seed: visualSeed)
        let outward: Float = lane == .center ? 0 : (lane.x > 0 ? GameWorld.coinOutwardOffset : -GameWorld.coinOutwardOffset)
        let streamZ = patternStreamSpawnZ
        entity.name = roll.charged ? "halfCrystalCharged" : "halfCrystal"
        attachPickupToPortalStream(
            entity,
            playfieldX: lane.x + outward + windCurrentX,
            playfieldY: GameWorld.coinHeight,
            playfieldZ: streamZ
        )
        let item = HalfCrystalItem(
            entity: entity,
            type: roll.type,
            charged: roll.charged,
            playfieldZ: streamZ,
            visualSeed: visualSeed
        )
        item.lastLightingWeight = 0
        halves.append(item)
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
            visualFX.spawnCrystalMerge(at: (leftPos + rightPos) * 0.5)
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
        // Crystal only: wrist/arm contact must not grab — fingertips + grip (the hand) only.
        if heldLeft == nil {
            let points = handPointsInRoot(
                CrystalCombine.handOnlyContacts(
                    from: leftHandContactsWorld,
                    grip: leftHandGripWorld
                )
            )
            if let index = nearestHalfIndex(toAnyOf: points) {
                grabHalf(at: index, left: true)
            }
        }
        if heldRight == nil {
            let points = handPointsInRoot(
                CrystalCombine.handOnlyContacts(
                    from: rightHandContactsWorld,
                    grip: rightHandGripWorld
                )
            )
            if let index = nearestHalfIndex(toAnyOf: points) {
                grabHalf(at: index, left: false)
            }
        }
    }

    /// Convert already-filtered world-space hand samples into root space.
    private func handPointsInRoot(_ contactsWorld: [SIMD3<Float>]) -> [SIMD3<Float>] {
        contactsWorld.map { root.convert(position: $0, from: nil) }
    }

    private func nearestHalfIndex(toAnyOf points: [SIMD3<Float>]) -> Int? {
        guard !points.isEmpty else { return nil }
        var bestIndex: Int?
        let pickupBonus = gameModel?.stats.modifier?.pickupRadiusBonus ?? 0
        var bestDistance = GameWorld.crystalCollectDistance + pickupBonus
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

        let radius: Float = source.charged ? 0.08 : 0.065
        let heldEntity = BiomeAssetCatalog.crystal(type: source.type, charged: source.charged,
                                                   radius: radius, seed: source.visualSeed)
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
        let ignoreWallHits = gameModel.isTutorialRun && tutorialHitCooldown > 0

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
        let jumpHalfWidth = GameWorld.jumpSlabWidth * 0.5 - 0.05
        let jumpHeadRise = JumpHeightDetection.headRise(
            headY: head.y,
            standingEyeHeight: standingEyeHeight
        )

        for wall in walls {
            // Still inside the portal tunnel — not yet a real-room hazard.
            guard !wall.hasResolvedHit, !wall.isEmerging else { continue }
            let wallZ = wall.playfieldZ
            let previousZ = wall.previousZ

            let hit: Bool
            switch wall.kind {
            case .duck:
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
            case .jump:
                // Headset-only: a small rise along universal up clears. Hands ignored.
                let centerX = wall.entity.position.x
                hit = WallCollision.pointHitsJumpBarrier(
                    point: head,
                    wallZ: wallZ,
                    previousWallZ: previousZ,
                    centerX: centerX,
                    halfWidth: jumpHalfWidth,
                    halfDepth: GameWorld.jumpHitHalfDepth,
                    headRise: jumpHeadRise,
                    minRise: GameWorld.jumpMinRise
                )
            case .standard, .ghost:
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
                if ignoreWallHits {
                    continue
                }
                wall.hasResolvedHit = true
                visualFX.spawnHitFlash(near: SIMD3(head.x, head.y, wall.playfieldZ))
                // Quick squash so the hit reads before game-over UI.
                wall.entity.scale = SIMD3(1.08, 0.92, 1.15)
                dropHeldHalves()
                if gameModel.isTutorialRun {
                    // Soft fail — flash + SFX, keep the calibration run going.
                    GameSFX.shared.playWallHit()
                    tutorialHitCooldown = 0.45
                    return
                }
                if gameModel.absorbHitIfPossible() {
                    GameSFX.shared.playShieldBreak()
                    return
                }
                GameSFX.shared.playWallHit()
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
                if wall.kind == .standard || wall.kind == .ghost {
                    let edgeDistance = wall.worldSlabXs()
                        .map { abs(abs(head.x - $0) - halfWidth) }
                        .min() ?? .greatestFiniteMagnitude
                    let nearMissRange = gameModel.stats.modifier?.nearMissRange ?? 0.2
                    if edgeDistance > 0.001, edgeDistance <= nearMissRange,
                       head.y >= GameWorld.headHitMinY, head.y <= GameWorld.headHitMaxY {
                        gameModel.registerNearMiss()
                        GameSFX.shared.playNearMiss()
                    }
                }
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
                let pickupBonus = gameModel.stats.modifier?.pickupRadiusBonus ?? 0
                if distance(hand, coinPos) <= GameWorld.collectDistance + pickupBonus {
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
        foundryItems.removeAll { item in
            if item.z > GameWorld.despawnZ {
                item.root.removeFromParent()
                for shape in item.shapes { shape.body.removeFromParent() }
                return true
            }
            return false
        }
        orbitItems.removeAll { item in
            if item.z > GameWorld.despawnZ {
                item.root.removeFromParent()
                return true
            }
            return false
        }
        walls.removeAll { item in
            if item.playfieldZ > GameWorld.despawnZ {
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
            if item.playfieldZ > GameWorld.despawnZ {
                item.entity.removeFromParent()
                return true
            }
            return false
        }
        halves.removeAll { item in
            if item.collected { return true }
            if item.playfieldZ > GameWorld.despawnZ {
                item.entity.removeFromParent()
                return true
            }
            return false
        }
    }
}
