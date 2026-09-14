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
        VStack(spacing: 14) {
            if gameModel.isTutorialRun {
                Text("TUTORIAL")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(neon.opacity(0.85))
            } else {
                runReadout
            }

            if gameModel.isPlaying, gameModel.isOffPlayfield {
                offTrackBanner
            }

            controls
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .frame(minWidth: 430)
        .xenotechPanel(primary: neon, secondary: gold, cornerRadius: 20)
        // Dissolve center HUD during overdrive / outro — coaching overlay owns the moment.
        .opacity(centerHUDOpacity)
        .animation(.easeInOut(duration: 0.45), value: gameModel.tutorialOverlayOpacity)
        .animation(.easeInOut(duration: 0.3), value: gameModel.tutorialBannerText)
        .animation(.easeInOut(duration: 0.25), value: gameModel.isOffPlayfield)
        .animation(.easeInOut(duration: 0.35), value: gameModel.isChoosingPortal)
    }

    private var runReadout: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 22) {
                compactMetric(title: "SCORE", value: "\(stats.score)", accent: neon)
                Divider().frame(height: 38).opacity(0.3)
                compactMetric(title: "TOKENS", value: "\(stats.coinsCollected)", accent: gold)

                if stats.shieldCharges > 0 {
                    Divider().frame(height: 38).opacity(0.3)
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(neon)
                        .accessibilityLabel("Aegis shield ready")
                }
            }

            HStack(spacing: 10) {
                Text("FLOW")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(neon)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.09))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [neon, stats.flow >= 80 ? gold : neon.opacity(0.72)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: proxy.size.width * CGFloat(stats.flow) / 100)
                    }
                }
                .frame(height: 7)
                Text("\(stats.flow)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .trailing)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Flow \(stats.flow) percent")

            if gameModel.isGameOver {
                Divider().opacity(0.3)
                HStack(spacing: 20) {
                    resultMetric(label: "GRADE", value: performanceGrade, accent: gradeColor)
                    resultMetric(label: "PEAK FLOW", value: "\(stats.highestFlow)", accent: neon)
                    resultMetric(label: "CLOSE SLIPS", value: "\(stats.nearMisses)", accent: gold)
                    resultMetric(label: "RIFTS", value: "\(stats.portalsCrossed)", accent: neon)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func resultMetric(label: String, value: String, accent: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: label == "GRADE" ? 25 : 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(accent)
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.9)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var performanceGrade: String {
        let mastery = stats.highestFlow + stats.nearMisses * 4 + stats.portalsCrossed * 10
        switch mastery {
        case 150...: return "S"
        case 100...: return "A"
        case 65...: return "B"
        case 30...: return "C"
        default: return "D"
        }
    }

    private var gradeColor: Color {
        performanceGrade == "S" || performanceGrade == "A" ? gold : neon
    }

    private func compactMetric(title: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(accent.opacity(0.85))
            Text(value)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
    }

    private var centerHUDOpacity: Double {
        if gameModel.isChoosingPortal { return 0 }
        // Keep Skip reachable for the whole tutorial (including auto-start / overdrive).
        // Only yield the center stage during the success banner.
        if gameModel.isTutorialRun {
            return gameModel.tutorialBannerOpacity > 0.05 ? 0 : 1
        }
        return 1
    }

    private var offTrackBanner: some View {
        HStack(spacing: 12) {
            LaneGlyph(accent: gold, lit: false)
            VStack(alignment: .leading, spacing: 2) {
                Text("Return to the track")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(gold)
                Text("Obstacles and music wind down until you step back in.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(gold.opacity(0.12))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(gold.opacity(0.45), lineWidth: 1)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
        .accessibilityLabel("Return to the track. Obstacles and music wind down until you step back in.")
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
