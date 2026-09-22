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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let neon = SlipframeUI.accent
    private let gold = SlipframeUI.reward

    var body: some View {
        VStack(spacing: 16) {
            if gameModel.isTutorialRun {
                Text("TUTORIAL")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
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
        .padding(.vertical, 22)
        .frame(width: 460)
        .xenotechPanel(primary: neon, cornerRadius: 18)
        // Dissolve center HUD during overdrive / outro — coaching overlay owns the moment.
        .opacity(centerHUDOpacity)
        .allowsHitTesting(centerHUDOpacity > 0)
        .accessibilityHidden(centerHUDOpacity == 0)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: gameModel.tutorialOverlayOpacity)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: gameModel.tutorialBannerText)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: gameModel.isOffPlayfield)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: gameModel.isChoosingPortal)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: gameModel.isGameOverMenuVisible)
    }

    private var runReadout: some View {
        VStack(spacing: 16) {
            if gameModel.isGameOver {
                HStack {
                    Text("RUN COMPLETE")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .tracking(1.6)
                    Spacer()
                    if gameModel.lastPersonalBestUpdate?.scoreImproved == true {
                        Label("Personal best", systemImage: "trophy.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(gold)
                    }
                }
                .foregroundStyle(.secondary)
            }

            HStack(alignment: .center, spacing: 20) {
                compactMetric(title: "SCORE", value: stats.score.formatted(), accent: neon)
                Spacer(minLength: 0)
                Divider().frame(height: 38).opacity(0.3)
                compactMetric(title: "TOKENS", value: stats.coinsCollected.formatted(), accent: gold)
            }

            if !gameModel.isGameOver {
                HStack(spacing: 10) {
                    Text("SCORE BONUS")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
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
                                .frame(width: proxy.size.width * CGFloat(min(100, max(0, stats.flow))) / 100)
                        }
                    }
                    .frame(height: 7)
                    Text("+\(stats.flow)%")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Score bonus \(stats.flow) percent")
            }

            if let modifier = stats.modifier, !gameModel.isGameOver {
                HStack(spacing: 8) {
                    RiftModifierIcon(modifier: modifier, accent: gold, size: 16)
                    Text(modifier.displayName)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 0)
                    Text(activeModifierEffect(for: modifier))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }

            if gameModel.isGameOver {
                Divider().opacity(0.3)
                HStack(spacing: 20) {
                    resultMetric(label: "GRADE", value: performanceGrade, accent: gradeColor)
                    resultMetric(label: "BEST BONUS", value: "+\(stats.highestFlow)%", accent: neon)
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
                .font(.system(size: label == "GRADE" ? 28 : 20, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(accent)
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(0.3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value)")
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
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(accent.opacity(0.85))
            Text(value)
                .font(.system(size: title == "SCORE" ? 38 : 28, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value)")
    }

    private func activeModifierEffect(for modifier: RiftModifier) -> String {
        if modifier == .aegis, stats.shieldCharges == 0 {
            return "Shield spent"
        }
        return modifier.effectDescription
    }

    private var centerHUDOpacity: Double {
        if !gameModel.isPlaying, !gameModel.isGameOver, !gameModel.isTutorialRun { return 0 }
        if gameModel.isChoosingPortal { return 0 }
        if gameModel.isGameOver, !gameModel.isGameOverMenuVisible { return 0 }
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
                    .font(.system(size: 18, weight: .bold, design: .default))
                    .foregroundStyle(gold)
                Text("Obstacles and music wind down until you step back in.")
                    .font(.system(size: 13, weight: .medium, design: .default))
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
                        .font(.system(size: 20, weight: .semibold, design: .default))
                        .frame(minWidth: 200)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            } else {
                Text("Clearing the track…")
                    .font(.system(size: 17, weight: .medium, design: .default))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    let model = GameModel()
    model.isPlaying = true
    model.stats.score = 12480
    model.stats.coinsCollected = 86
    model.stats.flow = 72
    return PlayHUDView()
        .environmentObject(model)
        .environmentObject(model.stats)
}
