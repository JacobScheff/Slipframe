//
//  EnvironmentProfile.swift
//  Endless Runner
//
//  Biome roster, palettes, and twist parameters. Materials / custom assets
//  should read tints from these profiles so art can be swapped in later.
//

import Foundation
import simd

enum EnvironmentID: String, CaseIterable, Identifiable, Codable {
    case emberRun
    case fogHollow
    case ghostGlass
    case lowCrawl
    case stormPass
    case crystalCave

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .emberRun: return "Ember Run"
        case .fogHollow: return "Fog Hollow"
        case .ghostGlass: return "Ghost Glass"
        case .lowCrawl: return "Low Crawl"
        case .stormPass: return "Storm Pass"
        case .crystalCave: return "Crystal Cave"
        }
    }

    /// Filename stem for the biome track in `Endless Runner/Music/`
    /// (e.g. `emberRun.m4a`). See Music/README.md.
    var musicCue: String { rawValue }
}

enum EnvironmentTwist: Equatable {
    case baseline
    case fogVisibility
    case ghostWalls
    case lowCrawl
    case windShove
    case crystalHalves
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
    /// >0 marks Fog Hollow — drives passthrough room dimming (not geometry fog cards).
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
                duckHazardChance: 0
            )

        case .fogHollow:
            return EnvironmentProfile(
                id: .fogHollow,
                twist: .fogVisibility,
                palette: EnvironmentPalette(
                    // Darker corridor so mist reads as gloom, not hard slabs.
                    floor: TintColor(r: 0.02, g: 0.022, b: 0.03, a: 1),
                    laneStripe: TintColor(r: 0.22, g: 0.26, b: 0.3, a: 0.35),
                    portalRim: TintColor(r: 0.18, g: 0.22, b: 0.26, a: 1),
                    portalVoid: TintColor(r: 0.008, g: 0.01, b: 0.014, a: 1),
                    portalRail: TintColor(r: 0.16, g: 0.2, b: 0.24, a: 1),
                    portalAccent: TintColor(r: 0.1, g: 0.12, b: 0.16, a: 1),
                    ambienceBrightness: 0.28,
                    // Room gloom comes from preferredSurroundingsEffect, not fog boxes.
                    fogDensity: 1.0,
                    fogColor: TintColor(r: 0.55, g: 0.6, b: 0.66, a: 0.0),
                    wallTint: TintColor(r: 0.45, g: 0.14, b: 0.12, a: 0.32),
                    wallEmissive: TintColor(r: 0.4, g: 0.12, b: 0.1, a: 1),
                    wallOpacity: 0.32,
                    wallEmissiveIntensity: 0.22,
                    coinTint: TintColor(r: 1.0, g: 0.86, b: 0.35, a: 1)
                ),
                ghostWallChance: 0,
                ghostWallOpacity: 0.32,
                lowCrawlTeachCount: 0,
                duckHazardChance: 0
            )

        case .ghostGlass:
            // All walls are white + transparent — no fog / haze volumes.
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
                    wallTint: TintColor(r: 0.95, g: 0.97, b: 1.0, a: 0.05),
                    wallEmissive: TintColor(r: 0.85, g: 0.92, b: 1.0, a: 1),
                    wallOpacity: 0.05,
                    wallEmissiveIntensity: 0.08,
                    coinTint: TintColor(r: 0.85, g: 0.95, b: 1.0, a: 1)
                ),
                ghostWallChance: 1.0,
                ghostWallOpacity: 0.05,
                lowCrawlTeachCount: 0,
                duckHazardChance: 0
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
                duckHazardChance: 0.55
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
                duckHazardChance: 0
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
                duckHazardChance: 0
            )
        }
    }
}

enum EnvironmentDebugMode: Equatable, Hashable {
    case normal
    case force(EnvironmentID)
}
