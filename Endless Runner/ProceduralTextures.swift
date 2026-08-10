//
//  ProceduralTextures.swift
//  Slipframe
//
//  Runtime-generated CoreGraphics textures for the "Xenotech Rift" art
//  direction. No shipped raster assets — every pixel is drawn on first launch
//  so the surface detail (etched circuit plating, embossed rune coin,
//  corona bloom, energy conduits) always matches the current palette code
//  and never drifts out of sync with an authored PNG. Deterministic seeds
//  keep the output stable run to run.
//

import CoreGraphics
import RealityKit
import UIKit

enum ProceduralTextures {

    // MARK: - Bitmap plumbing

    private static func renderTexture(
        width: Int,
        height: Int,
        opaque: Bool,
        draw: (CGContext) -> Void
    ) -> TextureResource? {
        guard width > 0, height > 0 else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        ctx.interpolationQuality = .high
        if opaque {
            ctx.setFillColor(UIColor.black.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        } else {
            ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
        }
        draw(ctx)

        guard let image = ctx.makeImage() else { return nil }
        return try? TextureResource(image: image, options: .init(semantic: .color))
    }

    private static func rng(_ seed: UInt64) -> SeededGenerator {
        SeededGenerator(seed: seed)
    }

    private static func radialGradient(_ stops: [(UIColor, CGFloat)]) -> CGGradient? {
        let colors = stops.map { $0.0.cgColor } as CFArray
        let locations: [CGFloat] = stops.map { $0.1 }
        return CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations)
    }

    // MARK: - Track floor (etched xenotech hull plating)

    static func trackFloor(size: Int = 1024) -> TextureResource? {
        renderTexture(width: size, height: size, opaque: true) { ctx in
            let w = CGFloat(size), h = CGFloat(size)
            var seed = rng(0xF10_0A_7EED)

            // Base ink slab with a faint center-to-edge vignette so the floor
            // doesn't read as a flat, uniform decal.
            if let grad = radialGradient([
                (UIColor(red: 0.09, green: 0.10, blue: 0.15, alpha: 1), 0),
                (UIColor(red: 0.045, green: 0.05, blue: 0.08, alpha: 1), 1)
            ]) {
                ctx.drawRadialGradient(
                    grad,
                    startCenter: CGPoint(x: w * 0.5, y: h * 0.5), startRadius: 0,
                    endCenter: CGPoint(x: w * 0.5, y: h * 0.5), endRadius: w * 0.75,
                    options: [.drawsAfterEndLocation]
                )
            }

            // Irregular hull plates: a jittered grid of quadrilateral panels
            // with dark seams and a subtle per-panel brightness variance —
            // reads as machined alien armor, not a checkerboard.
            let cols = 7, rows = 7
            let cellW = w / CGFloat(cols)
            let cellH = h / CGFloat(rows)
            let jitter: CGFloat = 0.22

            func node(_ cx: Int, _ cy: Int) -> CGPoint {
                var localSeed = UInt64(bitPattern: Int64(cx &* 92821 &+ cy &* 68917))
                localSeed ^= 0xA5A5_1234_ABCD_EF01
                var g = rng(localSeed)
                let jx = CGFloat.random(in: -jitter...jitter, using: &g)
                let jy = CGFloat.random(in: -jitter...jitter, using: &g)
                return CGPoint(x: (CGFloat(cx) + 0.5 + jx) * cellW, y: (CGFloat(cy) + 0.5 + jy) * cellH)
            }

            for cy in 0..<rows {
                for cx in 0..<cols {
                    let p00 = node(cx, cy)
                    let p10 = node(cx + 1, cy)
                    let p11 = node(cx + 1, cy + 1)
                    let p01 = node(cx, cy + 1)

                    let path = CGMutablePath()
                    path.move(to: p00)
                    path.addLine(to: p10)
                    path.addLine(to: p11)
                    path.addLine(to: p01)
                    path.closeSubpath()

                    let shade = CGFloat.random(in: 0.85...1.18, using: &seed)
                    let base = UIColor(red: 0.1 * shade, green: 0.115 * shade, blue: 0.16 * shade, alpha: 1)
                    ctx.setFillColor(base.cgColor)
                    ctx.addPath(path)
                    ctx.fillPath()

                    // Panel seam — thin, glowing cyan/violet alternating per row.
                    let seamTint = (cx + cy) % 2 == 0
                        ? UIColor(red: 0.22, green: 0.55, blue: 0.62, alpha: 0.55)
                        : UIColor(red: 0.34, green: 0.24, blue: 0.55, alpha: 0.45)
                    ctx.setStrokeColor(seamTint.cgColor)
                    ctx.setLineWidth(CGFloat.random(in: 1.4...2.6, using: &seed))
                    ctx.addPath(path)
                    ctx.strokePath()

                    // Corner rivet glints.
                    if Float.random(in: 0...1, using: &seed) < 0.6 {
                        let glint = UIColor(red: 0.55, green: 0.85, blue: 0.95, alpha: 0.5)
                        ctx.setFillColor(glint.cgColor)
                        let r = CGFloat.random(in: 1.6...3.2, using: &seed)
                        ctx.fillEllipse(in: CGRect(x: p00.x - r, y: p00.y - r, width: r * 2, height: r * 2))
                    }
                }
            }

            // Fine grain speckle for surface roughness at close range.
            for _ in 0..<2200 {
                let x = CGFloat.random(in: 0...w, using: &seed)
                let y = CGFloat.random(in: 0...h, using: &seed)
                let a = CGFloat.random(in: 0.02...0.07, using: &seed)
                ctx.setFillColor(UIColor(white: CGFloat.random(in: 0...1, using: &seed), alpha: a).cgColor)
                ctx.fill(CGRect(x: x, y: y, width: 1.2, height: 1.2))
            }
        }
    }

    // MARK: - Coin face (embossed alien rune disc)

    static func coinFace(size: Int = 512) -> TextureResource? {
        renderTexture(width: size, height: size, opaque: false) { ctx in
            let w = CGFloat(size), h = CGFloat(size)
            let center = CGPoint(x: w * 0.5, y: h * 0.5)
            let maxR = min(w, h) * 0.5
            var seed = rng(0xC01_0FACE)

            // Base disc — bright center falling to a darker rim so the face
            // reads as a bevel even before the biome tint/emissive multiply.
            if let grad = radialGradient([
                (UIColor(white: 1.0, alpha: 1), 0),
                (UIColor(white: 0.72, alpha: 1), 0.7),
                (UIColor(white: 0.5, alpha: 1), 1)
            ]) {
                ctx.drawRadialGradient(
                    grad, startCenter: center, startRadius: 0, endCenter: center, endRadius: maxR,
                    options: []
                )
            }

            // Concentric embossed grooves.
            let ringCount = 6
            for i in 0..<ringCount {
                let t = CGFloat(i + 1) / CGFloat(ringCount + 1)
                let r = maxR * t
                let bright = i.isMultiple(of: 2)
                ctx.setStrokeColor(UIColor(white: bright ? 0.95 : 0.4, alpha: 0.6).cgColor)
                ctx.setLineWidth(max(1.5, maxR * 0.012))
                ctx.strokeEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            }

            // Rim tick marks — dial-like detailing near the coin edge.
            let tickCount = 24
            for i in 0..<tickCount {
                let theta = CGFloat(i) / CGFloat(tickCount) * (2 * .pi)
                let inner = maxR * 0.88
                let outer = maxR * 0.97
                let p0 = CGPoint(x: center.x + cos(theta) * inner, y: center.y + sin(theta) * inner)
                let p1 = CGPoint(x: center.x + cos(theta) * outer, y: center.y + sin(theta) * outer)
                ctx.setStrokeColor(UIColor(white: 0.9, alpha: 0.5).cgColor)
                ctx.setLineWidth(max(1, maxR * 0.01))
                ctx.move(to: p0)
                ctx.addLine(to: p1)
                ctx.strokePath()
            }

            // Central alien rune — an angular hexagonal sigil with radiating
            // spokes, bright enough to double as the emissive glow map.
            let sides = 6
            let sigilR = maxR * 0.42
            let path = CGMutablePath()
            for i in 0...sides {
                let theta = CGFloat(i) / CGFloat(sides) * (2 * .pi) - .pi / 2
                let p = CGPoint(x: center.x + cos(theta) * sigilR, y: center.y + sin(theta) * sigilR)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
            ctx.setStrokeColor(UIColor.white.cgColor)
            ctx.setLineWidth(max(2, maxR * 0.045))
            ctx.addPath(path)
            ctx.strokePath()

            // Inner hexagon (smaller, offset rotation) for a layered-glyph look.
            let path2 = CGMutablePath()
            for i in 0...sides {
                let theta = CGFloat(i) / CGFloat(sides) * (2 * .pi) + .pi / 6
                let p = CGPoint(x: center.x + cos(theta) * sigilR * 0.55, y: center.y + sin(theta) * sigilR * 0.55)
                if i == 0 { path2.move(to: p) } else { path2.addLine(to: p) }
            }
            path2.closeSubpath()
            ctx.setStrokeColor(UIColor(white: 1, alpha: 0.85).cgColor)
            ctx.setLineWidth(max(1.5, maxR * 0.03))
            ctx.addPath(path2)
            ctx.strokePath()

            // Spokes connecting the two hexagons — like etched circuit traces.
            for i in 0..<sides {
                let theta = CGFloat(i) / CGFloat(sides) * (2 * .pi) - .pi / 2
                let p0 = CGPoint(x: center.x + cos(theta) * sigilR * 0.6, y: center.y + sin(theta) * sigilR * 0.6)
                let p1 = CGPoint(x: center.x + cos(theta) * sigilR * 0.92, y: center.y + sin(theta) * sigilR * 0.92)
                ctx.setStrokeColor(UIColor(white: 1, alpha: 0.7).cgColor)
                ctx.setLineWidth(max(1, maxR * 0.018))
                ctx.move(to: p0)
                ctx.addLine(to: p1)
                ctx.strokePath()
            }

            // Tiny center core dot — brightest point, doubles as the emissive hotspot.
            let coreR = maxR * 0.07
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.fillEllipse(in: CGRect(x: center.x - coreR, y: center.y - coreR, width: coreR * 2, height: coreR * 2))

            // Fine brushed-metal noise.
            for _ in 0..<900 {
                let a = CGFloat.random(in: 0...(2 * CGFloat.pi), using: &seed)
                let r = CGFloat.random(in: 0...maxR, using: &seed)
                let x = center.x + cos(a) * r
                let y = center.y + sin(a) * r
                ctx.setFillColor(UIColor(white: CGFloat.random(in: 0.4...1, using: &seed), alpha: 0.05).cgColor)
                ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
    }

    // MARK: - Portal glow (alien corona bloom sprite)

    static func portalGlow(size: Int = 1024) -> TextureResource? {
        renderTexture(width: size, height: size, opaque: false) { ctx in
            let w = CGFloat(size), h = CGFloat(size)
            let center = CGPoint(x: w * 0.5, y: h * 0.5)
            let maxR = min(w, h) * 0.5
            var seed = rng(0x6110_6104_6501)

            // Soft two-tone corona — hot cyan core dissolving into violet haze.
            if let grad = radialGradient([
                (UIColor(red: 0.85, green: 1.0, blue: 1.0, alpha: 0.95), 0),
                (UIColor(red: 0.45, green: 0.85, blue: 1.0, alpha: 0.55), 0.35),
                (UIColor(red: 0.55, green: 0.35, blue: 0.95, alpha: 0.22), 0.68),
                (UIColor(red: 0.55, green: 0.35, blue: 0.95, alpha: 0), 1)
            ]) {
                ctx.drawRadialGradient(
                    grad, startCenter: center, startRadius: 0, endCenter: center, endRadius: maxR,
                    options: []
                )
            }

            // Faint jagged corona ring — the tear's energy edge leaking outward.
            let noiseHarmonics: [(CGFloat, CGFloat, CGFloat)] = (0..<4).map { i in
                (
                    CGFloat(2 + i * 2),
                    CGFloat.random(in: 0...(2 * CGFloat.pi), using: &seed),
                    CGFloat.random(in: 0.3...1, using: &seed) / CGFloat(i + 1)
                )
            }
            func noise(_ theta: CGFloat) -> CGFloat {
                var total: CGFloat = 0
                for (freq, phase, amp) in noiseHarmonics { total += sin(theta * freq + phase) * amp }
                return total / 2.2
            }

            let ringPath = CGMutablePath()
            let sides = 48
            for i in 0...sides {
                let theta = CGFloat(i) / CGFloat(sides) * (2 * .pi)
                let r = maxR * (0.62 + noise(theta) * 0.1)
                let p = CGPoint(x: center.x + cos(theta) * r, y: center.y + sin(theta) * r)
                if i == 0 { ringPath.move(to: p) } else { ringPath.addLine(to: p) }
            }
            ringPath.closeSubpath()
            ctx.setStrokeColor(UIColor(red: 0.85, green: 0.95, blue: 1.0, alpha: 0.5).cgColor)
            ctx.setLineWidth(maxR * 0.02)
            ctx.addPath(ringPath)
            ctx.strokePath()

            // Streaks radiating outward — energy leaking from the wound.
            for _ in 0..<14 {
                let theta = CGFloat.random(in: 0...(2 * CGFloat.pi), using: &seed)
                let innerR = maxR * CGFloat.random(in: 0.15...0.3, using: &seed)
                let outerR = maxR * CGFloat.random(in: 0.55...0.95, using: &seed)
                let p0 = CGPoint(x: center.x + cos(theta) * innerR, y: center.y + sin(theta) * innerR)
                let p1 = CGPoint(x: center.x + cos(theta) * outerR, y: center.y + sin(theta) * outerR)
                let hot = Bool.random(using: &seed)
                let tint = hot
                    ? UIColor(red: 0.8, green: 0.98, blue: 1.0, alpha: 0.35)
                    : UIColor(red: 0.7, green: 0.5, blue: 1.0, alpha: 0.28)
                ctx.setStrokeColor(tint.cgColor)
                ctx.setLineWidth(CGFloat.random(in: 1...3, using: &seed))
                ctx.move(to: p0)
                ctx.addLine(to: p1)
                ctx.strokePath()
            }
        }
    }

    // MARK: - Lane stripe (energized conduit)

    static func laneStripe(width: Int = 64, height: Int = 512) -> TextureResource? {
        renderTexture(width: width, height: height, opaque: false) { ctx in
            let w = CGFloat(width), h = CGFloat(height)
            var seed = rng(0x1A_9E5_7211_9E00)

            // Bright vertical core, brightest in the middle, softening to the edges
            // (mapped across the stripe's short axis).
            if let grad = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor(white: 1, alpha: 0).cgColor,
                    UIColor(white: 1, alpha: 1).cgColor,
                    UIColor(white: 1, alpha: 0).cgColor
                ] as CFArray,
                locations: [0, 0.5, 1]
            ) {
                ctx.drawLinearGradient(
                    grad, start: CGPoint(x: 0, y: h * 0.5), end: CGPoint(x: w, y: h * 0.5), options: []
                )
            }

            // Segmented "circuit tick" bands running the length of the conduit.
            let segments = 14
            for i in 0..<segments {
                let t0 = CGFloat(i) / CGFloat(segments)
                let t1 = t0 + (1 / CGFloat(segments)) * CGFloat.random(in: 0.35...0.55, using: &seed)
                let brighten = Float.random(in: 0...1, using: &seed) < 0.4
                let alpha: CGFloat = brighten ? 1.0 : 0.55
                ctx.setFillColor(UIColor(white: 1, alpha: alpha).cgColor)
                ctx.fill(CGRect(x: 0, y: t0 * h, width: w, height: (t1 - t0) * h))
            }
        }
    }

    // MARK: - Start pad (stand-zone glow glyph)

    static func startPad(width: Int = 1024, height: Int = 256) -> TextureResource? {
        renderTexture(width: width, height: height, opaque: false) { ctx in
            let w = CGFloat(width), h = CGFloat(height)
            let center = CGPoint(x: w * 0.5, y: h * 0.5)
            var seed = rng(0x574A_4E44_5041_44)

            // Warm amber glow field, brightest along the stand line, easing out
            // toward the long edges — keeps the original "stand here" warmth
            // amid the cooler alien palette everywhere else.
            if let grad = radialGradient([
                (UIColor(red: 1.0, green: 0.9, blue: 0.65, alpha: 0.55), 0),
                (UIColor(red: 0.95, green: 0.75, blue: 0.4, alpha: 0.28), 0.55),
                (UIColor(red: 0.8, green: 0.6, blue: 0.35, alpha: 0), 1)
            ]) {
                ctx.drawRadialGradient(
                    grad, startCenter: center, startRadius: 0, endCenter: center, endRadius: w * 0.55,
                    options: []
                )
            }

            // Faint etched circuit arcs radiating from the stand line — reads as
            // a calibration glyph burned into alien floor plating.
            for i in 0..<5 {
                let radius = w * (0.12 + CGFloat(i) * 0.09)
                let alpha = 0.18 - CGFloat(i) * 0.02
                ctx.setStrokeColor(UIColor(red: 1, green: 0.85, blue: 0.55, alpha: max(0.03, alpha)).cgColor)
                ctx.setLineWidth(2)
                ctx.addArc(center: center, radius: radius, startAngle: 0.15 * .pi, endAngle: 0.85 * .pi, clockwise: false)
                ctx.strokePath()
                ctx.addArc(center: center, radius: radius, startAngle: 1.15 * .pi, endAngle: 1.85 * .pi, clockwise: false)
                ctx.strokePath()
            }

            // Sparse fine speckle for a worn-floor feel.
            for _ in 0..<400 {
                let x = CGFloat.random(in: 0...w, using: &seed)
                let y = CGFloat.random(in: 0...h, using: &seed)
                ctx.setFillColor(UIColor(red: 1, green: 0.9, blue: 0.7, alpha: CGFloat.random(in: 0.02...0.06, using: &seed)).cgColor)
                ctx.fill(CGRect(x: x, y: y, width: 1.4, height: 1.4))
            }
        }
    }
}
