//
//  PlayHUDView.swift
//  Slipframe
//
//  World-anchored play / score panel fixed above the track.
//

import SwiftUI

struct PlayHUDView: View {
    @EnvironmentObject private var gameModel: GameModel
    /// Separate from `GameModel` so score/coin ticks do not invalidate RealityView.
    @EnvironmentObject private var stats: RunStats

    private let neon = Color(red: 0.35, green: 0.92, blue: 1.0)
    private let gold = Color(red: 1.0, green: 0.82, blue: 0.32)
    private let hazard = Color(red: 1.0, green: 0.35, blue: 0.32)

    var body: some View {
        VStack(spacing: 18) {
            if gameModel.isTutorialRun {
                Text("TUTORIAL")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(neon.opacity(0.85))
            } else {
                HStack(spacing: 28) {
                    metricChip(title: "Score", value: "\(stats.score)", accent: neon)
                    metricChip(title: "Coins", value: "\(stats.coinsCollected)", accent: gold)
                }
            }

            controls
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 28)
        .frame(minWidth: 420)
        .xenotechPanel(primary: neon, secondary: gold, cornerRadius: 26)
        // Dissolve center HUD during overdrive / outro — coaching overlay owns the moment.
        .opacity(centerHUDOpacity)
        .animation(.easeInOut(duration: 0.45), value: gameModel.tutorialOverlayOpacity)
        .animation(.easeInOut(duration: 0.3), value: gameModel.tutorialBannerText)
    }

    private var centerHUDOpacity: Double {
        // Keep Skip reachable for the whole tutorial (including auto-start / overdrive).
        // Only yield the center stage during the success banner.
        if gameModel.isTutorialRun {
            return gameModel.tutorialBannerOpacity > 0.05 ? 0 : 1
        }
        return 1
    }

    @ViewBuilder
    private var controls: some View {
        if gameModel.isTutorialRun {
            if gameModel.isPlaying {
                Button {
                    gameModel.skipTutorial()
                } label: {
                    Label("Skip Tutorial", systemImage: "forward.end.fill")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .frame(minWidth: 200)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            } else {
                Text("Clearing the track…")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        } else if gameModel.isGameOver {
            Button {
                gameModel.startRun()
            } label: {
                Label("Restart", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .frame(minWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .tint(hazard)
            .controlSize(.large)
            .disabled(!gameModel.canStartRun)
        } else if !gameModel.isPlaying {
            Button {
                gameModel.startRun()
            } label: {
                Label("Start Run", systemImage: "play.fill")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .frame(minWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .tint(neon)
            .controlSize(.large)
            .disabled(!gameModel.canStartRun)
        }
    }

    private func metricChip(title: String, value: String, accent: Color) -> some View {
        VStack(spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(accent.opacity(0.9))
            Text(value)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .frame(minWidth: 150)
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(accent.opacity(0.1))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(accent.opacity(0.3), lineWidth: 1)
                }
        }
    }
}

#Preview {
    let model = GameModel()
    return PlayHUDView()
        .environmentObject(model)
        .environmentObject(model.stats)
}
