import SwiftUI

enum SlipframeStyle {
    static let ice = Color(red: 0.53, green: 0.86, blue: 1)
    static let amber = Color(red: 1, green: 0.77, blue: 0.43)
    static let muted = Color(red: 0.66, green: 0.74, blue: 0.81)
    static let ink = Color(red: 0.035, green: 0.057, blue: 0.09)
    static let line = Color.white.opacity(0.12)
}

struct ConsoleButtonStyle: ButtonStyle {
    var selected = false
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .foregroundStyle(prominent ? SlipframeStyle.ink : selected ? SlipframeStyle.ice : .white)
            .background {
                RoundedRectangle(cornerRadius: 13)
                    .fill(prominent ? SlipframeStyle.ice : .white.opacity(selected ? 0.13 : 0.055))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 13)
                    .strokeBorder(selected ? SlipframeStyle.ice.opacity(0.58) : SlipframeStyle.line)
            }
            .contentShape(.interaction, RoundedRectangle(cornerRadius: 13))
            .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: 13))
            .hoverEffect(.highlight)
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.42)
    }
}

struct ConsoleCaption: View {
    let title: String
    var color = SlipframeStyle.muted

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

struct ConsoleMetric: View {
    let title: String
    let value: String
    var color: Color = .white
    var size: CGFloat = 26

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ConsoleCaption(title: title)
            Text(value)
                .font(.system(size: size, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .combine)
    }
}

extension EnvironmentID {
    var interfaceSymbol: String {
        switch self {
        case .emberRun: return "flame"
        case .summitStep: return "mountain.2"
        case .ghostGlass: return "square.on.square"
        case .lowCrawl: return "arrow.down.to.line"
        case .stormPass: return "wind"
        case .crystalCave: return "diamond"
        case .vectorFoundry: return "move.3d"
        case .orbitGate: return "circle.circle"
        }
    }

    var interfaceTint: Color {
        let tint = EnvironmentCatalog.profile(for: self).palette.portalRim
        return Color(red: Double(tint.r), green: Double(tint.g), blue: Double(tint.b))
    }

    var mechanic: String {
        switch self {
        case .emberRun: return "Step or lean into open lanes. Reach out to collect tokens."
        case .summitStep: return "Rise over low hurdles and slip sideways past walls."
        case .ghostGlass: return "Watch for translucent walls that fade into view as they approach."
        case .lowCrawl: return "Lower your head beneath hanging barriers."
        case .stormPass: return "Watch for wind gusts that push obstacles across lanes."
        case .crystalCave: return "Grab two different crystal halves and bring your hands together."
        case .vectorFoundry: return "Aim a hand to lock onto a shape, then move your hand to guide it into its matching slot."
        case .orbitGate: return "Pass through hoops and time your movement through the rotating openings."
        }
    }
}

extension RiftModifier {
    var effect: String {
        switch self {
        case .tokenSurge: return "More token chains. Each token counts twice."
        case .aegis: return "A shield absorbs one collision. The hit halves your current bonus."
        case .overdrive: return "Earn 25% more distance points and build your bonus faster."
        case .magnet: return "Reach tokens and crystal halves from farther away."
        case .closeCall: return "Close slips count from farther away and give double rewards."
        case .bonusBank: return "Your score bonus drains half as fast."
        }
    }
}

struct BiomePreviewCard: View {
    let biome: EnvironmentID
    let label: String

    var body: some View {
        let tint = biome.interfaceTint
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                ConsoleCaption(title: label, color: SlipframeStyle.ice)
                Text(biome.displayName)
                    .font(.system(size: 32, weight: .semibold))
                Text(biome.mechanic)
                    .font(.system(size: 15))
                    .foregroundStyle(SlipframeStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)

            RiftArtwork(tint: tint)
                .frame(width: 155, height: 128)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 128)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(.linearGradient(colors: [SlipframeStyle.ink, tint.opacity(0.21)],
                                      startPoint: .leading, endPoint: .trailing))
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18).strokeBorder(tint.opacity(0.32))
        }
    }
}

/// Line art echoes the portal rim and receding lanes in the live 3D preview.
private struct RiftArtwork: View {
    let tint: Color

    var body: some View {
        Canvas { context, size in
            let x = size.width * 0.51
            let y = size.height * 0.45
            for offset in -3...3 {
                var lane = Path()
                lane.move(to: CGPoint(x: x + CGFloat(offset) * 9, y: y + 15))
                lane.addLine(to: CGPoint(x: x + CGFloat(offset) * 41, y: size.height))
                context.stroke(lane, with: .color(tint.opacity(0.24)), lineWidth: 1)
            }
            for row in 0..<5 {
                let lineY = y + 20 + CGFloat(row * row) * 3.2
                var line = Path()
                line.move(to: CGPoint(x: 0, y: lineY))
                line.addLine(to: CGPoint(x: size.width, y: lineY))
                context.stroke(line, with: .color(tint.opacity(0.14)), lineWidth: 1)
            }
            for ring in 0..<5 {
                let inset = CGFloat(ring) * 8
                let bounds = CGRect(x: x - 57 + inset, y: y - 45 + inset,
                                    width: 114 - inset * 2, height: 90 - inset * 2)
                let shape = Path(roundedRect: bounds, cornerRadius: 24 - CGFloat(ring) * 2)
                context.stroke(shape, with: .color(tint.opacity(0.78 - Double(ring) * 0.13)),
                               lineWidth: ring == 0 ? 2 : 1)
            }
            let core = CGRect(x: x - 12, y: y - 12, width: 24, height: 24)
            context.fill(Path(ellipseIn: core), with: .radialGradient(
                Gradient(colors: [tint.opacity(0.45), .clear]),
                center: CGPoint(x: x, y: y), startRadius: 0, endRadius: 12
            ))
        }
    }
}
