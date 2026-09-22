//
//  LeaderboardPanelView.swift
//  Slipframe
//
//  Scores tab: local personal bests always, plus Game Center
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

    private let neon = SlipframeUI.accent
    private let gold = SlipframeUI.reward
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

            localBestRow

            Divider().opacity(0.35)

            metricPicker

            boardPicker
                .padding(.top, 4)

            if case .daily = selectedBoard, metric == .score {
                dailyMessagesShareButton
            }

            audiencePicker

            remoteBlock
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Leaderboards")
                .font(.system(size: 23, weight: .semibold))
            HStack(spacing: 8) {
                Image(systemName: gameCenter.isAuthenticated ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                    .foregroundStyle(neon)
                    .accessibilityHidden(true)
                Text(gameCenter.statusMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var metricPicker: some View {
        HStack(spacing: 8) {
            ForEach(LeaderboardMetric.allCases) { option in
                Button {
                    metric = option
                } label: {
                    Label(option.title, systemImage: metricSymbol(for: option))
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 12)
                }
                .buttonStyle(ConsoleSelectionStyle(selected: metric == option))
                .accessibilityAddTraits(metric == option ? .isSelected : [])
            }
        }
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
        VStack(alignment: .leading, spacing: 10) {
            Text("LEADERBOARD")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: boardColumns, spacing: 8) {
                ForEach(boards) { board in
                    let selected = selectedBoard == board
                    Button {
                        selectedBoard = board
                    } label: {
                        Text(board.chipTitle)
                            .font(.system(size: 13, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(ConsoleSelectionStyle(selected: selected))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    private var localBestRow: some View {
        let value = personalBests.value(metric, for: selectedBoard)
        let highlightNew = isHighlightingNewBest(for: metric)

        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("YOUR BEST · \(selectedBoard.title.uppercased())")
                    .font(.system(size: 11, weight: .bold, design: .default))
                    .tracking(1.2)
                    .foregroundStyle(accent(for: metric).opacity(0.85))
                Text(value > 0 ? value.formatted() : "—")
                    .font(.system(size: 38, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(highlightNew ? accent(for: metric) : .primary)
            }
            Spacer()
            if highlightNew {
                Text("NEW")
                    .font(.system(size: 12, weight: .bold, design: .default))
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
                    .font(.system(size: 14, weight: .semibold, design: .default))
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
        .hoverEffect(.highlight)
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
            .font(.system(size: 14, weight: .regular, design: .default))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        } else if gameCenter.isLoadingRemote {
            ProgressView("Loading \(audience.title.lowercased())…")
                .font(.system(size: 14, weight: .medium, design: .default))
                .foregroundStyle(.secondary)
        } else if let error = gameCenter.remoteErrorMessage, (gameCenter.remoteSnapshot?.entries.isEmpty ?? true) {
            Text(error)
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundStyle(.orange.opacity(0.95))
                .fixedSize(horizontal: false, vertical: true)
        } else if let snapshot = gameCenter.remoteSnapshot {
            VStack(alignment: .leading, spacing: 8) {
                if let rank = snapshot.localRank, let value = snapshot.localValue {
                    Text("Your rank: #\(rank) · \(value)")
                        .font(.system(size: 13, weight: .semibold, design: .default))
                        .foregroundStyle(accent(for: metric).opacity(0.9))
                }

                if snapshot.entries.isEmpty {
                    Text("No scores yet for \(audience.title.lowercased()).")
                        .font(.system(size: 14, weight: .regular, design: .default))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snapshot.entries.prefix(8)) { entry in
                        rankRow(entry, accent: accent(for: metric))
                    }
                }
            }
        } else {
            ProgressView("Loading \(audience.title.lowercased()) scores…")
                .font(.system(size: 14, weight: .medium, design: .default))
                .foregroundStyle(.secondary)
        }
    }

    private func rankRow(_ entry: RemoteLeaderboardEntry, accent: Color) -> some View {
        let medal = medalSymbol(for: entry.rank)
        return HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(medal == nil ? Color.white.opacity(0.08) : accent.opacity(0.2))
                    .frame(width: 28, height: 28)
                if let medal {
                    Image(systemName: medal)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(medalColor(for: entry.rank))
                } else {
                    Text("\(entry.rank)")
                        .font(.system(size: 12, weight: .bold, design: .default))
                        .foregroundStyle(.secondary)
                }
            }
            Text(entry.displayName)
                .font(.system(
                    size: 14,
                    weight: entry.isLocalPlayer ? .bold : .medium,
                    design: .default
                ))
                .foregroundStyle(entry.isLocalPlayer ? accent : .primary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(entry.value)")
                .font(.system(size: 14, weight: .semibold, design: .default))
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(entry.isLocalPlayer ? accent.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .bottom) {
            Rectangle().fill(SlipframeUI.hairline).frame(height: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rank \(entry.rank), \(entry.displayName), \(entry.value)\(entry.isLocalPlayer ? ", you" : "")")
    }

    private func medalSymbol(for rank: Int) -> String? {
        switch rank {
        case 1: return "medal.fill"
        case 2: return "medal.fill"
        case 3: return "medal.fill"
        default: return nil
        }
    }

    private func medalColor(for rank: Int) -> Color {
        switch rank {
        case 1: return gold
        case 2: return Color(white: 0.82)
        case 3: return Color(red: 0.82, green: 0.55, blue: 0.32)
        default: return .secondary
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
            HStack(spacing: 6) {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(accent)
                }
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(ConsoleSelectionStyle(selected: selected))
        .disabled(!enabled)
        .accessibilityAddTraits(selected ? .isSelected : [])
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
