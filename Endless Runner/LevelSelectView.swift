//
//  LevelSelectView.swift
//  Slipframe
//
//  Play-tab content for the centered command console.
//

import SwiftUI

struct LevelSelectView: View {
    @EnvironmentObject private var gameModel: GameModel
    @Environment(\.openURL) private var openURL
    @State private var showReplayConfirm = false

    private let neon = Color(red: 0.35, green: 0.92, blue: 1.0)
    private let gold = Color(red: 1.0, green: 0.82, blue: 0.32)
    private let dailyAccent = Color(red: 0.45, green: 0.88, blue: 0.78)

    private let biomeColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !gameModel.hasCompletedTutorial {
                playTutorialButton
            }

            modePicker

            modeBody

            footerRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: gameModel.isPlaying) { _, playing in
            if playing { showReplayConfirm = false }
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
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(gold.opacity(0.22))
                        .frame(width: 40, height: 40)
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(gold)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Play Tutorial")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("Guided calibration with coaching overlays.")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(gold.opacity(0.7))
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
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
            spacing: 10
        ) {
            ForEach(PlayModeKind.allCases) { kind in
                modeCard(kind)
            }
        }
    }

    private func modeCard(_ kind: PlayModeKind) -> some View {
        let selected = gameModel.playKind == kind
        return Button {
            gameModel.playKind = kind
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(selected ? neon.opacity(0.28) : Color.white.opacity(0.08))
                        .frame(width: 44, height: 44)
                    Image(systemName: kind.symbolName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(selected ? neon : .secondary)
                        .symbolRenderingMode(.hierarchical)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .font(.system(size: 17, weight: selected ? .bold : .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(kind.cardBlurb)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(selected ? neon.opacity(0.16) : Color.white.opacity(0.05))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(selected ? neon.opacity(0.75) : Color.white.opacity(0.1), lineWidth: selected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
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
        VStack(alignment: .leading, spacing: 12) {
            Text(PlayModeKind.normal.subtitle)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                ForEach(EnvironmentID.allCases) { id in
                    biomePip(id)
                }
            }
            .frame(maxWidth: .infinity)

            Text("PORTAL MODIFIERS")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: biomeColumns, spacing: 8) {
                ForEach(RiftModifier.allCases, id: \.rawValue) { modifier in
                    modifierKey(modifier)
                }
            }
        }
    }

    private func modifierKey(_ modifier: RiftModifier) -> some View {
        HStack(spacing: 8) {
            RiftModifierIcon(modifier: modifier, accent: gold, size: 14)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(modifier.displayName)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                Text(modifier.effectDescription)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(modifier.displayName), \(modifier.effectDescription)")
    }

    private func biomePip(_ id: EnvironmentID) -> some View {
        let tint = EnvironmentCatalog.profile(for: id).palette.portalRim
        let color = Color(red: Double(tint.r), green: Double(tint.g), blue: Double(tint.b))
        return VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.28))
                    .frame(width: 36, height: 36)
                Image(systemName: id.symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text(id.displayName)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel(id.displayName)
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
            let dayKey = DailyChallenge.dayKey(for: context.date)
            let bestScore = gameModel.personalBests
                .best(for: .daily(dayKey: dayKey))
                .bestScore
            let progress = countdownProgress(remaining)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .stroke(dailyAccent.opacity(0.18), lineWidth: 8)
                            .frame(width: 86, height: 86)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(
                                dailyAccent,
                                style: StrokeStyle(lineWidth: 8, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: 86, height: 86)
                        VStack(spacing: 0) {
                            Image(systemName: "calendar")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(dailyAccent)
                            Text(DailyChallenge.formatCountdown(remaining))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(dailyAccent)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(DailyChallenge.displayDate(for: context.date))
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundStyle(dailyAccent)
                        Text(PlayModeKind.daily.subtitle)
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                dailyBestShareRow(bestScore: bestScore, date: context.date)
            }
        }
    }

    /// Fraction of the Eastern-Time day still remaining (1 at midnight, 0 at next midnight).
    private func countdownProgress(_ remaining: TimeInterval) -> CGFloat {
        let day: TimeInterval = 24 * 60 * 60
        return CGFloat(max(0, min(1, remaining / day)))
    }

    private func dailyBestShareRow(bestScore: Int, date: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("YOUR BEST TODAY")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(dailyAccent.opacity(0.85))
                Spacer(minLength: 8)
                Text(bestScore > 0 ? "\(bestScore)" : "—")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(bestScore > 0 ? .primary : .secondary)
            }

            Button {
                shareDailyBest(score: bestScore, date: date)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "message.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text(bestScore > 0 ? "Share to Messages" : "Play Daily to share")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Spacer(minLength: 4)
                }
                .foregroundStyle(bestScore > 0 ? dailyAccent : .secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(dailyAccent.opacity(bestScore > 0 ? 0.16 : 0.08))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(dailyAccent.opacity(bestScore > 0 ? 0.55 : 0.22), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .disabled(bestScore <= 0 || gameModel.isPlaying)
            .accessibilityLabel(
                bestScore > 0
                ? "Share today’s Daily best score \(bestScore) to Messages"
                : "Play Daily to unlock Messages share"
            )
        }
        .padding(.top, 4)
    }

    private func shareDailyBest(score: Int, date: Date) {
        guard score > 0, let url = DailyScoreShare.messagesURL(score: score, date: date) else { return }
        openURL(url)
    }

    private enum BiomeSelection {
        case solo
        case playlist
    }

    private func biomeGrid(selection: BiomeSelection) -> some View {
        LazyVGrid(columns: biomeColumns, spacing: 10) {
            ForEach(EnvironmentID.allCases) { id in
                let isOn: Bool = {
                    switch selection {
                    case .solo: return gameModel.soloEnvironment == id
                    case .playlist: return gameModel.playlistEnvironments.contains(id)
                    }
                }()
                BiomeCard(
                    id: id,
                    isOn: isOn,
                    selectionStyle: selection == .solo ? .radio : .check,
                    accent: neon
                ) {
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
                }
            }
        }
    }
}

/// Simple wrapping chip row without pulling in a layout dependency.
private struct FlowChips<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
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
