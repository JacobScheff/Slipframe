//
//  PlayMode.swift
//  Slipframe
//
//  Player-facing run configuration: Normal, Playlist, Loop, Daily, Tutorial.
//

import Foundation

enum PlayModeKind: String, CaseIterable, Identifiable {
    case normal
    case playlist
    case solo
    case daily

    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal: return "Normal"
        case .playlist: return "Playlist"
        case .solo: return "Loop"
        case .daily: return "Daily"
        }
    }

    var subtitle: String {
        switch self {
        case .normal:
            return "Random biomes, always opens on Ember Run."
        case .playlist:
            return "Your biomes, shuffled each switch. Pick a start or leave it random."
        case .solo:
            return "One biome on loop."
        case .daily:
            return "Same biomes and walls for everyone today (Eastern Time)."
        }
    }
}

/// Resolved configuration handed to EnvironmentDirector when a run begins.
enum PlayMode: Equatable {
    case normal
    case solo(EnvironmentID)
    /// `environments` must be non-empty. `start` nil → random pick from the set.
    case playlist(environments: Set<EnvironmentID>, start: EnvironmentID?)
    case daily
    /// Guided calibration run driven by `TutorialDirector` + `tutorial.m4a`.
    case tutorial

    var kind: PlayModeKind {
        switch self {
        case .normal, .tutorial: return .normal
        case .solo: return .solo
        case .playlist: return .playlist
        case .daily: return .daily
        }
    }

    var displayLabel: String {
        switch self {
        case .normal:
            return "Normal"
        case .solo(let id):
            return "Loop · \(id.displayName)"
        case .playlist(let environments, let start):
            let count = environments.count
            if let start {
                return "Playlist · \(count) · start \(start.displayName)"
            }
            return "Playlist · \(count) · random start"
        case .daily:
            return "Daily · \(DailyChallenge.displayDate())"
        case .tutorial:
            return "Tutorial"
        }
    }

    /// Leaderboard category key. Playlists and tutorial stay off the board.
    var leaderboardCategory: String? {
        LeaderboardBoard.matching(self)?.categoryKey
    }
}
