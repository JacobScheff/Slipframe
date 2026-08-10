//
//  ProceduralGeometry.swift
//  Slipframe
//
//  Deterministic mesh-building toolkit for the "Xenotech Rift" art direction —
//  jagged/irregular silhouettes for the portal rift, obstacle clusters, and
//  crystal facets. Everything here is generated at runtime (no authored USDZ),
//  seeded so a given spawn always looks the same on replay/daily challenge
//  streams while still reading as hand-cut rather than stamped-out.
//
//  All builders favor robustness over cleverness: shapes are constructed as
//  star-shaped polygons (radius-per-angle around a center), which are always
//  simple (non self-intersecting) and safe to fan-triangulate.
//

import RealityKit
import simd

enum ProceduralGeometryError: Error {
    case degenerate
}

enum ProceduralGeometry {

    // MARK: - Deterministic "noise"

    /// Cheap deterministic angular noise built from a handful of seeded sine
    /// harmonics. Much simpler (and just as organic-looking at gameplay
    /// viewing distances) than porting a real Perlin/Simplex implementation.
    struct RadialNoise {
        private let harmonics: [(freq: Float, phase: Float, amp: Float)]
        private let ampSum: Float

        init(seed: UInt64, octaves: Int = 4) {
            var rng = SeededGenerator(seed: seed &+ 0xA511_E9B3_2C4F_1D7B)
            var built: [(Float, Float, Float)] = []
            var sum: Float = 0
            for i in 0..<max(1, octaves) {
                let freq = Float(2 + i * 2) + Float.random(in: -0.35...0.35, using: &rng)
                let phase = Float.random(in: 0...(2 * Float.pi), using: &rng)
                let amp = Float.random(in: 0.35...1.0, using: &rng) / Float(i + 1)
                built.append((freq, phase, amp))
                sum += amp
            }
            harmonics = built
            ampSum = max(0.0001, sum)
        }

        /// Signed value roughly in -1...1 for angle `theta` (radians).
        func value(at theta: Float) -> Float {
            var total: Float = 0
            for h in harmonics {
                total += sin(theta * h.freq + h.phase) * h.amp
            }
            return total / ampSum
        }
    }

    // MARK: - 2D boundary generation

    /// Closed jagged outline: `sides` points swept around the origin, radius
    /// perturbed per-angle by `noise` — the shared "torn reality" silhouette
    /// language reused by the portal rift, shatter panes, and shard clusters.
    static func jaggedOutline(
        sides: Int,
        radiusX: Float,
        radiusY: Float,
        jitter: Float,
        noise: RadialNoise,
        angleOffset: Float = 0,
        minScale: Float = 0.35
    ) -> [SIMD2<Float>] {
        guard sides >= 3 else { return [] }
        var points: [SIMD2<Float>] = []
        points.reserveCapacity(sides)
        for i in 0..<sides {
            let theta = angleOffset + Float(i) / Float(sides) * (2 * Float.pi)
            let n = noise.value(at: theta)
            let scale = max(minScale, 1 + n * jitter)
            points.append(SIMD2(cos(theta) * radiusX * scale, sin(theta) * radiusY * scale))
        }
        return points
    }

    // MARK: - Flat / extruded polygon meshes

    /// Flat filled polygon fan-triangulated from the centroid — faces +Z.
    /// Used for the rift aperture plane and flat shard/pane faces.
    static func filledPolygon(points: [SIMD2<Float>]) throws -> MeshResource {
        guard points.count >= 3 else { throw ProceduralGeometryError.degenerate }
        let n = points.count
        let maxR = max(0.0001, points.map { simd_length($0) }.max() ?? 1)

        var positions: [SIMD3<Float>] = [SIMD3(0, 0, 0)]
        var normals: [SIMD3<Float>] = [SIMD3(0, 0, 1)]
        var uvs: [SIMD2<Float>] = [SIMD2(0.5, 0.5)]
        positions.reserveCapacity(n + 1)
        normals.reserveCapacity(n + 1)
        uvs.reserveCapacity(n + 1)

        for p in points {
            positions.append(SIMD3(p.x, p.y, 0))
            normals.append(SIMD3(0, 0, 1))
            uvs.append(SIMD2(0.5 + p.x / (2 * maxR), 0.5 + p.y / (2 * maxR)))
        }

        var indices: [UInt32] = []
        indices.reserveCapacity(n * 3)
        for i in 0..<n {
            indices.append(0)
            indices.append(UInt32(1 + i))
            indices.append(UInt32(1 + (i + 1) % n))
        }

        var descriptor = MeshDescriptor(name: "riftFilledPolygon")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }

    /// Extrude a closed 2D outline (XY plane) along Z by `depth`, centered on
    /// the origin, with flat-capped ends — a "jagged prism" body used for
    /// obstacle chunks and rift edge debris. Flat-shaded (duplicated verts per
    /// face) so facets read crisply even at low segment counts.
    static func extrudedPolygon(points: [SIMD2<Float>], depth: Float) throws -> MeshResource {
        guard points.count >= 3 else { throw ProceduralGeometryError.degenerate }
        let n = points.count
        let half = max(0.001, depth) * 0.5
        let maxR = max(0.0001, points.map { simd_length($0) }.max() ?? 1)

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        // Front cap (z = +half).
        let frontCenter = UInt32(positions.count)
        positions.append(SIMD3(0, 0, half))
        normals.append(SIMD3(0, 0, 1))
        uvs.append(SIMD2(0.5, 0.5))
        let frontStart = UInt32(positions.count)
        for p in points {
            positions.append(SIMD3(p.x, p.y, half))
            normals.append(SIMD3(0, 0, 1))
            uvs.append(SIMD2(0.5 + p.x / (2 * maxR), 0.5 + p.y / (2 * maxR)))
        }
        for i in 0..<n {
            indices.append(frontCenter)
            indices.append(frontStart + UInt32(i))
            indices.append(frontStart + UInt32((i + 1) % n))
        }

        // Back cap (z = -half), reversed winding + normal.
        let backCenter = UInt32(positions.count)
        positions.append(SIMD3(0, 0, -half))
        normals.append(SIMD3(0, 0, -1))
        uvs.append(SIMD2(0.5, 0.5))
        let backStart = UInt32(positions.count)
        for p in points {
            positions.append(SIMD3(p.x, p.y, -half))
            normals.append(SIMD3(0, 0, -1))
            uvs.append(SIMD2(0.5 + p.x / (2 * maxR), 0.5 + p.y / (2 * maxR)))
        }
        for i in 0..<n {
            indices.append(backCenter)
            indices.append(backStart + UInt32((i + 1) % n))
            indices.append(backStart + UInt32(i))
        }

        // Sides — one flat-shaded quad per edge.
        for i in 0..<n {
            let p0 = points[i]
            let p1 = points[(i + 1) % n]
            let v0 = SIMD3(p0.x, p0.y, half)
            let v1 = SIMD3(p1.x, p1.y, half)
            let v2 = SIMD3(p1.x, p1.y, -half)
            let v3 = SIMD3(p0.x, p0.y, -half)

            let edge = p1 - p0
            var outward = SIMD2(edge.y, -edge.x)
            let edgeLen = simd_length(outward)
            if edgeLen > 0.00001 {
                outward /= edgeLen
            }
            let normal = SIMD3(outward.x, outward.y, 0)

            let base = UInt32(positions.count)
            positions.append(contentsOf: [v0, v1, v2, v3])
            normals.append(contentsOf: [normal, normal, normal, normal])
            let u0 = Float(i) / Float(n)
            let u1 = Float(i + 1) / Float(n)
            uvs.append(contentsOf: [
                SIMD2(u0, 0), SIMD2(u1, 0), SIMD2(u1, 1), SIMD2(u0, 1)
            ])
            indices.append(contentsOf: [base, base + 1, base + 2])
            indices.append(contentsOf: [base, base + 2, base + 3])
        }

        var descriptor = MeshDescriptor(name: "riftExtrudedPolygon")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }

    /// A single thin, outward-tapering shard between two boundary points —
    /// "debris still falling off the wound" fringing the rift edge.
    static func edgeShard(p0: SIMD2<Float>, p1: SIMD2<Float>, outset: Float, thickness: Float) throws -> MeshResource {
        let mid = (p0 + p1) * 0.5
        let dir = simd_length(mid) > 0.0001 ? normalize(mid) : SIMD2<Float>(0, 1)
        let tip = mid + dir * outset

        let points: [SIMD2<Float>] = [p0, p1, tip]
        return try extrudedPolygon(points: points, depth: thickness)
    }

    // MARK: - Faceted crystal / gem meshes

    /// Full bipyramid ("gem") — an N-sided waist ring with a top and bottom
    /// apex, flat-shaded per facet. Used for Crystal Cave spires.
    static func bipyramid(
        sides: Int,
        radius: Float,
        topHeight: Float,
        bottomHeight: Float,
        jitter: Float = 0,
        seed: UInt64 = 0
    ) throws -> MeshResource {
        let n = max(3, sides)
        let noise: RadialNoise? = jitter > 0 ? RadialNoise(seed: seed, octaves: 3) : nil

        var ring: [SIMD3<Float>] = []
        ring.reserveCapacity(n)
        for i in 0..<n {
            let theta = Float(i) / Float(n) * (2 * Float.pi)
            var r = radius
            if let noise {
                r *= max(0.4, 1 + noise.value(at: theta) * jitter)
            }
            ring.append(SIMD3(cos(theta) * r, 0, sin(theta) * r))
        }
        let top = SIMD3<Float>(0, topHeight, 0)
        let bottom = SIMD3<Float>(0, -bottomHeight, 0)

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        for i in 0..<n {
            let a = top
            let b = ring[i]
            let c = ring[(i + 1) % n]
            let normal = flatNormal(a, b, c)
            let base = UInt32(positions.count)
            positions.append(contentsOf: [a, b, c])
            normals.append(contentsOf: [normal, normal, normal])
            uvs.append(contentsOf: [
                SIMD2(0.5, 0), SIMD2(Float(i) / Float(n), 0.5), SIMD2(Float(i + 1) / Float(n), 0.5)
            ])
            indices.append(contentsOf: [base, base + 1, base + 2])
        }

        for i in 0..<n {
            let a = bottom
            let b = ring[(i + 1) % n]
            let c = ring[i]
            let normal = flatNormal(a, b, c)
            let base = UInt32(positions.count)
            positions.append(contentsOf: [a, b, c])
            normals.append(contentsOf: [normal, normal, normal])
            uvs.append(contentsOf: [
                SIMD2(0.5, 1), SIMD2(Float(i + 1) / Float(n), 0.5), SIMD2(Float(i) / Float(n), 0.5)
            ])
            indices.append(contentsOf: [base, base + 1, base + 2])
        }

        var descriptor = MeshDescriptor(name: "riftGem")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }

    /// Half a bipyramid, sliced at the waist — a jagged fracture cap fills the
    /// cut face so it visibly reads as "snapped off" its other half. Used for
    /// Crystal Cave's hand-held collectible halves.
    static func crystalHalf(
        sides: Int,
        radius: Float,
        apexHeight: Float,
        jitter: Float = 0.12,
        seed: UInt64 = 0
    ) throws -> MeshResource {
        let n = max(3, sides)
        let noise = RadialNoise(seed: seed, octaves: 3)

        var ring: [SIMD3<Float>] = []
        ring.reserveCapacity(n)
        for i in 0..<n {
            let theta = Float(i) / Float(n) * (2 * Float.pi)
            let r = radius * max(0.45, 1 + noise.value(at: theta) * jitter)
            ring.append(SIMD3(cos(theta) * r, 0, sin(theta) * r))
        }
        let apex = SIMD3<Float>(0, apexHeight, 0)

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        // Faceted side toward the apex.
        for i in 0..<n {
            let a = apex
            let b = ring[i]
            let c = ring[(i + 1) % n]
            let normal = flatNormal(a, b, c)
            let base = UInt32(positions.count)
            positions.append(contentsOf: [a, b, c])
            normals.append(contentsOf: [normal, normal, normal])
            uvs.append(contentsOf: [
                SIMD2(0.5, 0), SIMD2(Float(i) / Float(n), 1), SIMD2(Float(i + 1) / Float(n), 1)
            ])
            indices.append(contentsOf: [base, base + 1, base + 2])
        }

        // Flat fracture cap at the waist (y = 0), fan-triangulated, normal −Y.
        let capCenter = UInt32(positions.count)
        positions.append(SIMD3(0, 0, 0))
        normals.append(SIMD3(0, -1, 0))
        uvs.append(SIMD2(0.5, 0.5))
        let capStart = UInt32(positions.count)
        for p in ring {
            positions.append(p)
            normals.append(SIMD3(0, -1, 0))
            uvs.append(SIMD2(0.5 + p.x / (2 * radius), 0.5 + p.z / (2 * radius)))
        }
        for i in 0..<n {
            indices.append(capCenter)
            indices.append(capStart + UInt32((i + 1) % n))
            indices.append(capStart + UInt32(i))
        }

        var descriptor = MeshDescriptor(name: "riftCrystalHalf")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }

    private static func flatNormal(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> SIMD3<Float> {
        let n = cross(b - a, c - a)
        let len = simd_length(n)
        return len > 0.00001 ? n / len : SIMD3(0, 1, 0)
    }
}
