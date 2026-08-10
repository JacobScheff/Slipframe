//
//  LevelSelectView.swift
//  Slipframe
//
//  World-anchored mode / level picker at the left track edge.
//

import SwiftUI

struct LevelSelectView: View {
    @EnvironmentObject private var gameModel: GameModel
    @State private var showReplayConfirm = false

    private let neon = Color(red: 0.35, green: 0.92, blue: 1.0)
    private let gold = Color(red: 1.0, green: 0.82, blue: 0.32)
    private let dailyAccent = Color(red: 0.45, green: 0.88, blue: 0.78)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            // First-time only — once completed, tutorial moves to a quiet footer control.
            if !gameModel.hasCompletedTutorial {
                playTutorialButton
            }

            modePicker

            Divider().opacity(0.35)

            modeBody

            footerRow
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(width: 420, alignment: .leading)
        .xenotechPanel(primary: neon, secondary: gold, cornerRadius: 22)
        // System confirmationDialog does not present from RealityKit attachments.
        .onChange(of: gameModel.isPlaying) { _, playing in
            if playing { showReplayConfirm = false }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Slipframe")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(neon)
            Text("Mode Selection")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    /// Privacy + optional replay control share one footer row to save vertical space.
    private var footerRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            privacyFooter
            Spacer(minLength: 8)
            if gameModel.hasCompletedTutorial {
                replayTutorialFooter
            }
        }
        .padding(.top, 4)
    }

    private var privacyFooter: some View {
        Link(destination: SlipframeLinks.privacyPolicy) {
            Text("Privacy Policy")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .underline()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Privacy Policy")
    }

    private var playTutorialButton: some View {
        Button {
            gameModel.startTutorial()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 18, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Play Tutorial")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("Guided calibration with coaching overlays.")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(gold.opacity(0.14))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(gold.opacity(0.55), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(gameModel.isPlaying)
    }

    /// Quiet footer — confirmation is inline because attachment views can't present dialogs.
    @ViewBuilder
    private var replayTutorialFooter: some View {
        if showReplayConfirm {
            VStack(alignment: .trailing, spacing: 8) {
                Text("Replay the full tutorial?")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)

                HStack(spacing: 10) {
                    Button("Cancel") {
                        showReplayConfirm = false
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                    Button("Replay") {
                        showReplayConfirm = false
                        gameModel.startTutorial()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(gold.opacity(0.9))
                }
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showReplayConfirm = true
                }
            } label: {
                Text("Replay tutorial…")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .disabled(gameModel.isPlaying)
            .accessibilityLabel("Replay tutorial")
        }
    }

    private var modePicker: some View {
        HStack(spacing: 8) {
            ForEach(PlayModeKind.allCases) { kind in
                let selected = gameModel.playKind == kind
                Button {
                    gameModel.playKind = kind
                } label: {
                    Text(kind.title)
                        .font(.system(size: 15, weight: selected ? .bold : .medium, design: .rounded))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selected ? neon.opacity(0.22) : Color.white.opacity(0.06))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(selected ? neon.opacity(0.7) : Color.white.opacity(0.12), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var modeBody: some View {
        switch gameModel.playKind {
        case .normal:
            normalBody
        case .playlist:
            playlistBody
        case .solo:
            soloBody
        case .daily:
            dailyBody
        }
    }

    private var normalBody: some View {
        Text(PlayModeKind.normal.subtitle)
            .font(.system(size: 16, weight: .regular, design: .rounded))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var soloBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(PlayModeKind.solo.subtitle)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)

            biomeGrid(selection: .solo)
        }
    }

    private var playlistBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(PlayModeKind.playlist.subtitle)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("BIOMES")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(.secondary)

            biomeGrid(selection: .playlist)

            if gameModel.playlistEnvironments.isEmpty {
                Text("Select at least one biome.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.orange)
            }

            Text("STARTING BIOME")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            playlistStartPicker
        }
    }

    private var playlistStartPicker: some View {
        let selected = gameModel.playlistEnvironments
        return FlowChips {
            startChip(title: "Random", isOn: gameModel.playlistStart == nil) {
                gameModel.playlistStart = nil
            }
            ForEach(EnvironmentID.allCases) { id in
                if selected.contains(id) {
                    startChip(title: id.displayName, isOn: gameModel.playlistStart == id) {
                        gameModel.playlistStart = id
                    }
                }
            }
        }
    }

    private func startChip(title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: isOn ? .bold : .medium, design: .rounded))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background {
                    Capsule(style: .continuous)
                        .fill(isOn ? gold.opacity(0.22) : Color.white.opacity(0.06))
                }
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(isOn ? gold.opacity(0.75) : Color.white.opacity(0.14), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private var dailyBody: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = DailyChallenge.secondsUntilRollover(from: context.date)

            VStack(alignment: .leading, spacing: 12) {
                Text(DailyChallenge.displayDate(for: context.date))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(dailyAccent)

                Text(PlayModeKind.daily.subtitle)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Image(systemName: "timer")
                        .foregroundStyle(dailyAccent)
                    Text(DailyChallenge.formatCountdown(remaining))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(dailyAccent)
                    Text("left today")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
        }
    }

    private enum BiomeSelection {
        case solo
        case playlist
    }

    private func biomeGrid(selection: BiomeSelection) -> some View {
        VStack(spacing: 8) {
            ForEach(EnvironmentID.allCases) { id in
                biomeRow(id: id, selection: selection)
            }
        }
    }

    private func biomeRow(id: EnvironmentID, selection: BiomeSelection) -> some View {
        let isOn: Bool = {
            switch selection {
            case .solo: return gameModel.soloEnvironment == id
            case .playlist: return gameModel.playlistEnvironments.contains(id)
            }
        }()

        return Button {
            switch selection {
            case .solo:
                gameModel.soloEnvironment = id
            case .playlist:
                if gameModel.playlistEnvironments.contains(id) {
                    gameModel.playlistEnvironments.remove(id)
                    if gameModel.playlistStart == id {
                        gameModel.playlistStart = nil
                    }
                } else {
                    gameModel.playlistEnvironments.insert(id)
                }
            }
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(biomeColor(id))
                    .frame(width: 12, height: 12)
                Text(id.displayName)
                    .font(.system(size: 17, weight: isOn ? .bold : .medium, design: .rounded))
                Spacer(minLength: 4)
                if isOn {
                    Image(systemName: selection == .solo ? "checkmark.circle.fill" : "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(neon)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isOn ? neon.opacity(0.14) : Color.white.opacity(0.04))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isOn ? neon.opacity(0.55) : Color.white.opacity(0.1), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func biomeColor(_ id: EnvironmentID) -> Color {
        let tint = EnvironmentCatalog.profile(for: id).palette.portalRim
        return Color(red: Double(tint.r), green: Double(tint.g), blue: Double(tint.b))
    }
}

/// Simple wrapping chip row without pulling in a layout dependency.
private struct FlowChips<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        // VisionOS panels are narrow — a wrapping LazyVGrid keeps chips tidy.
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 96), spacing: 8)],
            alignment: .leading,
            spacing: 8
        ) {
            content()
        }
    }
}

#Preview {
    LevelSelectView()
        .environmentObject(GameModel())
}
