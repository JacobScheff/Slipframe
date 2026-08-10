//
//  XenotechPanel.swift
//  Slipframe
//
//  Shared "alien instrumentation" panel chrome — tinted glass, a gradient
//  hairline border, and corner-bracket reticle accents applied uniformly to
//  every world-anchored SwiftUI surface (HUD, level select, leaderboard,
//  tutorial overlay) so the whole UI reads as one piece of synthetic tech
//  instead of a plain rounded card per view.
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
    /// Every world-anchored panel (HUD, level select, leaderboard, tutorial
    /// overlay) should use this instead of an ad-hoc background.
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
