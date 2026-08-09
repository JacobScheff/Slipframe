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
            titleBlock

            HStack(spacing: 28) {
                metricChip(title: "Score", value: "\(stats.score)", accent: neon)
                metricChip(title: "Coins", value: "\(stats.coinsCollected)", accent: gold)
            }

            if !gameModel.isPlaying {
                Text(gameModel.resolvedPlayMode.displayLabel)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(neon.opacity(0.85))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background {
                        Capsule(style: .continuous)
                            .fill(neon.opacity(0.12))
                            .overlay {
                                Capsule(style: .continuous)
                                    .strokeBorder(neon.opacity(0.35), lineWidth: 1)
                            }
                    }
            }

            Text(statusText)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(statusColor)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)

            controls
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 28)
        .frame(minWidth: 620)
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

    private var titleBlock: some View {
        VStack(spacing: 4) {
            Text("ENDLESS RUNNER")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .tracking(3.5)
                .foregroundStyle(neon.opacity(0.8))

            Text(gameModel.isGameOver ? "Run Over" : (gameModel.isPlaying ? "In Motion" : "Ready"))
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
        }
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
        } else {
            Text("Dodge with your head · grab coins with your hands")
                .font(.system(size: 17, weight: .regular, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
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

    private var statusText: String {
        if gameModel.isGameOver {
            if let update = gameModel.lastPersonalBestUpdate, update.anyImproved {
                switch (update.scoreImproved, update.coinsImproved) {
                case (true, true):
                    return "New personal best — score and coins! Check the board on the right."
                case (true, false):
                    return "New personal best score — check the board on the right."
                case (false, true):
                    return "New personal best coins — check the board on the right."
                case (false, false):
                    break
                }
            }
            return "Hit a wall — tweak mode on the left, or go again."
        }
        if gameModel.isPlaying {
            return "Obstacles stream from the portal."
        }
        if !gameModel.canStartRun {
            return "Add at least one biome to your playlist."
        }
        return "Choose a mode on the left, then start when ready."
    }

    private var statusColor: Color {
        if gameModel.isGameOver { return hazard.opacity(0.95) }
        if gameModel.isPlaying { return neon.opacity(0.9) }
        if !gameModel.canStartRun { return .orange.opacity(0.95) }
        return .secondary
    }
}

#Preview {
    let model = GameModel()
    return PlayHUDView()
        .environmentObject(model)
        .environmentObject(model.stats)
}
