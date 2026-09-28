"""Review the real ring prototypes with the same assembly transforms as Swift."""
from pathlib import Path
import bpy, math, runpy
ROOT=Path(__file__).resolve().parents[2]
H=runpy.run_path(str(ROOT/'Tools/Blender/render_previews.py'),run_name='gyre_review')

def part(scene,name,root,position,angle=0):
    obj=H['copy_asset'](scene,name,position)
    obj.parent=root;obj.rotation_euler.y=-angle
    return obj

def ring(scene,position,shutter=False):
    root=bpy.data.objects.new('Refined shutter' if shutter else 'Refined hoop',None)
    scene.collection.objects.link(root);root.location=position
    if shutter:part(scene,'orbit_shutter_hub',root,(0,0,0))
    for i in range(24):
        t=i*math.tau/24
        signed=t if t<=math.pi else t-math.tau
        if shutter and abs(signed)<=.52:continue
        if shutter:
            part(scene,'orbit_shutter_blade',root,(.65*math.cos(t),0,.65*math.sin(t)),t)
            part(scene,'orbit_shutter_band',root,(.65*math.cos(t),-.01,.65*math.sin(t)),t+math.pi/2)
            part(scene,'orbit_shutter_rim',root,(1.02*math.cos(t),-.02,1.02*math.sin(t)),t+math.pi/2)
        else:
            part(scene,'orbit_hoop_segment',root,(.8*math.cos(t),0,.8*math.sin(t)),t+math.pi/2)
            if i%6==0:part(scene,'orbit_marker',root,(.8*math.cos(t),-.10,.8*math.sin(t)))
    return root

def render():
    for scene in list(bpy.data.scenes):
        if scene.name.startswith('EnvironmentPolishReview_Gyre'):bpy.data.scenes.remove(scene)
    scene=H['studio']('EnvironmentPolishReview_Gyre',(1400,900))
    try:scene.render.engine='BLENDER_EEVEE'
    except TypeError:pass
    for obj in list(scene.objects):
        if obj.type=='LIGHT':bpy.data.objects.remove(obj,do_unlink=True)
    next(n for n in scene.world.node_tree.nodes if n.type=='BACKGROUND').inputs['Strength'].default_value=0
    H['copy_asset'](scene,'environment_orbitGate')
    ring(scene,(-1.05,4,.25)).rotation_euler.z=.20
    ring(scene,(-1.02,5.1,.25)).rotation_euler.x=-.20
    ring(scene,(-1.05,6.2,.25)).rotation_euler.z=-.25
    ring(scene,(1.35,5.2,.25),True)
    H['camera_at'](scene,(.4,-3.5,1.2),(0,5,.1),46)
    scene.render.filepath=str(ROOT/'Art/Previews/gyre-refined-rings.png')
    bpy.ops.render.render(write_still=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'Art/Blender/Slipframe_ArtSource.blend'))
    return scene

if __name__=='__main__':render()
