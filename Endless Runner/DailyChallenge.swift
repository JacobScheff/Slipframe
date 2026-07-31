//
//  DailyChallenge.swift
//  Endless Runner
//
//  Shared daily seed (America/New_York day boundary) so every player
//  gets the same endless random sequence for a given calendar day.
//

import Foundation

/// Deterministic RNG used for daily challenge (and tests).
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x4d595df4d0f33173 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}

enum DailyChallenge {
    /// Eastern Time — EST/EDT via the Olson identifier.
    static let timeZone = TimeZone(identifier: "America/New_York")!

    static func dayKey(for date: Date = Date(), timeZone: TimeZone = timeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func displayDate(for date: Date = Date(), timeZone: TimeZone = timeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }

    /// Stable UInt64 seed derived from the day key (and a version tag).
    static func seed(for dayKey: String) -> UInt64 {
        let material = "daily-\(dayKey)-v1"
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325 // FNV-1a 64-bit offset
        for byte in material.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100_0000_01b3
        }
        return hash
    }

    static func makeGenerator(dayKey: String) -> SeededGenerator {
        SeededGenerator(seed: seed(for: dayKey))
    }

    /// Seconds until the next midnight in America/New_York.
    static func secondsUntilRollover(from date: Date = Date(), timeZone: TimeZone = timeZone) -> TimeInterval {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let startOfDay = calendar.startOfDay(for: date)
        guard let nextMidnight = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return 0
        }
        return max(0, nextMidnight.timeIntervalSince(date))
    }

    static func formatCountdown(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }

    /// First `count` biomes for today's shared seed (start is randomized — not Ember-locked).
    static func previewSequence(dayKey: String, count: Int = 6) -> [EnvironmentID] {
        guard count > 0 else { return [] }
        var rng = makeGenerator(dayKey: dayKey)
        var current = EnvironmentID.allCases.randomElement(using: &rng) ?? .emberRun
        var result: [EnvironmentID] = [current]
        let pool = Array(EnvironmentID.allCases)
        for _ in 1..<count {
            current = EnvironmentDirector.randomNext(excluding: current, from: pool, rng: &rng)
            result.append(current)
        }
        return result
    }
}
