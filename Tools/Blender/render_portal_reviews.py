"""Player-distance composition checks, not a RealityKit lighting simulation.

Matches the authored main aperture (1.84 x 1.28 radii), 8 m default distance,
3.5--10 m placement range, and a 1.6 m eye above the floor. The opaque surround
is review-only: nothing in this file is exported to the game.
"""
from pathlib import Path
import bpy
import bmesh
import math
import runpy
import sys
from collections import Counter
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
H = runpy.run_path(str(ROOT/'Tools/Blender/render_backgrounds.py'), run_name='review_helpers')


def setup(key, distance=8, eye_x=0, eye_z=.35):
    scene = H['setup'](key)
    scene.view_layers[0].update()
    # RealityKit's portal clips background geometry at the portal plane. Apply
    # the same half-space to review copies (never to the source or exports).
    for obj in scene.objects:
        if obj.type != 'MESH':
            continue
        obj.data = obj.data.copy()
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        plane = obj.matrix_world.inverted() @ Vector((0, .02, 0))
        bmesh.ops.bisect_plane(bm, geom=list(bm.verts)+list(bm.edges)+list(bm.faces),
                              plane_co=plane, plane_no=(0, 1, 0),
                              clear_inner=True, clear_outer=False)
        bm.to_mesh(obj.data)
        bm.free()
    scene.name = 'PortalReview_' + key + '_' + str(distance) + 'm'
    scene.render.resolution_x = 1200
    scene.render.resolution_y = 800
    H['helpers']['camera_at'](scene, (eye_x, -distance, eye_z), (0, 0, 0),
                              24 if distance < 4 else 32)
    # Hole is exactly the exported ellipse, not a rectangular crop or a wide
    # beauty camera. The camera can only see scenery through this opening.
    material = bpy.data.materials.new('PortalReview_surround')
    node = next(n for n in material.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    node.inputs['Base Color'].default_value = (.008, .011, .016, 1)
    node.inputs['Emission Color'].default_value = (.008, .011, .016, 1)
    node.inputs['Emission Strength'].default_value = 1
    vertices, faces = [], []
    for i in range(128):
        t = i*math.tau/128
        vertices.extend([(1.84*math.cos(t), -.01, 1.28*math.sin(t)),
                         (500*math.cos(t), -.01, 500*math.sin(t))])
    for i in range(128):
        j = (i+1) % 128
        faces.append((2*i, 2*i+1, 2*j+1, 2*j))
    mesh = bpy.data.meshes.new('ReviewOnly_aperture_mask')
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(material)
    obj = bpy.data.objects.new('ReviewOnly_aperture_mask', mesh)
    scene.collection.objects.link(obj)
    H['helpers']['copy_asset'](scene, 'rift_frame')
    scene['review_only'] = True
    scene['portal_distance_m'] = distance
    scene['eye_height_m'] = 1.25 + eye_z
    scene['aperture_radii_m'] = [1.84, 1.28]
    return scene


def render(key, distance=8, eye_x=0, eye_z=.35, suffix=''):
    scene = setup(key, distance, eye_x, eye_z)
    scene.render.filepath = str(ROOT/'Art/Previews'/f'{key}-portal-{distance}m{suffix}.png')
    bpy.ops.render.render(write_still=True)
    print('PORTAL REVIEW', key, distance, eye_x, eye_z, flush=True)
    return scene


def check_sightlines(scene, columns=100, rows=70):
    """Trace first-hit visibility through the real ellipse, including occlusion."""
    bpy.context.window.scene = scene
    scene.view_layers[0].update()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    origin = scene.camera.location.copy()
    hits = Counter()
    for i in range(columns):
        x = 1.84*(2*(i+.5)/columns-1)
        for j in range(rows):
            z = 1.28*(2*(j+.5)/rows-1)
            if (x/1.84)**2+(z/1.28)**2 >= .95**2:
                continue
            opening = Vector((x,0,z))
            direction = (opening-origin).normalized()
            hit,location,normal,index,obj,matrix = scene.ray_cast(
                depsgraph, opening+direction*.03, direction, distance=350)
            if hit:
                label = 'new_landmark' if '__detail__portal' in obj.name else obj.name.split('__')[1] if '__' in obj.name else obj.name
                hits[label] += 1
    assert hits['body'] > 0, ('Original structures not visible',scene.name,hits)
    assert hits['new_landmark'] > 0, ('New landmarks entirely occluded',scene.name,hits)
    print('SIGHTLINE CHECK',scene.name,'eye',tuple(origin),dict(hits),flush=True)
    return dict(hits)


if __name__ == '__main__':
    args = sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    keys = args or H['helpers']['BIOMES']
    for key in keys:
        scene = render(key)
        check_sightlines(scene)
        original = scene.camera.location.copy()
        for x,z in [(0,.35),(-.6,.15),(.6,.55)]:
            scene.camera.location = (x,-10,z)
            check_sightlines(scene)
        scene.camera.location = original
    if not args:
        render('summitStep', 3.5)
        check_sightlines(render('summitStep', 10))
        check_sightlines(render('summitStep', 10, .6, .55, '-right'))
        check_sightlines(render('summitStep', 10, -.6, .15, '-left'))
