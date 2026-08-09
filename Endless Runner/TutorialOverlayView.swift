//
//  TutorialOverlayView.swift
//  Endless Runner
//
//  Lazy-locked coaching copy + finale success banner for the tutorial run.
//

import SwiftUI

struct TutorialOverlayView: View {
    @EnvironmentObject private var gameModel: GameModel

    private let neon = Color(red: 0.35, green: 0.92, blue: 1.0)
    private let success = Color(red: 0.45, green: 0.98, blue: 0.72)

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
        .animation(.easeInOut(duration: 0.25), value: gameModel.tutorialOverlayTitle)
        .allowsHitTesting(false)
    }

    private var coachingCard: some View {
        VStack(spacing: 14) {
            Text(gameModel.tutorialOverlayTitle)
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .foregroundStyle(neon)
                .multilineTextAlignment(.center)

            Text(gameModel.tutorialOverlayBody)
                .font(.system(size: 28, weight: .medium, design: .rounded))
                .foregroundStyle(.primary.opacity(0.92))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 28)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.black.opacity(0.42))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(neon.opacity(0.55), lineWidth: 1.2)
                }
        }
        .glassBackgroundEffect()
        .opacity(Double(gameModel.tutorialOverlayOpacity))
    }

    private func successBanner(text: String) -> some View {
        let scale = Double(gameModel.tutorialBannerScale)
        let opacity = Double(gameModel.tutorialBannerOpacity)
        let glow = Double(gameModel.tutorialBannerGlow)
        let lift = Double(gameModel.tutorialBannerExit) * -36

        return Text(text)
            .font(.system(size: 58, weight: .bold, design: .rounded))
            .tracking(4 + glow * 1.5)
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        .white,
                        success,
                        neon
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .padding(.horizontal, 48)
            .padding(.vertical, 30)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.black.opacity(0.5))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        success.opacity(0.95),
                                        neon.opacity(0.75),
                                        success.opacity(0.55 + glow * 0.35)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2.2
                            )
                    }
                    .shadow(color: success.opacity(0.35 + glow * 0.35), radius: 18 + glow * 16)
            }
            .glassBackgroundEffect()
            .scaleEffect(scale)
            .offset(y: lift)
            .opacity(opacity)
    }
}

#Preview {
    let model = GameModel()
    model.tutorialOverlayTitle = "The Basics"
    model.tutorialOverlayBody = "Side-step the red walls. Reach for gold coins with your hands."
    model.tutorialOverlayOpacity = 1
    return TutorialOverlayView()
        .environmentObject(model)
}
