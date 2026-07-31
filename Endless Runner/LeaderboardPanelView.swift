//
//  LeaderboardPanelView.swift
//  Endless Runner
//
//  Right-track placeholder for future local + Game Center boards.
//  Score tracking / GC submission intentionally deferred.
//

import SwiftUI

struct LeaderboardPanelView: View {
    private let neon = Color(red: 0.35, green: 0.92, blue: 1.0)
    private let gold = Color(red: 1.0, green: 0.82, blue: 0.32)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SCORES")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(gold.opacity(0.9))
                Text("Leaderboard")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            }

            Divider().opacity(0.35)

            VStack(alignment: .leading, spacing: 10) {
                Text("Coming soon")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(neon)

                Text("Top score and top coins per mode — Normal, each Loop biome, and Daily. Playlists stay off the board.")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Local bests first, then Game Center for All Players / Friends.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(width: 420, height: 360, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(gold.opacity(0.4), lineWidth: 1.2)
        }
        .glassBackgroundEffect()
    }
}

#Preview {
    LeaderboardPanelView()
}
