"""Environment reviews under emission-only lighting, matching portal isolation.

No physical lights or environment illumination hide unreadable shadow faces.
These are Blender art reviews, not device/portal-clipping validation.
"""
from pathlib import Path
import bpy
import runpy
import sys

ROOT = Path(__file__).resolve().parents[2]
helpers = runpy.run_path(str(ROOT / 'Tools/Blender/render_previews.py'), run_name='background_preview_helpers')


def setup(key):
    scene = helpers['studio']('BackgroundReview_' + key, (960, 640))
    # Runtime self-emission doesn't cast light onto other objects. EEVEE without
    # probes/lights models that condition much better than the lit Cycles studio.
    try:
        scene.render.engine = 'CYCLES' if '--cycles' in sys.argv else 'BLENDER_EEVEE'
    except TypeError:
        scene.render.engine = 'CYCLES'
        scene.cycles.max_bounces = 0
    for obj in list(scene.objects):
        if obj.type == 'LIGHT':
            bpy.data.objects.remove(obj, do_unlink=True)
    bg = next(n for n in scene.world.node_tree.nodes if n.type == 'BACKGROUND')
    bg.inputs['Strength'].default_value = 0
    helpers['copy_asset'](scene, 'environment_' + key)
    if key != 'lowCrawl':
        for i in range(8):
            suffix = '' if i % 3 == 0 else '_' + str(i % 3)
            side = -1 if i % 2 == 0 else 1
            helpers['copy_asset'](scene, 'prop_' + key + suffix,
                                  (side*3.2, 4+(i//2)*5.1+(1.05 if i%2 else 0), -1.25), .95)
    helpers['camera_at'](scene, (0, -3.8, .35), (0, 22, .9), 30)
    scene.camera.data.clip_end = 400
    return scene


def render(keys=None):
    for key in keys or helpers['BIOMES']:
        scene = setup(key)
        scene.render.filepath = str(ROOT / 'Art/Previews' / (key + '-background.png'))
        bpy.ops.render.render(write_still=True)
        # Refresh the shipped selection cards to match the revised scenery.
        dest = ROOT / 'Endless Runner/Assets.xcassets' / ('Biome_' + key + '.imageset') / (key + '.png')
        bpy.data.images['Render Result'].save_render(str(dest), scene=scene)
        print('BACKGROUND PREVIEW', key, flush=True)


if __name__ == '__main__':
    keys = sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else None
    render(keys)
