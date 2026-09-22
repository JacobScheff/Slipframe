"""Read-only USDZ contract checks. Run with Blender's bundled USD Python.

blender --background --python Tools/Blender/validate_assets.py
No scene or assets are modified. XCTest separately verifies RealityKit import.
"""
from pathlib import Path
import itertools
import json
import math
import zipfile
from pxr import Gf, Usd, UsdGeom, UsdShade, Sdf

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / 'Endless Runner' / 'ArtAssets'
BIOMES = ['emberRun', 'summitStep', 'ghostGlass', 'lowCrawl', 'stormPass', 'crystalCave']
SHARED = '''rift_frame rift_aperture rift_energy junction_frame junction_aperture
track_segment rail_segment track_endcap start_pad token crystal_azure crystal_azure_charged
crystal_coral crystal_coral_charged crystal_combined fx_shard gust_ribbon glyph_risk glyph_aegis
glyph_overdrive glyph_precision glyph_lock glyph_magnet hazard_duck hazard_jump'''.split()


def check():
    manifest = json.loads((ART / 'manifest.json').read_text())
    records = {a['id']: a for a in manifest['assets']}
    expected = set(SHARED)
    for base in ['hazard_duck','hazard_jump','token','crystal_azure','crystal_coral','crystal_azure_charged','crystal_coral_charged']:
        expected.update(f'{base}_{i}' for i in [1,2])
    for biome in BIOMES:
        expected.update(f'wall_{biome}_{i}' for i in range(3))
        expected.update(f'{kind}_{biome}' for kind in ['floor', 'prop', 'preview', 'environment'])
        if biome != 'lowCrawl':
            expected.update(f'prop_{biome}_{i}' for i in [1, 2])
    assert len(records) == len(manifest['assets']) == len(expected)
    assert set(records) == expected
    assert {p.stem for p in ART.glob('*.usdz')} == expected
    bounds = {}
    for name, record in records.items():
        path = ART / record['file']
        with zipfile.ZipFile(path) as archive:
            entries = archive.infolist()
            members = set(archive.namelist())
            assert entries[0].filename.endswith(('.usdc', '.usd')), name
            for entry in entries:
                assert entry.compress_type == zipfile.ZIP_STORED, (name, 'compressed member')
                offset = entry.header_offset + 30 + len(entry.filename.encode()) + len(entry.extra)
                assert offset % 64 == 0, (name, 'unaligned USDZ member')
        stage = Usd.Stage.Open(str(path))
        assert stage and stage.GetDefaultPrim().IsValid(), name
        assert UsdGeom.GetStageUpAxis(stage) == 'Y', name
        assert abs(UsdGeom.GetStageMetersPerUnit(stage) - 1) < 1e-6, name
        assert not stage.GetStartTimeCode() and not stage.GetEndTimeCode(), name
        mesh_count = triangle_count = 0
        mesh_names = []
        for prim in stage.Traverse():
            if prim.IsA(UsdShade.Shader) and prim.GetParent().GetName().startswith('SF_NearInvisible_'):
                if prim.GetAttribute('info:id').Get() == 'UsdPreviewSurface':
                    opacity=prim.GetAttribute('inputs:opacity').Get()
                    assert opacity is not None and 0 < opacity <= .035001, (name,'opaque Ghost Glass export',prim.GetPath(),opacity)
            if prim.IsA(UsdGeom.Xformable):
                ops = UsdGeom.Xformable(prim).GetOrderedXformOps()
                assert not ops, (name, 'unbaked transform', prim.GetPath())
            for attr in prim.GetAttributes():
                if attr.GetTypeName() == Sdf.ValueTypeNames.Asset:
                    value = attr.Get()
                    if value and value.path:
                        relative = value.path.removeprefix('./')
                        assert relative in members, (name, 'external/missing dependency', relative)
                        if relative.endswith('_relief.png'):
                            assert prim.GetAttribute('inputs:sourceColorSpace').Get() == 'raw', (name, 'emission detail must stay linear')
            if not prim.IsA(UsdGeom.Mesh):
                continue
            mesh_count += 1
            mesh_names.append(prim.GetName())
            mesh = UsdGeom.Mesh(prim)
            if name.startswith(('wall_ghostGlass','prop_ghostGlass')):
                targets=[prim]+[child for child in prim.GetChildren() if child.IsA(UsdGeom.Subset)]
                for target in targets:
                    material,_=UsdShade.MaterialBindingAPI(target).ComputeBoundMaterial()
                    if material:
                        assert material.GetPrim().GetName().startswith('SF_NearInvisible_'), (name,'opaque ghost binding',target.GetPath())
            points = mesh.GetPointsAttr().Get()
            counts = mesh.GetFaceVertexCountsAttr().Get()
            indices = mesh.GetFaceVertexIndicesAttr().Get()
            assert points and all(math.isfinite(v) for p in points for v in p), name
            assert all(c == 3 for c in counts), (name, 'not triangulated')
            assert len(indices) == sum(counts) and all(0 <= i < len(points) for i in indices), name
            triangle_count += len(counts)
            if name.endswith('_aperture'):
                assert all(abs(p[2]) < 1e-5 for p in points), (name, 'mask not XY planar')
                for i in range(0, len(indices), 3):
                    p, q, r = [Gf.Vec3d(points[j]) for j in indices[i:i+3]]
                    assert Gf.Cross(q-p, r-p)[2] > 0, (name, 'mask faces away from player')
            if '__sky__' in prim.GetName():
                center = Gf.Vec3d(0, 0, -15)
                for i in range(0, len(indices), 3):
                    p, q, r = [Gf.Vec3d(points[j]) for j in indices[i:i+3]]
                    assert Gf.Dot(Gf.Cross(q-p, r-p), (p+q+r)/3-center) < 0, (name, 'outward sky face')
        assert mesh_count == record['meshCount'] and triangle_count == record['triangles'], name
        motion_role = {'environment_stormPass': '__motion_rotor__',
                       'environment_ghostGlass': '__motion_float__',
                       'environment_crystalCave': '__motion_float__'}.get(name)
        if motion_role:
            assert any(motion_role in part for part in mesh_names), (name, 'missing animation binding')
        cache = UsdGeom.BBoxCache(Usd.TimeCode.Default(), [UsdGeom.Tokens.default_, UsdGeom.Tokens.render])
        box = cache.ComputeWorldBound(stage.GetDefaultPrim()).ComputeAlignedRange()
        bounds[name] = box
        for computed, exported in [(box.GetMin(), record['boundsMin']), (box.GetMax(), record['boundsMax'])]:
            assert all(abs(a-b) < 1e-5 for a, b in zip(computed, exported)), name
        nominal = None
        if name.startswith('wall_'): nominal = (.7, 1.8, .7)
        if name.startswith('hazard_duck'): nominal = (2.5, .75, .595)
        if name.startswith('hazard_jump'): nominal = (2.5, .14, .22)
        if nominal:
            assert all(abs(a-b) < .0001 for a, b in zip(box.GetSize(), nominal)), (name, box.GetSize())
            assert box.GetMidpoint().GetLength() < .0001, (name, 'off-center hazard')
        if name.startswith('wall_'): assert triangle_count < 5000, name
        if name.startswith('environment_'): assert triangle_count < 25000, name
        if name.startswith('environment_'):
            assert any('__sky__' in part for part in mesh_names), (name, 'missing continuous sky')
            assert not any('__backdrop__' in part for part in mesh_names), (name, 'old flat enclosure')
            assert any('__distanceRoad__' in part for part in mesh_names), (name, 'road still ends early')
            assert any('__detail__portal' in part for part in mesh_names), (name, 'missing player-distance landmarks')
    # Worst-case variation bounds, including tilt, anisotropic scale and all corners.
    clearance = float('inf')
    for biome in BIOMES:
        if biome == 'lowCrawl': continue
        # Every new silhouette is contained by the original envelope, so the
        # following extreme rotation/scale test also bounds all the variants.
        box = bounds['prop_' + biome]
        for variant in [1, 2]:
            other = bounds[f'prop_{biome}_{variant}']
            assert all(a >= b-1e-5 for a, b in zip(other.GetMin(), box.GetMin())), (biome, variant)
            assert all(a <= b+1e-5 for a, b in zip(other.GetMax(), box.GetMax())), (biome, variant)
        natural = biome in ['emberRun', 'summitStep', 'crystalCave']
        for yaw, lean in itertools.product([-0.24, 0, .24] if natural else [-.08, 0, .08], [-.045, 0, .045] if natural else [0]):
            scale = 1.12 if natural else 1.05
            rotation = Gf.Rotation(Gf.Vec3d(0, 1, 0), math.degrees(yaw))
            tilt = Gf.Rotation(Gf.Vec3d(0, 0, 1), math.degrees(lean))
            for corner in itertools.product(*zip(box.GetMin(), box.GetMax())):
                point = Gf.Vec3d(corner[0] * scale, corner[1] * scale * (1.08 if natural else 1), corner[2] * scale)
                point = rotation.TransformDir(tilt.TransformDir(point))
                clearance = min(clearance, 3.05 - abs(point[0]))
    assert clearance > 1.85, ('scenery could enter the playable corridor', clearance)
    summary = dict(assets=len(records), triangles=sum(a['triangles'] for a in records.values()),
                   packageMiB=round(sum(a['bytes'] for a in records.values()) / 2**20, 2),
                   minimumSceneryInnerEdgeMeters=round(clearance, 3),
                   checks='self-contained aligned USDZ, Y-up meters, identity transforms, valid mesh data, +Z planar masks, exact collision envelopes, cosmetic clearance')
    print('ASSET VALIDATION PASSED\n' + json.dumps(summary, indent=2))


if __name__ == '__main__':
    check()
