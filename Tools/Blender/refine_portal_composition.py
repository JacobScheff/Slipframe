"""Restore original massing; compose readable features for an 8--10 m viewer.

Only environment assets change. No gameplay, portal meshes, or portal materials
are modified. The original ten deformed meshes come from the committed source.
"""
from pathlib import Path
import bpy
import hashlib
import json
import math
import runpy
import subprocess
import tempfile
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
P = runpy.run_path(str(ROOT/'Tools/Blender/polish_backgrounds.py'), run_name='composition_helpers')
F, sf, A, M = P['first'], P['sf'], P['A'], P['M']
FLOOR = -1.25


def leave_local_view():
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == 'VIEW_3D' and area.spaces.active.local_view:
                with bpy.context.temp_override(screen=screen, area=area,
                     region=next(r for r in area.regions if r.type == 'WINDOW')):
                    bpy.ops.view3d.localview(frame_selected=False)


def restore_originals():
    originals = {o.name: o for key in F['BIOMES']
                 for o in sf['ASSETS']['environment_'+key]['collection'].objects
                 if o.get('cliff_shape_v2')}
    if not originals:
        return
    with tempfile.TemporaryDirectory(prefix='slipframe-original-') as directory:
        path = Path(directory)/'original.blend'
        path.write_bytes(subprocess.check_output(
            ['git', 'show', 'b4933e4:Art/Blender/Slipframe_ArtSource.blend'], cwd=ROOT))
        with bpy.data.libraries.load(str(path), link=False) as (source, target):
            assert all(name in source.objects for name in originals)
            target.objects = list(originals)
        for name, loaded in zip(originals, target.objects):
            obj = originals[name]
            old = obj.data
            slots = list(old.materials)
            restored = loaded.data.copy()
            restored.materials.clear()
            for material in slots:
                restored.materials.append(material)
            light = Vector((-.55, -.70, .85)).normalized()
            for face in restored.polygons:
                face.material_index = min(3, int(max(0, face.normal.dot(light))*4)) if len(slots) == 4 else 0
            # Refresh existing review copies as well as the library object.
            for reference in bpy.data.objects:
                if reference.type == 'MESH' and reference.data == old:
                    reference.data = restored
            assert len(restored.vertices) == len(loaded.data.vertices)
            assert all((a.co-b.co).length < 1e-6 for a,b in zip(restored.vertices,loaded.data.vertices))
            obj['original_massing_restored'] = 'b4933e4'
            del obj['cliff_shape_v2']
            bpy.data.objects.remove(loaded, do_unlink=True)
    print('Restored exact original geometry:', len(originals), flush=True)


def landmark_material(key, color, strength=.85):
    M[key] = sf['material']('SF_'+key, color, .08, .82, strength)
    return key


def add_landmarks(key):
    target = sf['ASSETS']['environment_'+key]
    a = A('portal_composition_'+key, key)
    # A feature at (x,y,z) projects onto the opening at x*d/(d+y),
    # eye_z+(z-eye_z)*d/(d+y). Choose grounded masses with readable tops
    # inside that ellipse at d=10, not only from a free-orbit beauty camera.
    if key == 'summitStep':
        stone = landmark_material('portalAlpineStone', (.29,.33,.36))
        snow = landmark_material('portalAlpineSnow', (.66,.74,.77))
        for i,(x,y,width,height) in enumerate([(-3.7,25,3.0,4.0),(4.1,30,3.7,4.8),
                                               (-5.0,39,4.6,6.0),(6.0,46,5.8,7.3)]):
            P['rock'](a,(x,y,FLOOR+height*.46),(width,4.2,height),stone,840+i,snow)
        # Replace the tiny floating-looking shelves with grounded shoulders.
        P['remove_parts'](target,['__detail__detail_alpineLedge'])
    elif key == 'emberRun':
        rock = landmark_material('portalForgeStone', (.13,.10,.085))
        cap = landmark_material('portalForgeCut', (.22,.14,.085))
        heat = landmark_material('portalForgeHeat', (.65,.12,.014),1.2)
        for i,(x,y,h) in enumerate([(-3.5,24,3.4),(3.8,31,4.2),(-4.9,40,5.2)]):
            P['rock'](a,(x,y,FLOOR+h*.47),(2.7,3.3,h),rock,730+i,cap)
            # Broad, recessed hot seam faces the observer, not the side wall.
            a.box((x,y-1.55,.1+h*.15),(.13,.06,h*.49),heat,0,role='detail')
    elif key == 'crystalCave':
        violet = landmark_material('portalCrystalViolet', (.27,.11,.40))
        pale = landmark_material('portalCrystalFacet', (.40,.25,.53))
        teal = landmark_material('portalCrystalTeal', (.085,.37,.36))
        for i,(x,y,h) in enumerate([(-3.3,23,3.5),(3.8,30,4.4),(-5.0,39,5.8)]):
            P['rock'](a,(x,y,-.60),(2.5,2.7,1.6),violet,380+i)
            for j in range(3):
                size=h*(.63+.18*j)
                a.gem((x+(j-1)*.52,y+.35*j,FLOOR+size*.50),.40+.1*j,size,
                      [violet,pale,teal][j],6,role='detail',tilt=(j-1)*.15)
    elif key == 'ghostGlass':
        stone = landmark_material('portalGlassStone', (.19,.31,.37))
        pearl = landmark_material('portalGlassPearl', (.41,.63,.68))
        for i,(x,y,h) in enumerate([(-3.15,12,3.1),(3.7,19,3.8),(-4.4,28,4.6)]):
            a.box((x,y,FLOOR+.16),(1.9,1.7,.32),stone,.03,role='detail')
            for j in range(3):
                a.plate([(-.24,0),(.24,.12),(.34,h*.77),(.03,h),(-.28,h*.73)],
                        .22,pearl if j==1 else stone,'detail',(x+(j-1)*.47,y+j*.3,FLOOR+.32))
    elif key == 'stormPass':
        steel = landmark_material('portalStormSteel', (.14,.22,.28))
        silver = landmark_material('portalStormEdge', (.31,.40,.43))
        ochre = landmark_material('portalStormOchre', (.44,.23,.07))
        for i,(side,y) in enumerate([(-1,13),(1,20),(-1,28)]):
            x=side*(3.25+i*.45)
            a.box((x,y,-.55),(1.35,1.8,1.4),steel,.045,role='detail')
            a.beam((x,y,-.15),(x,y,2.0+i*.5),.18,.22,silver,'detail')
            for z in [.1,.42,.74]:
                a.plate([(-.64,-.10),(.65,-.10),(.44,.1),(-.48,.1)],.08,
                        ochre,'detail',(x,y-.95,z))
    else:
        steel = landmark_material('portalServiceSteel', (.10,.16,.21))
        trim = landmark_material('portalServiceTrim', (.27,.35,.38))
        light = landmark_material('portalServiceLight', (.10,.45,.57))
        for side,y in [(-1,11),(1,19),(-1,25)]:
            # Broad front-facing cabinets remain visible from the lane center.
            x=side*2.53
            a.box((x,y,.07),(.93,.65,2.5),steel,.04,role='detail')
            a.box((x,y-.34,.63),(.67,.02,.38),light,0,role='detail')
            for z in [-.65,-.37,-.09]:
                a.box((x,y-.35,z),(.68,.03,.07),trim,0,role='detail')
    for (role,material),(vertices,faces) in a.parts.items():
        assert all(abs(x)>1.85 for x,y,z in vertices), (key,'landmark enters track')
    F['merge_additions'](a,target)
    P['shade_details'](target)
    return target


def protected_hashes():
    paths = list((ROOT/'Endless Runner').glob('*.swift'))
    paths += [p for p in sf['RUNTIME'].glob('*.usdz') if not p.name.startswith('environment_')]
    return {str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}


def run():
    scene = bpy.data.scenes[sf['SCENE_NAME']]
    assert not scene.get('portal_composition_v3'), 'Already applied: edit saved assets directly.'
    protected = protected_hashes()
    leave_local_view()
    bpy.context.window.scene = scene
    restore_originals()
    for key in F['BIOMES']:
        add_landmarks(key)
    scene['portal_composition_v3'] = True
    changed = ['environment_'+key for key in F['BIOMES']]
    updates = {r['id']:r for r in sf['export_assets'](changed)}
    path = sf['RUNTIME']/'manifest.json'
    manifest = json.loads(path.read_text())
    manifest['assets'] = [updates.get(r['id'],r) for r in manifest['assets']]
    path.write_text(json.dumps(manifest,indent=2)+'\n')
    assert protected == protected_hashes(), 'Protected gameplay/portal/prop file changed.'
    sf['save_source']()
    print('Portal composition complete; protected files unchanged:',len(protected),flush=True)


if __name__ == '__main__':
    run()
