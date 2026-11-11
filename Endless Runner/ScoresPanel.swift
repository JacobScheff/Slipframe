import SwiftUI

struct ScoresPanel: View {
    @ObservedObject var center: GameCenterService
    @ObservedObject var bests: PersonalBestStore
    let preferredMode: PlayMode
    let signIn: () -> Void

    @State private var selectedBoard: LeaderboardBoard?
    @State private var metric = LeaderboardMetric.score
    @State private var audience = LeaderboardAudience.allPlayers

    private struct Query: Equatable {
        let board: LeaderboardBoard
        let metric: LeaderboardMetric
        let audience: LeaderboardAudience
        let authenticated: Bool
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let date = context.date
            let board = currentBoard(on: date)
            let query = Query(board: board, metric: metric, audience: audience, authenticated: center.isAuthenticated)

            HStack(alignment: .top, spacing: 16) {
                boards(selected: board, date: date)
                    .frame(width: 316)
                VStack(alignment: .leading, spacing: 10) {
                    personalBest(for: board, date: date)
                    HStack(spacing: 6) {
                        ForEach(LeaderboardMetric.allCases) { option in
                            filter(option.title, selected: metric == option) { metric = option }
                        }
                        Spacer(minLength: 3)
                        ForEach(LeaderboardAudience.allCases) { option in
                            filter(option.title, selected: audience == option) { audience = option }
                        }
                    }
                    Divider()
                    rankings
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: query, initial: true) { _, current in
                if current.authenticated {
                    center.loadRemoteScores(board: current.board, metric: current.metric, audience: current.audience)
                } else {
                    center.clearRemote()
                }
            }
        }
        .onDisappear { center.clearRemote() }
    }

    private func currentBoard(on date: Date) -> LeaderboardBoard {
        let board = selectedBoard ?? LeaderboardBoard.matching(preferredMode, on: date) ?? .normal
        if case .daily = board { return .daily(dayKey: DailyChallenge.dayKey(for: date)) }
        return board
    }

    private func boards(selected: LeaderboardBoard, date: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Leaderboards")
                .font(.system(size: 29, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 7) {
                ForEach(LeaderboardBoard.browseable(on: date)) { board in
                    Button {
                        selectedBoard = board
                    } label: {
                        Text(board.chipTitle).lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(ConsoleButtonStyle(selected: selected == board))
                    .accessibilityAddTraits(selected == board ? .isSelected : [])
                    .accessibilityLabel(boardLabel(board))
                }
            }
            Text("Biome rankings are for Loop runs.")
                .font(.system(size: 14))
                .foregroundStyle(SlipframeStyle.muted)
        }
    }

    private func boardLabel(_ board: LeaderboardBoard) -> String {
        if case .loop = board { return "\(board.chipTitle), Loop" }
        return board.chipTitle
    }

    private func personalBest(for board: LeaderboardBoard, date: Date) -> some View {
        let best = bests.value(metric, for: board)
        return VStack(alignment: .leading, spacing: 10) {
            Text(board.title)
                .font(.system(size: 23, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 12) {
                ConsoleMetric(title: "Local best · \(metric.title)", value: best.formatted(),
                              color: metric == .score ? SlipframeStyle.ice : SlipframeStyle.amber)
                Spacer()
                if case .daily = board {
                    let score = bests.value(.score, for: board)
                    if score > 0, let url = DailyScoreShare.messagesURL(score: score, date: date) {
                        Link(destination: url) { Label("Share best", systemImage: "message") }
                            .buttonStyle(ConsoleButtonStyle())
                            .accessibilityLabel("Share Daily best score in Messages")
                    }
                }
            }
        }
        .padding(13)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 15))
    }

    @ViewBuilder
    private var rankings: some View {
        if !center.isAuthenticated {
            VStack(alignment: .leading, spacing: 10) {
                Label("Game Center", systemImage: "person.crop.circle")
                    .font(.system(size: 18, weight: .semibold))
                if center.needsSignInPresentation {
                    Text("Sign in to load online rankings and submit your bests.")
                        .foregroundStyle(SlipframeStyle.muted)
                    Button("Sign in", action: signIn)
                        .buttonStyle(ConsoleButtonStyle(selected: true))
                } else if center.statusMessage == "Checking Game Center…" {
                    ProgressView("Checking Game Center…")
                } else {
                    Text("Sign in to Game Center in visionOS Settings to see online rankings.")
                        .foregroundStyle(SlipframeStyle.muted)
                }
            }
            .padding(.top, 6)
        } else if center.isLoadingRemote {
            ProgressView("Loading rankings…").padding(.top, 6)
        } else if center.remoteErrorMessage != nil {
            Label("Rankings are currently unavailable.", systemImage: "exclamationmark.circle")
                .foregroundStyle(SlipframeStyle.muted)
                .padding(.top, 6)
        } else if let snapshot = center.remoteSnapshot {
            if let rank = snapshot.localRank, let value = snapshot.localValue {
                HStack {
                    Text("Your rank").foregroundStyle(SlipframeStyle.muted)
                    Text("#\(rank.formatted())").foregroundStyle(SlipframeStyle.ice)
                    Spacer()
                    Text(value.formatted())
                }
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .padding(10)
                .background(SlipframeStyle.ice.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityElement(children: .combine)
            }
            if snapshot.entries.isEmpty {
                Text(audience == .friends ? "No ranked friends yet." : "No ranked runs yet.")
                    .foregroundStyle(SlipframeStyle.muted)
                    .padding(.top, 6)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(snapshot.entries) { entry in
                            HStack(spacing: 12) {
                                Text("#\(entry.rank)").frame(width: 46, alignment: .leading)
                                    .monospacedDigit()
                                Text(entry.displayName).lineLimit(1)
                                Spacer()
                                Text(entry.value.formatted()).monospacedDigit()
                            }
                            .font(.system(size: 15, weight: entry.isLocalPlayer ? .bold : .medium))
                            .foregroundStyle(entry.isLocalPlayer ? SlipframeStyle.ice : .white)
                            .padding(.vertical, 8)
                            .accessibilityElement(children: .combine)
                            Divider()
                        }
                    }
                    .padding(.trailing, 8)
                }
            }
        } else {
            ProgressView("Loading rankings…").padding(.top, 6)
        }
    }

    private func filter(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(ConsoleButtonStyle(selected: selected))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
