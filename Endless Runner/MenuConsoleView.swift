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

    private let neon = Color(red: 0.35, green: 0.92, blue: 1.0)
    private let gold = Color(red: 1.0, green: 0.82, blue: 0.32)

    var body: some View {
        VStack(spacing: 18) {
            header
            tabPicker
            Divider().opacity(0.28)

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
            .frame(minHeight: 280, alignment: .top)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .frame(width: 720, alignment: .top)
        .xenotechPanel(primary: neon, secondary: gold, cornerRadius: 26)
        .animation(.easeInOut(duration: 0.18), value: tab)
    }

    private var header: some View {
        HStack(spacing: 14) {
            RiftGlyph(accent: neon, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("SLIPFRAME")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .tracking(3.2)
                    .foregroundStyle(neon.opacity(0.9))
                Text("Command Console")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            Spacer(minLength: 8)
            LaneGlyph(accent: neon, lit: gameModel.showsTrack)
        }
    }

    private var tabPicker: some View {
        HStack(spacing: 10) {
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
                            .font(.system(size: 16, weight: selected ? .bold : .semibold, design: .rounded))
                    }
                    .foregroundStyle(selected ? neon : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: selected
                                        ? [neon.opacity(0.28), neon.opacity(0.08)]
                                        : [Color.white.opacity(0.07), Color.white.opacity(0.03)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                selected ? neon.opacity(0.8) : Color.white.opacity(0.1),
                                lineWidth: selected ? 1.5 : 1
                            )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private var settingsBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("DISPLAY")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(.secondary)

            HStack(alignment: .center, spacing: 16) {
                LaneGlyph(accent: neon, lit: gameModel.showsTrack)
                    .scaleEffect(1.15)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Floor track")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("Optional neon lanes on the floor. The play area stays the same either way — hide the slab if you want a clearer view of the room.")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
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
                    .fill(neon.opacity(gameModel.showsTrack ? 0.14 : 0.06))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(neon.opacity(gameModel.showsTrack ? 0.55 : 0.18), lineWidth: 1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Floor track")
            .accessibilityValue(gameModel.showsTrack ? "Shown" : "Hidden")

            HStack(spacing: 10) {
                Image(systemName: "figure.walk")
                    .foregroundStyle(gold)
                Text("Step off the play area during a run and the stream winds down. Step back in and it eases back up to speed.")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
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
