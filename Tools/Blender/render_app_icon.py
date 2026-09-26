"""Render the visionOS icon from the shipped game's authored meshes.

Run: blender --background --python Tools/Blender/render_app_icon.py
No generated illustrations or edits to the game art library are involved.
"""
from pathlib import Path
import json
import math
import sys

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'Art' / 'AppIcon'
CATALOG = ROOT / 'Endless Runner/Assets.xcassets/AppIcon.solidimagestack'
ASSETS = ['rift_frame', 'crystal_combined']


def asset(scene, name, layer, position=(0, 0, 0), scale=(1, 1, 1), yaw=0):
    root = bpy.data.objects.new(name + '_icon', None)
    scene.collection.objects.link(root)
    root.location = position
    root.scale = scale
    root.rotation_euler.z = yaw
    for original in bpy.data.collections[name].objects:
        if original.type != 'MESH':
            continue
        # Isolate the azure body of the game's merged crystal: its coral
        # inlay and gameplay orbit compete with the silhouette at icon size.
        if name == 'crystal_combined' and not original.name.endswith('__blue'):
            continue
        obj = original.copy()
        scene.collection.objects.link(obj)
        obj.parent = root
        obj.location = original.location
        obj['icon_layer'] = layer
        if name == 'crystal_combined':
            # Subpixel bevels catch studio highlights without losing the
            # game's large, flat crystal facets.
            bevel = obj.modifiers.new('Polished facet edges', 'BEVEL')
            bevel.width = .00065
            bevel.segments = 3
            bevel.limit_method = 'ANGLE'
            bevel.angle_limit = .15
    return root


def setup():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    with bpy.data.libraries.load(str(ROOT / 'Art/Blender/Slipframe_ArtSource.blend')) as (source, target):
        assert all(name in source.collections for name in ASSETS)
        target.collections = ASSETS
    scene = bpy.context.scene
    scene.name = 'Slipframe_AppIcon'
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 128
    scene.cycles.use_denoising = True
    scene.render.resolution_x = scene.render.resolution_y = 1024
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_depth = '8'
    scene.render.film_transparent = True
    scene.view_settings.view_transform = 'AgX'
    scene.world = bpy.data.worlds.new('Icon studio')
    scene.world.use_nodes = True
    bg = scene.world.node_tree.nodes.get('Background')
    bg.inputs['Color'].default_value = (.08, .12, .22, 1)
    bg.inputs['Strength'].default_value = .35
    for name, pos, energy, color, size in [
        ('Softbox', (-3, -4, 6), 950, (.79, .91, 1), 5),
        ('Cyan edge', (4, 0, 3), 550, (.18, .75, 1), 3),
        ('Violet rim', (-3, 2, 1), 700, (.48, .23, 1), 3),
    ]:
        data = bpy.data.lights.new(name, 'AREA')
        data.energy, data.color, data.shape, data.size = energy, color, 'DISK', size
        obj = bpy.data.objects.new(name, data)
        scene.collection.objects.link(obj)
        obj.location = pos
        obj.rotation_euler = (Vector((0, 0, 0)) - obj.location).to_track_quat('-Z', 'Y').to_euler()
    data = bpy.data.cameras.new('Icon camera')
    camera = bpy.data.objects.new('Icon camera', data)
    scene.collection.objects.link(camera)
    camera.location = (2.8, -11, 2.0)
    camera.rotation_euler = (Vector((0, 0, 0)) - camera.location).to_track_quat('-Z', 'Y').to_euler()
    data.type, data.ortho_scale = 'ORTHO', 5.2
    scene.camera = camera

    # Full-bleed opaque navy backdrop; its gentle falloff is a shader, not noise.
    mesh = bpy.data.meshes.new('Backdrop')
    mesh.from_pydata([(-30, 8, -30), (30, 8, -30), (30, 8, 30), (-30, 8, 30)], [], [(0, 1, 2, 3)])
    obj = bpy.data.objects.new('Backdrop', mesh)
    scene.collection.objects.link(obj)
    obj['icon_layer'] = 'Back'
    mat = bpy.data.materials.new('Ink gradient')
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.clear()
    geo = nodes.new('ShaderNodeNewGeometry')
    distance = nodes.new('ShaderNodeVectorMath'); distance.operation = 'DISTANCE'
    distance.inputs[1].default_value = (-1.6, 8, -1.4)
    links.new(geo.outputs['Position'], distance.inputs[0])
    divide = nodes.new('ShaderNodeMath'); divide.operation = 'DIVIDE'; divide.inputs[1].default_value = 5.5
    links.new(distance.outputs['Value'], divide.inputs[0])
    ramp = nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].color = (.012, .035, .09, 1)
    ramp.color_ramp.elements[1].color = (.001, .002, .008, 1)
    links.new(divide.outputs[0], ramp.inputs[0])
    emission = nodes.new('ShaderNodeEmission')
    links.new(ramp.outputs['Color'], emission.inputs['Color'])
    output = nodes.new('ShaderNodeOutputMaterial')
    links.new(emission.outputs[0], output.inputs['Surface'])
    mesh.materials.append(mat)

    # One bold silhouette: the game's azure crystal emerging from its rift.
    # A tilted ring gives the composition movement without a tiny diorama.
    rift = asset(scene, 'rift_frame', 'Middle', (0, .45, 0), (.94, .94, 1.13))
    rift.rotation_euler.y = math.radians(-22)
    crystal = asset(scene, 'crystal_combined', 'Front', (.02, -.45, .04), (8.5, 8.5, 10))
    crystal.rotation_euler.y = math.radians(-22)
    crystal.rotation_euler.z = math.radians(12)
    # Icon-only material tuning: saturated facets and restrained metal. The
    # source game's materials are only loaded here, never saved back to it.
    for name, color, metal, rough, emit in [
        ('SF_CrystalAzure', (.016, .34, .48, 1), .38, .16, .10),
        ('SF_RiftAlloy', (.055, .09, .14, 1), .72, .28, .025),
        ('SF_BrushedEdges', (.18, .27, .34, 1), .75, .26, .04),
    ]:
        material = bpy.data.materials.get(name)
        if material:
            node = next(n for n in material.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
            node.inputs['Base Color'].default_value = color
            node.inputs['Metallic'].default_value = metal
            node.inputs['Roughness'].default_value = rough
            node.inputs['Emission Color'].default_value = color
            node.inputs['Emission Strength'].default_value = emit
            if name == 'SF_CrystalAzure':
                node.inputs['Coat Weight'].default_value = .55
                node.inputs['Coat Roughness'].default_value = .12
    return scene


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    scene = setup()
    if '--draft' in sys.argv:
        scene.cycles.samples = 24
        scene.render.resolution_percentage = 75
        scene.render.image_settings.color_mode = 'RGBA'
        scene.render.filepath = str(OUT / 'draft.png')
        bpy.ops.render.render(write_still=True)
        return
    for layer in ('Back', 'Middle', 'Front'):
        for obj in scene.objects:
            if 'icon_layer' in obj:
                obj.hide_render = obj['icon_layer'] != layer
        scene.render.image_settings.color_mode = 'RGB' if layer == 'Back' else 'RGBA'
        directory = CATALOG / (layer + '.solidimagestacklayer') / 'Content.imageset'
        filename = 'slipframe-icon-' + layer.lower() + '.png'
        scene.render.filepath = str(directory / filename)
        bpy.ops.render.render(write_still=True)
        (directory / 'Contents.json').write_text(json.dumps({
            'images': [{'filename': filename, 'idiom': 'vision', 'scale': '2x'}],
            'info': {'author': 'xcode', 'version': 1},
        }, indent=2) + '\n')
    for obj in scene.objects:
        obj.hide_render = False
    # Discard unlinked library objects; retain the icon's copied mesh instances.
    bpy.data.orphans_purge(do_recursive=True)
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.filepath = str(OUT / 'studio.png')
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / 'Slipframe_AppIcon.blend'))


if __name__ == '__main__':
    main()
