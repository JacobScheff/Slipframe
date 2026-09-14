//
//  EnvironmentProfile.swift
//  Slipframe
//
//  Biome roster, palettes, and twist parameters. Materials / custom assets
//  should read tints from these profiles so art can be swapped in later.
//

import Foundation
import simd

enum EnvironmentID: String, CaseIterable, Identifiable, Codable {
    case emberRun
    case summitStep
    case ghostGlass
    case lowCrawl
    case stormPass
    case crystalCave

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .emberRun: return "Ember Run"
        case .summitStep: return "Summit Step"
        case .ghostGlass: return "Ghost Glass"
        case .lowCrawl: return "Low Crawl"
        case .stormPass: return "Storm Pass"
        case .crystalCave: return "Crystal Cave"
        }
    }

    /// Filename stem for the biome track in `Music/`
    /// (e.g. `emberRun.m4a`). See Music/README.md.
    var musicCue: String { rawValue }

    var symbolName: String {
        switch self {
        case .emberRun: return "flame.fill"
        case .summitStep: return "mountain.2.fill"
        case .ghostGlass: return "sparkle"
        case .lowCrawl: return "arrow.down.to.line"
        case .stormPass: return "wind"
        case .crystalCave: return "diamond.fill"
        }
    }

    /// Short verb printed on biome tiles so the twist is readable at a glance.
    var twistCaption: String {
        switch self {
        case .emberRun: return "Clear path"
        case .summitStep: return "Hop hurdles"
        case .ghostGlass: return "See-through"
        case .lowCrawl: return "Duck low"
        case .stormPass: return "Wind shove"
        case .crystalCave: return "Combine"
        }
    }
}

enum EnvironmentTwist: Equatable {
    case baseline
    case summitStep
    case ghostWalls
    case lowCrawl
    case windShove
    case crystalHalves
}

/// Player-chosen challenge contract for one Normal-mode biome visit.
/// Risk changes pattern density / complexity and rewards, never stream speed.
enum RiftRisk: String, CaseIterable, Equatable, Hashable, Codable {
    case stable
    case charged
    case unstable

    var scoreMultiplier: Float {
        switch self {
        case .stable: return 1
        case .charged: return 1.5
        case .unstable: return 2
        }
    }

    var spawnGapScale: Float {
        switch self {
        case .stable: return 1.18
        case .charged: return 1
        case .unstable: return 0.86
        }
    }

    var collectibleChanceBonus: Float {
        switch self {
        case .stable: return 0.05
        case .charged: return 0.12
        case .unstable: return 0.2
        }
    }

    /// A wordless, redundant visual code: one calm ring through three broken rings.
    var ringCount: Int {
        switch self {
        case .stable: return 1
        case .charged: return 2
        case .unstable: return 3
        }
    }
}

/// Small initial modifier set. Each is fully functional and has its own portal glyph.
enum RiftModifier: String, CaseIterable, Equatable, Codable {
    /// Extra collectible chains and doubled token value.
    case tokenSurge
    /// Grants one collision-absorbing shield on biome entry.
    case aegis
    /// Raises distance rewards and Flow gains for the visit.
    case overdrive
}

struct RiftPortalOption: Equatable {
    var environment: EnvironmentID
    var risk: RiftRisk
    var modifier: RiftModifier
}

enum RiftJunctionRules {
    static let choiceSeconds: Float = 10
    static let crossingSeconds: Float = 1.2

    /// Three distinct destinations with one of each risk tier. Lanes are shuffled.
    static func makeOptions<RNG: RandomNumberGenerator>(
        excluding current: EnvironmentID,
        rng: inout RNG
    ) -> [RiftPortalOption] {
        var environments = EnvironmentID.allCases.filter { $0 != current }
        environments.shuffle(using: &rng)
        var risks = RiftRisk.allCases
        risks.shuffle(using: &rng)
        var modifiers = RiftModifier.allCases
        modifiers.shuffle(using: &rng)
        return (0..<3).map { index in
            RiftPortalOption(
                environment: environments[index],
                risk: risks[index],
                modifier: modifiers[index]
            )
        }
    }

    static func nearestOptionIndex(headX: Float, laneSpacing: Float) -> Int {
        let centers = [-laneSpacing, 0, laneSpacing]
        return centers.enumerated().min {
            abs(headX - $0.element) < abs(headX - $1.element)
        }?.offset ?? 1
    }
}

/// Linear sRGB colors used to tint procedural meshes (and later, custom assets).
struct TintColor: Equatable {
    var r: Float
    var g: Float
    var b: Float
    var a: Float

    static let clear = TintColor(r: 0, g: 0, b: 0, a: 0)

    func mixed(toward other: TintColor, t: Float) -> TintColor {
        let u = max(0, min(1, t))
        return TintColor(
            r: r + (other.r - r) * u,
            g: g + (other.g - g) * u,
            b: b + (other.b - b) * u,
            a: a + (other.a - a) * u
        )
    }
}

struct EnvironmentPalette: Equatable {
    var floor: TintColor
    var laneStripe: TintColor
    var portalRim: TintColor
    var portalVoid: TintColor
    var portalRail: TintColor
    var portalAccent: TintColor
    /// Multiplies overall ambience darkness (1 = normal, lower = darker).
    var ambienceBrightness: Float
    /// Reserved palette channel (kept for blend continuity; unused as a gameplay flag).
    var fogDensity: Float
    var fogColor: TintColor
    var wallTint: TintColor
    var wallEmissive: TintColor
    var wallOpacity: Float
    var wallEmissiveIntensity: Float
    var coinTint: TintColor
}

struct EnvironmentProfile: Equatable {
    var id: EnvironmentID
    var twist: EnvironmentTwist
    var palette: EnvironmentPalette
    /// Chance a Ghost Glass wall spawns as a hard-to-see ghost variant.
    var ghostWallChance: Float
    /// Opacity used when a wall is ghosted (Ghost Glass only).
    var ghostWallOpacity: Float
    /// How many duck-only teaching gates to spawn at the start of a Low Crawl visit.
    var lowCrawlTeachCount: Int
    /// Chance to spawn a duck hazard after teaching gates (Low Crawl).
    var duckHazardChance: Float
    /// How many jump-only teaching gates to spawn at the start of a Summit Step visit.
    var summitStepTeachCount: Int
    /// Chance to spawn a jump hazard after teaching gates (Summit Step).
    var jumpHazardChance: Float
}

enum EnvironmentCatalog {
    /// Used when a biome track is missing or has an unreadable duration.
    static let fallbackSwitchInterval: Float = 45
    /// Clamp so a too-short / too-long file cannot break pacing.
    static let minSwitchInterval: Float = 20
    static let maxSwitchInterval: Float = 120
    static let ambienceLerpSeconds: Float = 1.25
    static let telegraphSeconds: Float = 1.0

    static func profile(for id: EnvironmentID) -> EnvironmentProfile {
        switch id {
        case .emberRun:
            return EnvironmentProfile(
                id: .emberRun,
                twist: .baseline,
                palette: EnvironmentPalette(
                    floor: TintColor(r: 0.16, g: 0.09, b: 0.06, a: 1),
                    laneStripe: TintColor(r: 1.0, g: 0.55, b: 0.18, a: 0.9),
                    portalRim: TintColor(r: 1.0, g: 0.45, b: 0.12, a: 1),
                    portalVoid: TintColor(r: 0.06, g: 0.03, b: 0.02, a: 1),
                    portalRail: TintColor(r: 1.0, g: 0.5, b: 0.15, a: 1),
                    portalAccent: TintColor(r: 0.95, g: 0.35, b: 0.1, a: 1),
                    ambienceBrightness: 1.0,
                    fogDensity: 0.0,
                    fogColor: TintColor(r: 0.4, g: 0.25, b: 0.15, a: 0.0),
                    wallTint: TintColor(r: 0.95, g: 0.18, b: 0.1, a: 0.45),
                    wallEmissive: TintColor(r: 1.0, g: 0.28, b: 0.1, a: 1),
                    wallOpacity: 0.45,
                    wallEmissiveIntensity: 0.65,
                    coinTint: TintColor(r: 1.0, g: 0.84, b: 0.2, a: 1)
                ),
                ghostWallChance: 0,
                ghostWallOpacity: 0.45,
                lowCrawlTeachCount: 0,
                duckHazardChance: 0,
                summitStepTeachCount: 0,
                jumpHazardChance: 0
            )

        case .summitStep:
            return EnvironmentProfile(
                id: .summitStep,
                twist: .summitStep,
                palette: EnvironmentPalette(
                    // Sunlit alpine stone — warm contrast to Low Crawl's cool blues.
                    floor: TintColor(r: 0.1, g: 0.08, b: 0.05, a: 1),
                    laneStripe: TintColor(r: 1.0, g: 0.78, b: 0.35, a: 0.85),
                    portalRim: TintColor(r: 0.95, g: 0.68, b: 0.28, a: 1),
                    portalVoid: TintColor(r: 0.04, g: 0.03, b: 0.02, a: 1),
                    portalRail: TintColor(r: 0.9, g: 0.62, b: 0.25, a: 1),
                    portalAccent: TintColor(r: 0.75, g: 0.45, b: 0.15, a: 1),
                    ambienceBrightness: 0.95,
                    fogDensity: 0.0,
                    fogColor: TintColor(r: 0.55, g: 0.45, b: 0.3, a: 0.0),
                    wallTint: TintColor(r: 0.85, g: 0.5, b: 0.18, a: 0.42),
                    wallEmissive: TintColor(r: 1.0, g: 0.65, b: 0.22, a: 1),
                    wallOpacity: 0.42,
                    wallEmissiveIntensity: 0.55,
                    coinTint: TintColor(r: 1.0, g: 0.62, b: 0.38, a: 1)
                ),
                ghostWallChance: 0,
                ghostWallOpacity: 0.42,
                lowCrawlTeachCount: 0,
                duckHazardChance: 0,
                summitStepTeachCount: 3,
                jumpHazardChance: 0.55
            )

        case .ghostGlass:
            // Mix readable glass with rarer spectral panes — no fog / haze volumes.
            return EnvironmentProfile(
                id: .ghostGlass,
                twist: .ghostWalls,
                palette: EnvironmentPalette(
                    floor: TintColor(r: 0.12, g: 0.13, b: 0.16, a: 1),
                    laneStripe: TintColor(r: 0.75, g: 0.85, b: 0.95, a: 0.7),
                    portalRim: TintColor(r: 0.7, g: 0.85, b: 0.95, a: 1),
                    portalVoid: TintColor(r: 0.04, g: 0.05, b: 0.07, a: 1),
                    portalRail: TintColor(r: 0.65, g: 0.8, b: 0.9, a: 1),
                    portalAccent: TintColor(r: 0.45, g: 0.65, b: 0.8, a: 1),
                    ambienceBrightness: 1.0,
                    fogDensity: 0.0,
                    fogColor: TintColor(r: 0.7, g: 0.8, b: 0.9, a: 0.0),
                    wallTint: TintColor(r: 0.95, g: 0.97, b: 1.0, a: 0.24),
                    wallEmissive: TintColor(r: 0.85, g: 0.92, b: 1.0, a: 1),
                    wallOpacity: 0.24,
                    wallEmissiveIntensity: 0.28,
                    coinTint: TintColor(r: 0.85, g: 0.95, b: 1.0, a: 1)
                ),
                ghostWallChance: 0.45,
                ghostWallOpacity: 0.075,
                lowCrawlTeachCount: 0,
                duckHazardChance: 0,
                summitStepTeachCount: 0,
                jumpHazardChance: 0
            )

        case .lowCrawl:
            return EnvironmentProfile(
                id: .lowCrawl,
                twist: .lowCrawl,
                palette: EnvironmentPalette(
                    floor: TintColor(r: 0.06, g: 0.1, b: 0.16, a: 1),
                    laneStripe: TintColor(r: 0.25, g: 0.75, b: 1.0, a: 0.85),
                    portalRim: TintColor(r: 0.2, g: 0.7, b: 1.0, a: 1),
                    portalVoid: TintColor(r: 0.02, g: 0.04, b: 0.08, a: 1),
                    portalRail: TintColor(r: 0.2, g: 0.65, b: 0.95, a: 1),
                    portalAccent: TintColor(r: 0.15, g: 0.45, b: 0.75, a: 1),
                    ambienceBrightness: 0.85,
                    fogDensity: 0.0,
                    fogColor: TintColor(r: 0.15, g: 0.3, b: 0.45, a: 0.0),
                    wallTint: TintColor(r: 0.2, g: 0.45, b: 0.85, a: 0.42),
                    wallEmissive: TintColor(r: 0.25, g: 0.55, b: 1.0, a: 1),
                    wallOpacity: 0.42,
                    wallEmissiveIntensity: 0.55,
                    coinTint: TintColor(r: 0.45, g: 0.9, b: 1.0, a: 1)
                ),
                ghostWallChance: 0,
                ghostWallOpacity: 0.42,
                lowCrawlTeachCount: 3,
                duckHazardChance: 0.55,
                summitStepTeachCount: 0,
                jumpHazardChance: 0
            )

        case .stormPass:
            return EnvironmentProfile(
                id: .stormPass,
                twist: .windShove,
                palette: EnvironmentPalette(
                    floor: TintColor(r: 0.07, g: 0.09, b: 0.14, a: 1),
                    laneStripe: TintColor(r: 0.45, g: 0.65, b: 0.85, a: 0.8),
                    portalRim: TintColor(r: 0.4, g: 0.7, b: 0.95, a: 1),
                    portalVoid: TintColor(r: 0.02, g: 0.03, b: 0.06, a: 1),
                    portalRail: TintColor(r: 0.35, g: 0.6, b: 0.85, a: 1),
                    portalAccent: TintColor(r: 0.25, g: 0.4, b: 0.65, a: 1),
                    ambienceBrightness: 0.75,
                    fogDensity: 0.0,
                    fogColor: TintColor(r: 0.3, g: 0.4, b: 0.55, a: 0.0),
                    wallTint: TintColor(r: 0.35, g: 0.45, b: 0.7, a: 0.42),
                    wallEmissive: TintColor(r: 0.4, g: 0.55, b: 0.95, a: 1),
                    wallOpacity: 0.42,
                    wallEmissiveIntensity: 0.5,
                    coinTint: TintColor(r: 0.75, g: 0.9, b: 1.0, a: 1)
                ),
                ghostWallChance: 0,
                ghostWallOpacity: 0.42,
                lowCrawlTeachCount: 0,
                duckHazardChance: 0,
                summitStepTeachCount: 0,
                jumpHazardChance: 0
            )

        case .crystalCave:
            return EnvironmentProfile(
                id: .crystalCave,
                twist: .crystalHalves,
                palette: EnvironmentPalette(
                    floor: TintColor(r: 0.1, g: 0.06, b: 0.16, a: 1),
                    laneStripe: TintColor(r: 0.7, g: 0.4, b: 1.0, a: 0.85),
                    portalRim: TintColor(r: 0.75, g: 0.35, b: 1.0, a: 1),
                    portalVoid: TintColor(r: 0.04, g: 0.02, b: 0.08, a: 1),
                    portalRail: TintColor(r: 0.65, g: 0.3, b: 0.95, a: 1),
                    portalAccent: TintColor(r: 0.45, g: 0.2, b: 0.75, a: 1),
                    ambienceBrightness: 0.9,
                    fogDensity: 0.0,
                    fogColor: TintColor(r: 0.45, g: 0.25, b: 0.65, a: 0.0),
                    wallTint: TintColor(r: 0.65, g: 0.25, b: 0.85, a: 0.38),
                    wallEmissive: TintColor(r: 0.75, g: 0.3, b: 1.0, a: 1),
                    wallOpacity: 0.38,
                    wallEmissiveIntensity: 0.6,
                    coinTint: TintColor(r: 0.85, g: 0.55, b: 1.0, a: 1)
                ),
                ghostWallChance: 0,
                ghostWallOpacity: 0.38,
                lowCrawlTeachCount: 0,
                duckHazardChance: 0,
                summitStepTeachCount: 0,
                jumpHazardChance: 0
            )
        }
    }
}
