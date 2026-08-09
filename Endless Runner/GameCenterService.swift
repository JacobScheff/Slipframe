//
//  GameCenterService.swift
//  Endless Runner
//
//  Game Center auth, score submission, and leaderboard loads.
//
//  App Store Connect / Developer setup (manual) — required before remote
//  boards work. GKError 15 (“not recognized by Game Center”) means this
//  checklist is incomplete or Apple’s catalog hasn’t refreshed yet:
//  1. Developer portal App ID `Jacob-Scheff.Endless-Runner-1` → enable Game Center.
//  2. App Store Connect app with that exact bundle ID → Services → Game Center on.
//  3. Create leaderboards with these IDs (classic unless noted):
//     score/coins × normal, emberRun, fogHollow, ghostGlass, lowCrawl,
//     stormPass, crystalCave → e.g. `score.normal`, `coins.emberRun`.
//     Recurring daily (1-day): `score.daily`, `coins.daily`.
//  4. If still unrecognized: add/remove a dummy leaderboard to force a refresh,
//     wait for propagation, delete the app from device, rebuild & relaunch.
//  5. Sandbox-test with two+ Game Center accounts (Friends scope).
//

import Foundation
import GameKit
import SwiftUI
import UIKit

enum GameCenterErrorPresentation {
    static let expectedBundleID = "Jacob-Scheff.Endless-Runner-1"

    /// User-facing copy for GameKit failures (keeps local bests usable).
    static func message(for error: Error) -> String {
        let nsError = error as NSError
        let description = nsError.localizedDescription
        let isUnrecognized =
            (nsError.domain == GKError.errorDomain
                && nsError.code == GKError.Code.gameUnrecognized.rawValue)
            || description.localizedCaseInsensitiveContains("not recognized by Game Center")

        if isUnrecognized {
            return """
            Game Center doesn’t recognize this build yet. Enable Game Center for bundle ID \(expectedBundleID) in the Developer portal and App Store Connect, create the leaderboards listed in GameCenterService.swift, then delete the app and relaunch. Local bests still work.
            """
        }
        return description
    }
}

enum LeaderboardAudience: String, CaseIterable, Identifiable {
    case allPlayers
    case friends

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allPlayers: return "All Players"
        case .friends: return "Friends"
        }
    }

    var playerScope: GKLeaderboard.PlayerScope {
        switch self {
        case .allPlayers: return .global
        case .friends: return .friendsOnly
        }
    }
}

struct RemoteLeaderboardEntry: Identifiable, Equatable {
    var id: String { "\(rank)-\(displayName)-\(value)" }
    let rank: Int
    let displayName: String
    let value: Int
    let isLocalPlayer: Bool
}

struct RemoteLeaderboardSnapshot: Equatable {
    var entries: [RemoteLeaderboardEntry]
    var localRank: Int?
    var localValue: Int?
}

/// Maps browseable boards + metrics onto App Store Connect leaderboard IDs.
enum GameCenterLeaderboardID {
    static func identifier(metric: LeaderboardMetric, board: LeaderboardBoard) -> String {
        switch board {
        case .normal:
            return "\(metric.rawValue).normal"
        case .loop(let environment):
            return "\(metric.rawValue).\(environment.rawValue)"
        case .daily:
            // Recurring daily board in App Store Connect (not per calendar-day ID).
            return "\(metric.rawValue).daily"
        }
    }

    /// All classic + recurring IDs that should exist in App Store Connect.
    static var allConfiguredIDs: [String] {
        var ids: [String] = []
        for metric in LeaderboardMetric.allCases {
            ids.append(identifier(metric: metric, board: .normal))
            for environment in EnvironmentID.allCases {
                ids.append(identifier(metric: metric, board: .loop(environment)))
            }
            ids.append(identifier(metric: metric, board: .daily(dayKey: "placeholder")))
        }
        return ids
    }
}

/// Abstraction so tests can observe submit calls without talking to GameKit.
@MainActor
protocol GameCenterSubmitting: AnyObject {
    func submitRun(board: LeaderboardBoard, score: Int, coins: Int)
}

@MainActor
final class GameCenterService: NSObject, ObservableObject, GameCenterSubmitting {
    @Published private(set) var isAuthenticated = false
    @Published private(set) var localPlayerDisplayName: String?
    @Published private(set) var statusMessage: String = "Checking Game Center…"
    /// GameKit sign-in UI to present from `GameCenterAuthWindow` (not immersive sheets).
    @Published private(set) var authenticationViewController: UIViewController?
    /// True while GameKit has handed us a sign-in controller that still needs presentation.
    @Published private(set) var needsSignInPresentation = false

    @Published private(set) var remoteSnapshot: RemoteLeaderboardSnapshot?
    @Published private(set) var isLoadingRemote = false
    @Published private(set) var remoteErrorMessage: String?

    private var didConfigureHandler = false
    private var personalBests: PersonalBestStore?
    private var loadTask: Task<Void, Never>?

    func attachPersonalBests(_ store: PersonalBestStore) {
        personalBests = store
    }

    /// Installs the GameKit auth handler (idempotent). Call once on app/immersive appear.
    func start() {
        guard !didConfigureHandler else {
            refreshAuthState()
            return
        }
        didConfigureHandler = true

        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            Task { @MainActor in
                guard let self else { return }
                if GKLocalPlayer.local.isAuthenticated {
                    self.clearAuthenticationPresentation()
                    self.refreshAuthState(error: error)
                    await self.publishAllLocalBests()
                } else {
                    self.authenticationViewController = viewController
                    self.needsSignInPresentation = viewController != nil
                    self.refreshAuthState(error: error)
                }
            }
        }
    }

    /// Clears a dismissed / completed sign-in presentation without disturbing auth state.
    func clearAuthenticationPresentation() {
        authenticationViewController = nil
        needsSignInPresentation = false
    }

    func refreshAuthState(error: Error? = nil) {
        let player = GKLocalPlayer.local
        isAuthenticated = player.isAuthenticated
        if player.isAuthenticated {
            localPlayerDisplayName = player.displayName
            statusMessage = "Signed in as \(player.displayName)"
            remoteErrorMessage = nil
        } else if let error {
            localPlayerDisplayName = nil
            statusMessage = "Game Center unavailable — local bests only."
            remoteErrorMessage = GameCenterErrorPresentation.message(for: error)
        } else if needsSignInPresentation {
            localPlayerDisplayName = nil
            statusMessage = "Sign in to Game Center to compete."
        } else {
            localPlayerDisplayName = nil
            statusMessage = "Not signed in — local bests only."
        }
    }

    /// Submits this run’s score + coins. Game Center keeps the player’s best.
    func submitRun(board: LeaderboardBoard, score: Int, coins: Int) {
        Task {
            await submitRunAsync(board: board, score: score, coins: coins)
        }
    }

    func submitRunAsync(board: LeaderboardBoard, score: Int, coins: Int) async {
        guard GKLocalPlayer.local.isAuthenticated else { return }
        guard score > 0 || coins > 0 else { return }

        do {
            if score > 0 {
                try await GKLeaderboard.submitScore(
                    score,
                    context: 0,
                    player: GKLocalPlayer.local,
                    leaderboardIDs: [GameCenterLeaderboardID.identifier(metric: .score, board: board)]
                )
            }
            if coins > 0 {
                try await GKLeaderboard.submitScore(
                    coins,
                    context: 0,
                    player: GKLocalPlayer.local,
                    leaderboardIDs: [GameCenterLeaderboardID.identifier(metric: .coins, board: board)]
                )
            }
        } catch {
            remoteErrorMessage = GameCenterErrorPresentation.message(for: error)
        }
    }

    /// Pushes every stored local best into Game Center after sign-in.
    func publishAllLocalBests() async {
        guard let personalBests, GKLocalPlayer.local.isAuthenticated else { return }
        for board in LeaderboardBoard.browseable() {
            let best = personalBests.best(for: board)
            await submitRunAsync(board: board, score: best.bestScore, coins: best.bestCoins)
        }
    }

    func loadRemoteScores(
        board: LeaderboardBoard,
        metric: LeaderboardMetric,
        audience: LeaderboardAudience,
        count: Int = 10
    ) {
        loadTask?.cancel()
        loadTask = Task {
            await loadRemoteScoresAsync(board: board, metric: metric, audience: audience, count: count)
        }
    }

    func loadRemoteScoresAsync(
        board: LeaderboardBoard,
        metric: LeaderboardMetric,
        audience: LeaderboardAudience,
        count: Int = 10
    ) async {
        guard GKLocalPlayer.local.isAuthenticated else {
            remoteSnapshot = nil
            remoteErrorMessage = nil
            isLoadingRemote = false
            return
        }

        isLoadingRemote = true
        remoteErrorMessage = nil
        defer { isLoadingRemote = false }

        let leaderboardID = GameCenterLeaderboardID.identifier(metric: metric, board: board)
        do {
            let leaderboards = try await GKLeaderboard.loadLeaderboards(IDs: [leaderboardID])
            guard let leaderboard = leaderboards.first else {
                remoteSnapshot = RemoteLeaderboardSnapshot(entries: [], localRank: nil, localValue: nil)
                remoteErrorMessage = "Leaderboard “\(leaderboardID)” not found in App Store Connect."
                return
            }

            let length = max(1, count)
            let (localEntry, entries, _) = try await leaderboard.loadEntries(
                for: audience.playerScope,
                timeScope: .allTime,
                range: NSRange(location: 1, length: length)
            )

            if Task.isCancelled { return }

            let localPlayerID = GKLocalPlayer.local.gamePlayerID
            let mapped = (entries).map { entry in
                RemoteLeaderboardEntry(
                    rank: entry.rank,
                    displayName: entry.player.displayName,
                    value: entry.score,
                    isLocalPlayer: entry.player.gamePlayerID == localPlayerID
                )
            }
            remoteSnapshot = RemoteLeaderboardSnapshot(
                entries: mapped,
                localRank: localEntry?.rank,
                localValue: localEntry?.score
            )
        } catch {
            if Task.isCancelled { return }
            remoteSnapshot = nil
            remoteErrorMessage = GameCenterErrorPresentation.message(for: error)
        }
    }

    func clearRemote() {
        loadTask?.cancel()
        remoteSnapshot = nil
        remoteErrorMessage = nil
        isLoadingRemote = false
    }
}
