import ARKit
import RealityKit
import UIKit
import simd

/// One square lattice per measured wall or ceiling, clipped to its footprint.
/// Overlapping plane anchors share a basis and never draw the same area twice.
@MainActor
final class RoomGrid {
    let root = Entity()
    var reduceMotion = false

    private enum Style {
        static let spacing: Float = 0.50
        static let lineWidth: Float = 0.004
        static let wallOpacity: Float = 0.30
        static let ceilingOpacity: Float = 0.22
        static let playingOpacity: Float = 0.80
    }

    private struct Vertex {
        var position: SIMD3<Float>
        var uv: SIMD2<Float>
    }

    private struct Plane {
        let id: UUID
        let triangles: [[SIMD3<Float>]]
        let normal: SIMD3<Float>
        let center: SIMD3<Float>
        let ceiling: Bool
        let order: Int
        let signature: Int
    }

    private struct Group {
        var planes: [Plane]
        let normal: SIMD3<Float>
        let center: SIMD3<Float>
        let ceiling: Bool
    }

    @MainActor
    private final class Surface {
        let entity: ModelEntity
        var normal: SIMD3<Float>
        var center: SIMD3<Float>
        var ceiling: Bool
        var signature: Int = 0
        var reveal: Float = 0

        init(mesh: MeshResource, material: UnlitMaterial, group: Group) {
            entity = ModelEntity(mesh: mesh, materials: [material])
            normal = group.normal
            center = group.center
            ceiling = group.ceiling
            entity.components.set(OpacityComponent(opacity: 0))
        }
    }

    private var planes: [UUID: Plane] = [:]
    private var surfaces: [UUID: Surface] = [:]
    private var nextOrder = 0
    private var pulseRemaining: Float = 0
    private var lastOpacity = -1
    private let ink = UIColor(red: 0.64, green: 0.84, blue: 0.96, alpha: 1)
    private var color = UIColor(red: 0.64, green: 0.84, blue: 0.96, alpha: 1)

    private var material: UnlitMaterial {
        var material = UnlitMaterial(color: color)
        // Draw each triangle once, visible from either side of the surface.
        material.faceCulling = .none
        return material
    }

    func setTint(_ color: UIColor) {
        self.color = EnvironmentMaterials.lerpColor(ink, color, 0.30)
        for surface in surfaces.values { surface.entity.model?.materials = [material] }
    }

    func update(_ anchor: PlaneAnchor) {
        let ceiling = anchor.classification == .ceiling
        guard ceiling || anchor.classification == .wall else { remove(anchor.id); return }
        let matrix = anchor.originFromAnchorTransform
        var normal = normalize(SIMD3(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z))
        guard ceiling ? abs(normal.y) > 0.94 : abs(normal.y) < 0.18 else { remove(anchor.id); return }
        // Give opposite-facing estimates of the same plane the same normal.
        let dominant = ceiling ? 1 : abs(normal.x) > abs(normal.z) ? 0 : 2
        if normal[dominant] < 0 { normal = -normal }
        let source = anchor.geometry.meshVertices
        let faces = anchor.geometry.meshFaces
        guard source.count >= 3, faces.count > 0, source.componentsPerVector == 3,
              faces.bytesPerIndex == 2 || faces.bytesPerIndex == 4,
              faces.count * 3 * faces.bytesPerIndex <= faces.buffer.length else { remove(anchor.id); return }

        var vertices: [SIMD3<Float>] = []
        var signature = Hasher()
        signature.combine(ceiling)
        for axis in 0..<3 { signature.combine(Int((normal[axis] * 1000).rounded())) }
        for i in 0..<source.count {
            let offset = source.offset + i * source.stride
            guard offset + 12 <= source.buffer.length else { remove(anchor.id); return }
            let pointer = source.buffer.contents().advanced(by: offset).assumingMemoryBound(to: Float.self)
            // Mesh vertices use anchor coordinates, not rectangular-extent coordinates.
            let world4 = matrix * SIMD4(pointer[0], pointer[1], pointer[2], 1)
            let world = SIMD3(world4.x, world4.y, world4.z)
            guard world.x.isFinite, world.y.isFinite, world.z.isFinite,
                  max(abs(world.x), max(abs(world.y), abs(world.z))) < 1000 else { remove(anchor.id); return }
            vertices.append(world)
            for axis in 0..<3 { signature.combine(Int((world[axis] * 1000).rounded())) }
        }
        func index(_ i: Int) -> Int {
            let pointer = faces.buffer.contents().advanced(by: i * faces.bytesPerIndex)
            return faces.bytesPerIndex == 2
                ? Int(pointer.assumingMemoryBound(to: UInt16.self).pointee)
                : Int(pointer.assumingMemoryBound(to: UInt32.self).pointee)
        }
        var triangles: [[SIMD3<Float>]] = []
        for face in 0..<faces.count {
            let ids = (0..<3).map { index(face * 3 + $0) }
            guard ids.allSatisfy({ vertices.indices.contains($0) }) else { continue }
            for id in ids { signature.combine(id) }
            triangles.append(ids.map { vertices[$0] })
        }
        guard !triangles.isEmpty else { remove(anchor.id); return }
        let fingerprint = signature.finalize()
        if planes[anchor.id]?.signature == fingerprint { return }
        let center = vertices.reduce(SIMD3<Float>.zero, +) / Float(vertices.count)
        let order = planes[anchor.id]?.order ?? nextOrder
        if planes[anchor.id] == nil { nextOrder += 1 }
        planes[anchor.id] = Plane(id: anchor.id, triangles: triangles, normal: normal,
                                  center: center, ceiling: ceiling, order: order, signature: fingerprint)
        rebuildSurfaces()
    }

    private func matches(normal: SIMD3<Float>, center: SIMD3<Float>, ceiling: Bool, group: Group) -> Bool {
        ceiling == group.ceiling && dot(normal, group.normal) > 0.999
            && abs(dot(center - group.center, group.normal)) < 0.025
    }

    private func rebuildSurfaces() {
        var groups: [Group] = []
        for plane in planes.values.sorted(by: { $0.order < $1.order }) {
            if let index = groups.firstIndex(where: { matches(normal: plane.normal, center: plane.center,
                                                              ceiling: plane.ceiling, group: $0) }) {
                groups[index].planes.append(plane)
            } else {
                groups.append(Group(planes: [plane], normal: plane.normal, center: plane.center, ceiling: plane.ceiling))
            }
        }
        var unused = surfaces
        var next: [UUID: Surface] = [:]
        for group in groups {
            guard let id = group.planes.first?.id else { continue }
            var signature = Hasher()
            for plane in group.planes { signature.combine(plane.id); signature.combine(plane.signature) }
            let fingerprint = signature.finalize()
            if let existing = unused[id], existing.signature == fingerprint {
                next[id] = existing
                unused.removeValue(forKey: id)
                continue
            }
            // An orthonormal basis makes the cell dimensions equal on both axes,
            // including slightly tilted walls and ceilings. Every anchor on the
            // same surface uses this one world-registered lattice.
            let reference = group.ceiling ? SIMD3<Float>(1, 0, 0) : SIMD3<Float>(0, 1, 0)
            let v = normalize(reference - group.normal * dot(reference, group.normal))
            let u = normalize(cross(v, group.normal))
            var coverage: [[Vertex]] = []
            var footprint: [[Vertex]] = []
            for plane in group.planes {
                let triangles = plane.triangles.map { triangle in
                    triangle.map { Vertex(position: $0, uv: [dot($0, u), dot($0, v)]) }
                }.filter { area($0) > 0.0000001 }
                for triangle in triangles {
                    var fragments = [triangle]
                    // Give earlier anchors ownership of overlapping measured
                    // patches. Keep only uncovered pieces of later anchors,
                    // retaining their actual measured 3D positions.
                    for covered in coverage {
                        fragments = fragments.flatMap { subtract($0, coveredBy: covered) }
                        if fragments.isEmpty { break }
                    }
                    footprint += fragments
                }
                coverage += triangles
            }
            guard let mesh = makeGrid(footprint) else { continue }
            let surface: Surface
            if let existing = unused.removeValue(forKey: id) {
                surface = existing
            } else if let previous = unused.first(where: {
                matches(normal: $0.value.normal, center: $0.value.center, ceiling: $0.value.ceiling, group: group)
            }) {
                surface = previous.value
                unused.removeValue(forKey: previous.key)
            } else {
                surface = Surface(mesh: mesh, material: material, group: group)
                root.addChild(surface.entity)
            }
            surface.entity.model?.mesh = mesh
            surface.normal = group.normal
            surface.center = group.center
            surface.ceiling = group.ceiling
            surface.signature = fingerprint
            next[id] = surface
        }
        for surface in unused.values { surface.entity.removeFromParent() }
        surfaces = next
    }

    func remove(_ id: UUID) {
        guard planes.removeValue(forKey: id) != nil else { return }
        rebuildSurfaces()
    }

    func clear() {
        for surface in surfaces.values { surface.entity.removeFromParent() }
        surfaces.removeAll()
        planes.removeAll()
        nextOrder = 0
        pulseRemaining = 0
        lastOpacity = -1
    }
    func pulse() { pulseRemaining = 3.2 }
    func scan() { pulse() }

    func tick(deltaTime: Float, playing: Bool, head: SIMD3<Float>?) {
        guard deltaTime.isFinite, deltaTime > 0 else { return }
        let dt = min(deltaTime, 0.1)
        pulseRemaining = max(0, pulseRemaining - dt)
        guard root.isEnabled else { return }
        let lift: Float = reduceMotion ? 0 : sin((pulseRemaining / 3.2) * .pi) * 0.10
        for surface in surfaces.values {
            if let head {
                let sign: Float = dot(head - surface.center, surface.normal) >= 0 ? 1 : -1
                surface.entity.position = surface.normal * (sign * 0.002)
            }
            surface.reveal = min(1, surface.reveal + dt / 1.1)
            let reveal = surface.reveal * surface.reveal * (3 - 2 * surface.reveal)
            let base = surface.ceiling ? Style.ceilingOpacity : Style.wallOpacity
            // Pulse the existing grid; no second, wider line is layered over it.
            surface.entity.components.set(OpacityComponent(opacity: (base + lift) * reveal))
        }
        let opacity = Int((playing ? Style.playingOpacity : 1) * 100)
        if opacity != lastOpacity {
            root.components.set(OpacityComponent(opacity: Float(opacity) / 100))
            lastOpacity = opacity
        }
    }

    private func makeGrid(_ footprint: [[Vertex]]) -> MeshResource? {
        let points = footprint.flatMap { $0 }
        guard let first = points.first else { return nil }
        var lower = first.uv, upper = first.uv
        for point in points { lower = simd_min(lower, point.uv); upper = simd_max(upper, point.uv) }
        guard upper.x - lower.x < 30, upper.y - lower.y < 30 else { return nil }
        var polygons: [[Vertex]] = []
        for axis in 0..<2 {
            let start = Int(ceil(lower[axis] / Style.spacing))
            let end = Int(floor(upper[axis] / Style.spacing))
            guard start <= end else { continue }
            for index in start...end {
                let center = Float(index) * Style.spacing
                for polygon in footprint {
                    let a = clip(polygon, distance: { $0.uv[axis] - (center - Style.lineWidth / 2) })
                    let b = clip(a, distance: { center + Style.lineWidth / 2 - $0.uv[axis] })
                    if area(b) > 0.00000001 { polygons.append(b) }
                }
            }
        }
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for polygon in polygons {
            let first = UInt32(positions.count)
            positions += polygon.map(\.position)
            for i in 1..<(polygon.count - 1) { indices += [first, first + UInt32(i), first + UInt32(i + 1)] }
        }
        guard !indices.isEmpty else { return nil }
        var descriptor = MeshDescriptor(name: "Square surface grid")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }

    private func area(_ polygon: [Vertex]) -> Float {
        guard polygon.count >= 3 else { return 0 }
        var twiceArea: Float = 0
        for i in polygon.indices {
            let a = polygon[i].uv, b = polygon[(i + 1) % polygon.count].uv
            twiceArea += a.x * b.y - a.y * b.x
        }
        return abs(twiceArea) * 0.5
    }

    /// Subtract a convex triangle by keeping the outside of each edge, and
    /// passing only the still-inside piece to the next edge.
    private func subtract(_ polygon: [Vertex], coveredBy triangle: [Vertex]) -> [[Vertex]] {
        guard !polygon.isEmpty else { return [] }
        let lower = polygon.reduce(polygon[0].uv) { simd_min($0, $1.uv) }
        let upper = polygon.reduce(polygon[0].uv) { simd_max($0, $1.uv) }
        let otherLower = triangle.reduce(triangle[0].uv) { simd_min($0, $1.uv) }
        let otherUpper = triangle.reduce(triangle[0].uv) { simd_max($0, $1.uv) }
        if upper.x <= otherLower.x || otherUpper.x <= lower.x || upper.y <= otherLower.y || otherUpper.y <= lower.y {
            return [polygon]
        }
        let ab = triangle[1].uv - triangle[0].uv, ac = triangle[2].uv - triangle[0].uv
        let sign: Float = ab.x * ac.y - ab.y * ac.x >= 0 ? 1 : -1
        var remaining = polygon
        var outside: [[Vertex]] = []
        for i in 0..<3 {
            let a = triangle[i].uv, edge = triangle[(i + 1) % 3].uv - a
            func distance(_ vertex: Vertex) -> Float {
                let delta = vertex.uv - a
                return sign * (edge.x * delta.y - edge.y * delta.x)
            }
            let piece = clip(remaining, distance: { -distance($0) })
            if area(piece) > 0.0000001 { outside.append(piece) }
            remaining = clip(remaining, distance: distance)
            if remaining.count < 3 { break }
        }
        return outside
    }

    private func clip(_ polygon: [Vertex], distance: (Vertex) -> Float) -> [Vertex] {
        guard var previous = polygon.last else { return [] }
        var output: [Vertex] = []
        var previousDistance = distance(previous)
        for current in polygon {
            let currentDistance = distance(current)
            if (currentDistance >= 0) != (previousDistance >= 0) {
                let t = previousDistance / (previousDistance - currentDistance)
                output.append(Vertex(position: previous.position + (current.position - previous.position) * t,
                                     uv: previous.uv + (current.uv - previous.uv) * t))
            }
            if currentDistance >= 0 { output.append(current) }
            previous = current
            previousDistance = currentDistance
        }
        return output
    }
}
