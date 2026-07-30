//
//  GameVisuals.swift
//  Endless Runner
//
//  Shared palette, materials, and polished procedural mesh builders.
//  Placeholder geometry until custom USDZ art lands (see ASSET_SPEC.md).
//

import RealityKit
import UIKit

// MARK: - Palette

enum GamePalette {
    /// Deep ink under the track — reads against passthrough without going pure black.
    static let trackInk = UIColor(red: 0.06, green: 0.07, blue: 0.11, alpha: 1)
    /// Cool cyan neon — primary guide / portal accent.
    static let neonCyan = UIColor(red: 0.28, green: 0.93, blue: 1.0, alpha: 1)
    static let neonCyanSoft = UIColor(red: 0.28, green: 0.93, blue: 1.0, alpha: 0.55)
    static let neonCyanHot = UIColor(red: 0.75, green: 0.98, blue: 1.0, alpha: 1)
    /// Danger red for walls.
    static let hazardRed = UIColor(red: 0.98, green: 0.16, blue: 0.14, alpha: 1)
    static let hazardRedSoft = UIColor(red: 0.98, green: 0.22, blue: 0.18, alpha: 0.38)
    static let hazardEdge = UIColor(red: 1.0, green: 0.55, blue: 0.42, alpha: 1)
    /// Coin gold.
    static let coinGold = UIColor(red: 1.0, green: 0.78, blue: 0.22, alpha: 1)
    static let coinGoldHot = UIColor(red: 1.0, green: 0.92, blue: 0.55, alpha: 1)
    /// Stand-line warm cream.
    static let standCream = UIColor(red: 0.98, green: 0.93, blue: 0.78, alpha: 1)
    static let standAmber = UIColor(red: 1.0, green: 0.82, blue: 0.38, alpha: 1)
    /// Portal tunnel void.
    static let voidInk = UIColor(red: 0.02, green: 0.03, blue: 0.06, alpha: 1)
    static let tunnelAccent = UIColor(red: 0.12, green: 0.45, blue: 0.62, alpha: 1)
}

// MARK: - Materials

enum GameMaterials {
    private static var didWarmTextures = false
    private static var trackFloorTexture: TextureResource?
    private static var wallEnergyTexture: TextureResource?
    private static var coinFaceTexture: TextureResource?
    private static var portalGlowTexture: TextureResource?
    private static var laneStripeTexture: TextureResource?
    private static var startPadTexture: TextureResource?

    /// Load catalog textures once; fall back to solid colors if a name is missing.
    static func warmTextures() {
        guard !didWarmTextures else { return }
        didWarmTextures = true
        trackFloorTexture = try? TextureResource.load(named: "TrackFloor")
        wallEnergyTexture = try? TextureResource.load(named: "WallEnergy")
        coinFaceTexture = try? TextureResource.load(named: "CoinFace")
        portalGlowTexture = try? TextureResource.load(named: "PortalGlow")
        laneStripeTexture = try? TextureResource.load(named: "LaneStripe")
        startPadTexture = try? TextureResource.load(named: "StartPad")
    }

    static func trackFloor() -> any RealityKit.Material {
        warmTextures()
        if let texture = trackFloorTexture {
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(texture: .init(texture), tint: GamePalette.trackInk)
            material.roughness = .init(floatLiteral: 0.78)
            material.metallic = .init(floatLiteral: 0.12)
            material.emissiveColor = .init(
                color: UIColor(red: 0.05, green: 0.12, blue: 0.16, alpha: 1),
                texture: .init(texture)
            )
            material.emissiveIntensity = 0.22
            return material
        }
        return SimpleMaterial(color: GamePalette.trackInk, roughness: 0.85, isMetallic: false)
    }

    static func laneCore() -> UnlitMaterial {
        warmTextures()
        var material = UnlitMaterial(color: GamePalette.neonCyan)
        if let texture = laneStripeTexture {
            material.color = .init(tint: GamePalette.neonCyan, texture: .init(texture))
        }
        return material
    }

    static func laneGlow() -> any RealityKit.Material {
        // Soft under-glow — alpha on tint handles transparency on visionOS 1.x.
        UnlitMaterial(color: GamePalette.neonCyanSoft)
    }

    static func railNeon() -> UnlitMaterial {
        UnlitMaterial(color: GamePalette.neonCyan)
    }

    static func railDark() -> SimpleMaterial {
        SimpleMaterial(
            color: UIColor(red: 0.1, green: 0.12, blue: 0.16, alpha: 1),
            roughness: 0.7,
            isMetallic: true
        )
    }

    static func wallBody() -> any RealityKit.Material {
        warmTextures()
        var material = PhysicallyBasedMaterial()
        if let texture = wallEnergyTexture {
            material.baseColor = .init(texture: .init(texture), tint: .white)
            material.emissiveColor = .init(color: .white, texture: .init(texture))
        } else {
            material.baseColor = .init(tint: GamePalette.hazardRedSoft)
            material.emissiveColor = .init(color: GamePalette.hazardRed)
        }
        material.roughness = .init(floatLiteral: 0.28)
        material.metallic = .init(floatLiteral: 0.08)
        material.emissiveIntensity = 0.7
        material.blending = .transparent(opacity: .init(floatLiteral: 0.48))
        return material
    }

    static func wallGlowShell() -> any RealityKit.Material {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: 1.0, green: 0.25, blue: 0.18, alpha: 0.18))
        material.emissiveColor = .init(color: UIColor(red: 1.0, green: 0.3, blue: 0.2, alpha: 1))
        material.emissiveIntensity = 0.35
        material.roughness = .init(floatLiteral: 1.0)
        material.metallic = .init(floatLiteral: 0.0)
        material.blending = .transparent(opacity: .init(floatLiteral: 0.18))
        return material
    }

    static func wallEdge() -> UnlitMaterial {
        UnlitMaterial(color: GamePalette.hazardEdge)
    }

    static func wallVein() -> UnlitMaterial {
        UnlitMaterial(color: UIColor(red: 1.0, green: 0.35, blue: 0.28, alpha: 1))
    }

    static func coinMetal() -> any RealityKit.Material {
        warmTextures()
        var material = PhysicallyBasedMaterial()
        if let texture = coinFaceTexture {
            material.baseColor = .init(texture: .init(texture), tint: .white)
            material.emissiveColor = .init(color: GamePalette.coinGoldHot, texture: .init(texture))
        } else {
            material.baseColor = .init(tint: GamePalette.coinGold)
            material.emissiveColor = .init(color: GamePalette.coinGoldHot)
        }
        material.roughness = .init(floatLiteral: 0.28)
        material.metallic = .init(floatLiteral: 0.92)
        material.emissiveIntensity = 0.45
        return material
    }

    static func coinCore() -> UnlitMaterial {
        UnlitMaterial(color: GamePalette.coinGoldHot)
    }

    static func coinAura() -> any RealityKit.Material {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: 1.0, green: 0.85, blue: 0.35, alpha: 0.22))
        material.emissiveColor = .init(color: GamePalette.coinGoldHot)
        material.emissiveIntensity = 0.4
        material.roughness = .init(floatLiteral: 1.0)
        material.metallic = .init(floatLiteral: 0.0)
        material.blending = .transparent(opacity: .init(floatLiteral: 0.22))
        return material
    }

    static func portalRimHot() -> UnlitMaterial {
        UnlitMaterial(color: GamePalette.neonCyanHot)
    }

    static func portalRimMid() -> UnlitMaterial {
        UnlitMaterial(color: GamePalette.neonCyan)
    }

    static func portalRimBloom() -> any RealityKit.Material {
        warmTextures()
        if let texture = portalGlowTexture {
            var material = UnlitMaterial(color: .white)
            material.color = .init(tint: .white, texture: .init(texture))
            return material
        }
        return UnlitMaterial(color: GamePalette.neonCyanSoft)
    }

    static func portalVoid() -> UnlitMaterial {
        UnlitMaterial(color: GamePalette.voidInk)
    }

    static func portalRail() -> UnlitMaterial {
        UnlitMaterial(color: GamePalette.neonCyan)
    }

    static func portalAccent() -> UnlitMaterial {
        UnlitMaterial(color: GamePalette.tunnelAccent)
    }

    static func portalRing() -> any RealityKit.Material {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: 0.2, green: 0.7, blue: 0.9, alpha: 0.45))
        material.emissiveColor = .init(color: UIColor(red: 0.25, green: 0.75, blue: 0.95, alpha: 1))
        material.emissiveIntensity = 0.5
        material.roughness = .init(floatLiteral: 1.0)
        material.metallic = .init(floatLiteral: 0.0)
        material.blending = .transparent(opacity: .init(floatLiteral: 0.45))
        return material
    }

    static func startLine() -> UnlitMaterial {
        UnlitMaterial(color: GamePalette.standCream)
    }

    static func startAccent() -> UnlitMaterial {
        UnlitMaterial(color: GamePalette.standAmber)
    }

    static func startPad() -> any RealityKit.Material {
        warmTextures()
        if let texture = startPadTexture {
            var material = UnlitMaterial(color: .white)
            material.color = .init(tint: .white, texture: .init(texture))
            return material
        }
        return UnlitMaterial(color: UIColor(red: 1, green: 0.9, blue: 0.7, alpha: 0.55))
    }

    static func hitFlash() -> any RealityKit.Material {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: 1.0, green: 0.15, blue: 0.12, alpha: 0.45))
        material.emissiveColor = .init(color: GamePalette.hazardRed)
        material.emissiveIntensity = 0.8
        material.roughness = .init(floatLiteral: 1.0)
        material.metallic = .init(floatLiteral: 0.0)
        material.blending = .transparent(opacity: .init(floatLiteral: 0.45))
        return material
    }

    static func spark(color: UIColor) -> UnlitMaterial {
        UnlitMaterial(color: color)
    }
}

// MARK: - Builders

enum GameVisualBuilders {
    /// Multi-layer hazard slab: soft glow shell + energy body + emissive frame + veins.
    static func makeWallSlab(width: Float, height: Float, thickness: Float) -> Entity {
        let root = Entity()
        root.name = "wallSlab"

        let bodyMesh = MeshResource.generateBox(width: width, height: height, depth: thickness)
        let body = ModelEntity(mesh: bodyMesh, materials: [GameMaterials.wallBody()])
        body.name = "wallBody"
        root.addChild(body)

        // Soft outer aura — slightly larger, reads as volumetric heat.
        let glowMesh = MeshResource.generateBox(
            width: width * 1.06,
            height: height * 1.02,
            depth: thickness * 1.08
        )
        let glow = ModelEntity(mesh: glowMesh, materials: [GameMaterials.wallGlowShell()])
        glow.name = "wallGlow"
        root.addChild(glow)

        // Front-face neon frame (toward the player).
        let edge = GameMaterials.wallEdge()
        let frameZ = thickness * 0.5 + 0.008
        let barT: Float = 0.028
        let top = ModelEntity(
            mesh: MeshResource.generateBox(width: width * 0.98, height: barT, depth: barT),
            materials: [edge]
        )
        top.position = SIMD3(0, height * 0.5 - barT, frameZ)
        root.addChild(top)

        let bottom = ModelEntity(
            mesh: MeshResource.generateBox(width: width * 0.98, height: barT, depth: barT),
            materials: [edge]
        )
        bottom.position = SIMD3(0, -height * 0.5 + barT, frameZ)
        root.addChild(bottom)

        for sign: Float in [-1, 1] {
            let side = ModelEntity(
                mesh: MeshResource.generateBox(width: barT, height: height * 0.98, depth: barT),
                materials: [edge]
            )
            side.position = SIMD3(sign * (width * 0.5 - barT), 0, frameZ)
            root.addChild(side)
        }

        // Vertical energy veins for readable silhouette at distance.
        let veinMat = GameMaterials.wallVein()
        for offset: Float in [-0.18, 0, 0.18] {
            let vein = ModelEntity(
                mesh: MeshResource.generateBox(width: 0.012, height: height * 0.82, depth: 0.012),
                materials: [veinMat]
            )
            vein.position = SIMD3(offset, 0, frameZ + 0.004)
            root.addChild(vein)
        }

        // Corner pips — tiny hot points that catch the eye.
        for xSign: Float in [-1, 1] {
            for ySign: Float in [-1, 1] {
                let pip = ModelEntity(
                    mesh: MeshResource.generateSphere(radius: 0.03),
                    materials: [UnlitMaterial(color: GamePalette.hazardEdge)]
                )
                pip.position = SIMD3(
                    xSign * (width * 0.5 - 0.04),
                    ySign * (height * 0.5 - 0.04),
                    frameZ + 0.01
                )
                root.addChild(pip)
            }
        }

        return root
    }

    /// Gold disc coin with emissive core + soft aura (spins / bobs via GameWorld).
    static func makeCoin(radius: Float) -> Entity {
        let root = Entity()
        root.name = "coin"

        // Flattened cylinder reads as a collectible disc, not a marble.
        let discMesh = MeshResource.generateCylinder(height: radius * 0.28, radius: radius)
        let disc = ModelEntity(mesh: discMesh, materials: [GameMaterials.coinMetal()])
        disc.name = "coinDisc"
        // Cylinder axis is Y; tip toward player (+Z) so the face is visible.
        disc.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0))
        root.addChild(disc)

        let core = ModelEntity(
            mesh: MeshResource.generateSphere(radius: radius * 0.35),
            materials: [GameMaterials.coinCore()]
        )
        core.name = "coinCore"
        root.addChild(core)

        let aura = ModelEntity(
            mesh: MeshResource.generateSphere(radius: radius * 1.55),
            materials: [GameMaterials.coinAura()]
        )
        aura.name = "coinAura"
        root.addChild(aura)

        // Tiny orbiting sparkle for life.
        let spark = ModelEntity(
            mesh: MeshResource.generateSphere(radius: radius * 0.14),
            materials: [UnlitMaterial(color: GamePalette.coinGoldHot)]
        )
        spark.name = "coinSpark"
        spark.position = SIMD3(radius * 0.85, radius * 0.2, 0)
        root.addChild(spark)

        return root
    }

    /// Fixed track slab with neon lane guides and side rails.
    static func makeTrack(width: Float, depth: Float, laneXs: [Float]) -> Entity {
        let root = Entity()
        root.name = "trackAssembly"

        let floor = ModelEntity(
            mesh: MeshResource.generateBox(width: width, height: 0.025, depth: depth),
            materials: [GameMaterials.trackFloor()]
        )
        floor.name = "floor"
        floor.position = SIMD3(0, 0, 0)
        root.addChild(floor)

        // Soft under-glow strips under each lane.
        for x in laneXs {
            let glow = ModelEntity(
                mesh: MeshResource.generateBox(width: 0.16, height: 0.01, depth: depth),
                materials: [GameMaterials.laneGlow()]
            )
            glow.position = SIMD3(x, 0.014, 0)
            root.addChild(glow)

            let core = ModelEntity(
                mesh: MeshResource.generateBox(width: 0.05, height: 0.018, depth: depth),
                materials: [GameMaterials.laneCore()]
            )
            core.name = "laneStripe"
            core.position = SIMD3(x, 0.022, 0)
            root.addChild(core)
        }

        // Side rails — dark metal bar + neon edge light.
        for sign: Float in [-1, 1] {
            let railX = sign * (width * 0.5 - 0.04)
            let bar = ModelEntity(
                mesh: MeshResource.generateBox(width: 0.08, height: 0.06, depth: depth),
                materials: [GameMaterials.railDark()]
            )
            bar.position = SIMD3(railX, 0.04, 0)
            root.addChild(bar)

            let neon = ModelEntity(
                mesh: MeshResource.generateBox(width: 0.025, height: 0.02, depth: depth),
                materials: [GameMaterials.railNeon()]
            )
            neon.position = SIMD3(railX, 0.075, 0)
            root.addChild(neon)
        }

        // Distance tick marks along the center for motion parallax.
        let tickCount = max(4, Int(depth / 1.4))
        let halfDepth = depth * 0.5
        for i in 0..<tickCount {
            let t = Float(i) / Float(max(tickCount - 1, 1))
            let z = halfDepth - t * depth
            let tick = ModelEntity(
                mesh: MeshResource.generateBox(width: 0.22, height: 0.012, depth: 0.03),
                materials: [UnlitMaterial(color: UIColor(red: 0.35, green: 0.75, blue: 0.9, alpha: 0.55))]
            )
            tick.position = SIMD3(0, 0.03, z)
            root.addChild(tick)
        }

        return root
    }

    /// Synth Riders-style portal rim: bloom plate + mid neon + hot inner edge.
    static func makePortalRim(width: Float, height: Float, cornerRadius: Float, thickness: Float) -> Entity {
        let rim = Entity()
        rim.name = "portalRim"

        // Soft bloom plate behind the aperture.
        let bloomMesh = MeshResource.generatePlane(
            width: width + thickness * 4.5,
            height: height + thickness * 4.5,
            cornerRadius: cornerRadius + thickness * 1.2
        )
        let bloom = ModelEntity(mesh: bloomMesh, materials: [GameMaterials.portalRimBloom()])
        bloom.name = "portalBloom"
        bloom.position = SIMD3(0, 0, -0.04)
        rim.addChild(bloom)

        // Mid neon halo.
        let midMesh = MeshResource.generatePlane(
            width: width + thickness * 2.2,
            height: height + thickness * 2.2,
            cornerRadius: cornerRadius + thickness * 0.55
        )
        let mid = ModelEntity(mesh: midMesh, materials: [GameMaterials.portalRimMid()])
        mid.name = "portalMid"
        mid.position = SIMD3(0, 0, -0.02)
        rim.addChild(mid)

        // Hot inner edge that peeks tightly around the portal mesh.
        let hotMesh = MeshResource.generatePlane(
            width: width + thickness * 0.85,
            height: height + thickness * 0.85,
            cornerRadius: cornerRadius + thickness * 0.25
        )
        let hot = ModelEntity(mesh: hotMesh, materials: [GameMaterials.portalRimHot()])
        hot.name = "portalHot"
        hot.position = SIMD3(0, 0, -0.008)
        rim.addChild(hot)

        // Four corner sparks for a crafted, non-flat rim silhouette.
        let insetX = width * 0.42
        let insetY = height * 0.38
        for xSign: Float in [-1, 1] {
            for ySign: Float in [-1, 1] {
                let spark = ModelEntity(
                    mesh: MeshResource.generateSphere(radius: 0.045),
                    materials: [UnlitMaterial(color: GamePalette.neonCyanHot)]
                )
                spark.position = SIMD3(xSign * insetX, ySign * insetY, 0.01)
                rim.addChild(spark)
            }
        }

        return rim
    }

    /// Dark tunnel visible through the portal — rings + rails + far glow for depth.
    static func makePortalInterior(portalHeight: Float) -> Entity {
        let interior = Entity()
        interior.name = "portalInterior"
        interior.position = SIMD3(0, 0, -0.05)

        let voidMat = GameMaterials.portalVoid()
        let railMat = GameMaterials.portalRail()
        let accentMat = GameMaterials.portalAccent()
        let ringMat = GameMaterials.portalRing()

        let tunnelW: Float = 4.4
        let tunnelH = portalHeight + 0.4
        let tunnelDepth: Float = 12

        let floor = ModelEntity(
            mesh: MeshResource.generateBox(width: tunnelW, height: 0.06, depth: tunnelDepth),
            materials: [voidMat]
        )
        floor.name = "portalFloor"
        floor.position = SIMD3(0, -tunnelH * 0.5, -tunnelDepth * 0.5)
        interior.addChild(floor)

        let ceiling = ModelEntity(
            mesh: MeshResource.generateBox(width: tunnelW, height: 0.06, depth: tunnelDepth),
            materials: [voidMat]
        )
        ceiling.name = "portalCeiling"
        ceiling.position = SIMD3(0, tunnelH * 0.5, -tunnelDepth * 0.5)
        interior.addChild(ceiling)

        for sign: Float in [-1, 1] {
            let wall = ModelEntity(
                mesh: MeshResource.generateBox(width: 0.06, height: tunnelH, depth: tunnelDepth),
                materials: [voidMat]
            )
            wall.name = "portalSide"
            wall.position = SIMD3(sign * tunnelW * 0.5, 0, -tunnelDepth * 0.5)
            interior.addChild(wall)
        }

        let back = ModelEntity(
            mesh: MeshResource.generateBox(width: tunnelW, height: tunnelH, depth: 0.08),
            materials: [voidMat]
        )
        back.name = "portalBack"
        back.position = SIMD3(0, 0, -tunnelDepth)
        interior.addChild(back)

        // Receding neon rings — classic portal depth cue.
        for i in 0..<7 {
            let t = Float(i) / 6.0
            let z = -1.2 - t * (tunnelDepth - 2.4)
            let scale = 1.0 - t * 0.35
            let ring = ModelEntity(
                mesh: MeshResource.generatePlane(
                    width: tunnelW * 0.72 * scale,
                    height: tunnelH * 0.82 * scale,
                    cornerRadius: 0.55 * scale
                ),
                materials: [ringMat]
            )
            ring.name = "portalRing"
            ring.position = SIMD3(0, 0, z)
            interior.addChild(ring)
        }

        // Floor rails.
        for sign: Float in [-1, 1] {
            let rail = ModelEntity(
                mesh: MeshResource.generateBox(width: 0.05, height: 0.05, depth: tunnelDepth - 0.5),
                materials: [railMat]
            )
            rail.name = "portalRail"
            rail.position = SIMD3(sign * 1.35, -tunnelH * 0.5 + 0.08, -tunnelDepth * 0.5)
            interior.addChild(rail)
        }

        // Chevron arrows on the tunnel floor pointing toward the player (emergence).
        for i in 0..<5 {
            let z = -2.0 - Float(i) * 1.8
            let chevron = makeFloorChevron(material: accentMat)
            chevron.position = SIMD3(0, -tunnelH * 0.5 + 0.05, z)
            interior.addChild(chevron)
        }

        // Layered far glow — hot core + soft bloom.
        let farCore = ModelEntity(
            mesh: MeshResource.generateSphere(radius: 0.35),
            materials: [UnlitMaterial(color: GamePalette.neonCyanHot)]
        )
        farCore.name = "farCore"
        farCore.position = SIMD3(0, -0.1, -tunnelDepth + 1.4)
        interior.addChild(farCore)

        var bloomMat = PhysicallyBasedMaterial()
        bloomMat.baseColor = .init(tint: UIColor(red: 0.2, green: 0.65, blue: 0.95, alpha: 0.3))
        bloomMat.emissiveColor = .init(color: UIColor(red: 0.2, green: 0.65, blue: 0.95, alpha: 1))
        bloomMat.emissiveIntensity = 0.55
        bloomMat.roughness = .init(floatLiteral: 1.0)
        bloomMat.metallic = .init(floatLiteral: 0.0)
        bloomMat.blending = .transparent(opacity: .init(floatLiteral: 0.3))
        let farBloom = ModelEntity(
            mesh: MeshResource.generateSphere(radius: 0.95),
            materials: [bloomMat]
        )
        farBloom.position = SIMD3(0, -0.1, -tunnelDepth + 1.4)
        interior.addChild(farBloom)

        return interior
    }

    private static func makeFloorChevron(material: UnlitMaterial) -> Entity {
        let root = Entity()
        // Two angled bars form a simple > chevron pointing +Z (toward player / out of portal).
        for sign: Float in [-1, 1] {
            let bar = ModelEntity(
                mesh: MeshResource.generateBox(width: 0.35, height: 0.02, depth: 0.05),
                materials: [material]
            )
            bar.position = SIMD3(sign * 0.14, 0, 0)
            bar.orientation = simd_quatf(angle: sign * 0.55, axis: SIMD3(0, 1, 0))
            root.addChild(bar)
        }
        return root
    }

    /// Stand zone: soft pad, crisp line, forward chevrons, center tick.
    static func makeStartMarker() -> Entity {
        let marker = Entity()
        marker.name = "startMarker"
        marker.position = SIMD3(0, 0.03, 0)

        let pad = ModelEntity(
            mesh: MeshResource.generatePlane(width: 2.6, height: 0.55),
            materials: [GameMaterials.startPad()]
        )
        // Plane faces +Y by default after rotating from XY… generatePlane is XY facing +Z.
        // Lay it flat on the floor.
        pad.orientation = simd_quatf(angle: -.pi / 2, axis: SIMD3(1, 0, 0))
        pad.position = SIMD3(0, 0.002, 0.05)
        marker.addChild(pad)

        let line = ModelEntity(
            mesh: MeshResource.generateBox(width: 2.4, height: 0.01, depth: 0.032),
            materials: [GameMaterials.startLine()]
        )
        line.position = SIMD3(0, 0.008, 0)
        marker.addChild(line)

        let tick = ModelEntity(
            mesh: MeshResource.generateBox(width: 0.12, height: 0.014, depth: 0.12),
            materials: [GameMaterials.startAccent()]
        )
        tick.position = SIMD3(0, 0.012, 0)
        marker.addChild(tick)

        // Three forward chevrons pointing toward the portal (−Z).
        for i in 0..<3 {
            let chevron = makeWorldChevron()
            chevron.position = SIMD3(0, 0.01, -0.22 - Float(i) * 0.18)
            let s = 1.0 - Float(i) * 0.12
            chevron.scale = SIMD3(repeating: s)
            marker.addChild(chevron)
        }

        return marker
    }

    private static func makeWorldChevron() -> Entity {
        let root = Entity()
        let mat = GameMaterials.startAccent()
        for sign: Float in [-1, 1] {
            let bar = ModelEntity(
                mesh: MeshResource.generateBox(width: 0.22, height: 0.012, depth: 0.04),
                materials: [mat]
            )
            bar.position = SIMD3(sign * 0.09, 0, 0)
            // Angle so the V opens toward +Z and points toward −Z (portal).
            bar.orientation = simd_quatf(angle: sign * (-0.6), axis: SIMD3(0, 1, 0))
            root.addChild(bar)
        }
        return root
    }

    /// Brief full-field red flash for wall hits.
    static func makeHitFlash(width: Float = 3.5, height: Float = 2.4) -> ModelEntity {
        let mesh = MeshResource.generatePlane(width: width, height: height, cornerRadius: 0.2)
        let flash = ModelEntity(mesh: mesh, materials: [GameMaterials.hitFlash()])
        flash.name = "hitFlash"
        return flash
    }

    /// Small burst of sparks for coin collects.
    static func makeCollectBurst(at position: SIMD3<Float>, parent: Entity) -> [BurstSpark] {
        var sparks: [BurstSpark] = []
        let colors = [GamePalette.coinGoldHot, GamePalette.coinGold, GamePalette.neonCyanHot]
        for i in 0..<10 {
            let color = colors[i % colors.count]
            let sphere = ModelEntity(
                mesh: MeshResource.generateSphere(radius: Float.random(in: 0.012...0.028)),
                materials: [GameMaterials.spark(color: color)]
            )
            sphere.position = position
            parent.addChild(sphere)

            let angle = Float(i) / 10.0 * (.pi * 2) + Float.random(in: -0.2...0.2)
            let speed = Float.random(in: 0.9...1.6)
            let velocity = SIMD3<Float>(
                cos(angle) * speed,
                Float.random(in: 0.4...1.2),
                sin(angle) * speed * 0.35
            )
            sparks.append(BurstSpark(entity: sphere, velocity: velocity, age: 0, lifetime: 0.35))
        }
        return sparks
    }
}

// MARK: - Lightweight VFX state

struct BurstSpark {
    let entity: Entity
    var velocity: SIMD3<Float>
    var age: Float
    let lifetime: Float
}

@MainActor
final class VisualFXController {
    private var sparks: [BurstSpark] = []
    private var hitFlash: Entity?
    private var hitFlashAge: Float = 0
    private let hitFlashLifetime: Float = 0.28
    private weak var parent: Entity?

    func attach(to parent: Entity) {
        self.parent = parent
    }

    func clear() {
        for spark in sparks {
            spark.entity.removeFromParent()
        }
        sparks.removeAll()
        hitFlash?.removeFromParent()
        hitFlash = nil
        hitFlashAge = 0
    }

    func spawnCoinBurst(at position: SIMD3<Float>) {
        guard let parent else { return }
        sparks.append(contentsOf: GameVisualBuilders.makeCollectBurst(at: position, parent: parent))
    }

    func spawnHitFlash(near position: SIMD3<Float>) {
        guard let parent else { return }
        hitFlash?.removeFromParent()
        let flash = GameVisualBuilders.makeHitFlash()
        flash.position = SIMD3(position.x, max(1.2, position.y), position.z - 0.35)
        parent.addChild(flash)
        hitFlash = flash
        hitFlashAge = 0
    }

    func tick(deltaTime: Float) {
        // Sparks.
        var alive: [BurstSpark] = []
        alive.reserveCapacity(sparks.count)
        for var spark in sparks {
            spark.age += deltaTime
            if spark.age >= spark.lifetime {
                spark.entity.removeFromParent()
                continue
            }
            spark.velocity.y -= 2.8 * deltaTime
            spark.entity.position += spark.velocity * deltaTime
            let life = 1.0 - spark.age / spark.lifetime
            spark.entity.scale = SIMD3(repeating: max(0.05, life))
            alive.append(spark)
        }
        sparks = alive

        // Hit flash fade.
        if let flash = hitFlash {
            hitFlashAge += deltaTime
            let t = hitFlashAge / hitFlashLifetime
            if t >= 1 {
                flash.removeFromParent()
                hitFlash = nil
            } else {
                let fade = 1.0 - t
                flash.scale = SIMD3(1 + t * 0.15, 1 + t * 0.15, 1)
                // Approximate fade via scale + opacity isn't trivial on UnlitMaterial; shrink & drop.
                flash.position.z += deltaTime * 0.2
                _ = fade
            }
        }
    }
}
