import ARKit
import RealityKit
import UIKit
import simd

/// Sparse, visual-only lines in the local plane coordinates of detected room surfaces.
@MainActor
final class RoomGrid {
    let root = Entity()
    var reduceMotion = false

    private struct Surface {
        let entity: ModelEntity
        let size: SIMD2<Float>
    }

    private var surfaces: [UUID: Surface] = [:]
    private var pulseRemaining: Float = 0
    private var lastOpacity = -1
    private let color = UIColor(red: 0.40, green: 0.80, blue: 1, alpha: 1)

    func update(_ anchor: PlaneAnchor) {
        guard anchor.classification == .wall || anchor.classification == .ceiling else {
            remove(anchor.id)
            return
        }
        let extent = anchor.geometry.extent
        guard extent.width >= 0.85, extent.height >= 0.85 else {
            remove(anchor.id)
            return
        }

        // Round down so the outer lines stay inside the measured extent. The
        // mesh is rebuilt only when the usable surface changes by several cm.
        let size = SIMD2<Float>(
            floor(min(extent.width, 12) * 10) / 10,
            floor(min(extent.height, 12) * 10) / 10
        )
        let transform = Transform(matrix: anchor.originFromAnchorTransform * extent.anchorFromExtentTransform)
        if let existing = surfaces[anchor.id] {
            existing.entity.transform = transform
            if existing.size == size { return }
        }
        guard let mesh = makeLines(size: size) else { return }
        if let existing = surfaces[anchor.id] {
            existing.entity.model?.mesh = mesh
            surfaces[anchor.id] = Surface(entity: existing.entity, size: size)
        } else {
            let entity = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: color)])
            entity.transform = transform
            surfaces[anchor.id] = Surface(entity: entity, size: size)
            root.addChild(entity)
        }
    }

    func remove(_ id: UUID) {
        surfaces.removeValue(forKey: id)?.entity.removeFromParent()
    }

    func clear() {
        for surface in surfaces.values {
            surface.entity.removeFromParent()
        }
        surfaces.removeAll()
        pulseRemaining = 0
        lastOpacity = -1
    }

    func pulse() {
        pulseRemaining = 1.2
    }

    func tick(deltaTime: Float, playing: Bool) {
        pulseRemaining = max(0, pulseRemaining - deltaTime)
        let base: Float = playing ? 0.13 : 0.24
        let lift: Float = reduceMotion ? 0 : 0.16 * sin((pulseRemaining / 1.2) * .pi)
        let step = Int((base + lift) * 50)
        guard step != lastOpacity else { return }
        lastOpacity = step
        root.components.set(OpacityComponent(opacity: Float(step) / 50))
    }

    private func makeLines(size: SIMD2<Float>) -> MeshResource? {
        let half = size * 0.5 - SIMD2(repeating: 0.07)
        let spacing: Float = 0.5
        let lineHalfWidth: Float = 0.0015
        var vertices: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        func strip(x0: Float, x1: Float, z0: Float, z1: Float) {
            let first = UInt32(vertices.count)
            let y: Float = 0.008
            vertices += [[x0, y, z0], [x0, y, z1], [x1, y, z1], [x1, y, z0]]
            // Both sides face the room even when a plane's normal is reversed.
            indices += [first, first + 1, first + 2, first, first + 2, first + 3,
                        first + 2, first + 1, first, first + 3, first + 2, first]
        }

        let columns = Int((half.x - lineHalfWidth) / spacing)
        for column in -columns...columns {
            let x = Float(column) * spacing
            strip(x0: x - lineHalfWidth, x1: x + lineHalfWidth, z0: -half.y, z1: half.y)
        }
        let rows = Int((half.y - lineHalfWidth) / spacing)
        for row in -rows...rows {
            let z = Float(row) * spacing
            strip(x0: -half.x, x1: half.x, z0: z - lineHalfWidth, z1: z + lineHalfWidth)
        }

        var descriptor = MeshDescriptor(name: "Room grid")
        descriptor.positions = MeshBuffers.Positions(vertices)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }
}
