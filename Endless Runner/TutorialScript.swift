//
//  TutorialScript.swift
//  Slipframe
//
//  Timestamped sections for the single bundled tutorial track (`tutorial.m4a`).
//

import Foundation

/// Filename stem for `Music/tutorial.m4a` (or .mp3 / .wav / …).
enum TutorialMusic {
    static let cue = "tutorial"
    /// Built-in silence / hand-off beat in the master track (do not cut playback early).
    static let silenceAt: Float = 171
}

enum TutorialSectionID: String, CaseIterable, Equatable {
    case basics
    case ducking
    case movingWalls
    case phantomWalls
    case crystalCave
    case jumping
    case overdrive
    case outro
}

struct TutorialSection: Equatable {
    var id: TutorialSectionID
    /// Inclusive start time in the tutorial song (seconds).
    var startTime: Float
    /// Exclusive end time (seconds). Outro uses +∞ conceptually via `silenceAt`.
    var endTime: Float
    /// Biome visuals / spawn rules. Nil keeps the previous environment (outro).
    var environment: EnvironmentID?
    var title: String
    var body: String
    /// Multiplies base scroll speed for this section.
    var speedMultiplier: Float
    /// When true, coaching overlay fades out (overdrive hand-off).
    var hidesOverlay: Bool
    /// Violent portal pulse for the finale.
    var portalOverdrive: Bool
    /// Flash success banner, then reveal the main menu.
    var isOutro: Bool
}

enum TutorialCatalog {
    /// Ordered beats matching the tutorial master track.
    static let sections: [TutorialSection] = [
        TutorialSection(
            id: .basics,
            startTime: 0,
            endTime: 26,
            environment: .emberRun,
            title: "The Basics",
            body: "Side-step the red walls. Reach for glowing Data Tokens with your hands.",
            speedMultiplier: 1.0,
            hidesOverlay: false,
            portalOverdrive: false,
            isOutro: false
        ),
        TutorialSection(
            id: .ducking,
            startTime: 26,
            endTime: 42,
            environment: .lowCrawl,
            title: "Ducking Protocol",
            body: "Low slabs ahead — duck your head under the hanging barriers.",
            speedMultiplier: 1.0,
            hidesOverlay: false,
            portalOverdrive: false,
            isOutro: false
        ),
        TutorialSection(
            id: .movingWalls,
            startTime: 42,
            endTime: 71,
            environment: .stormPass,
            title: "Moving Walls",
            body: "Wind shoves the corridor. Weave left and right as the walls drift.",
            speedMultiplier: 1.05,
            hidesOverlay: false,
            portalOverdrive: false,
            isOutro: false
        ),
        TutorialSection(
            id: .phantomWalls,
            startTime: 71,
            endTime: 93,
            environment: .ghostGlass,
            title: "Phantom Walls",
            body: "Some walls are nearly invisible. Stay alert — they still collide.",
            speedMultiplier: 1.0,
            hidesOverlay: false,
            portalOverdrive: false,
            isOutro: false
        ),
        TutorialSection(
            id: .crystalCave,
            startTime: 93,
            endTime: 120,
            environment: .crystalCave,
            title: "Crystal Cave",
            body: "Fist-grab a crystal half, then slam different colors together to combine.",
            speedMultiplier: 1.0,
            hidesOverlay: false,
            portalOverdrive: false,
            isOutro: false
        ),
        TutorialSection(
            id: .jumping,
            startTime: 120,
            endTime: 144,
            environment: .summitStep,
            title: "Jumping Mechanic",
            body: "Floor hurdles incoming — hop so your head clears the low barriers.",
            speedMultiplier: 1.05,
            hidesOverlay: false,
            portalOverdrive: false,
            isOutro: false
        ),
        TutorialSection(
            id: .overdrive,
            startTime: 144,
            endTime: 171,
            environment: .emberRun,
            title: "System Overdrive",
            body: "Calibration complete. Survive the surge.",
            speedMultiplier: 1.45,
            hidesOverlay: true,
            portalOverdrive: true,
            isOutro: false
        ),
        TutorialSection(
            id: .outro,
            startTime: 171,
            endTime: 176,
            environment: nil,
            title: "TEST RUN SUCCEEDED",
            body: "",
            speedMultiplier: 0,
            hidesOverlay: true,
            portalOverdrive: false,
            isOutro: true
        )
    ]

    static func sectionIndex(at time: Float) -> Int {
        for (index, section) in sections.enumerated() {
            if time < section.endTime {
                return index
            }
        }
        return sections.count - 1
    }

    static func section(at time: Float) -> TutorialSection {
        sections[sectionIndex(at: time)]
    }
}
