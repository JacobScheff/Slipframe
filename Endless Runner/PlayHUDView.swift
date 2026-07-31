//
//  PlayHUDView.swift
//  Endless Runner
//
//  World-anchored play / score panel fixed above the track.
//

import SwiftUI

struct PlayHUDView: View {
    @EnvironmentObject private var gameModel: GameModel
    @State private var isEnvironmentMenuOpen = false

    private let neon = Color(red: 0.35, green: 0.92, blue: 1.0)
    private let gold = Color(red: 1.0, green: 0.82, blue: 0.32)
    private let hazard = Color(red: 1.0, green: 0.35, blue: 0.32)

    var body: some View {
        VStack(spacing: 22) {
            titleBlock

            HStack(spacing: 40) {
                metricChip(title: "Score", value: "\(gameModel.score)", accent: neon)
                metricChip(title: "Coins", value: "\(gameModel.coinsCollected)", accent: gold)
            }

            Text(statusText)
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .foregroundStyle(statusColor)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)

            controls

            debugEnvironmentPicker
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 36)
        .frame(minWidth: 700)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            neon.opacity(0.7),
                            neon.opacity(0.15),
                            gold.opacity(0.35)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        }
        .glassBackgroundEffect()
        // Open menu overlays upward above the HUD so it doesn't grow the card.
        .overlay(alignment: .bottom) {
            if isEnvironmentMenuOpen {
                environmentMenuPanel
                    .padding(.bottom, 96)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .zIndex(isEnvironmentMenuOpen ? 20 : 0)
    }

    private var titleBlock: some View {
        VStack(spacing: 6) {
            Text("ENDLESS RUNNER")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .tracking(4)
                .foregroundStyle(neon.opacity(0.85))

            Text(gameModel.isGameOver ? "Run Over" : (gameModel.isPlaying ? "In Motion" : "Ready"))
                .font(.system(size: 44, weight: .semibold, design: .rounded))
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
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .frame(minWidth: 220)
            }
            .buttonStyle(.borderedProminent)
            .tint(hazard)
            .controlSize(.large)
        } else if !gameModel.isPlaying {
            Button {
                gameModel.startRun()
            } label: {
                Label("Start Run", systemImage: "play.fill")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .frame(minWidth: 220)
            }
            .buttonStyle(.borderedProminent)
            .tint(neon)
            .controlSize(.large)
        } else {
            Text("Dodge walls with your head and hands.\nGrab gold coins with your hands.")
                .font(.system(size: 20, weight: .regular, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("End Run") {
                gameModel.endRun()
            }
            .controlSize(.large)
            .font(.system(size: 20, weight: .medium, design: .rounded))
        }
    }

    /// Temporary test control — keep the closed control compact like the original menu.
    private var debugEnvironmentPicker: some View {
        VStack(spacing: 10) {
            Text("Debug Environment")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isEnvironmentMenuOpen.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Text(currentEnvironmentLabel)
                        .font(.title3)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
        .padding(.top, 8)
    }

    private var environmentMenuPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            environmentOptionButton(title: "Normal (random)", value: .normal)
            ForEach(EnvironmentID.allCases) { id in
                environmentOptionButton(
                    title: "Force: \(id.displayName)",
                    value: .force(id)
                )
            }
        }
        .padding(18)
        .frame(minWidth: 520, alignment: .leading)
        .glassBackgroundEffect()
    }

    private func environmentOptionButton(title: String, value: DebugPickerValue) -> some View {
        let selected = debugModeBinding.wrappedValue == value
        return Button {
            debugModeBinding.wrappedValue = value
            withAnimation(.easeInOut(duration: 0.15)) {
                isEnvironmentMenuOpen = false
            }
        } label: {
            HStack(spacing: 16) {
                Text(title)
                    .font(.system(size: 54, weight: selected ? .bold : .medium))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 36, weight: .bold))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var currentEnvironmentLabel: String {
        switch gameModel.environmentDebugMode {
        case .normal:
            return "Normal (random)"
        case .force(let id):
            return "Force: \(id.displayName)"
        }
    }

    private var debugModeBinding: Binding<DebugPickerValue> {
        Binding(
            get: {
                switch gameModel.environmentDebugMode {
                case .normal: return .normal
                case .force(let id): return .force(id)
                }
            },
            set: { value in
                switch value {
                case .normal:
                    gameModel.environmentDebugMode = .normal
                case .force(let id):
                    gameModel.environmentDebugMode = .force(id)
                }
            }
        )
    }

    private func metricChip(title: String, value: String, accent: Color) -> some View {
        VStack(spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(accent.opacity(0.9))
            Text(value)
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .frame(minWidth: 160)
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(accent.opacity(0.12))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(accent.opacity(0.35), lineWidth: 1)
                }
        }
    }

    private var statusText: String {
        if gameModel.isGameOver {
            return "Hit a wall — shake it off and go again."
        }
        if gameModel.isPlaying {
            return "Obstacles stream from the portal."
        }
        return "Stand on the line. Obstacles emerge from the portal — dodge and grab coins."
    }

    private var statusColor: Color {
        if gameModel.isGameOver { return hazard.opacity(0.95) }
        if gameModel.isPlaying { return neon.opacity(0.9) }
        return .secondary
    }
}

/// Hashable picker tags for the temporary environment debug control.
private enum DebugPickerValue: Hashable {
    case normal
    case force(EnvironmentID)
}

#Preview {
    PlayHUDView()
        .environmentObject(GameModel())
}
