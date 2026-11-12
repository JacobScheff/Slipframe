import SwiftUI

struct RunConsole: View {
    @ObservedObject var model: GameModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let recenter: () -> Void
    let signIn: () -> Void

    @AppStorage("tutorial.completed.v3") private var completedTutorial = false
    @AppStorage("tutorial.offerDismissed.v3") private var dismissedTutorialOffer = false
    @State private var tab = Tab.run
    @State private var configuringAfterRun = false
    @State private var inspectedBiome = EnvironmentID.emberRun
    @State private var tutorialReturnTab = Tab.run
    @State private var tutorialReturnConfiguration = false

    private enum Tab: String, CaseIterable, Identifiable {
        case run = "Play", biomes = "Biomes", guide = "Learn", scores = "Scores", settings = "Settings"
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
                    if !completedTutorial && !dismissedTutorialOffer && !model.isGameOver {
                        welcome
                    } else if showsResults {
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
                    learningLibrary
                case .scores:
                    ScoresPanel(center: model.gameCenter, bests: model.personalBests,
                                preferredMode: model.resolvedPlayMode, signIn: signIn)
                case .settings:
                    settings
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if tab == .run {
                Rectangle().fill(SlipframeStyle.line).frame(height: 1)
                launchBar
            }
        }
        .frame(width: 920, height: 620)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .background {
            RoundedRectangle(cornerRadius: 27)
                .fill(.linearGradient(colors: [SlipframeStyle.panel, SlipframeStyle.ink],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 27))
        .overlay {
            RoundedRectangle(cornerRadius: 27)
                .strokeBorder(.linearGradient(colors: [SlipframeStyle.ice.opacity(0.22), SlipframeStyle.line],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                .allowsHitTesting(false)
        }
        .onChange(of: model.showsTutorial) { _, showing in
            if showing {
                tutorialReturnTab = tab
                tutorialReturnConfiguration = configuringAfterRun
                dismissedTutorialOffer = true
            } else {
                tab = model.tutorialReturnsToSetup ? .run : tutorialReturnTab
                configuringAfterRun = model.tutorialReturnsToSetup ? true : tutorialReturnConfiguration
            }
        }
        .onChange(of: model.isGameOver) { _, isGameOver in
            if isGameOver {
                tab = .run
                configuringAfterRun = false
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            SlipframeMark().frame(width: 28, height: 33)
            VStack(alignment: .leading, spacing: 3) {
                Text("SLIPFRAME")
                    .font(.system(size: 20, weight: .semibold))
                    .tracking(3)
                    .accessibilityAddTraits(.isHeader)
                Text("Your room. Eight worlds.")
                    .font(.system(size: 12))
                    .foregroundStyle(SlipframeStyle.muted)
            }
            Spacer()
            ForEach(Tab.allCases) { item in
                Button(item.rawValue) {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { tab = item }
                }
                .buttonStyle(.plain)
                .font(.system(size: 15, weight: tab == item ? .semibold : .medium))
                .foregroundStyle(tab == item ? .white : SlipframeStyle.muted)
                .padding(.horizontal, 17)
                .frame(minHeight: 46)
                .background(tab == item ? .white.opacity(0.075) : .clear, in: Capsule())
                .contentShape(.hoverEffect, Capsule())
                .hoverEffect(.highlight)
                .accessibilityAddTraits(tab == item ? .isSelected : [])
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }

    private var welcome: some View {
        HStack(spacing: 26) {
            VStack(alignment: .leading, spacing: 18) {
                ConsoleCaption(title: "Welcome to Slipframe", color: SlipframeStyle.ice)
                Text("Find your\nnext opening.")
                    .font(.system(size: 48, weight: .medium))
                    .lineSpacing(-2)
                Text("Lean past walls. Reach for gold.\nChoose a new world at every rift.")
                    .font(.system(size: 19))
                    .foregroundStyle(SlipframeStyle.muted)
                    .lineSpacing(5)
                HStack(spacing: 10) {
                    Button("Learn the moves") {
                        dismissedTutorialOffer = true
                        model.showTutorial()
                    }
                    .buttonStyle(ConsoleButtonStyle(prominent: true))
                    .disabled(!model.fieldIsClear)
                    Button("Choose a run") { dismissedTutorialOffer = true }
                        .buttonStyle(ConsoleButtonStyle())
                }
                Text("Six short lessons. Replay each example at your own pace.")
                    .font(.system(size: 13)).foregroundStyle(SlipframeStyle.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            BiomeArtwork(biome: .emberRun)
                .frame(width: 290, height: 350)
                .accessibilityHidden(true)
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private var learningLibrary: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 16) {
                ConsoleCaption(title: "How to play", color: SlipframeStyle.ice)
                Text("Learn one move\nat a time.")
                    .font(.system(size: 32, weight: .medium))
                Text("Start with the essentials, or open a guide for the mechanic you want to practice.")
                    .font(.system(size: 17)).foregroundStyle(SlipframeStyle.muted)
                Button("Start the basics") { model.showTutorial() }
                    .buttonStyle(ConsoleButtonStyle(prominent: true))
                    .disabled(!model.fieldIsClear)
                Button("Difficulty & modifiers") { model.showTutorial(.difficulty) }
                    .buttonStyle(ConsoleButtonStyle())
                    .disabled(!model.fieldIsClear)
                Button("Run modes") { model.showTutorial(.modes) }
                    .buttonStyle(ConsoleButtonStyle())
                    .disabled(!model.fieldIsClear)
            }
            .frame(width: 260, alignment: .leading)
            RiftGuide()
        }
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
            Button("How to play") { model.showTutorial() }
                .buttonStyle(ConsoleButtonStyle())
                .disabled(!model.fieldIsClear)
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
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .background(.black.opacity(0.10))
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
            .frame(width: 310)
            VStack(alignment: .leading, spacing: 14) {
                BiomePreviewCard(biome: inspectedBiome, label: "Biome mechanic")
                Text("Every biome adds a different way to move or interact. Open its guide to see the mechanic before starting a Loop.")
                    .font(.system(size: 16)).foregroundStyle(SlipframeStyle.muted)
                Button("Show me the mechanic") {
                    model.showTutorial(TutorialLesson(rawValue: inspectedBiome.rawValue) ?? .space)
                }
                .buttonStyle(ConsoleButtonStyle())
                .disabled(!model.fieldIsClear)
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
            ConsoleCaption(title: "Make it yours", color: SlipframeStyle.ice)
            Text("Keep your room in view.").font(.system(size: 32, weight: .medium))
                .accessibilityAddTraits(.isHeader)
            Text("A few light touches on the surfaces around you. Adjust them to suit your space.")
                .font(.system(size: 17)).foregroundStyle(SlipframeStyle.muted)
                .padding(.bottom, 8)
            Toggle(isOn: $model.showsTrack) {
                settingLabel("Floor track", detail: "Show lane markings and the track surface.")
            }
            Toggle(isOn: $model.showsRoomGrid) {
                settingLabel("Wall & ceiling grid", detail: "Square grid cells traced onto detected walls and ceiling.")
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
                BiomePreviewCard(biome: biome, label: model.playKind == .solo ? "Loop biome" : "Starting biome",
                                 compact: model.playKind == .solo || model.playKind == .playlist)
            } else if model.playKind == .playlist {
                VStack(alignment: .leading, spacing: 12) {
                    ConsoleCaption(title: "Your route", color: SlipframeStyle.ice)
                    Text("Build a playlist.").font(.system(size: 32, weight: .medium))
                    Text("Choose at least one biome below. Add a few favorites, then pick where to start.")
                        .font(.system(size: 16)).foregroundStyle(SlipframeStyle.muted)
                }
                .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
                .padding(24)
                .background(SlipframeStyle.ink, in: RoundedRectangle(cornerRadius: 21))
                .overlay { RoundedRectangle(cornerRadius: 21).strokeBorder(SlipframeStyle.line) }
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
                    playlistStarts
                }
                HStack {
                    ConsoleCaption(title: "Playlist · \(model.playlistEnvironments.count) selected")
                    Spacer()
                    Button("Select all") {
                        model.playlistEnvironments = Set(EnvironmentID.allCases)
                    }
                    .disabled(model.playlistEnvironments.count == EnvironmentID.allCases.count)
                    Button("Clear") {
                        model.playlistEnvironments = []
                        model.playlistStart = nil
                    }
                    .disabled(model.playlistEnvironments.isEmpty)
                }
                .font(.system(size: 13, weight: .medium))
                .tint(SlipframeStyle.ice)
                biomeButtons
            case .daily:
                dailyDetails(date: date)
            }
            if model.playKind == .normal || model.playKind == .solo {
                let board: LeaderboardBoard = model.playKind == .normal ? .normal : .loop(model.soloEnvironment)
                let best = bests.best(for: board)
                HStack(spacing: 30) {
                    ConsoleMetric(title: "Your best score", value: best.bestScore.formatted(), size: 21)
                    ConsoleMetric(title: "Your best tokens", value: best.bestCoins.formatted(), color: SlipframeStyle.amber, size: 21)
                }
                .padding(.top, 8)
            } else if model.playKind == .playlist {
                Text("Unranked · Your selected biomes shuffle after the first world")
                    .font(.system(size: 13)).foregroundStyle(SlipframeStyle.muted)
            }
        }
        .padding(.trailing, 7)
    }

    private var biomeButtons: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(EnvironmentID.allCases) { biome in
                let isLoop = model.playKind == .solo
                let selected = isLoop ? model.soloEnvironment == biome : model.playlistEnvironments.contains(biome)
                Button {
                    if isLoop { model.soloEnvironment = biome }
                    else { model.togglePlaylistBiome(biome) }
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: biome.interfaceSymbol)
                            .foregroundStyle(biome.interfaceTint)
                            .frame(width: 20)
                        Text(biome.displayName).lineLimit(1)
                        Spacer(minLength: 0)
                        if !isLoop {
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected ? SlipframeStyle.ice : SlipframeStyle.muted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(ConsoleButtonStyle(selected: selected))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private var playlistStarts: some View {
        Menu {
            Button("Random") { model.playlistStart = nil }
            ForEach(EnvironmentID.allCases.filter { model.playlistEnvironments.contains($0) }) { biome in
                Button(biome.displayName) { model.playlistStart = biome }
            }
        } label: {
            HStack {
                Text("First world").foregroundStyle(SlipframeStyle.muted)
                Spacer()
                Text(model.playlistStart?.displayName ?? "Random")
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold))
            }
        }
        .buttonStyle(ConsoleButtonStyle())
        .accessibilityLabel("First playlist world")
        .accessibilityValue(model.playlistStart?.displayName ?? "Random")
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
                            HStack(spacing: 4) {
                                ForEach(0..<risk.difficultyMarkerCount, id: \.self) { _ in
                                    Image(systemName: "diamond.fill").font(.system(size: 9))
                                }
                            }
                            .foregroundStyle(risk.interfaceTint)
                            .frame(height: 16)
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
                        Text(modifier.displayName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(SlipframeStyle.ice)
                            .frame(width: 120, alignment: .leading)
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
        case .magnet: return "dot.radiowaves.left.and.right"
        case .closeCall: return "scope"
        case .bonusBank: return "lock"
        }
    }
}
