"""Additive archive clue pass. Execute in the live Blender MCP session.

Only meshes tagged story_clue_v1 are replaced on an explicit refresh. Existing
artist geometry, materials, gameplay assets and scene setup are retained.
Runtime animations use baked Y-up pivots documented in BiomeAssetCatalog.swift.
"""
from pathlib import Path
import bpy
import bmesh
import json
import math
import runpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
sf = runpy.run_path(str(ROOT/'Tools/Blender/build_slipframe.py'), run_name='clue_helpers')
for collection in bpy.data.collections:
    root=next((o for o in collection.objects if o.get('asset_id')),None)
    if root:
        sf['ASSETS'][root['asset_id']]=dict(root=root,collection=collection,family=collection.name)
A, M = sf['Asset'], sf['MATS']


class ClueAsset(A):
    # Thin trim and rain streaks do not benefit from bevel tessellation at 8 m.
    def box(self, pos, size, mat, bevel=.02, role='body', rot=0):
        super().box(pos,size,mat,0 if min(size)<=.18 else bevel,role,rot)

    def beam(self,a,b,width,depth,mat,role='body'):
        a,b=Vector(a),Vector(b)
        vertices,faces=sf['bevel_box_geometry']((width,depth,(b-a).length),0)
        self.add(vertices,faces,mat,role,(a+b)/2,(b-a).to_track_quat('Z','Y').to_matrix())
KEYS = ['emberRun','summitStep','lowCrawl','ghostGlass','stormPass','crystalCave','vectorFoundry','orbitGate']
FLOOR = -1.25


def materials():
    colors = {
        'archive_dark': (.045,.065,.079), 'archive_edge': (.21,.29,.32),
        'archive_ceramic': (.34,.37,.35), 'archive_orange': (.78,.23,.045),
        'archive_rock': (.16,.105,.065), 'archive_snow': (.65,.75,.77),
        'archive_cyan': (.075,.46,.43), 'archive_coral': (.47,.10,.22),
        'archive_scan': (.44,.71,.73),
        'archive_fold': (.19,.29,.35), 'archive_pulse': (.27,.78,.70),
        'archive_stone0': (.10,.105,.11), 'archive_stone1': (.17,.16,.145),
        'archive_stone2': (.23,.21,.175),
    }
    for key,color in colors.items():
        M[key] = sf['material']('SF_'+key, color, .1, .68,
                               1.15 if key in ['archive_orange','archive_scan','archive_pulse'] else .85)


def mark(a, p, radius=.24, role='story_mark'):
    # Small recessed service slots replace the conspicuous repeated emblem.
    for i in range(3):
        a.box((p[0]+(i-1)*radius*.35,p[1],p[2]),
              (radius*.18,.018,radius*.65),'archive_edge',0,role)


def plaque(a, p):
    a.box(p,(.55,.07,.26),'archive_dark',.015,'story_static')
    for i in range(6):
        a.box((p[0]+(i-2.5)*.072,p[1]-.04,p[2]),(.035,.018,.16),
              'archive_edge',0,'story_static')


def bolt(a,p):
    a.ring(.045,.045,.022,.023,'archive_edge',6,'story_static',p)


def speaker(a,p,scale=1):
    x,y,z=p
    a.box(p,(.85*scale,.42*scale,.90*scale),'archive_dark',.055,'story_static')
    a.ring(.32*scale,.32*scale,.05*scale,.05,'archive_edge',24,'story_static',
           (x,y-.23*scale,z))
    a.ring(.23*scale,.23*scale,.16*scale,.02,'archive_fold',20,'story_speaker',
           (x,y-.24*scale,z))
    for i in range(7):
        a.box((x+(i-3)*.087*scale,y-.28*scale,z),(.024*scale,.025,.65*scale),
              'archive_edge',0,'story_static')


def cable(a,points,role='story_static'):
    for p,q in zip(points,points[1:]):
        a.beam(p,q,.055,.055,'archive_dark',role)


def build(key):
    a=ClueAsset('archive_additions_'+key,'ArchiveClues')
    palette={'archive_dark':'substrate','archive_edge':'surface',
             'archive_ceramic':'highlight','archive_fold':'surface',
             'archive_scan':'highlight','archive_pulse':'emission','archive_orange':'highlight'}
    for alias,suffix in palette.items():
        material=bpy.data.materials.get('SF_'+key+'_'+suffix)
        if material: M[alias]=material
    # Every addition stays outside the 1.85 m decoration clearance.
    if key=='emberRun':
        # Grounded basalt columns with fissures; no freestanding display panel.
        for i,(dx,h,r) in enumerate([(-.25,2.60,.29),(.26,2.05,.33),(.07,.90,.32)]):
            x=2.84+dx;y=9.7+(i%2)*.22
            a.prism((x,y,FLOOR+h/2),r,h,'archive_dark' if i%2 else 'archive_edge',5,top=.77,role='story_static',rot=i*.5)
            for j in range(3):
                z=FLOOR+h*(.20+j*.24)
                a.beam((x-r*.7,y-r*.65,z),(x+r*.45,y-r*.65,z+.025),.016,.016,'archive_ceramic','story_static')
            a.beam((x-r*.34,y-r*.80,FLOOR+.12),(x-r*.10,y-r*.80,FLOOR+h*.80),.018,.018,'archive_orange','story_static')
    elif key=='summitStep':
        # Ledges form a single cliff outcrop; its small rear brackets are secondary.
        for i,(dx,h,r) in enumerate([(-.30,1.75,.32),(.15,2.30,.37),(.43,1.25,.26)]):
            x=-2.90+dx;y=10+(i%2)*.16
            a.prism((x,y,FLOOR+h/2),r,h,'archive_edge',5,top=.78,role='story_static',rot=i*.6)
            for j in range(2):
                z=FLOOR+h*(.48+j*.36)
                a.plate([(-r,-.04),(r*.8,-.05),(r,.035),(.10,.13),(-r,.06)],r*1.6,'archive_snow','story_static',(x,y-.07,z))
            a.box((x,y+r*.7,FLOOR+h*.40),(.06,.13,.28),'archive_dark',0,'story_static')
    elif key=='lowCrawl':
        a.box((2.68,10.05,.04),(1.3,.68,2.50),'archive_dark',.04,'story_static')
        for i in range(4):
            a.box((2.68,9.68,-.63+i*.34),(1.04,.04,.30),'archive_fold',.015,'story_static')
            a.beam((2.19,9.64,-.58+i*.34),(3.14,9.64,-.68+i*.34),.035,.02,
                   'archive_snow','story_static')
        a.box((2.67,9.51,.04),(1.20,.11,2.34),'archive_edge',.04,'story_hatch')
        mark(a,(2.52,9.435,.43),role='story_hatch')
        for dz in [-.58,.78]: bolt(a,(3.28,9.44,dz))
    elif key=='ghostGlass':
        a.box((-3.12,9.78,-.25),(.065,1.25,2.0),'archive_fold',.015,'story_static')
        # A nonfigurative array of fractured optical panes and their mounts.
        for i in range(5):
            x=-2.72+(i%2)*.22
            z=-.88+i*.37
            a.plate([(-.25,-.12),(.25,-.16),(.29,.10),(-.16,.20)],.055,
                    'archive_fold','story_static',(x,9.45+i*.10,z))
            a.beam((x-.22,9.41+i*.10,z-.09),(x+.18,9.41+i*.10,z+.12),
                   .012,.014,'archive_scan','story_static')
        a.box((-2.62,9.72,-1.10),(.90,.75,.30),'archive_dark',.025,'story_static')
    elif key=='stormPass':
        a.box((2.70,9.54,-.20),(1.12,.70,2.10),'archive_dark',.06,'story_static')
        speaker(a,(2.70,9.09,1.13),.90)
        a.ring(.49,.49,.075,.10,'archive_edge',32,'story_static',(2.70,9.07,.05))
        for i in range(5):
            t=i*math.tau/5
            a.beam((2.70+.10*math.cos(t),9.06,.05+.10*math.sin(t)),
                   (2.70+.41*math.cos(t+.23),9.06,.05+.41*math.sin(t+.23)),
                   .11,.045,'archive_ceramic','story_fan')
        plaque(a,(2.70,9.12,-.76))
        # A hard-edged rain booth: only the strip beneath these nozzles rains.
        a.box((-2.60,10.0,1.25),(1.15,.13,.15),'archive_edge',.02,'story_static')
        a.box((-2.60,10.0,-1.20),(1.15,.30,.09),'archive_dark',.01,'story_static')
        for i in range(7):
            x=-3.05+i*.15
            a.box((x,10.0,1.12),(.055,.075,.13),'archive_ceramic',.01,'story_static')
            for j in range(3):
                a.beam((x,10.0,.95-j*.67),(x,10.0,.71-j*.67),.009,.009,
                       'archive_scan',f'story_rain{i%3}')
    elif key=='crystalCave':
        a.box((2.57,9.45,-.94),(1.05,.80,.42),'archive_ceramic',.04,'story_static')
        for i,mat in enumerate(['archive_cyan','archive_coral']):
            x=2.32+i*.46
            a.prism((x,9.4,-.67),.22,.17,'archive_dark',8,role='story_static')
            a.gem((x,9.4,-.22),.19,.88,mat,6,role='story_static',tilt=-.12+i*.24)
        points=[(2.56,9.2,-.74),(2.07,9.2,-.74),(2.07,9.2,-1.12),(2.07,10.2,-1.12),
                (2.07,11.2,-1.12),(2.07,12.2,-1.12),(2.07,13.2,-1.12)]
        cable(a,points)
        for i,p in enumerate(points):
            a.gem(p,.055,.11,'archive_pulse',6,role=f'story_pulse{i}')
    elif key=='vectorFoundry':
        # A fabrication gantry with rails, a carriage and replaceable die plates.
        for x in [2.10,3.45]:
            a.box((x,10.8,.30),(.16,.35,3.05),'archive_edge',.025,'story_static')
            for z in [-.90,-.25,.40,1.05,1.60]:
                a.box((x,10.58,z),(.08,.05,.22),'archive_ceramic',0,'story_static')
        for z in [-1.07,1.66]:
            a.box((2.77,10.75,z),(1.54,.70,.20),'archive_dark',.025,'story_static')
        a.box((2.77,10.70,.70),(.56,.40,.36),'archive_fold',.035,'story_static')
        a.beam((2.77,10.70,.50),(2.77,10.70,.03),.12,.12,'archive_ceramic','story_static')
        for i in range(3):
            a.box((2.35+i*.40,10.46,-.78),(.31,.31,.15),'archive_ceramic',.015,'story_static')
            a.box((2.35+i*.40,10.29,-.78),(.18,.015,.035),'archive_pulse',0,'story_static')
        cable(a,[(3.4,10.94,1.5),(3.1,10.94,1.5),(3.1,10.94,.75),(2.9,10.94,.75)])
        for i in range(7):
            p=(2.02,8.0+i*.52,-1.10)
            a.box(p,(.04,.43,.045),'archive_dark',0,'story_static')
            a.gem(p,.04,.08,'archive_pulse',6,role=f'story_pulse{i}')
    elif key=='orbitGate':
        for depth in [10.7,11.1,11.5]:
            a.ring(1.05,1.10,.065,.10,'archive_edge',48,'story_static',(3.14,depth,-.07),.18,math.tau-.18)
        for i in range(32):
            if i in [0,1,31]: continue
            t=i*math.tau/32
            a.beam((3.14+.94*math.cos(t),10.62,-.07+.99*math.sin(t)),
                   (3.14+1.04*math.cos(t),10.62,-.07+1.09*math.sin(t)),
                   .018,.024,'archive_scan' if i%4==0 else 'archive_ceramic','story_static')
        a.box((3.14,11.0,-1.14),(1.95,1.10,.20),'archive_dark',.025,'story_static')
        cable(a,[(3.14,11,-1.05),(2.10,11,-1.05),(2.10,15,-1.05)])
        for i in range(3):
            a.box((2.67+i*.25,10.39,-1.02),(.15,.035,.035),'archive_scan',0,'story_sync')
        for x in [2.25,4.02]:
            a.box((x,11,-.07),(.16,.98,.32),'archive_dark',.025,'story_static')
            for y in [10.73,11.07,11.41]:
                bolt(a,(x,y,-.07))
    # Measured first-hit portal sightlines: these positions clear existing rocks.
    shift={'emberRun':(-.32,2,0),'summitStep':(.12,0,0)}.get(key,(0,0,0))
    for (role,mat),(verts,faces) in a.parts.items():
        for i,v in enumerate(verts): verts[i]=tuple(Vector(v)+Vector(shift))
    for (role,mat),(verts,faces) in a.parts.items():
        assert all(abs(x)>=1.85-1e-5 for x,y,z in verts), (key,role,'clue enters route')
    return a


def install(key, refresh=False):
    target=sf['ASSETS']['environment_'+key]
    old=[o for o in target['collection'].objects if o.get('story_clue_v1')]
    assert refresh or not old, 'Clues already installed; explicit refresh required.'
    for obj in old:
        mesh=obj.data
        bpy.data.objects.remove(obj,do_unlink=True)
        if mesh.users==0: bpy.data.meshes.remove(mesh)
    a=build(key)
    a.finish()
    temporary=sf['ASSETS'].pop(a.name)
    for obj in list(temporary['collection'].objects):
        if obj.type!='MESH': continue
        temporary['collection'].objects.unlink(obj)
        target['collection'].objects.link(obj)
        obj.parent=target['root']
        obj.name=obj.name.replace(a.name,'environment_'+key)
        obj.data.name=obj.name
        obj['story_clue_v1']=True
        obj['clue_biome']=key
    bpy.data.objects.remove(temporary['root'],do_unlink=True)
    bpy.data.collections.remove(temporary['collection'])
    bpy.context.view_layer.update()
    print('CLUES INSTALLED',key,len([o for o in target['collection'].objects if o.get('story_clue_v1')]))


def export():
    updates={r['id']:r for r in sf['export_assets'](['environment_'+key for key in KEYS])}
    path=sf['RUNTIME']/'manifest.json'
    manifest=json.loads(path.read_text())
    manifest['assets']=[updates.get(r['id'],r) for r in manifest['assets']]
    path.write_text(json.dumps(manifest,indent=2)+'\n')
    sf['save_source']()


def run(refresh=False):
    expected=ROOT/'Art/Blender/Slipframe_ArtSource.blend'
    assert Path(bpy.data.filepath).resolve()==expected.resolve(), 'Unexpected open source.'
    backup=expected.with_name(expected.name+'20260926-pre-story-clues')
    if not backup.exists():
        # Capture the current live state, including any unsaved artist changes.
        bpy.ops.wm.save_as_mainfile(filepath=str(backup),copy=True)
    bpy.context.window.scene=bpy.data.scenes['Slipframe_ArtLibrary']
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=='VIEW_3D' and area.spaces.active.local_view:
                with bpy.context.temp_override(screen=screen,area=area,
                     region=next(r for r in area.regions if r.type=='WINDOW')):
                    bpy.ops.view3d.localview(frame_selected=False)
    materials()
    for key in KEYS: install(key,refresh)
    bpy.data.scenes['Slipframe_ArtLibrary']['story_clues_v1']=True
    sf['save_source']()


if __name__=='__main__':
    run()
