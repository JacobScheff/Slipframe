//
//  LevelSelectView.swift
//  Slipframe
//
//  Run setup. The console owns the persistent launch action.
//

import SwiftUI

struct LevelSelectView: View {
    @EnvironmentObject private var gameModel: GameModel
    @EnvironmentObject private var personalBests: PersonalBestStore
    @Environment(\.openURL) private var openURL
    @State private var showsPortalGuide = false
    @State private var showReplayConfirm = false

    private let accent = SlipframeUI.accent
    private let gold = SlipframeUI.reward
    private let biomeColumns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !gameModel.hasCompletedTutorial {
                tutorialPrompt
            }

            modePicker

            Group {
                switch gameModel.playKind {
                case .normal: normalBody
                case .solo: soloBody
                case .playlist: playlistBody
                case .daily: dailyBody
                }
            }

            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: gameModel.isPlaying) { _, playing in
            if playing { showReplayConfirm = false }
        }
    }

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("RUN MODE")
            HStack(spacing: 8) {
                ForEach(PlayModeKind.allCases) { kind in
                    let selected = gameModel.playKind == kind
                    Button {
                        gameModel.playKind = kind
                    } label: {
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                Image(systemName: kind.symbolName)
                                    .foregroundStyle(selected ? accent : Color.secondary)
                                Spacer()
                                if selected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(accent)
                                }
                            }
                            Text(kind.title)
                                .font(.system(size: 16, weight: .semibold))
                            Text(kind.cardBlurb)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.interaction, RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(ConsoleSelectionStyle(selected: selected))
                    .accessibilityLabel("\(kind.title), \(kind.cardBlurb)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    private var normalBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack(alignment: .leading) {
                BiomeSlideshow(isActive: !gameModel.isPlaying && (!gameModel.isGameOver || gameModel.isGameOverMenuVisible))
                LinearGradient(
                    stops: [
                        .init(color: SlipframeUI.surface.opacity(0.98), location: 0),
                        .init(color: SlipframeUI.surface.opacity(0.90), location: 0.38),
                        .init(color: SlipframeUI.surface.opacity(0.12), location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("EIGHT BIOMES. YOUR PATH.")
                    Text("Into the rift.")
                        .font(.system(size: 30, weight: .semibold))
                    Text("Dodge. Reach. Find your flow.\nChoose your next world at each crossing.")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineSpacing(3)
                }
                .padding(22)
            }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            // Cropping affects drawing, not hit testing. The entire hero is
            // decorative so its oversized image cannot intercept the mode row.
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)

            DisclosureGroup(isExpanded: $showsPortalGuide) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Step into a lane to choose a portal. More warning diamonds mean harder patterns. The symbol below a portal shows its bonus.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 16) {
                        ForEach(RiftModifier.allCases, id: \.rawValue) { modifier in
                            HStack(alignment: .top, spacing: 10) {
                                RiftModifierIcon(modifier: modifier, accent: gold, size: 18)
                                    .frame(width: 24, height: 22)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(modifier.displayName)
                                        .font(.system(size: 14, weight: .semibold))
                                    Text(modifier == .tokenSurge
                                         ? "Tokens arrive in threes. Each token is worth 2×. More crystal halves in Crystal Cave."
                                         : modifier.effectDescription)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    Text("No symbol means no modifier.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 14)
            } label: {
                Label("Portal field guide", systemImage: "book.closed")
                    .font(.system(size: 14, weight: .medium))
                    .frame(minHeight: 44)
            }
            .tint(accent)
        }
    }

    private var soloBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeading("Find your rhythm", detail: "Choose one biome to play on repeat.")
            biomeGrid(isPlaylist: false)
        }
    }

    private var playlistBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                sectionHeading("Choose your biomes", detail: "Selected biomes shuffle throughout your run.")
                Spacer()
                Text("\(gameModel.playlistEnvironments.count) / \(EnvironmentID.allCases.count) selected")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(accent)
            }
            biomeGrid(isPlaylist: true)

            if gameModel.playlistEnvironments.isEmpty {
                Label("Choose at least one biome to start.", systemImage: "info.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(gold)
            } else {
                sectionLabel("STARTING BIOME")
                    .padding(.top, 4)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                    startChip("Random", id: nil)
                    ForEach(EnvironmentID.allCases.filter { gameModel.playlistEnvironments.contains($0) }) { id in
                        startChip(id.displayName, id: id)
                    }
                }
            }
        }
    }

    private func startChip(_ title: String, id: EnvironmentID?) -> some View {
        let selected = gameModel.playlistStart == id
        return Button {
            gameModel.playlistStart = id
        } label: {
            HStack(spacing: 6) {
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                }
                Text(title).font(.system(size: 13, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
        }
        .buttonStyle(ConsoleSelectionStyle(selected: selected))
        .accessibilityLabel("Start: \(title)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func biomeGrid(isPlaylist: Bool) -> some View {
        LazyVGrid(columns: biomeColumns, spacing: 12) {
            ForEach(EnvironmentID.allCases) { id in
                BiomeCard(
                    id: id,
                    isOn: isPlaylist ? gameModel.playlistEnvironments.contains(id) : gameModel.soloEnvironment == id,
                    selectionStyle: isPlaylist ? .check : .radio,
                    accent: accent
                ) {
                    if !isPlaylist {
                        gameModel.soloEnvironment = id
                    } else if gameModel.playlistEnvironments.contains(id) {
                        gameModel.playlistEnvironments.remove(id)
                        if gameModel.playlistStart == id { gameModel.playlistStart = nil }
                    } else {
                        gameModel.playlistEnvironments.insert(id)
                    }
                }
            }
        }
    }

    private var dailyBody: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = DailyChallenge.secondsUntilRollover(from: context.date)
            let best = personalBests.best(for: .daily(dayKey: DailyChallenge.dayKey(for: context.date))).bestScore
            VStack(alignment: .leading, spacing: 20) {
                sectionHeading("One day. A shared challenge.", detail: PlayModeKind.daily.subtitle)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        sectionLabel("TODAY'S RUN")
                        Text(DailyChallenge.displayDate(for: context.date))
                            .font(.system(size: 22, weight: .semibold))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        sectionLabel("RESETS IN")
                        Text(DailyChallenge.formatCountdown(remaining))
                            .font(.system(size: 22, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(accent)
                    }
                    .accessibilityElement(children: .combine)
                }
                Divider().overlay(SlipframeUI.hairline)
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        sectionLabel("YOUR BEST TODAY")
                        Text(best > 0 ? best.formatted() : "—")
                            .font(.system(size: 36, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                    }
                    Spacer()
                    Button {
                        guard best > 0, let url = DailyScoreShare.messagesURL(score: best, date: context.date) else { return }
                        openURL(url)
                    } label: {
                        Label("Share best", systemImage: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(best <= 0 || gameModel.isPlaying)
                    .accessibilityLabel("Share today's best score to Messages")
                }
                if best == 0 {
                    Text("Finish a Daily run to set your first score.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(22)
            .background(SlipframeUI.inset, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var tutorialPrompt: some View {
        Button {
            gameModel.startTutorial()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 22))
                    .foregroundStyle(gold)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your first crossing")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Learn to dodge, collect, and move through the rifts.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text("Learn to play")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(gold)
                Image(systemName: "arrow.right").foregroundStyle(gold)
            }
            .padding(16)
            .background(gold.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .disabled(gameModel.isPlaying)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider().overlay(SlipframeUI.hairline)
            HStack {
                Link("Privacy policy", destination: SlipframeLinks.privacyPolicy)
                    .frame(minHeight: 44)
                Spacer()
                if gameModel.hasCompletedTutorial {
                    Button("Replay tutorial") { showReplayConfirm.toggle() }
                        .frame(minHeight: 44)
                        .disabled(gameModel.isPlaying)
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)

            // RealityView attachments cannot present confirmation dialogs.
            if showReplayConfirm {
                HStack {
                    Text("Replay the guided tutorial?")
                        .font(.system(size: 14))
                    Spacer()
                    Button("Cancel") { showReplayConfirm = false }
                        .buttonStyle(.bordered)
                    Button("Replay") {
                        showReplayConfirm = false
                        gameModel.startTutorial()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                }
                .controlSize(.large)
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .tracking(1.2)
            .foregroundStyle(.secondary)
    }

    private func sectionHeading(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 21, weight: .semibold))
            Text(detail)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Only the artwork changes; the hero's text and geometry stay still.
private struct BiomeSlideshow: View {
    var isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var biome = EnvironmentID.allCases.randomElement() ?? .emberRun

    private var shouldAdvance: Bool {
        isActive && scenePhase == .active
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image("Biome_\(biome.rawValue)")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .id(biome)
                    .transition(.opacity)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: shouldAdvance) {
            guard shouldAdvance else { return }
            // Use a separate shuffled bag; menu animation never consumes the
            // deterministic gameplay random stream used by Daily challenges.
            var upcoming = EnvironmentID.allCases.filter { $0 != biome }.shuffled()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(6))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                if upcoming.isEmpty {
                    upcoming = EnvironmentID.allCases.shuffled()
                    if upcoming.count > 1, upcoming.first == biome {
                        upcoming.swapAt(0, 1)
                    }
                }
                guard !upcoming.isEmpty else { return }
                let next = upcoming.removeFirst()
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 1)) {
                    biome = next
                }
            }
        }
    }
}

#Preview {
    let model = GameModel()
    return LevelSelectView()
        .environmentObject(model)
        .environmentObject(model.personalBests)
        .padding(28)
        .frame(width: 720)
        .xenotechPanel(primary: SlipframeUI.accent)
}
