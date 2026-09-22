"""Incremental background pass on the saved library; never rebuild portal assets.

Run once in the live Blender file, then use export_from_source for later edits.
Background-only materials bake a restrained directional fill into USD emission,
so facets survive RealityKit's zero environment-light weight inside the portal.
"""
from pathlib import Path
import bpy
import json
import math
import random
import runpy
import numpy as np
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
module = runpy.run_path(str(ROOT / 'Tools/Blender/refine_slipframe.py'), run_name='background_helpers')
sf = module['sf']
A, M = sf['Asset'], sf['MATS']
BIOMES = list(sf['BIOMES'])
VARIED = [key for key in BIOMES if key != 'lowCrawl']
SKIES = {
    'summitStep': ((.065, .15, .27), (.36, .48, .54)),
    'emberRun': ((.013, .012, .026), (.12, .055, .031)),
    'ghostGlass': ((.025, .055, .10), (.15, .24, .29)),
    'lowCrawl': ((.006, .014, .028), (.024, .065, .10)),
    'stormPass': ((.018, .033, .075), (.095, .15, .21)),
    'crystalCave': ((.016, .010, .043), (.085, .045, .15)),
}


def shader(material):
    return next(n for n in material.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')


def merge_additions(asset, target):
    """Append generated meshes to an existing asset without replacing its artwork."""
    asset.finish()
    temporary = sf['ASSETS'].pop(asset.name)
    for obj in list(temporary['collection'].objects):
        if obj.type != 'MESH':
            continue
        temporary['collection'].objects.unlink(obj)
        target['collection'].objects.link(obj)
        obj.parent = target['root']
        obj.name = obj.name.replace(asset.name, target['root']['asset_id'])
        obj.data.name = obj.name
    bpy.data.objects.remove(temporary['root'], do_unlink=True)
    bpy.data.collections.remove(temporary['collection'])


def sky_dome(key, target):
    # Opaque, inward-facing enclosure with a portable baked sky gradient. No
    # volume fog, no flat back wall, and no alpha blending with passthrough.
    top, horizon = [np.array(c) for c in SKIES[key]]
    width, height = 256, 128
    yy, xx = np.mgrid[0:height, 0:width]
    elevation = np.sin((yy / (height - 1) - .5) * math.pi)
    warmth = np.exp(-np.abs(elevation) * 4.5)
    rgb = top + (horizon - top) * warmth[..., None]
    cloud = np.sin(xx * math.tau / width * 3 + elevation * 23) * np.sin(elevation * 41)
    rgb *= (1 + cloud[..., None] * .035)
    pixels = np.ones((height, width, 4), dtype=np.float32)
    pixels[:, :, :3] = rgb
    tex = bpy.data.images.new('SF_' + key + '_skyGradient', width=width, height=height, alpha=False)
    tex.pixels.foreach_set(pixels.ravel())
    tex.filepath_raw = str(sf['SOURCE'] / 'Textures' / (key + '_sky.png'))
    formats = tex.bl_rna.properties['file_format'].enum_items.keys()
    assert 'PNG' in formats
    tex.file_format = 'PNG'
    tex.save()
    material = sf['material']('SF_' + key + '_skyDome', tuple(horizon), 0, 1, 1, texture=tex)
    node = next(n for n in material.node_tree.nodes if n.type == 'TEX_IMAGE')
    material.node_tree.links.new(node.outputs['Color'], shader(material).inputs['Emission Color'])
    # 32 x 16 is ample at this distance, with separate UVs at the seam.
    segments, rings, radius = 32, 16, 140
    verts = [(0, 15, -radius)]
    for row in range(1, rings):
        latitude = -math.pi / 2 + row * math.pi / rings
        for i in range(segments):
            angle = i * math.tau / segments
            verts.append((radius * math.cos(latitude) * math.cos(angle),
                          15 + radius * math.cos(latitude) * math.sin(angle), radius * math.sin(latitude)))
    verts.append((0, 15, radius))
    faces = []
    for i in range(segments):
        j = (i + 1) % segments
        faces.append((0, 1 + i, 1 + j))
        for row in range(rings - 2):
            a, b = 1 + row * segments, 1 + (row + 1) * segments
            faces.append((a + i, b + i, b + j, a + j))
        a = 1 + (rings - 2) * segments
        faces.append((a + i, len(verts) - 1, a + j))
    mesh = bpy.data.meshes.new(key + '_skyDome')
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    uv = mesh.uv_layers.new(name='st')
    for face in mesh.polygons:
        values = []
        for vi in face.vertices:
            p = Vector(verts[vi]) - Vector((0, 15, 0))
            values.append((math.atan2(p.y, p.x) / math.tau % 1, math.asin(p.z / radius) / math.pi + .5))
        if max(u for u, v in values) - min(u for u, v in values) > .5:
            values = [(u + 1 if u < .5 else u, v) for u, v in values]
        for li, value in zip(face.loop_indices, values):
            uv.data[li].uv = value
    assert all(p.normal.dot(p.center - Vector((0, 15, 0))) < 0 for p in mesh.polygons)
    obj = bpy.data.objects.new('environment_' + key + '__sky__gradient', mesh)
    target['collection'].objects.link(obj)
    obj.parent = target['root']
    mesh.materials.append(material)


def directional_fill(target, key):
    light = Vector((-.55, -.70, .85)).normalized()
    for obj in target['collection'].objects:
        if obj.type != 'MESH' or '__body__' not in obj.name or obj.get('background_fill'):
            continue
        source = obj.data.materials[0]
        color = np.array(source.diffuse_color[:3])
        # Dark industrial plates get a small ambient floor; alpine stone gets
        # stronger warm/cool facet separation. Shared source materials are copied.
        color = np.maximum(color, (.055, .063, .075))
        if key == 'summitStep':
            color = np.maximum(color, (.28, .30, .32))
        obj.data.materials.clear()
        for band, weight in enumerate([.34, .52, .74, 1.0]):
            name = 'SF_BG_' + key + '_' + source.name + '_' + str(band)
            mat = bpy.data.materials.get(name)
            if mat is None:
                mat = source.copy()
                mat.name = name
                node = shader(mat)
                tint = np.array((1.10, 1.01, .88)) if band >= 2 else np.array((.88, .99, 1.15))
                node.inputs['Emission Color'].default_value = (*np.clip(color * tint * weight, 0, 1), 1)
                node.inputs['Emission Strength'].default_value = .82 if key == 'summitStep' else .62
                node.inputs['Metallic'].default_value = min(node.inputs['Metallic'].default_value, .3)
            obj.data.materials.append(mat)
        for face in obj.data.polygons:
            diffuse = max(0, face.normal.dot(light))
            face.material_index = min(3, int(diffuse * 4))
        obj['background_fill'] = True


def distant_world(key, target):
    a = A('background_extension_' + key, key)
    r = random.Random(814 + BIOMES.index(key))
    horizon = np.array(SKIES[key][1])
    for layer in range(3):
        mat = key + '_distance_' + str(layer)
        tint = horizon * (.42 + layer * .17)
        M[mat] = sf['material']('SF_' + mat, tuple(tint), 0, 1, 1)
        # Continuous irregular ridge silhouettes, separated by real depth. A
        # central valley leaves the lane's vanishing point open until 100 m.
        y = 45 + layer * 23
        xs = list(range(-105, 106, 7))
        heights = [-2 + (6 + r.random() * (11 if key == 'summitStep' else 6) + layer)
                   * min(1, abs(x) / 20) for x in xs]
        for i in range(len(xs) - 1):
            a.add([(xs[i], y, -4), (xs[i+1], y, -4),
                   (xs[i+1], y, heights[i+1]), (xs[i], y, heights[i])], [[0, 1, 2, 3]], mat, 'horizon')
        if key == 'summitStep':
            for i in range(0, len(xs), 3):
                x, h = xs[i], heights[i]
                a.add([(x-2.0, y-.05, h-1.6), (x, y-.05, h), (x+2.4, y-.05, h-1.1)],
                      [[0, 1, 2]], mat, 'horizon')
    ground = key + '_distance_0'
    a.box((0, 49, -1.47), (220, 104, .12), ground, 0, role='terrain')
    # Continue the physical road past its former 27 m cutoff. Guide emission
    # falls away in depth, avoiding a conspicuous terminal stripe or back plate.
    for i in range(18):
        y = 27.6 + i * 3.25
        layer = min(2, i // 6)
        band = i // 3
        road = key + '_road_' + str(band)
        if road not in M:
            fade = (band / 5) ** .7
            near = np.array(M[key].diffuse_color[:3]) * .32
            tint = near * (1-fade) + horizon * .42 * fade
            M[road] = sf['material']('SF_' + road, tuple(tint), 0, .9, 1)
        a.box((0, y, -1.25), (3.1, 3.27, .035), road, 0, role='distanceRoad')
        if i < 13:
            line = key + '_guide_' + str(layer)
            if line not in M:
                tint = np.array(sf['BIOMES'][key]['accent']) * (.22 - layer * .065)
                M[line] = sf['material']('SF_' + line, tuple(tint), 0, 1, 1)
            for x in [-.75, 0, .75]:
                a.box((x, y, -1.225), (.016, 3.24, .009), line, 0, role='distanceLane')
    if key == 'lowCrawl':
        # Offset equipment bays and diminishing ribs extend the service tunnel.
        for y in [30, 36, 44, 54, 66, 80]:
            for side in [-1, 1]:
                a.box((side*2.35, y, .15), (.21, .30, 2.8), key+'_distance_1', 0, role='distanceStructure')
                a.box((side*2.03, y-.16, .7), (.026, .025, .40), key+'_guide_0', 0, role='distanceLight')
            a.box((0, y, 1.62), (4.9, .30, .20), key+'_distance_1', 0, role='distanceStructure')
        a.box((0, 56, 2.35), (6.5, 58, .20), ground, 0, role='distanceStructure')
    elif key in ['ghostGlass', 'stormPass']:
        for y in [35, 45, 59, 76]:
            for side in [-1, 1]:
                x = side * (4.1 + r.random()*1.6)
                a.beam((x, y, -1.3), (x-side*.7, y, 6+r.random()*3), .22, .3,
                       key+'_distance_1', 'distanceStructure')
                if key == 'ghostGlass':
                    a.gem((x, y, 2.8), .38, 5.3, key+'_distance_2', 5, role='distanceStructure', tilt=side*.17)
    elif key == 'crystalCave':
        for y in [34, 43, 57, 72]:
            for side in [-1, 1]:
                for j in range(3):
                    a.gem((side*(3.8+j*1.4), y, 2.4+j), .55, 6+j,
                          key+'_distance_'+str(j), 5, role='distanceStructure', tilt=-side*.19)
    elif key == 'emberRun':
        for side in [-1, 1]:
            for y in [34, 46, 62, 78]:
                a.prism((side*(4+r.random()*2), y, 2), 1.6, 6, key+'_distance_1', 7, role='distanceStructure')
                a.box((side*3.7, y, -1.26), (.6, 10, .02), key+'_guide_1', 0, role='distanceLight')
    merge_additions(a, target)


def prop_variants(key):
    # Distinct arrangements share the original prop's envelope, guaranteeing
    # existing grounding and worst-case corridor clearance still apply.
    original = sf['ASSETS']['prop_' + key]
    vertices = [v.co for o in original['collection'].objects if o.type == 'MESH' for v in o.data.vertices]
    low = np.min([tuple(v) for v in vertices], axis=0)
    high = np.max([tuple(v) for v in vertices], axis=0)
    for variant in [1, 2]:
        name = 'prop_' + key + '_' + str(variant)
        assert name not in sf['ASSETS'], 'Variant already exists: ' + name
        a = A(name, key)
        if key in ['emberRun', 'summitStep', 'crystalCave']:
            if variant == 1:
                module['prop'](a, key, (0, 0, 0), .72, seed=73)
                module['prop'](a, key, (.42, .14, 0), .48, seed=192)
            else:
                module['prop'](a, key, (0, 0, 0), .9, seed=218)
                module['rock'](a, (-.40, -.12, .20), (.8, .7, .4), key, 92, snow=key=='summitStep')
        elif key == 'stormPass':
            module['prop'](a, key, (0, 0, 0), .85, seed=variant)
            if variant == 1:
                a.box((.43, 0, .55), (.36, .6, 1.1), key, .04)
                a.beam((.43, 0, .9), (.48, 0, 1.95), .05, .06, 'silver')
            else:
                a.ring(.28, .28, .055, .13, key, 18, pos=(-.28, -.07, 1.0))
                a.box((.30, .08, .6), (.28, .45, 1.2), key, .03)
        else:
            for i in range(3 if variant == 1 else 5):
                height = (1.2 + ((i*7+variant)%5)*.32)
                a.gem(((i-1)*.28, (i%2)*.18, height*.5), .18, height,
                      key+'_pale', 4, tilt=(i-1)*.14)
                a.beam(((i-1)*.28, -.08, .15), ((i-1)*.28+.05, -.08, height*.8),
                       .012, .018, key+'_glow', 'accent')
        allv = np.array([v for vs, fs in a.parts.values() for v in vs])
        lo, hi = allv.min(axis=0), allv.max(axis=0)
        size = (high-low) * np.array((.96, .96, .82 if variant == 1 else .97))
        for part, (vs, faces) in list(a.parts.items()):
            a.parts[part] = ([tuple((np.array(v)-lo)/(hi-lo)*size+low) for v in vs], faces)
        a.finish()
        directional_fill(sf['ASSETS'][name], key)


def run():
    scene = bpy.data.scenes[sf['SCENE_NAME']]
    assert not scene.get('background_refinement_v1'), 'Pass already applied; edit the saved source directly.'
    bpy.context.window.scene = scene
    changed = []
    for key in BIOMES:
        target = sf['ASSETS']['environment_' + key]
        # The wider horizon domes need more room on the source-library racks.
        target['root'].location = (BIOMES.index(key)*350, 400, 0)
        for obj in list(target['collection'].objects):
            if '__backdrop__' in obj.name:
                mesh = obj.data
                bpy.data.objects.remove(obj, do_unlink=True)
                if mesh.users == 0:
                    bpy.data.meshes.remove(mesh)
        sky_dome(key, target)
        directional_fill(target, key)
        directional_fill(sf['ASSETS']['prop_' + key], key)
        distant_world(key, target)
        changed.extend(['environment_'+key, 'prop_'+key])
        if key in VARIED:
            prop_variants(key)
            changed.extend(['prop_'+key+'_1', 'prop_'+key+'_2'])
    scene['background_refinement_v1'] = True
    scene['background_refinement_assets'] = json.dumps(changed)
    sf['save_source']()
    print('Refined backgrounds and props:', changed)


def refresh_distance():
    """Rebuild only this pass's additions after art-review adjustments."""
    for key in BIOMES:
        target = sf['ASSETS']['environment_' + key]
        target['root'].location = (BIOMES.index(key)*350, 400, 0)
        roles = ['horizon', 'terrain', 'distanceRoad', 'distanceLane',
                 'distanceStructure', 'distanceLight']
        for obj in list(target['collection'].objects):
            if any('__'+role+'__' in obj.name for role in roles):
                mesh = obj.data
                bpy.data.objects.remove(obj, do_unlink=True)
                if mesh.users == 0:
                    bpy.data.meshes.remove(mesh)
        # Recovered material keys may refer to the previous review's palette.
        for suffix in range(18):
            M.pop(key+'_road_'+str(suffix), None)
        distant_world(key, target)
    sf['save_source']()


def export():
    scene = bpy.data.scenes[sf['SCENE_NAME']]
    changed = json.loads(scene['background_refinement_assets'])
    updates = {record['id']: record for record in sf['export_assets'](changed)}
    path = sf['RUNTIME'] / 'manifest.json'
    manifest = json.loads(path.read_text())
    records = {record['id']: record for record in manifest['assets']}
    records.update(updates)
    manifest['assets'] = list(records.values())
    path.write_text(json.dumps(manifest, indent=2)+'\n')
    print('Exported', len(updates), 'background assets; retained all other packages byte-for-byte.')


if __name__ == '__main__':
    run()
    export()
