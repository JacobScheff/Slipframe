import SwiftUI

enum SlipframeStyle {
    static let ice = Color(red: 0.68, green: 0.87, blue: 0.88)
    static let amber = Color(red: 0.98, green: 0.76, blue: 0.46)
    static let muted = Color(red: 0.66, green: 0.73, blue: 0.76)
    static let ink = Color(red: 0.035, green: 0.053, blue: 0.065)
    static let panel = Color(red: 0.080, green: 0.115, blue: 0.135)
    static let line = Color.white.opacity(0.10)
}

/// A split doorway, used consistently instead of an unrelated SF Symbol logo.
struct SlipframeMark: View {
    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width, h = geometry.size.height
            Path { path in
                path.move(to: CGPoint(x: w * 0.38, y: h * 0.93))
                path.addLine(to: CGPoint(x: w * 0.10, y: h * 0.93))
                path.addLine(to: CGPoint(x: w * 0.10, y: h * 0.10))
                path.addLine(to: CGPoint(x: w * 0.64, y: h * 0.10))
                path.addLine(to: CGPoint(x: w * 0.64, y: h * 0.55))
            }
            .stroke(SlipframeStyle.ice, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            Path { path in
                path.move(to: CGPoint(x: w * 0.40, y: h * 0.45))
                path.addLine(to: CGPoint(x: w * 0.40, y: h * 0.86))
                path.addLine(to: CGPoint(x: w * 0.90, y: h * 0.86))
                path.addLine(to: CGPoint(x: w * 0.90, y: h * 0.23))
            }
            .stroke(SlipframeStyle.amber, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

struct ConsoleButtonStyle: ButtonStyle {
    var selected = false
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .foregroundStyle(prominent ? SlipframeStyle.ink : selected ? SlipframeStyle.ice : .white)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(prominent ? SlipframeStyle.ice : selected ? SlipframeStyle.ice.opacity(0.10) : Color.white.opacity(0.035))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(selected ? SlipframeStyle.ice.opacity(0.42) : prominent ? .clear : SlipframeStyle.line)
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
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.7)
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
                .font(.system(size: size, weight: .medium, design: .rounded))
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
        case .orbitGate: return "circle.dashed"
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
    var hudSummary: String {
        switch self {
        case .tokenSurge: return "Tokens count twice"
        case .aegis: return "Absorbs one hit"
        case .overdrive: return "25% more distance points"
        case .magnet: return "Wider pickup reach"
        case .closeCall: return "Double close-slip rewards"
        case .bonusBank: return "Half-speed bonus drain"
        }
    }

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
    var compact = false

    var body: some View {
        let tint = biome.interfaceTint
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                ConsoleCaption(title: label, color: tint)
                Text(biome.displayName)
                    .font(.system(size: compact ? 28 : 34, weight: .medium))
                Text(biome.mechanic)
                    .font(.system(size: 16))
                    .foregroundStyle(SlipframeStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(compact ? 20 : 24)

            BiomeArtwork(biome: biome)
                .frame(width: compact ? 140 : 188, height: compact ? 144 : 184)
                .accessibilityHidden(true)
        }
        .frame(minHeight: compact ? 144 : 184)
        .background {
            RoundedRectangle(cornerRadius: 21)
                .fill(.linearGradient(colors: [SlipframeStyle.ink, tint.opacity(0.10)],
                                      startPoint: .leading, endPoint: .trailing))
        }
        .clipShape(RoundedRectangle(cornerRadius: 21))
        .overlay {
            RoundedRectangle(cornerRadius: 21).strokeBorder(tint.opacity(0.20))
        }
    }
}

/// A distinct, quiet landscape for each destination, framed by a single doorway.
/// These code-native illustrations stay crisp at attachment resolution.
struct BiomeArtwork: View {
    let biome: EnvironmentID

    var body: some View {
        Canvas { context, size in
            let tint = biome.interfaceTint
            let w = size.width, h = size.height
            let bounds = CGRect(x: w * 0.15, y: h * 0.10, width: w * 0.68, height: h * 0.77)
            let frame = Path(roundedRect: bounds, cornerRadius: w * 0.27)
            context.stroke(frame, with: .color(tint.opacity(0.55)), lineWidth: 1.5)
            var scene = context
            scene.clip(to: frame)
            scene.fill(frame, with: .linearGradient(Gradient(colors: [tint.opacity(0.13), .clear]),
                                                    startPoint: CGPoint(x: w / 2, y: 0), endPoint: CGPoint(x: w / 2, y: h)))
            if biome == .orbitGate {
                for i in 0..<3 {
                    let inset = CGFloat(i) * 13
                    scene.stroke(Path(ellipseIn: CGRect(x: w * 0.25 + inset, y: h * 0.26 + inset,
                                                        width: w * 0.48 - inset * 2, height: h * 0.45 - inset * 2)),
                                 with: .color(tint.opacity(0.75 - Double(i) * 0.18)), lineWidth: 2)
                }
            } else if biome == .crystalCave {
                for i in 0..<5 {
                    let x = w * (0.24 + CGFloat(i) * 0.12)
                    let y = h * (i.isMultiple(of: 2) ? 0.55 : 0.66)
                    let height = h * (i.isMultiple(of: 2) ? 0.30 : 0.18)
                    var crystal = Path()
                    crystal.move(to: CGPoint(x: x, y: y - height))
                    crystal.addLines([CGPoint(x: x + 12, y: y - height * 0.35), CGPoint(x: x, y: y + 8),
                                      CGPoint(x: x - 12, y: y - height * 0.35)])
                    crystal.closeSubpath()
                    scene.fill(crystal, with: .color(tint.opacity(0.16)))
                    scene.stroke(crystal, with: .color(tint.opacity(0.7)), lineWidth: 1)
                }
            } else if biome == .vectorFoundry {
                for i in 0..<3 {
                    let rect = CGRect(x: w * 0.25 + CGFloat(i) * 29, y: h * 0.35 + CGFloat(i % 2) * 25, width: 22, height: 28)
                    scene.stroke(Path(roundedRect: rect, cornerRadius: 3), with: .color(tint.opacity(0.8)), lineWidth: 1.5)
                }
            } else {
                for layer in 0..<3 {
                    var ridge = Path()
                    let y = h * (0.48 + CGFloat(layer) * 0.13)
                    ridge.move(to: CGPoint(x: 0, y: h))
                    ridge.addLine(to: CGPoint(x: 0, y: y + 26))
                    for i in 0..<7 {
                        let x = CGFloat(i) * w / 6
                        let peak = CGFloat((i * 7 + layer * 3) % 5) * (biome == .summitStep ? 13 : 6)
                        ridge.addLine(to: CGPoint(x: x, y: y - peak))
                    }
                    ridge.addLine(to: CGPoint(x: w, y: h)); ridge.closeSubpath()
                    scene.fill(ridge, with: .color(tint.opacity(0.12 + Double(layer) * 0.07)))
                    scene.stroke(ridge, with: .color(tint.opacity(0.3)), lineWidth: 0.7)
                }
                if biome == .stormPass {
                    for i in 0..<5 {
                        let y = h * 0.24 + CGFloat(i) * 12
                        var wind = Path()
                        wind.move(to: CGPoint(x: w * 0.30, y: y))
                        wind.addQuadCurve(to: CGPoint(x: w * 0.75, y: y - 12), control: CGPoint(x: w * 0.58, y: y + 4))
                        scene.stroke(wind, with: .color(tint.opacity(0.6)), lineWidth: 1)
                    }
                }
                if biome == .lowCrawl || biome == .ghostGlass {
                    let rect = CGRect(x: w * 0.30, y: h * 0.26, width: w * 0.40, height: h * 0.32)
                    scene.stroke(Path(roundedRect: rect, cornerRadius: 2), with: .color(tint.opacity(0.7)), lineWidth: 1.5)
                }
            }
            for lane in -1...1 {
                var line = Path()
                line.move(to: CGPoint(x: w * 0.49 + CGFloat(lane) * 9, y: h * 0.78))
                line.addLine(to: CGPoint(x: w * 0.49 + CGFloat(lane) * 36, y: h))
                context.stroke(line, with: .color(tint.opacity(0.22)), lineWidth: 1)
            }
        }
    }
}
