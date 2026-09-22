"""Distinct spawn silhouettes, matching collision envelopes, faint Ghost Glass.

One-time art pass; leaves portal geometry and non-Ghost environments intact.
"""
from pathlib import Path
import bpy
import hashlib
import json
import math
import runpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
H = runpy.run_path(str(ROOT/'Tools/Blender/refine_slipframe.py'), run_name='variant_helpers')
sf, A, M = H['sf'], H['A'], H['M']


def wall(key, v):
    name = f'wall_{key}_{v}'
    location = sf['ASSETS'][name]['root'].location.copy()
    H['replace'](name)
    a = A(name,key,nominal=(.7,.7,1.8))
    dark, pale, glow = key+'_dark', key+'_pale', key+'_glow'
    if key in ['emberRun','summitStep','crystalCave']:
        # Solid backbone keeps the blocked lane visually filled. Large changes
        # in the front slabs/crystal crowns read from the portal, unlike grain.
        a.box((0,.12,0),(.61,.39,1.72),dark,.06)
        if v == 1:
            for i in range(3):
                x=(i-1)*.205
                h=[1.38,1.83,1.57][i]
                if key=='crystalCave':
                    a.gem((x,-.14,-.85+h/2),.21,h,pale if i==1 else key,5,tilt=(i-1)*.08)
                else:
                    H['rock'](a,(x,-.15,-.85+h/2),(.31,.55,h),key,310+i,snow=key=='summitStep')
            a.beam((-.29,-.36,-.45),(.28,-.36,-.10),.09,.04,pale)
        else:
            for i in range(4):
                H['rock'](a,((-.05 if i%2 else .035),-.13,-.67+i*.46),
                          (.69,.56,.48),key,620+i,snow=key=='summitStep' and i==3)
            if key=='crystalCave':
                a.gem((-.13,-.33,.15),.21,1.1,pale,5,tilt=-.25)
                a.gem((.20,-.28,-.1),.13,.85,'mineral_teal',6,tilt=.17)
            else:
                a.beam((-.27,-.40,-.60),(.28,-.40,.58),.10,.035,'copper')
        for x,z in [(-.20,-.38),(.19,.32)]:
            a.gem((x,-.40,z),.05,.26,glow,4,role='accent')
    elif key=='ghostGlass':
        outlines = [
            [(-.35,-.9),(.22,-.9),(.35,-.55),(.23,-.25),(.35,.20),(.12,.9),(-.35,.65),(-.22,.10)],
            [(-.25,-.9),(.35,-.72),(.24,-.20),(.35,.65),(.05,.9),(-.34,.55),(-.22,.16),(-.35,-.30)]
        ]
        outline=outlines[v-1]
        a.plate(outline,.45,'ghost_body','ghost_body')
        for i,(x,z) in enumerate(outline):
            xx,zz=outline[(i+1)%len(outline)]
            a.beam((x,-.24,z),(xx,-.24,zz),.009,.012,glow,'ghost_edge')
        for i in range(3):
            a.beam((-.3,-.245,-.65+i*.6),(.3,-.245,-.4+i*.5),.008,.01,glow,'ghost_edge')
        a.plate([(-.12,-.26),(.14,0),(-.08,.32)],.10,'ghost_body','ghost_body',(.18,-.3,.25 if v==1 else -.3))
    else:
        a.box((0,.10,0),(.66,.46,1.8),dark,.055)
        if v==1:
            # Large diagonal braces and a tall central service window.
            for side in [-1,1]:
                a.beam((side*.27,-.28,-.76),(-side*.27,-.28,.76),.12,.12,pale)
            a.box((0,-.36,.08),(.24,.10,.85),key,.025)
            for z in [-.22,.04,.30]:
                a.box((0,-.42,z),(.15,.025,.12),glow,.008,role='accent')
        else:
            # Two conspicuous hubs rather than one rotor / repeated shutter.
            for z in [-.42,.43]:
                a.ring(.29,.29,.085,.16,key,24,pos=(0,-.28,z))
                a.ring(.19,.19,.022,.025,glow,24,role='accent',pos=(0,-.38,z))
                a.beam((-.16,-.39,z),(.16,-.39,z),.07,.025,pale)
            a.box((0,-.28,0),(.60,.16,.11),pale,.015)
    a.finish().location=location


def hazard(kind,v):
    name=f'hazard_{kind}_{v}'
    assert name not in sf['ASSETS']
    duck=kind=='duck'
    key='lowCrawl' if duck else 'summitStep'
    a=A(name,key,nominal=(2.5,.595,.75) if duck else (2.5,.22,.14))
    if duck:
        a.box((0,.03,0),(2.5,.46,.75),key+'_dark',.04)
        count=4 if v==1 else 9
        for i in range(count):
            x=-1.10+i*2.20/(count-1)
            if v==1:
                a.plate([(-.23,-.27),(.23,-.27),(.18,.27),(-.10,.30)],.13,key,pos=(x,-.26,0))
                a.box((x,-.34,.03),(.26,.03,.10),'silver',.01)
            else:
                a.beam((x-.09,-.27,-.26),(x+.09,-.27,.25),.14,.13,key)
        # Keep the actual duck clearance a continuous line.
        a.box((0,-.32,-.36),(2.5,.05,.026),key+'_glow',.004,role='accent')
    else:
        a.box((0,0,-.015),(2.5,.20,.11),key+'_dark',.01)
        count=4 if v==1 else 11
        for i in range(count):
            x=-1.07+i*2.14/(count-1)
            a.plate([(-.20,-.04),(.20,-.04),(.12,.035),(-.12,.06)] if v==1
                    else [(-.095,-.04),(.095,-.04),(0,.065)],.18,key,pos=(x,-.01,.015))
        a.box((0,-.112,.046),(2.5,.015,.023),key+'_glow',.003,role='accent')
    a.finish()


def pickup(base,v):
    name=base+'_'+str(v)
    assert name not in sf['ASSETS']
    a=A(name,'03_Shared_Pickups')
    source=sf['ASSETS'][base]['collection']
    if base=='token':
        a.gem((0,0,0),.067,.16,'gold',4 if v==1 else 6)
        a.gem((0,-.025,0),.037,.115,'warm',4 if v==1 else 3,role='tint_pickup')
        a.ring(.086,.086,.011,.018,'gold',4 if v==1 else 6)
        for i in range(4 if v==1 else 3):
            t=i*math.tau/(4 if v==1 else 3)
            a.gem((.078*math.cos(t),-.012,.078*math.sin(t)),.013,.026,'white',4,role='tint_hot')
    else:
        # Keep crown vs fork and the charged orbit; change the actual cut and
        # fracture proportions. The normalization below preserves size/center.
        for obj in source.objects:
            if obj.type!='MESH': continue
            _,role,mat=obj.name.split('__')
            M[mat]=obj.data.materials[0]
            verts=[]
            for vertex in obj.data.vertices:
                x,y,z=vertex.co
                if role not in ['charged_orbit','charged_core']:
                    x=x*(.68 if v==1 else 1.15)+(.020 if v==1 else -.016)*math.sin(z*23)
                    z=z*(1.12 if v==1 else .82)
                verts.append((x,y,z))
            a.add(verts,[list(p.vertices) for p in obj.data.polygons],mat,role)
    a.finish()
    src=[vertex.co for obj in source.objects if obj.type=='MESH' for vertex in obj.data.vertices]
    dst=[vertex for obj in sf['ASSETS'][name]['collection'].objects if obj.type=='MESH' for vertex in obj.data.vertices]
    lo=Vector([min(v[i] for v in src) for i in range(3)]); hi=Vector([max(v[i] for v in src) for i in range(3)])
    dlo=Vector([min(v.co[i] for v in dst) for i in range(3)]); dhi=Vector([max(v.co[i] for v in dst) for i in range(3)])
    for vertex in dst:
        vertex.co=Vector([lo[i]+(vertex.co[i]-dlo[i])/(dhi[i]-dlo[i])*(hi[i]-lo[i]) for i in range(3)])


def ghost_material(source, edge=False):
    name='SF_NearInvisible_'+source.name+('_edge' if edge else '_body')
    mat=bpy.data.materials.get(name)
    if mat: return mat
    mat=source.copy(); mat.name=name
    node=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    for socket in ['Alpha','Emission Color','Emission Strength','Base Color']:
        for link in list(node.inputs[socket].links): mat.node_tree.links.remove(link)
    node.inputs['Alpha'].default_value=.035 if edge else .012
    node.inputs['Base Color'].default_value=(.48,.68,.75,1)
    node.inputs['Metallic'].default_value=0
    node.inputs['Roughness'].default_value=.38
    node.inputs['Emission Color'].default_value=(.25,.38,.42,1)
    node.inputs['Emission Strength'].default_value=.025 if edge else 0
    assert 'BLENDED' in mat.bl_rna.properties['surface_render_method'].enum_items.keys()
    mat.surface_render_method='BLENDED'
    mat.use_backface_culling=True
    mat.diffuse_color=(.48,.68,.75,.035 if edge else .012)
    return mat


def ghost_objects(name):
    for obj in sf['ASSETS'][name]['collection'].objects:
        if obj.type!='MESH': continue
        role=obj.name.split('__')[1]
        if name.startswith('environment_') and role in ['sky','horizon','terrain','lane','distanceRoad','distanceLane']:
            continue
        # Copies ensure shared portal materials and other biomes are untouched.
        obj.data=obj.data.copy()
        old=list(obj.data.materials)
        for mat in old: obj.data.materials.append(ghost_material(mat,role in ['ghost_edge','accent','distanceLight']))
        for face in obj.data.polygons:
            # The mixed road/architecture body retains its walkable floor.
            if name.startswith('environment_') and face.center.z < -1.10:
                continue
            face.material_index += len(old)
        # Remove unused opaque slots and tag mesh changes before USD evaluates
        # the dependency graph; otherwise stale bindings can survive export.
        indices=sorted({p.material_index for p in obj.data.polygons})
        materials=[obj.data.materials[i] for i in indices]
        remap={old:new for new,old in enumerate(indices)}
        face_indices=[remap[p.material_index] for p in obj.data.polygons]
        obj.data.materials.clear()
        for mat in materials: obj.data.materials.append(mat)
        for face,index in zip(obj.data.polygons,face_indices): face.material_index=index
        obj.data.update()
        obj.update_tag()


def run():
    scene=bpy.data.scenes[sf['SCENE_NAME']]
    assert not scene.get('distinct_spawn_variants_v1'), 'Already applied; edit saved assets.'
    bpy.context.window.scene=scene
    for area in bpy.context.screen.areas:
        if area.type=='VIEW_3D' and area.spaces.active.local_view:
            with bpy.context.temp_override(area=area,region=next(r for r in area.regions if r.type=='WINDOW')):
                bpy.ops.view3d.localview(frame_selected=False)
    # Recover original wall palettes instead of background-only emission copies.
    for key in sf['BIOMES']:
        for obj in sf['ASSETS'][f'wall_{key}_0']['collection'].objects:
            if obj.type=='MESH': M[obj.name.split('__')[-1]]=obj.data.materials[0]
    changed=[]
    for key in sf['BIOMES']:
        for v in [1,2]: wall(key,v); changed.append(f'wall_{key}_{v}')
    for kind in ['duck','jump']:
        for v in [1,2]: hazard(kind,v); changed.append(f'hazard_{kind}_{v}')
    for base in ['token','crystal_azure','crystal_coral','crystal_azure_charged','crystal_coral_charged']:
        for v in [1,2]: pickup(base,v); changed.append(f'{base}_{v}')
    ghost_names=[name for name in sf['ASSETS'] if 'ghostGlass' in name and not name.startswith('floor_')]
    for name in ghost_names: ghost_objects(name)
    changed=sorted(set(changed+ghost_names))
    protected={p:hashlib.sha256(p.read_bytes()).hexdigest() for p in sf['RUNTIME'].glob('*.usdz') if p.stem not in changed}
    updates={r['id']:r for r in sf['export_assets'](changed)}
    path=sf['RUNTIME']/'manifest.json'; manifest=json.loads(path.read_text())
    records={r['id']:r for r in manifest['assets']}; records.update(updates)
    manifest['assets']=list(records.values()); path.write_text(json.dumps(manifest,indent=2)+'\n')
    assert all(hashlib.sha256(p.read_bytes()).hexdigest()==digest for p,digest in protected.items())
    scene['distinct_spawn_variants_v1']=True
    sf['save_source']()
    print('EXPORTED DISTINCT VARIANTS',len(changed),'PROTECTED',len(protected),flush=True)


if __name__=='__main__': run()
