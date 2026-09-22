//
//  TutorialOverlayView.swift
//  Slipframe
//
//  Lazy-locked coaching copy + finale success banner for the tutorial run.
//

import SwiftUI

struct TutorialOverlayView: View {
    @EnvironmentObject private var gameModel: GameModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let neon = SlipframeUI.accent
    private let success = Color(red: 0.58, green: 0.88, blue: 0.73)

    var body: some View {
        ZStack {
            if gameModel.tutorialBannerOpacity > 0.02,
               let banner = gameModel.tutorialBannerText {
                successBanner(text: banner)
            } else if gameModel.tutorialOverlayOpacity > 0.02 {
                coachingCard
            }
        }
        .frame(minWidth: 620, minHeight: 160)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: gameModel.tutorialOverlayTitle)
        .allowsHitTesting(false)
    }

    private var coachingCard: some View {
        VStack(spacing: 14) {
            Text("LEARN TO PLAY")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .tracking(2)
                .foregroundStyle(neon)
            Text(gameModel.tutorialOverlayTitle)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            Text(gameModel.tutorialOverlayBody)
                .font(.system(size: 25, weight: .regular))
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 28)
        .xenotechPanel(primary: neon, cornerRadius: 24, fillOpacity: 0.3)
        .opacity(Double(gameModel.tutorialOverlayOpacity))
    }

    private func successBanner(text: String) -> some View {
        let scale = reduceMotion ? 1 : Double(gameModel.tutorialBannerScale)
        let opacity = Double(gameModel.tutorialBannerOpacity)
        let lift = reduceMotion ? 0 : Double(gameModel.tutorialBannerExit) * -36

        return Text(text)
            .font(.system(size: 48, weight: .semibold))
            .tracking(1)
            .foregroundStyle(success)
            .padding(.horizontal, 48)
            .padding(.vertical, 30)
            .xenotechPanel(primary: success, cornerRadius: 22, fillOpacity: 0.36)
            .scaleEffect(scale)
            .offset(y: lift)
            .opacity(opacity)
    }
}

#Preview {
    let model = GameModel()
    model.tutorialOverlayTitle = "The Basics"
    model.tutorialOverlayBody = "Side-step the red walls. Reach for glowing Data Tokens with your hands."
    model.tutorialOverlayOpacity = 1
    return TutorialOverlayView()
        .environmentObject(model)
}
