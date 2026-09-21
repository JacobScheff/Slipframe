"""Export the open/saved authored source without rebuilding any artist edits.

blender --background Art/Blender/Slipframe_ArtSource.blend --python Tools/Blender/export_from_source.py
"""
from pathlib import Path
import bpy
import runpy

ROOT = Path(__file__).resolve().parents[2]
assert bpy.data.scenes.get('Slipframe_ArtLibrary'), 'Open Slipframe_ArtSource.blend first.'
# Loading as a module registers the existing collections; does not run a builder.
module = runpy.run_path(str(ROOT / 'Tools' / 'Blender' / 'refine_slipframe.py'), run_name='slipframe_export')
module['sf']['export_assets']()
module['sf']['save_source']()
