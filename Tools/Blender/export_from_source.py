"""Export the saved art library without rebuilding artist edits."""
from pathlib import Path
import bpy
import runpy

ROOT = Path(__file__).resolve().parents[2]
assert bpy.data.scenes.get('Slipframe_ArtLibrary'), 'Open Slipframe_ArtSource.blend first.'
# Export only needs the collection registry. Do not load historical authoring
# helpers, which depend on materials removed by later art passes.
sf = runpy.run_path(str(ROOT/'Tools/Blender/build_slipframe.py'), run_name='slipframe_export')
for collection in bpy.data.collections:
    root = next((obj for obj in collection.objects if obj.get('asset_id')), None)
    if root:
        sf['ASSETS'][root['asset_id']] = dict(root=root, collection=collection, family=collection.name)
sf['export_assets']()
sf['save_source']()
