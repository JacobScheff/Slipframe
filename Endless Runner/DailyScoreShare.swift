//
//  DailyScoreShare.swift
//  Slipframe
//
//  Builds a Messages (iMessage / SMS) share payload for today’s Daily best.
//

import Foundation

enum DailyScoreShare {
    /// Player-facing copy for challenging a friend with today’s Daily top score.
    static func message(score: Int, date: Date = Date()) -> String {
        let day = DailyChallenge.displayDate(for: date)
        if score > 0 {
            return "I scored \(score) on Slipframe Daily (\(day)). Can you beat it?"
        }
        return "Challenge me on Slipframe Daily (\(day))!"
    }

    /// Opens Messages with the challenge text prefilled (`sms:` URL scheme).
    static func messagesURL(score: Int, date: Date = Date()) -> URL? {
        var components = URLComponents()
        components.scheme = "sms"
        components.queryItems = [
            URLQueryItem(name: "body", value: message(score: score, date: date))
        ]
        return components.url
    }
}
