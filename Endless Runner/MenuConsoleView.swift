//
//  MenuConsoleView.swift
//  Slipframe
//
//  Centered ready-state console: Play / Scores / Settings tabs facing the player.
//

import SwiftUI

enum MenuConsoleTab: String, CaseIterable, Identifiable {
    case play
    case scores
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .play: return "Play"
        case .scores: return "Scores"
        case .settings: return "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .play: return "play.square.fill"
        case .scores: return "flag.checkered"
        case .settings: return "slider.horizontal.3"
        }
    }
}

struct MenuConsoleView: View {
    @EnvironmentObject private var gameModel: GameModel
    @State private var tab: MenuConsoleTab = .play
    @State private var contentHeight: CGFloat = 360
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let neon = SlipframeUI.accent
    private let gold = SlipframeUI.reward

    private var consoleWidth: CGFloat {
        if tab == .scores { return 800 }
        if tab == .play, gameModel.playKind == .playlist || gameModel.playKind == .solo { return 800 }
        return 720
    }

    /// Keep the world-anchored console within a comfortable viewing envelope.
    /// Longer guides and rankings can scroll after the panel reaches this limit.
    private var viewportHeight: CGFloat {
        min(max(contentHeight, 220), tab == .play ? 660 : 720)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 28)
                .padding(.top, 26)
                .padding(.bottom, 22)
            tabPicker
                .padding(.horizontal, 28)
                .padding(.bottom, 18)
            Divider().overlay(SlipframeUI.hairline)

            ScrollView {
                Group {
                    switch tab {
                    case .play:
                        LevelSelectView()
                    case .scores:
                        LeaderboardPanelView()
                    case .settings:
                        settingsBody
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    ceil(proxy.size.height)
                } action: { height in
                    contentHeight = height
                }
            }
            .frame(height: viewportHeight)
            .contentShape(Rectangle())
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.visible)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: viewportHeight)
            .id(tab)

            if tab == .play {
                launchBar
            }
        }
        .frame(width: consoleWidth, alignment: .top)
        .xenotechPanel(primary: neon, cornerRadius: 22)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: consoleWidth)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: tab)
    }

    private var header: some View {
        HStack(spacing: 14) {
            RiftGlyph(accent: neon, size: 32)
            Text("SLIPFRAME")
                .font(.system(size: 25, weight: .semibold))
                .tracking(4)
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
        }
    }

    private var tabPicker: some View {
        HStack(spacing: 6) {
            ForEach(MenuConsoleTab.allCases) { item in
                let selected = tab == item
                Button {
                    tab = item
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: item.symbolName)
                            .font(.system(size: 16, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                        Text(item.title)
                            .font(.system(size: 16, weight: selected ? .semibold : .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(ConsoleSelectionStyle(selected: selected))
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private var launchBar: some View {
        VStack(spacing: 0) {
            Divider().overlay(SlipframeUI.hairline)
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(gameModel.canStartRun ? "READY TO RUN" : "BUILD YOUR PLAYLIST")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(gameModel.canStartRun ? neon : gold)
                    Text(gameModel.canStartRun ? gameModel.resolvedPlayMode.displayLabel : "Select at least one biome above.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button {
                    gameModel.startRun()
                } label: {
                    Label(gameModel.isGameOver ? "Run again" : "Start run", systemImage: "play.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(minWidth: 142, minHeight: 32)
                }
                .buttonStyle(.borderedProminent)
                .tint(neon)
                .controlSize(.large)
                .disabled(!gameModel.canStartRun || gameModel.isPlaying)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
        }
    }

    private var settingsBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Display & comfort")
                    .font(.system(size: 23, weight: .semibold))
                Text("Keep your view comfortable while you play.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .center, spacing: 16) {
                LaneGlyph(accent: neon, lit: gameModel.showsTrack)
                    .scaleEffect(1.15)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Floor track")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Show the three lanes beneath you. Hiding them keeps the same play area.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Toggle("Show track", isOn: $gameModel.showsTrack)
                    .labelsHidden()
                    .tint(neon)
                    .disabled(gameModel.isPlaying)
            }
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(SlipframeUI.inset)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(SlipframeUI.hairline, lineWidth: 1)
            }

            HStack(spacing: 10) {
                Image(systemName: "figure.walk")
                    .foregroundStyle(gold)
                Text("Need a breather? Step outside the play area to slow the stream. Step back in when you’re ready.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    let model = GameModel()
    return MenuConsoleView()
        .environmentObject(model)
        .environmentObject(model.personalBests)
        .environmentObject(model.gameCenter)
}

#Preview("Playlist setup") {
    let model = GameModel(defaults: UserDefaults(suiteName: "preview.console.playlist"))
    model.hasCompletedTutorial = true
    model.playKind = .playlist
    return MenuConsoleView()
        .environmentObject(model)
        .environmentObject(model.personalBests)
        .environmentObject(model.gameCenter)
}

#Preview("Empty playlist") {
    let model = GameModel(defaults: UserDefaults(suiteName: "preview.console.empty"))
    model.hasCompletedTutorial = true
    model.playKind = .playlist
    model.playlistEnvironments = []
    return MenuConsoleView()
        .environmentObject(model)
        .environmentObject(model.personalBests)
        .environmentObject(model.gameCenter)
}

#Preview("Daily challenge") {
    let model = GameModel(defaults: UserDefaults(suiteName: "preview.console.daily"))
    model.hasCompletedTutorial = true
    model.playKind = .daily
    return MenuConsoleView()
        .environmentObject(model)
        .environmentObject(model.personalBests)
        .environmentObject(model.gameCenter)
}
