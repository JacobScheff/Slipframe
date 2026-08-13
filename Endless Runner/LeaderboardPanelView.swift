//
//  LeaderboardPanelView.swift
//  Slipframe
//
//  Right-track leaderboard: local personal bests always, plus Game Center
//  All Players / Friends when signed in.
//

import SwiftUI

struct LeaderboardPanelView: View {
    @EnvironmentObject private var gameModel: GameModel
    @EnvironmentObject private var personalBests: PersonalBestStore
    @EnvironmentObject private var gameCenter: GameCenterService
    @Environment(\.openURL) private var openURL

    @State private var selectedBoard: LeaderboardBoard = .normal
    @State private var metric: LeaderboardMetric = .score
    @State private var audience: LeaderboardAudience = .allPlayers

    private let neon = Color(red: 0.35, green: 0.92, blue: 1.0)
    private let gold = Color(red: 1.0, green: 0.82, blue: 0.32)
    private let dailyAccent = Color(red: 0.45, green: 0.88, blue: 0.78)

    private var boards: [LeaderboardBoard] {
        LeaderboardBoard.browseable()
    }

    private let boardColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            metricPicker

            audiencePicker

            boardPicker
                .padding(.top, 4)

            Divider().opacity(0.35)

            localBestRow

            if case .daily = selectedBoard, metric == .score {
                dailyMessagesShareButton
            }

            remoteBlock
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .frame(width: 620, alignment: .topLeading)
        .xenotechPanel(primary: gold, secondary: neon, cornerRadius: 22)
        .onAppear {
            syncBoardToPlayMode()
            reloadRemote()
        }
        .onChange(of: gameModel.playKind) { _, _ in
            syncBoardToPlayMode()
        }
        .onChange(of: gameModel.soloEnvironment) { _, _ in
            syncBoardToPlayMode()
        }
        .onChange(of: selectedBoard) { _, _ in
            reloadRemote()
        }
        .onChange(of: metric) { _, _ in
            reloadRemote()
        }
        .onChange(of: audience) { _, _ in
            reloadRemote()
        }
        .onChange(of: gameCenter.isAuthenticated) { _, _ in
            reloadRemote()
        }
        .onChange(of: gameModel.isGameOver) { _, isOver in
            if isOver { reloadRemote() }
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
            Text(gameCenter.statusMessage)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    /// Primary Score / Tokens sections — large, visual, spaced away from filters below.
    private var metricPicker: some View {
        HStack(spacing: 12) {
            ForEach(LeaderboardMetric.allCases) { option in
                metricSectionButton(option)
            }
        }
    }

    private func metricSectionButton(_ option: LeaderboardMetric) -> some View {
        let selected = metric == option
        let color = accent(for: option)

        return Button {
            metric = option
        } label: {
            VStack(spacing: 6) {
                Image(systemName: metricSymbol(for: option))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(selected ? color : color.opacity(0.55))
                    .symbolRenderingMode(.hierarchical)

                Text(option.title.uppercased())
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(selected ? color : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: selected
                                ? [color.opacity(0.28), color.opacity(0.1)]
                                : [Color.white.opacity(0.07), Color.white.opacity(0.03)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(
                                selected ? color.opacity(0.85) : Color.white.opacity(0.12),
                                lineWidth: selected ? 1.6 : 1
                            )
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var audiencePicker: some View {
        HStack(spacing: 8) {
            ForEach(LeaderboardAudience.allCases) { option in
                pickerButton(
                    title: option.title,
                    selected: audience == option,
                    accent: gold
                ) {
                    audience = option
                }
            }
        }
    }

    private var boardPicker: some View {
        LazyVGrid(columns: boardColumns, spacing: 8) {
            ForEach(boards) { board in
                let selected = selectedBoard == board
                Button {
                    selectedBoard = board
                } label: {
                    Text(board.chipTitle)
                        .font(.system(size: 13, weight: selected ? .bold : .medium, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selected ? gold.opacity(0.22) : Color.white.opacity(0.06))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
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

    private var localBestRow: some View {
        let value = personalBests.value(metric, for: selectedBoard)
        let highlightNew = isHighlightingNewBest(for: metric)

        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("YOUR BEST · \(selectedBoard.title.uppercased())")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(accent(for: metric).opacity(0.85))
                Text(value > 0 ? "\(value)" : "—")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(highlightNew ? accent(for: metric) : .primary)
            }
            Spacer()
            if highlightNew {
                Text("NEW")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(1.1)
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

    @ViewBuilder
    private var dailyMessagesShareButton: some View {
        let value = personalBests.value(.score, for: selectedBoard)
        Button {
            guard value > 0, let url = DailyScoreShare.messagesURL(score: value) else { return }
            openURL(url)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "message.fill")
                    .font(.system(size: 15, weight: .semibold))
                Text(value > 0 ? "Share Daily best to Messages" : "Play Daily to share")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Spacer(minLength: 4)
            }
            .foregroundStyle(value > 0 ? dailyAccent : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(dailyAccent.opacity(value > 0 ? 0.16 : 0.08))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(dailyAccent.opacity(value > 0 ? 0.55 : 0.22), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(value <= 0)
        .accessibilityLabel(
            value > 0
            ? "Share Daily best score \(value) to Messages"
            : "Play Daily to unlock Messages share"
        )
    }

    @ViewBuilder
    private var remoteBlock: some View {
        if !gameCenter.isAuthenticated {
            Text(
                audience == .friends
                ? "Sign in to Game Center to see Friends."
                : "Sign in to Game Center for All Players rankings."
            )
            .font(.system(size: 14, weight: .regular, design: .rounded))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        } else if gameCenter.isLoadingRemote {
            Text("Loading \(audience.title.lowercased())…")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        } else if let error = gameCenter.remoteErrorMessage, (gameCenter.remoteSnapshot?.entries.isEmpty ?? true) {
            Text(error)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(.orange.opacity(0.95))
                .fixedSize(horizontal: false, vertical: true)
        } else if let snapshot = gameCenter.remoteSnapshot {
            VStack(alignment: .leading, spacing: 8) {
                if let rank = snapshot.localRank, let value = snapshot.localValue {
                    Text("Your rank: #\(rank) · \(value)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(accent(for: metric).opacity(0.9))
                }

                if snapshot.entries.isEmpty {
                    Text("No scores yet for \(audience.title.lowercased()).")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snapshot.entries.prefix(8)) { entry in
                        HStack(spacing: 10) {
                            Text("#\(entry.rank)")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .leading)
                            Text(entry.displayName)
                                .font(.system(
                                    size: 14,
                                    weight: entry.isLocalPlayer ? .bold : .medium,
                                    design: .rounded
                                ))
                                .foregroundStyle(entry.isLocalPlayer ? accent(for: metric) : .primary)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text("\(entry.value)")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                        }
                    }
                }
            }
        } else {
            Text("Pulling \(audience.title.lowercased()) scores…")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private func pickerButton(
        title: String,
        selected: Bool,
        accent: Color,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: selected ? .bold : .medium, design: .rounded))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(selected ? accent.opacity(0.22) : Color.white.opacity(0.06))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            selected ? accent.opacity(0.7) : Color.white.opacity(0.12),
                            lineWidth: 1
                        )
                }
                .opacity(enabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func accent(for metric: LeaderboardMetric) -> Color {
        switch metric {
        case .score: return neon
        case .coins: return gold
        }
    }

    private func metricSymbol(for metric: LeaderboardMetric) -> String {
        switch metric {
        case .score: return "flag.checkered"
        case .coins: return "circle.circle.fill"
        }
    }

    private func syncBoardToPlayMode() {
        if let match = LeaderboardBoard.matching(gameModel.resolvedPlayMode) {
            selectedBoard = match
        }
    }

    private func reloadRemote() {
        guard gameCenter.isAuthenticated else {
            gameCenter.clearRemote()
            return
        }
        gameCenter.loadRemoteScores(board: selectedBoard, metric: metric, audience: audience)
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
    let bests = PersonalBestStore(defaults: UserDefaults(suiteName: "preview.leaderboard.gc")!)
    let model = GameModel(personalBests: bests)
    bests.record(category: "normal", score: 420, coins: 12)
    return LeaderboardPanelView()
        .environmentObject(model)
        .environmentObject(model.personalBests)
        .environmentObject(model.gameCenter)
}
