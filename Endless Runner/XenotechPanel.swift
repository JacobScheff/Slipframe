//
//  XenotechPanel.swift
//  Slipframe
//
//  Shared spatial instrumentation: charcoal glass, restrained rift marks,
//  and a consistent palette for controls, readouts, and coaching.
//

import SwiftUI

/// A small material palette: cyan identifies interaction, amber identifies rewards.
enum SlipframeUI {
    static let accent = Color(red: 0.48, green: 0.86, blue: 0.90)
    static let reward = Color(red: 0.95, green: 0.77, blue: 0.46)
    static let surface = Color(red: 0.045, green: 0.065, blue: 0.08)
    static let inset = Color.white.opacity(0.045)
    static let hairline = Color.white.opacity(0.12)
}

/// Shared gaze target and pressed state for custom selection controls.
struct ConsoleSelectionStyle: ButtonStyle {
    var selected: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(selected ? Color.white : Color.white.opacity(0.72))
            .frame(minHeight: 48)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.16 : (selected ? 0.10 : 0.025)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? SlipframeUI.accent.opacity(0.65) : .clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .hoverEffect(.highlight)
    }
}

/// Four L-shaped accent marks drawn just inside a panel's bounds — the
/// "targeting reticle" motif that ties every panel back to the game's
/// xenotech identity.
struct XenotechCornerBrackets: Shape {
    var length: CGFloat = 22
    var inset: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let l = max(6, min(length, min(rect.width, rect.height) * 0.3))
        let corners: [(CGPoint, CGPoint, CGPoint)] = [
            (
                CGPoint(x: rect.minX + inset, y: rect.minY + inset + l),
                CGPoint(x: rect.minX + inset, y: rect.minY + inset),
                CGPoint(x: rect.minX + inset + l, y: rect.minY + inset)
            ),
            (
                CGPoint(x: rect.maxX - inset - l, y: rect.minY + inset),
                CGPoint(x: rect.maxX - inset, y: rect.minY + inset),
                CGPoint(x: rect.maxX - inset, y: rect.minY + inset + l)
            ),
            (
                CGPoint(x: rect.maxX - inset, y: rect.maxY - inset - l),
                CGPoint(x: rect.maxX - inset, y: rect.maxY - inset),
                CGPoint(x: rect.maxX - inset - l, y: rect.maxY - inset)
            ),
            (
                CGPoint(x: rect.minX + inset + l, y: rect.maxY - inset),
                CGPoint(x: rect.minX + inset, y: rect.maxY - inset),
                CGPoint(x: rect.minX + inset, y: rect.maxY - inset - l)
            )
        ]
        for (a, b, c) in corners {
            p.move(to: a)
            p.addLine(to: b)
            p.addLine(to: c)
        }
        return p
    }
}

/// Dark glass keeps text legible against every biome and the player's room.
private struct XenotechPanelModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var primary: Color
    var cornerRadius: CGFloat
    var fillOpacity: Double

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                shape.fill(
                    LinearGradient(
                        colors: [
                            SlipframeUI.surface.opacity(reduceTransparency ? 1 : min(0.96, 0.82 + fillOpacity)),
                            SlipframeUI.surface.opacity(reduceTransparency ? 1 : min(0.96, 0.72 + fillOpacity))
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.24), Color.white.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
            }
            .overlay {
                XenotechCornerBrackets(length: 10, inset: 9)
                    .stroke(primary.opacity(0.38), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .top) {
                Capsule()
                    .fill(primary.opacity(0.65))
                    .frame(width: 44, height: 2)
                    .padding(.top, 1)
                    .allowsHitTesting(false)
            }
            .clipShape(shape)
            .glassBackgroundEffect(in: shape)
            .environment(\.colorScheme, .dark)
    }
}

extension View {
    /// Applies the shared dark glass, neutral hairline, and subtle rift accents.
    /// Every world-anchored panel (HUD, command console, tutorial overlay)
    /// should use this instead of an ad-hoc background.
    func xenotechPanel(
        primary: Color,
        cornerRadius: CGFloat = 24,
        fillOpacity: Double = 0.04
    ) -> some View {
        modifier(XenotechPanelModifier(
            primary: primary,
            cornerRadius: cornerRadius,
            fillOpacity: fillOpacity
        ))
    }
}

// MARK: - Shared HUD graphics

/// Modifier icon that avoids optional SF Symbols for gameplay-critical marks.
/// `magnet.fill` is absent on some visionOS symbol sets, so Magnet is drawn here.
struct RiftModifierIcon: View {
    var modifier: RiftModifier
    var accent: Color
    var size: CGFloat = 18

    @ViewBuilder
    var body: some View {
        if modifier == .magnet {
            MagnetGlyphShape()
                .stroke(
                    accent,
                    style: StrokeStyle(
                        lineWidth: max(2, size * 0.17),
                        lineCap: .square,
                        lineJoin: .round
                    )
                )
                .frame(width: size, height: size)
                .shadow(color: accent.opacity(0.45), radius: 3)
                .accessibilityHidden(true)
        } else {
            Image(systemName: modifier.symbolName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(accent)
                .accessibilityHidden(true)
        }
    }
}

/// Open-top horseshoe magnet with outward-facing pole caps.
private struct MagnetGlyphShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let left = rect.minX + rect.width * 0.22
        let right = rect.maxX - rect.width * 0.22
        let top = rect.minY + rect.height * 0.12
        let bend = rect.minY + rect.height * 0.62

        path.move(to: CGPoint(x: left, y: top))
        path.addLine(to: CGPoint(x: left, y: bend))
        path.addCurve(
            to: CGPoint(x: right, y: bend),
            control1: CGPoint(x: left, y: rect.minY + rect.height * 0.94),
            control2: CGPoint(x: right, y: rect.minY + rect.height * 0.94)
        )
        path.addLine(to: CGPoint(x: right, y: top))

        let cap = rect.width * 0.17
        path.move(to: CGPoint(x: left - cap, y: top))
        path.addLine(to: CGPoint(x: left + cap, y: top))
        path.move(to: CGPoint(x: right - cap, y: top))
        path.addLine(to: CGPoint(x: right + cap, y: top))
        return path
    }
}

/// Three vertical neon lanes — used as a track glyph in settings / off-track coaching.
struct LaneGlyph: View {
    var accent: Color
    var lit: Bool = true

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: lit
                                ? [accent.opacity(index == 1 ? 1 : 0.7), accent.opacity(0.25)]
                                : [Color.white.opacity(0.18), Color.white.opacity(0.06)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 7, height: 34)
                    .shadow(color: lit ? accent.opacity(0.55) : .clear, radius: lit ? 6 : 0)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.28))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(accent.opacity(lit ? 0.45 : 0.18), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

/// Jagged diamond “rift” mark used as a console identity glyph.
struct RiftGlyph: View {
    var accent: Color
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            Diamond()
                .fill(accent.opacity(0.18))
                .frame(width: size, height: size)
            Diamond()
                .stroke(accent.opacity(0.95), lineWidth: 1.6)
                .frame(width: size, height: size)
            Diamond()
                .fill(accent)
                .frame(width: size * 0.28, height: size * 0.28)
                .shadow(color: accent.opacity(0.8), radius: 6)
        }
        .accessibilityHidden(true)
    }
}

private struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        p.closeSubpath()
        return p
    }
}

/// Blender-rendered destination preview with native labels and selection controls.
struct BiomeCard: View {
    var id: EnvironmentID
    var isOn: Bool
    var selectionStyle: SelectionStyle = .check
    var accent: Color
    var action: () -> Void

    enum SelectionStyle {
        case check
        case radio
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Image("Biome_\(id.rawValue)")
                    .resizable()
                    .scaledToFill()
                    .frame(height: 96)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .saturation(isOn ? 1 : 0.8)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(id.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(id.twistCaption)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isOn ? accent.opacity(0.10) : SlipframeUI.inset)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isOn ? accent.opacity(0.8) : SlipframeUI.hairline, lineWidth: 1)
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: isOn ? "checkmark.circle.fill" : (selectionStyle == .radio ? "circle" : "plus.circle"))
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isOn ? accent : Color.white)
                    .padding(5)
                    .background(SlipframeUI.surface.opacity(0.92), in: Circle())
                    .padding(8)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel("\(id.displayName), \(id.twistCaption)")
        .accessibilityValue(isOn ? "Selected" : "Not selected")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

}
