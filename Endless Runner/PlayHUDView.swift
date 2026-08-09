//
//  PlayHUDView.swift
//  Endless Runner
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
            HStack(spacing: 28) {
                metricChip(title: "Score", value: "\(stats.score)", accent: neon)
                metricChip(title: "Coins", value: "\(stats.coinsCollected)", accent: gold)
            }

            controls
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 28)
        .frame(minWidth: 420)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.black.opacity(0.18))
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    neon.opacity(0.65),
                                    Color.white.opacity(0.08),
                                    gold.opacity(0.35)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.25
                        )
                }
        }
        .glassBackgroundEffect()
    }

    @ViewBuilder
    private var controls: some View {
        if gameModel.isGameOver {
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
