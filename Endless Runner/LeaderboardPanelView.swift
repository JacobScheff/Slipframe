//
//  LeaderboardPanelView.swift
//  Endless Runner
//
//  Right-track local personal bests for Normal, each Loop biome, and Daily.
//  Game Center (All Players / Friends) is deferred until wired up separately.
//

import SwiftUI

struct LeaderboardPanelView: View {
    @EnvironmentObject private var gameModel: GameModel
    @EnvironmentObject private var personalBests: PersonalBestStore

    @State private var selectedBoard: LeaderboardBoard = .normal
    @State private var metric: LeaderboardMetric = .score

    private let neon = Color(red: 0.35, green: 0.92, blue: 1.0)
    private let gold = Color(red: 1.0, green: 0.82, blue: 0.32)

    private var boards: [LeaderboardBoard] {
        LeaderboardBoard.browseable()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            metricPicker

            boardPicker

            Divider().opacity(0.35)

            bestBlock

            Spacer(minLength: 0)

            footerNote
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(width: 420, height: 420, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(gold.opacity(0.4), lineWidth: 1.2)
        }
        .glassBackgroundEffect()
        .onAppear {
            syncBoardToPlayMode()
        }
        .onChange(of: gameModel.playKind) { _, _ in
            syncBoardToPlayMode()
        }
        .onChange(of: gameModel.soloEnvironment) { _, _ in
            syncBoardToPlayMode()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SCORES")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .tracking(2)
                .foregroundStyle(gold.opacity(0.9))
            Text("Leaderboard")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
        }
    }

    private var metricPicker: some View {
        HStack(spacing: 8) {
            ForEach(LeaderboardMetric.allCases) { option in
                let selected = metric == option
                Button {
                    metric = option
                } label: {
                    Text(option.title)
                        .font(.system(size: 15, weight: selected ? .bold : .medium, design: .rounded))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selected ? accent(for: option).opacity(0.22) : Color.white.opacity(0.06))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(
                                    selected ? accent(for: option).opacity(0.7) : Color.white.opacity(0.12),
                                    lineWidth: 1
                                )
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var boardPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(boards) { board in
                    let selected = selectedBoard == board
                    Button {
                        selectedBoard = board
                    } label: {
                        Text(board.title)
                            .font(.system(size: 14, weight: selected ? .bold : .medium, design: .rounded))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(selected ? gold.opacity(0.22) : Color.white.opacity(0.06))
                            }
                            .overlay {
                                Capsule(style: .continuous)
                                    .strokeBorder(
                                        selected ? gold.opacity(0.7) : Color.white.opacity(0.12),
                                        lineWidth: 1
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var bestBlock: some View {
        let value = personalBests.value(metric, for: selectedBoard)
        let otherMetric: LeaderboardMetric = metric == .score ? .coins : .score
        let otherValue = personalBests.value(otherMetric, for: selectedBoard)
        let highlightNew = isHighlightingNewBest(for: metric)

        return VStack(alignment: .leading, spacing: 12) {
            Text(selectedBoard.subtitle.uppercased())
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(accent(for: metric).opacity(0.85))

            Text(selectedBoard.title)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Your best \(metric.title.lowercased())")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(value > 0 ? "\(value)" : "—")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(highlightNew ? accent(for: metric) : .primary)

                    if highlightNew {
                        Text("NEW")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .tracking(1.2)
                            .foregroundStyle(accent(for: metric))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(accent(for: metric).opacity(0.18))
                            }
                    }
                }
            }

            Text("Best \(otherMetric.title.lowercased()): \(otherValue > 0 ? "\(otherValue)" : "—")")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary.opacity(0.9))
        }
    }

    private var footerNote: some View {
        Text("Local bests for now. Playlists stay off the board. Game Center All Players / Friends comes next.")
            .font(.system(size: 13, weight: .regular, design: .rounded))
            .foregroundStyle(.secondary.opacity(0.9))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func accent(for metric: LeaderboardMetric) -> Color {
        switch metric {
        case .score: return neon
        case .coins: return gold
        }
    }

    private func syncBoardToPlayMode() {
        if let match = LeaderboardBoard.matching(gameModel.resolvedPlayMode) {
            selectedBoard = match
        }
    }

    private func isHighlightingNewBest(for metric: LeaderboardMetric) -> Bool {
        guard gameModel.isGameOver,
              let update = gameModel.lastPersonalBestUpdate,
              let match = LeaderboardBoard.matching(gameModel.resolvedPlayMode),
              match == selectedBoard
        else { return false }

        switch metric {
        case .score: return update.scoreImproved
        case .coins: return update.coinsImproved
        }
    }
}

#Preview {
    let model = GameModel(
        personalBests: PersonalBestStore(defaults: UserDefaults(suiteName: "preview.leaderboard")!)
    )
    model.personalBests.record(category: "normal", score: 420, coins: 12)
    return LeaderboardPanelView()
        .environmentObject(model)
        .environmentObject(model.personalBests)
}
