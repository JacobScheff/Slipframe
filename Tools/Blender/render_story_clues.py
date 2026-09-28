"""Portal and detail reviews of the archive clues; never exported as game art."""
from pathlib import Path
from collections import Counter
import bpy
import runpy
from mathutils import Vector, Matrix

ROOT=Path(__file__).resolve().parents[2]
H=runpy.run_path(str(ROOT/'Tools/Blender/render_portal_reviews.py'),run_name='story_review_helpers')
KEYS=['emberRun','summitStep','lowCrawl','ghostGlass','stormPass','crystalCave','vectorFoundry','orbitGate']


def pose(scene, key):
    for obj in scene.objects:
        if obj.type!='MESH' or not obj.get('story_clue_v1'): continue
        role=obj.name.split('__')[1]
        if role=='story_hatch':
            pivot=Vector((3.27,9.51,.04))
            obj.matrix_local=Matrix.Translation(pivot)@Matrix.Rotation(1.12,4,'Z')@Matrix.Translation(-pivot)
        elif role.startswith('story_pulse'):
            obj.hide_render=not role.endswith('3')


def check_sightlines(scene):
    bpy.context.window.scene=scene
    scene.view_layers[0].update()
    depsgraph=bpy.context.evaluated_depsgraph_get()
    origin=scene.camera.location.copy()
    hits=Counter()
    for i in range(140):
        for j in range(95):
            x=1.84*(2*(i+.5)/140-1)
            z=1.28*(2*(j+.5)/95-1)
            if (x/1.84)**2+(z/1.28)**2>=.93**2: continue
            opening=Vector((x,0,z))
            direction=(opening-origin).normalized()
            hit,location,normal,index,obj,matrix=scene.ray_cast(depsgraph,opening+direction*.03,direction,distance=80)
            if hit and '__story_' in obj.name:
                hits[obj.name.split('__')[1]]+=1
    assert sum(hits.values())>=8,(scene.name,'clues occluded',dict(hits))
    return dict(hits)


def render(key):
    scene=H['setup'](key)
    scene.name='StoryClueReview_'+key
    pose(scene,key)
    scene.render.filepath=str(ROOT/'Art/Previews'/f'{key}-story-portal.png')
    bpy.ops.render.render(write_still=True)
    visibility=check_sightlines(scene)
    # Save a detailed view as an art review, not a claimed gameplay screenshot.
    side=-1 if key in ['summitStep','ghostGlass'] else 1
    for obj in scene.objects:
        if obj.name.startswith('ReviewOnly_') or obj.name.startswith('preview_rift_frame'):
            obj.hide_render=True
            for child in obj.children: child.hide_render=True
    scene.render.resolution_x=1100
    scene.render.resolution_y=850
    H['H']['helpers']['camera_at'](scene,(side*.3,3.5,.6),(side*2.65,10,.10),52)
    scene.render.filepath=str(ROOT/'Art/Previews'/f'{key}-story-detail.png')
    bpy.ops.render.render(write_still=True)
    # Restore the portal view for the saved, user-browsable source scene.
    for obj in scene.objects:
        if obj.name.startswith('ReviewOnly_') or obj.name.startswith('preview_rift_frame'):
            obj.hide_render=False
            for child in obj.children: child.hide_render=False
    H['H']['helpers']['camera_at'](scene,(0,-8,.35),(0,0,0),32)
    scene.render.resolution_x=1200
    scene.render.resolution_y=800
    return visibility


def queue():
    state={'pending':list(KEYS),'done':{},'error':None}
    bpy.app.driver_namespace['story_review_job']=state
    def tick():
        try:
            if not state['pending']:
                bpy.context.window.scene=bpy.data.scenes['StoryClueReview_vectorFoundry']
                bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'Art/Blender/Slipframe_ArtSource.blend'))
                return None
            key=state['pending'].pop(0)
            state['done'][key]=render(key)
            return .5
        except Exception as exc:
            import traceback
            state['error']=traceback.format_exc()
            return None
    bpy.app.timers.register(tick,first_interval=.5)
    return state
