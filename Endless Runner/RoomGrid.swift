import ARKit
import RealityKit
import UIKit
import simd

/// Ink on measured surfaces, never a room-sized wireframe or a fallback box.
/// Every strip is intersected with ARKit's actual plane triangles.
@MainActor
final class RoomGrid {
    let root = Entity()
    var reduceMotion = false

    private struct Vertex {
        var position: SIMD3<Float>
        var uv: SIMD2<Float>
    }
    private struct Echo {
        let entity: ModelEntity
        let delay: Float
    }
    @MainActor
    private final class Surface {
        let entity: Entity
        let lines: ModelEntity
        let accents: ModelEntity
        var echoes: [Echo] = []
        var signature: Int
        var reveal: Float = 0

        init(mesh: MeshResource, color: UIColor, signature: Int) {
            entity = Entity()
            lines = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: color)])
            accents = ModelEntity()
            self.signature = signature
            entity.addChild(lines)
            entity.addChild(accents)
            entity.components.set(OpacityComponent(opacity: 0))
        }
    }
    private var surfaces: [UUID: Surface] = [:]
    private var pulseRemaining: Float = 0
    private var elapsed: Float = 0
    private var lastOpacity = -1
    private var accentColor = UIColor(red: 0.59, green: 0.81, blue: 0.91, alpha: 1)
    private let ink = UIColor(red: 0.55, green: 0.78, blue: 0.88, alpha: 1)

    func setTint(_ color: UIColor) {
        accentColor = EnvironmentMaterials.lerpColor(ink, color, 0.30)
        for surface in surfaces.values {
            surface.accents.model?.materials = [UnlitMaterial(color: accentColor)]
            for echo in surface.echoes { echo.entity.model?.materials = [UnlitMaterial(color: accentColor)] }
        }
    }

    func update(_ anchor: PlaneAnchor) {
        let ceiling = anchor.classification == .ceiling
        guard ceiling || anchor.classification == .wall else { remove(anchor.id); return }
        let matrix = anchor.originFromAnchorTransform
        let normal = normalize(SIMD3(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z))
        // Classification can settle before orientation; wait for both to agree.
        guard ceiling ? abs(normal.y) > 0.94 : abs(normal.y) < 0.18 else { remove(anchor.id); return }
        let source = anchor.geometry.meshVertices
        let faces = anchor.geometry.meshFaces
        guard source.count >= 3, faces.count > 0, source.componentsPerVector == 3,
              faces.bytesPerIndex == 2 || faces.bytesPerIndex == 4 else { remove(anchor.id); return }
        // Mesh vertices are in ANCHOR coordinates. Extent's transform belongs
        // only to the rectangular extent and must not be applied to this mesh.
        let tangent = ceiling ? SIMD3<Float>(1, 0, 0) : normalize(cross(SIMD3(0, 1, 0), normal))
        var vertices: [Vertex] = []
        for i in 0..<source.count {
            let offset = source.offset + i * source.stride
            guard offset + 12 <= source.buffer.length else { remove(anchor.id); return }
            let pointer = source.buffer.contents().advanced(by: offset).assumingMemoryBound(to: Float.self)
            let local = SIMD3(pointer[0], pointer[1], pointer[2])
            let world4 = matrix * SIMD4(local, 1)
            let world = SIMD3(world4.x, world4.y, world4.z)
            guard local.x.isFinite, local.y.isFinite, local.z.isFinite,
                  world.x.isFinite, world.y.isFinite, world.z.isFinite else { remove(anchor.id); return }
            vertices.append(Vertex(position: local, uv: [dot(world, tangent), ceiling ? world.z : world.y]))
        }
        guard faces.count * 3 * faces.bytesPerIndex <= faces.buffer.length else { remove(anchor.id); return }
        func index(_ i: Int) -> Int {
            let pointer = faces.buffer.contents().advanced(by: i * faces.bytesPerIndex)
            return faces.bytesPerIndex == 2
                ? Int(pointer.assumingMemoryBound(to: UInt16.self).pointee)
                : Int(pointer.assumingMemoryBound(to: UInt32.self).pointee)
        }
        var triangles: [[Vertex]] = []
        var signature = Hasher()
        signature.combine(ceiling)
        // Ignore sub-millimeter refinements instead of repeatedly rebuilding
        // identical line meshes as the room estimate settles.
        for column in 0..<4 {
            for row in 0..<4 { signature.combine(Int((matrix[column][row] * 1000).rounded())) }
        }
        for vertex in vertices {
            for axis in 0..<3 { signature.combine(Int((vertex.position[axis] * 1000).rounded())) }
        }
        for face in 0..<faces.count {
            let ids = (0..<3).map { index(face * 3 + $0) }
            guard ids.allSatisfy({ vertices.indices.contains($0) }) else { continue }
            for id in ids { signature.combine(id) }
            triangles.append(ids.map { vertices[$0] })
        }
        guard !triangles.isEmpty else { remove(anchor.id); return }
        let geometrySignature = signature.finalize()
        if let surface = surfaces[anchor.id], surface.signature == geometrySignature {
            surface.entity.transform = Transform(matrix: matrix)
            return
        }
        var linePolygons: [[Vertex]] = []
        var accentPolygons: [[Vertex]] = []
        var echoPolygons: [(polygons: [[Vertex]], delay: Float)] = []
        let minU = vertices.map { $0.uv.x }.min() ?? 0
        let maxU = vertices.map { $0.uv.x }.max() ?? 0
        let minV = vertices.map { $0.uv.y }.min() ?? 0
        let maxV = vertices.map { $0.uv.y }.max() ?? 0
        guard maxU - minU < 30, maxV - minV < 30 else { remove(anchor.id); return }
        // Global height registration makes horizontal traces meet at corners.
        for axis in 0..<2 {
            let spacing: Float = axis == 0 ? 1.25 : 0.85
            let first = Int(ceil((axis == 0 ? minU : minV) / spacing))
            let last = Int(floor((axis == 0 ? maxU : maxV) / spacing))
            guard first <= last else { continue }
            for i in first...last {
                let height = Float(i) * spacing
                linePolygons += bands(triangles, axis: axis, center: height, width: 0.0018)
                if !ceiling, axis == 1, height > 0, height < 3.5 {
                    echoPolygons.append((bands(triangles, axis: 1, center: height, width: 0.005),
                                         min(0.62, height / 3.5 * 0.62)))
                }
            }
        }
        if ceiling {
            // Contour arcs etched onto the ceiling, clipped at every measured edge.
            for radius: Float in [1.4, 2.6, 3.8] {
                var ringPolygons: [[Vertex]] = []
                for segment in 0..<96 where segment % 12 < 8 {
                    let a = Float(segment) / 96 * 2 * Float.pi
                    let b = Float(segment + 1) / 96 * 2 * Float.pi
                    ringPolygons += clippedStroke(triangles, from: SIMD2(cos(a), sin(a)) * radius,
                                                 to: SIMD2(cos(b), sin(b)) * radius, width: 0.003)
                }
                accentPolygons += ringPolygons
                echoPolygons.append((ringPolygons, 0.62 + radius / 3.8 * 0.16))
            }
        } else {
            for height: Float in [2.12, 2.15] {
                accentPolygons += bands(triangles, axis: 1, center: height, width: 0.0025)
            }
        }
        guard let lineMesh = mesh(linePolygons, name: "Surface traces") else { remove(anchor.id); return }
        let surface: Surface
        if let existing = surfaces[anchor.id] {
            surface = existing
            surface.signature = geometrySignature
            surface.lines.model?.mesh = lineMesh
        } else {
            surface = Surface(mesh: lineMesh, color: ink, signature: geometrySignature)
            root.addChild(surface.entity)
        }
        surface.entity.transform = Transform(matrix: matrix)
        if let accentMesh = mesh(accentPolygons, name: "Surface contours") {
            surface.accents.model = ModelComponent(mesh: accentMesh, materials: [UnlitMaterial(color: accentColor)])
        } else { surface.accents.model = nil }
        surface.lines.components.set(OpacityComponent(opacity: ceiling ? 0.055 : 0.10))
        surface.accents.components.set(OpacityComponent(opacity: 0.14))
        for echo in surface.echoes { echo.entity.removeFromParent() }
        surface.echoes = echoPolygons.compactMap { entry in
            guard let echoMesh = mesh(entry.polygons, name: "Surface echo") else { return nil }
            let entity = ModelEntity(mesh: echoMesh, materials: [UnlitMaterial(color: accentColor)])
            entity.isEnabled = false
            surface.entity.addChild(entity)
            return Echo(entity: entity, delay: entry.delay)
        }
        surfaces[anchor.id] = surface
    }

    func remove(_ id: UUID) { surfaces.removeValue(forKey: id)?.entity.removeFromParent() }
    func clear() {
        for surface in surfaces.values { surface.entity.removeFromParent() }
        surfaces.removeAll()
        pulseRemaining = 0
        lastOpacity = -1
        elapsed = 0
    }
    func pulse() { pulseRemaining = 3.2 }
    func scan() { pulse() }

    func tick(deltaTime: Float, playing: Bool, head: SIMD3<Float>?) {
        guard deltaTime.isFinite, deltaTime > 0 else { return }
        let dt = min(deltaTime, 0.1)
        elapsed += dt
        pulseRemaining = max(0, pulseRemaining - dt)
        guard root.isEnabled else { return }
        let p = 1 - pulseRemaining / 3.2
        for surface in surfaces.values {
            // Two mm toward the observer, with no extrusion into the room.
            if let head {
                let local = surface.entity.convert(position: head, from: nil)
                let offset: Float = local.y >= 0 ? 0.002 : -0.002
                surface.lines.position.y = offset
                surface.accents.position.y = offset
                for echo in surface.echoes { echo.entity.position.y = offset * 1.25 }
            }
            surface.reveal = min(1, surface.reveal + dt / 1.1)
            surface.entity.components.set(OpacityComponent(opacity: surface.reveal * surface.reveal * (3 - 2 * surface.reveal)))
            let breathing: Float = reduceMotion ? 1 : 0.92 + sin(elapsed * 0.35) * 0.08
            surface.accents.components.set(OpacityComponent(opacity: 0.14 * breathing))
            // Geometry stays fixed. A smooth opacity wave climbs shared wall
            // heights, then reaches the ceiling arcs, with no frame-time meshing.
            for echo in surface.echoes {
                let phase = (p - echo.delay) / 0.22
                let visible = pulseRemaining > 0 && !reduceMotion && phase > 0 && phase < 1
                echo.entity.isEnabled = visible
                if visible { echo.entity.components.set(OpacityComponent(opacity: sin(phase * .pi) * 0.10)) }
            }
        }
        let opacity = Int((playing ? Float(0.60) : 1) * 100)
        if opacity != lastOpacity {
            root.components.set(OpacityComponent(opacity: Float(opacity) / 100))
            lastOpacity = opacity
        }
    }

    private func bands(_ triangles: [[Vertex]], axis: Int, center: Float, width: Float) -> [[Vertex]] {
        triangles.compactMap { triangle in
            let a = clip(triangle, distance: { $0.uv[axis] - (center - width / 2) })
            let b = clip(a, distance: { (center + width / 2) - $0.uv[axis] })
            return b.count >= 3 ? b : nil
        }
    }

    private func clippedStroke(_ triangles: [[Vertex]], from p: SIMD2<Float>, to q: SIMD2<Float>, width: Float) -> [[Vertex]] {
        let direction = normalize(q - p), normal = SIMD2(-(q - p).y, (q - p).x) / length(q - p)
        return triangles.compactMap { triangle in
            var polygon = clip(triangle, distance: { dot($0.uv - p, direction) })
            polygon = clip(polygon, distance: { dot(q - $0.uv, direction) })
            polygon = clip(polygon, distance: { dot($0.uv - p, normal) + width / 2 })
            polygon = clip(polygon, distance: { width / 2 - dot($0.uv - p, normal) })
            return polygon.count >= 3 ? polygon : nil
        }
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

    private func mesh(_ polygons: [[Vertex]], name: String) -> MeshResource? {
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for polygon in polygons where polygon.count >= 3 {
            let first = UInt32(positions.count)
            positions += polygon.map(\.position)
            for i in 1..<(polygon.count - 1) {
                let b = first + UInt32(i), c = b + 1
                indices += [first, b, c, c, b, first]
            }
        }
        guard !indices.isEmpty else { return nil }
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }
}
