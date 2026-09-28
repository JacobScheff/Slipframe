"""Review each added obstacle variant and the new scenery silhouettes."""
from pathlib import Path
import bpy,runpy
ROOT=Path(__file__).resolve().parents[2]
H=runpy.run_path(str(ROOT/'Tools/Blender/render_previews.py'),run_name='polish_review')

def setup(name,size):
    scene=H['studio']('EnvironmentPolishReview_'+name,size)
    try:scene.render.engine='BLENDER_EEVEE'
    except TypeError:pass
    for obj in list(scene.objects):
        if obj.type=='LIGHT':bpy.data.objects.remove(obj,do_unlink=True)
    node=next(n for n in scene.world.node_tree.nodes if n.type=='BACKGROUND')
    node.inputs['Color'].default_value=(.012,.015,.022,1);node.inputs['Strength'].default_value=1
    return scene

def render():
    scene=setup('Walls',(1200,1200))
    for row,key in enumerate(['emberRun','summitStep','lowCrawl','orbitGate']):
        for v in range(4):
            obj=H['copy_asset'](scene,f'wall_{key}_{v}',((v-1.5)*1.7,0,3.3-row*2.2))
            obj.rotation_euler.z=-.14
    H['camera_at'](scene,(0,-15,1.2),(0,0,0),40,ortho=9.6)
    scene.render.filepath=str(ROOT/'Art/Previews/refined-wall-variations.png');bpy.ops.render.render(write_still=True)
    scene=setup('Scenery',(1000,1200))
    for row,key in enumerate(['emberRun','summitStep','crystalCave','orbitGate']):
        for v in [3,4]:
            obj=H['copy_asset'](scene,f'prop_{key}_{v}',((v-3.5)*2.2,0,3.2-row*2.4),.65)
            obj.rotation_euler.z=-.15
    H['camera_at'](scene,(0,-15,2),(0,0,0),40,ortho=11.3)
    scene.render.filepath=str(ROOT/'Art/Previews/refined-scenery-variations.png');bpy.ops.render.render(write_still=True)

if __name__=='__main__':render()
