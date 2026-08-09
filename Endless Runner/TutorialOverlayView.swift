//
//  TutorialOverlayView.swift
//  Endless Runner
//
//  Lazy-locked coaching copy + finale banner for the tutorial run.
//

import SwiftUI

struct TutorialOverlayView: View {
    @EnvironmentObject private var gameModel: GameModel

    private let neon = Color(red: 0.35, green: 0.92, blue: 1.0)
    private let hazard = Color(red: 1.0, green: 0.35, blue: 0.32)

    var body: some View {
        ZStack {
            if let banner = gameModel.tutorialBannerText {
                Text(banner)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 36)
                    .padding(.vertical, 22)
                    .background {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(hazard.opacity(0.88))
                    }
                    .transition(.scale.combined(with: .opacity))
            } else if gameModel.tutorialOverlayOpacity > 0.02 {
                VStack(spacing: 10) {
                    Text(gameModel.tutorialOverlayTitle)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(neon)
                        .multilineTextAlignment(.center)

                    Text(gameModel.tutorialOverlayBody)
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.92))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
                .background {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.black.opacity(0.42))
                        .overlay {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(neon.opacity(0.55), lineWidth: 1.2)
                        }
                }
                .glassBackgroundEffect()
                .opacity(Double(gameModel.tutorialOverlayOpacity))
            }
        }
        .frame(minWidth: 480, minHeight: 120)
        .animation(.easeInOut(duration: 0.35), value: gameModel.tutorialBannerText)
        .animation(.easeInOut(duration: 0.25), value: gameModel.tutorialOverlayTitle)
        .allowsHitTesting(false)
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
