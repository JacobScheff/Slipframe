import SwiftUI

struct RunHUD: View {
    @ObservedObject var model: GameModel
    @ObservedObject var stats: RunStats
    @State private var hint: EnvironmentID?

    private struct BiomeVisit: Equatable {
        let isPlaying: Bool
        let runID: Int
        let biome: EnvironmentID
    }

    var body: some View {
        // A fixed bottom edge keeps score placement stable when a hint or junction opens.
        VStack(spacing: 8) {
            if model.isOffPlayfield {
                Label("Return to the start area to resume", systemImage: "figure.walk")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(SlipframeStyle.amber)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(SlipframeStyle.ink.opacity(0.94), in: Capsule())
                    .accessibilityAddTraits(.updatesFrequently)
            } else if model.isChoosingPortal {
                junction
            } else if let hint {
                Label(hint.mechanic, systemImage: hint.interfaceSymbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(SlipframeStyle.ice)
                    .padding(12)
                    .background(SlipframeStyle.ink.opacity(0.94), in: RoundedRectangle(cornerRadius: 12))
            }
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    ConsoleCaption(title: model.activeEnvironment.displayName, color: SlipframeStyle.ice)
                    if let modifier = stats.modifier {
                        Text(modifier == .aegis ? (stats.shieldCharges > 0 ? "Aegis · Shield ready" : "Aegis · Shield spent")
                                                : modifier.displayName)
                            .font(.system(size: 15, weight: .semibold))
                        if modifier != .aegis || stats.shieldCharges > 0 {
                            Text(modifier.hudSummary)
                                .font(.system(size: 13))
                                .foregroundStyle(SlipframeStyle.muted)
                                .lineLimit(2)
                        }
                    }
                }
                .frame(maxWidth: 185, alignment: .leading)
                Spacer(minLength: 0)
                ConsoleMetric(title: "Score", value: stats.score.formatted(), size: 28)
                ConsoleMetric(title: "Tokens", value: stats.coinsCollected.formatted(), color: SlipframeStyle.amber, size: 24)
                VStack(alignment: .leading, spacing: 7) {
                    ConsoleMetric(title: "Bonus", value: "+\(stats.flow)%", color: SlipframeStyle.ice, size: 24)
                    GeometryReader { geometry in
                        Capsule().fill(.white.opacity(0.10))
                        Capsule().fill(SlipframeStyle.ice)
                            .frame(width: geometry.size.width * CGFloat(min(100, max(0, stats.flow))) / 100)
                    }
                    .frame(width: 60, height: 3)
                    .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 17)
            .padding(.vertical, 12)
            .background(SlipframeStyle.ink.opacity(0.88), in: RoundedRectangle(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(SlipframeStyle.line) }
        }
        .frame(width: 520, height: 192, alignment: .bottom)
        .foregroundStyle(.white)
        .allowsHitTesting(false)
        .task(id: BiomeVisit(isPlaying: model.isPlaying, runID: model.runID, biome: model.activeEnvironment)) {
            hint = nil
            let biome = model.activeEnvironment
            guard model.isPlaying, biome == .vectorFoundry || biome == .orbitGate else { return }
            hint = biome
            do {
                try await Task.sleep(for: .seconds(6))
                hint = nil
            } catch {
                // The next biome or the end of the run replaces this hint.
            }
        }
    }

    private var junction: some View {
        VStack(spacing: 6) {
            Text("Move into a lane to choose your next rift")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SlipframeStyle.ice)
            HStack(spacing: 6) {
                ForEach(Array(model.portalOptions.enumerated()), id: \.offset) { index, option in
                    VStack(spacing: 4) {
                        ConsoleCaption(title: ["Left", "Center", "Right"][index])
                        Text(option.environment.displayName)
                            .font(.system(size: 15, weight: .semibold))
                        Text(option.risk.rawValue.capitalized)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(option.risk.interfaceTint)
                        Text(option.modifier?.displayName ?? "No modifier")
                            .font(.system(size: 12))
                            .foregroundStyle(SlipframeStyle.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(9)
        .background(SlipframeStyle.ink.opacity(0.94), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct RunResults: View {
    @ObservedObject var model: GameModel
    @ObservedObject var stats: RunStats
    let changeSetup: () -> Void

    private var grade: String {
        switch stats.highestFlow + stats.nearMisses * 4 + stats.portalsCrossed * 10 {
        case 150...: return "S"
        case 100...: return "A"
        case 65...: return "B"
        case 30...: return "C"
        default: return "D"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    ConsoleCaption(title: model.runMode.kind.title, color: SlipframeStyle.ice)
                    Text("Run complete")
                        .font(.system(size: 32, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer()
                Button("Run setup", action: changeSetup)
                    .buttonStyle(ConsoleButtonStyle())
            }
            HStack(spacing: 14) {
                resultCard(title: "Final score", value: stats.score.formatted(),
                           color: SlipframeStyle.ice, isBest: model.lastPersonalBestUpdate?.scoreImproved == true)
                resultCard(title: "Tokens", value: stats.coinsCollected.formatted(),
                           color: SlipframeStyle.amber, isBest: model.lastPersonalBestUpdate?.coinsImproved == true)
                resultCard(title: "Grade", value: grade, color: grade == "S" || grade == "A" ? SlipframeStyle.amber : .white)
            }
            HStack(spacing: 0) {
                detail("Peak bonus", "+\(stats.highestFlow)%")
                detail("Close slips", stats.nearMisses.formatted())
                detail("Rifts crossed", stats.portalsCrossed.formatted())
            }
            .padding(15)
            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 15))
        }
    }

    private func resultCard(title: String, value: String, color: Color, isBest: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ConsoleMetric(title: title, value: value, color: color, size: 43)
            if isBest {
                Label("Personal best", systemImage: "arrow.up.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
            }
        }
        .padding(17)
        .frame(maxWidth: .infinity, minHeight: 123, alignment: .topLeading)
        .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(color.opacity(0.26)) }
    }

    private func detail(_ title: String, _ value: String) -> some View {
        ConsoleMetric(title: title, value: value, size: 23)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
