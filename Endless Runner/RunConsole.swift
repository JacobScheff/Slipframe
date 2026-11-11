import SwiftUI

struct RunConsole: View {
    @ObservedObject var model: GameModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let recenter: () -> Void
    let signIn: () -> Void

    @State private var tab = Tab.run
    @State private var configuringAfterRun = false
    @State private var inspectedBiome = EnvironmentID.emberRun

    private enum Tab: String, CaseIterable, Identifiable {
        case run = "Run", biomes = "Biomes", guide = "Rift guide", scores = "Scores", settings = "Settings"
        var id: Self { self }
    }

    private var showsResults: Bool { model.isGameOver && !configuringAfterRun }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(SlipframeStyle.line).frame(height: 1)
            Group {
                switch tab {
                case .run:
                    if showsResults {
                        RunResults(model: model, stats: model.stats) {
                            configuringAfterRun = true
                        }
                    } else {
                        RunSetup(model: model, bests: model.personalBests) {
                            tab = .guide
                        }
                    }
                case .biomes:
                    biomeRoster
                case .guide:
                    RiftGuide()
                case .scores:
                    ScoresPanel(center: model.gameCenter, bests: model.personalBests,
                                preferredMode: model.resolvedPlayMode, signIn: signIn)
                case .settings:
                    settings
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if tab == .run {
                Rectangle().fill(SlipframeStyle.line).frame(height: 1)
                launchBar
            }
        }
        .frame(width: 808, height: 568)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .background {
            RoundedRectangle(cornerRadius: 27)
                .fill(.linearGradient(colors: [Color(red: 0.073, green: 0.111, blue: 0.158),
                                              SlipframeStyle.ink.opacity(0.97)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 27))
        .overlay {
            RoundedRectangle(cornerRadius: 27)
                .strokeBorder(.linearGradient(colors: [SlipframeStyle.ice.opacity(0.36), SlipframeStyle.line],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                .allowsHitTesting(false)
        }
        .onChange(of: model.isGameOver) { _, isGameOver in
            if isGameOver {
                tab = .run
                configuringAfterRun = false
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .foregroundStyle(SlipframeStyle.ice)
                .font(.system(size: 23, weight: .semibold))
                .accessibilityHidden(true)
            Text("SLIPFRAME")
                .font(.system(size: 21, weight: .heavy, design: .monospaced))
                .tracking(2)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            ForEach(Tab.allCases) { item in
                Button(item.rawValue) {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { tab = item }
                }
                .buttonStyle(ConsoleButtonStyle(selected: tab == item))
                .accessibilityAddTraits(tab == item ? .isSelected : [])
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private var launchBar: some View {
        HStack(spacing: 12) {
            if !model.fieldIsClear {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
                Text("Clearing the track…")
            } else if !model.canStartRun {
                Label("Select at least one biome to start.", systemImage: "info.circle")
            } else if model.isGameOver, !showsResults {
                Button("Last result") { configuringAfterRun = false }
                    .buttonStyle(ConsoleButtonStyle())
            } else {
                Label("Stand at the start marker and face the rift.", systemImage: "figure.stand")
            }
            Spacer()
            Button {
                guard model.fieldIsClear else { return }
                model.startRun()
            } label: {
                Label(showsResults && model.resolvedPlayMode == model.runMode ? "Play again" : "Start run",
                      systemImage: "arrow.right")
                    .frame(minWidth: 130)
            }
            .buttonStyle(ConsoleButtonStyle(prominent: true))
            .disabled(!model.fieldIsClear || !model.canStartRun)
        }
        .font(.system(size: 15))
        .foregroundStyle(SlipframeStyle.muted)
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }

    private var biomeRoster: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Biomes").font(.system(size: 29, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(EnvironmentID.allCases) { biome in
                        Button { inspectedBiome = biome } label: {
                            Label(biome.displayName, systemImage: biome.interfaceSymbol)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(ConsoleButtonStyle(selected: inspectedBiome == biome))
                        .accessibilityAddTraits(inspectedBiome == biome ? .isSelected : [])
                    }
                }
            }
            .frame(width: 349)
            VStack(alignment: .leading, spacing: 14) {
                BiomePreviewCard(biome: inspectedBiome, label: "Biome mechanic")
                Button {
                    model.soloEnvironment = inspectedBiome
                    model.playKind = .solo
                    configuringAfterRun = true
                    tab = .run
                } label: {
                    Label("Set up Loop", systemImage: "repeat")
                }
                .buttonStyle(ConsoleButtonStyle())
            }
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Settings").font(.system(size: 29, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Toggle(isOn: $model.showsTrack) {
                settingLabel("Floor track", detail: "Show lane markings and the track surface.")
            }
            Toggle(isOn: $model.showsRoomGrid) {
                settingLabel("Room grid", detail: "Trace detected walls and ceiling in light blue.")
            }
            Divider()
            HStack(spacing: 10) {
                Button(action: recenter) {
                    Label("Recenter track", systemImage: "scope")
                }
                .buttonStyle(ConsoleButtonStyle())
                .disabled(!model.fieldIsClear)
                Link(destination: SlipframeLinks.privacyPolicy) {
                    Label("Privacy policy", systemImage: "arrow.up.right")
                }
                .buttonStyle(ConsoleButtonStyle())
            }
        }
        .tint(SlipframeStyle.ice)
    }

    private func settingLabel(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 18, weight: .semibold))
            Text(detail).font(.system(size: 15)).foregroundStyle(SlipframeStyle.muted)
        }
        .padding(.vertical, 7)
    }
}

private struct RunSetup: View {
    @ObservedObject var model: GameModel
    @ObservedObject var bests: PersonalBestStore
    let openGuide: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                ConsoleCaption(title: "Run mode").padding(.bottom, 3)
                ForEach([PlayModeKind.normal, .solo, .playlist, .daily]) { mode in
                    let selected = model.playKind == mode
                    Button { model.playKind = mode } label: {
                        HStack(spacing: 10) {
                            Image(systemName: mode.symbol).frame(width: 20)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(mode.title).font(.system(size: 17, weight: .semibold))
                                Text(mode.summary)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(SlipframeStyle.muted)
                            }
                            Spacer(minLength: 0)
                            if selected {
                                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                            }
                        }
                        .frame(minHeight: 55)
                    }
                    .buttonStyle(ConsoleButtonStyle(selected: selected))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .frame(width: 205)
            ScrollView {
                if model.playKind == .daily {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        runDetails(on: context.date)
                    }
                } else {
                    runDetails(on: .now)
                }
            }
            .defaultScrollAnchor(.top)
            .id(model.playKind)
        }
    }

    private func runDetails(on date: Date) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            if let biome = model.previewEnvironment(on: date) {
                BiomePreviewCard(biome: biome, label: model.playKind == .solo ? "Loop biome" : "Starting biome")
            }
            switch model.playKind {
            case .normal:
                Text("At each junction, move into the lane of the rift you want to enter.")
                    .font(.system(size: 17))
                    .foregroundStyle(SlipframeStyle.muted)
                    .padding(.top, 3)
                Button(action: openGuide) { Label("Read the rift guide", systemImage: "arrow.up.right") }
                    .buttonStyle(ConsoleButtonStyle())
            case .solo:
                ConsoleCaption(title: "Choose a biome")
                biomeButtons
            case .playlist:
                if !model.playlistEnvironments.isEmpty {
                    ConsoleCaption(title: "First biome")
                    playlistStarts
                }
                ConsoleCaption(title: "Playlist · \(model.playlistEnvironments.count) selected")
                biomeButtons
            case .daily:
                dailyDetails(date: date)
            }
        }
        .padding(.trailing, 7)
    }

    private var biomeButtons: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            ForEach(EnvironmentID.allCases) { biome in
                let isLoop = model.playKind == .solo
                let selected = isLoop ? model.soloEnvironment == biome : model.playlistEnvironments.contains(biome)
                Button {
                    if isLoop { model.soloEnvironment = biome }
                    else { model.togglePlaylistBiome(biome) }
                } label: {
                    Label(biome.displayName, systemImage: isLoop ? biome.interfaceSymbol : selected ? "checkmark" : "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(ConsoleButtonStyle(selected: selected))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private var playlistStarts: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                startButton(title: "Random", start: nil)
                ForEach(EnvironmentID.allCases.filter { model.playlistEnvironments.contains($0) }) { biome in
                    startButton(title: biome.displayName, start: biome)
                }
            }
        }
    }

    private func startButton(title: String, start: EnvironmentID?) -> some View {
        let selected = model.playlistStart == start
        return Button {
            model.playlistStart = start
        } label: {
            Text(title).frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(ConsoleButtonStyle(selected: selected))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func dailyDetails(date: Date) -> some View {
        let board = LeaderboardBoard.daily(dayKey: DailyChallenge.dayKey(for: date))
        let best = bests.best(for: board)
        return VStack(alignment: .leading, spacing: 12) {
            Text(DailyChallenge.displayDate(for: date))
                .font(.system(size: 18, weight: .semibold))
            HStack(spacing: 27) {
                ConsoleMetric(title: "Resets at midnight ET",
                              value: DailyChallenge.formatCountdown(DailyChallenge.secondsUntilRollover(from: date)),
                              color: SlipframeStyle.ice, size: 20)
                ConsoleMetric(title: "Best score", value: best.bestScore.formatted(), size: 20)
                ConsoleMetric(title: "Best tokens", value: best.bestCoins.formatted(), color: SlipframeStyle.amber, size: 20)
            }
        }
        .padding(13)
    }
}

private extension PlayModeKind {
    var symbol: String {
        switch self {
        case .normal: return "arrow.triangle.branch"
        case .solo: return "repeat"
        case .playlist: return "shuffle"
        case .daily: return "calendar"
        }
    }

    var summary: String {
        switch self {
        case .normal: return "Choose your route"
        case .solo: return "Stay in one biome"
        case .playlist: return "Shuffle your biomes"
        case .daily: return "One seed for everyone"
        }
    }
}

private struct RiftGuide: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Choose a rift")
                    .font(.system(size: 29, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("Move left, center, or right to line up with a destination. Hold that lane as the rift approaches.")
                    .font(.system(size: 17))
                    .foregroundStyle(SlipframeStyle.muted)
                HStack(spacing: 8) {
                    ForEach(RiftRisk.allCases, id: \.self) { risk in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(String(repeating: "◆ ", count: risk.difficultyMarkerCount))
                                .foregroundStyle(risk.interfaceTint)
                                .accessibilityHidden(true)
                            Text(risk.rawValue.capitalized).font(.system(size: 17, weight: .semibold))
                            Text("\(risk.scoreMultiplier.formatted())× distance score")
                                .foregroundStyle(SlipframeStyle.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(13)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 13))
                        .accessibilityElement(children: .combine)
                    }
                }
                Text("More diamonds mean denser obstacle patterns and more chances to collect tokens.")
                    .foregroundStyle(SlipframeStyle.muted)
                ConsoleCaption(title: "Rift modifiers")
                ForEach(RiftModifier.allCases, id: \.rawValue) { modifier in
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Label(modifier.displayName, systemImage: modifier.interfaceSymbol)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(SlipframeStyle.ice)
                            .frame(width: 165, alignment: .leading)
                        Text(modifier.effect)
                            .font(.system(size: 16))
                    }
                    Divider()
                }
            }
            .padding(.trailing, 10)
        }
    }
}

extension RiftRisk {
    var interfaceTint: Color {
        switch self {
        case .stable: return .mint
        case .charged: return SlipframeStyle.amber
        case .unstable: return Color(red: 1, green: 0.48, blue: 0.47)
        }
    }
}

extension RiftModifier {
    var interfaceSymbol: String {
        switch self {
        case .tokenSurge: return "diamond.fill"
        case .aegis: return "shield"
        case .overdrive: return "bolt"
        case .magnet: return "magnet"
        case .closeCall: return "scope"
        case .bonusBank: return "lock"
        }
    }
}
