//
//  PlayMode.swift
//  Slipframe
//
//  Player-facing run configuration: Normal, Playlist, Loop, and Daily.
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
}

/// Resolved configuration handed to EnvironmentDirector when a run begins.
enum PlayMode: Equatable {
    case normal
    case solo(EnvironmentID)
    /// `environments` must be non-empty. `start` nil → random pick from the set.
    case playlist(environments: Set<EnvironmentID>, start: EnvironmentID?)
    case daily
    var kind: PlayModeKind {
        switch self {
        case .normal: return .normal
        case .solo: return .solo
        case .playlist: return .playlist
        case .daily: return .daily
        }
    }

    /// Leaderboard category key for ranked modes.
    var leaderboardCategory: String? {
        LeaderboardBoard.matching(self)?.categoryKey
    }
}
