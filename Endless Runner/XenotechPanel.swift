//
//  XenotechPanel.swift
//  Slipframe
//
//  Shared "alien instrumentation" panel chrome — tinted glass, a gradient
//  hairline border, and corner-bracket reticle accents applied uniformly to
//  every world-anchored SwiftUI surface (HUD, command console, tutorial overlay)
//  so the whole UI reads as one piece of synthetic tech instead of a plain
//  rounded card per view.
//

import SwiftUI

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

/// Shared panel chrome: tinted glass fill, gradient hairline border, and
/// corner-bracket accents in the caller's chosen palette.
private struct XenotechPanelModifier: ViewModifier {
    var primary: Color
    var secondary: Color
    var cornerRadius: CGFloat
    var fillOpacity: Double

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                shape.fill(
                    LinearGradient(
                        colors: [Color.black.opacity(fillOpacity + 0.14), primary.opacity(0.07)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [primary.opacity(0.8), secondary.opacity(0.45), primary.opacity(0.25)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
            }
            .overlay {
                XenotechCornerBrackets(length: max(14, cornerRadius * 0.9))
                    .stroke(primary.opacity(0.9), lineWidth: 1.6)
            }
            .clipShape(shape)
            .glassBackgroundEffect(in: shape)
    }
}

extension View {
    /// Applies the shared xenotech panel treatment — tinted glass, gradient
    /// hairline border, and reticle corner brackets — in the given palette.
    /// Every world-anchored panel (HUD, command console, tutorial overlay)
    /// should use this instead of an ad-hoc background.
    func xenotechPanel(
        primary: Color,
        secondary: Color? = nil,
        cornerRadius: CGFloat = 24,
        fillOpacity: Double = 0.04
    ) -> some View {
        modifier(XenotechPanelModifier(
            primary: primary,
            secondary: secondary ?? primary,
            cornerRadius: cornerRadius,
            fillOpacity: fillOpacity
        ))
    }
}

// MARK: - Shared HUD graphics

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

/// Colored biome tile: swatch + SF Symbol + name + twist caption.
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
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [biomeColor.opacity(isOn ? 0.85 : 0.45), biomeColor.opacity(0.12)],
                                center: .center,
                                startRadius: 2,
                                endRadius: 28
                            )
                        )
                        .frame(width: 52, height: 52)
                        .shadow(color: isOn ? biomeColor.opacity(0.55) : .clear, radius: 8)
                    Image(systemName: id.symbolName)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .symbolRenderingMode(.hierarchical)
                }

                Text(id.displayName)
                    .font(.system(size: 14, weight: isOn ? .bold : .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(id.twistCaption.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(isOn ? biomeColor : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isOn ? biomeColor.opacity(0.16) : Color.white.opacity(0.05))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isOn ? biomeColor.opacity(0.8) : Color.white.opacity(0.1), lineWidth: isOn ? 1.6 : 1)
            }
            .overlay(alignment: .topTrailing) {
                if isOn {
                    Image(systemName: selectionStyle == .radio ? "checkmark.circle.fill" : "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(accent)
                        .padding(8)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(id.displayName)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var biomeColor: Color {
        let tint = EnvironmentCatalog.profile(for: id).palette.portalRim
        return Color(red: Double(tint.r), green: Double(tint.g), blue: Double(tint.b))
    }
}
