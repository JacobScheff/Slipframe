//
//  PersonalBestStore.swift
//  Slipframe
//
//  Local personal bests per leaderboard category (Normal, each Loop biome, Daily).
//  Game Center submission / remote loads live in GameCenterService.
//

import Foundation

struct PersonalBest: Equatable, Codable {
    var bestScore: Int
    var bestCoins: Int

    static let zero = PersonalBest(bestScore: 0, bestCoins: 0)
}

struct PersonalBestUpdate: Equatable {
    var scoreImproved: Bool
    var coinsImproved: Bool

    var anyImproved: Bool { scoreImproved || coinsImproved }
}

/// Browseable boards shown in the right-track leaderboard panel.
enum LeaderboardBoard: Hashable, Identifiable {
    case normal
    case loop(EnvironmentID)
    case daily(dayKey: String)

    var id: String { categoryKey }

    var categoryKey: String {
        switch self {
        case .normal:
            return "normal"
        case .loop(let id):
            return id.rawValue
        case .daily(let dayKey):
            return "daily.\(dayKey)"
        }
    }

    var title: String {
        switch self {
        case .normal:
            return "Normal"
        case .loop(let id):
            return id.displayName
        case .daily(let dayKey):
            return "Daily · \(Self.shortDate(for: dayKey))"
        }
    }

    var subtitle: String {
        switch self {
        case .normal:
            return "Random biomes"
        case .loop:
            return "Loop"
        case .daily:
            return "Shared challenge"
        }
    }

    /// Compact label for board chips (avoids long Daily dates in the grid).
    var chipTitle: String {
        switch self {
        case .normal:
            return "Normal"
        case .loop(let id):
            return id.displayName
        case .daily:
            return "Daily"
        }
    }

    /// Boards players can browse: Normal → Daily → each Loop biome.
    static func browseable(on date: Date = Date()) -> [LeaderboardBoard] {
        var boards: [LeaderboardBoard] = [
            .normal,
            .daily(dayKey: DailyChallenge.dayKey(for: date))
        ]
        boards.append(contentsOf: EnvironmentID.allCases.map { .loop($0) })
        return boards
    }

    static func matching(_ mode: PlayMode, on date: Date = Date()) -> LeaderboardBoard? {
        switch mode {
        case .normal:
            return .normal
        case .solo(let id):
            return .loop(id)
        case .playlist, .tutorial:
            return nil
        case .daily:
            return .daily(dayKey: DailyChallenge.dayKey(for: date))
        }
    }

    private static func shortDate(for dayKey: String) -> String {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = DailyChallenge.timeZone
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: dayKey) else { return dayKey }

        let display = DateFormatter()
        display.calendar = Calendar(identifier: .gregorian)
        display.locale = Locale(identifier: "en_US")
        display.timeZone = DailyChallenge.timeZone
        display.dateFormat = "MMM d"
        return display.string(from: date)
    }
}

enum LeaderboardMetric: String, CaseIterable, Identifiable {
    case score
    case coins

    var id: String { rawValue }

    var title: String {
        switch self {
        case .score: return "Score"
        case .coins: return "Tokens"
        }
    }
}

@MainActor
final class PersonalBestStore: ObservableObject {
    @Published private(set) var bests: [String: PersonalBest] = [:]

    private let defaults: UserDefaults
    private let storageKey: String

    init(defaults: UserDefaults = .standard, storageKey: String = "personalBests.v1") {
        self.defaults = defaults
        self.storageKey = storageKey
        reload()
    }

    func best(for category: String) -> PersonalBest {
        bests[category] ?? .zero
    }

    func best(for board: LeaderboardBoard) -> PersonalBest {
        best(for: board.categoryKey)
    }

    func value(_ metric: LeaderboardMetric, for board: LeaderboardBoard) -> Int {
        let entry = best(for: board)
        switch metric {
        case .score: return entry.bestScore
        case .coins: return entry.bestCoins
        }
    }

    /// Updates stored bests when either metric improves. Returns which metrics changed.
    @discardableResult
    func record(category: String, score: Int, coins: Int) -> PersonalBestUpdate {
        let current = best(for: category)
        let scoreImproved = score > current.bestScore
        let coinsImproved = coins > current.bestCoins
        guard scoreImproved || coinsImproved else {
            return PersonalBestUpdate(scoreImproved: false, coinsImproved: false)
        }

        var next = current
        if scoreImproved { next.bestScore = score }
        if coinsImproved { next.bestCoins = coins }
        bests[category] = next
        persist()
        return PersonalBestUpdate(scoreImproved: scoreImproved, coinsImproved: coinsImproved)
    }

    @discardableResult
    func record(board: LeaderboardBoard, score: Int, coins: Int) -> PersonalBestUpdate {
        record(category: board.categoryKey, score: score, coins: coins)
    }

    func reload() {
        guard let data = defaults.data(forKey: storageKey) else {
            bests = [:]
            return
        }
        do {
            bests = try JSONDecoder().decode([String: PersonalBest].self, from: data)
        } catch {
            bests = [:]
        }
    }

    /// Test helper — clears in-memory and persisted state.
    func resetAll() {
        bests = [:]
        defaults.removeObject(forKey: storageKey)
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(bests)
            defaults.set(data, forKey: storageKey)
        } catch {
            // Ignore encode failures; in-memory bests still apply for the session.
        }
    }
}
