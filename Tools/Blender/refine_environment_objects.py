"""Environment detail and Gyre hardware pass, applied to the live source library.

Original environment meshes are preserved. Detail meshes have a refresh tag;
ring prototypes are intentionally replaced, retaining their asset IDs/envelopes.
"""
from pathlib import Path
import bpy, json, math, runpy
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2]
C=runpy.run_path(str(ROOT/'Tools/Blender/add_story_clues.py'),run_name='detail_helpers')
sf=C['sf']; A=C['ClueAsset']; M=sf['MATS']
KEYS=C['KEYS']; CHANGED=set()
for col in bpy.data.collections:
    for obj in col.objects:
        if obj.type=='MESH' and '__' in obj.name and obj.data.materials:
            M[obj.name.split('__')[2].split('.')[0]]=obj.data.materials[0]


def bounds(name):
    vertices=[o.matrix_local@v.co for o in sf['ASSETS'][name]['collection'].objects if o.type=='MESH' for v in o.data.vertices]
    return [Vector(tuple(fn(v[i] for v in vertices) for i in range(3))) for fn in (min,max)]


def install(a,target=None):
    name=target or a.name
    old=sf['ASSETS'].get(name)
    location=old['root'].location.copy() if old else None
    if old and not target:
        for o in list(old['collection'].objects): bpy.data.objects.remove(o,do_unlink=True)
        bpy.data.collections.remove(old['collection'])
        sf['ASSETS'].pop(name)
    a.finish()
    if target:
        temp=sf['ASSETS'].pop(a.name)
        for obj in list(temp['collection'].objects):
            if obj.type!='MESH': continue
            temp['collection'].objects.unlink(obj); old['collection'].objects.link(obj)
            obj.parent=old['root']; obj.name=obj.name.replace(a.name,name)
            obj.data.name=obj.name; obj['environment_polish_v2']=True
        bpy.data.objects.remove(temp['root'],do_unlink=True); bpy.data.collections.remove(temp['collection'])
    elif location is not None: sf['ASSETS'][name]['root'].location=location
    CHANGED.add(name)


def arc(a,r,inner,outer,y,depth,mat,role='body',half=math.pi/24,steps=4):
    # Local Z points inward after the runtime tangent rotation.
    vertices=[];faces=[]
    for i in range(steps+1):
        t=-half+2*half*i/steps
        vertices.extend((radius*math.sin(t),yy,r-radius*math.cos(t))
                        for yy in [y-depth/2,y+depth/2] for radius in [inner,outer])
    for i in range(steps):
        k=i*4
        faces.extend([[k,k+4,k+5,k+1],[k+2,k+3,k+7,k+6],
                      [k,k+2,k+6,k+4],[k+1,k+5,k+7,k+3]])
    faces.extend([[0,1,3,2],[steps*4,steps*4+2,steps*4+3,steps*4+1]])
    a.add(vertices,faces,mat,role)


def gyre():
    for key,color,metal,rough,emit in [
        ('gyre_shell',(.105,.026,.11),.7,.38,.45),
        ('gyre_inset',(.025,.012,.041),.45,.52,.28),
        ('gyre_edge',(.35,.15,.33),.65,.32,.65),
        ('gyre_channel',(.58,.29,.53),.25,.35,.90),
        ('gyre_fastener',(.51,.38,.53),.8,.3,.65)]:
        M[key]=sf['material']('SF_'+key,color,metal,rough,emit)
    for name,r,width,depth,nominal in [
        ('orbit_hoop_segment',.8,.14,.14,(.22,.14,.14)),
        ('orbit_shutter_band',.65,.18,.16,(.21,.16,.18)),
        ('orbit_shutter_rim',1.02,.13,.16,(.25,.16,.13))]:
        a=A(name,'GyreRefined',nominal)
        arc(a,r,r-width/2,r+width/2,0,depth,'gyre_shell')
        for z in [-1,1]:
            radius=r+z*(width/2-.010)
            arc(a,r,radius-.009,radius+.009,-depth*.42,.018,'gyre_edge')
        arc(a,r,r-.024,r+.024,-depth*.48,.008,'gyre_inset',half=.105)
        arc(a,r,r-.008,r+.008,-depth*.51,.008,'gyre_channel','accent',half=.093)
        for x in [-.075,.075]:
            a.ring(.014,.014,.005,.008,'gyre_fastener',6,'fastener',(x,-depth*.48,.003))
        install(a)
    a=A('orbit_marker','GyreRefined',(.16,.10,.16))
    a.plate([(-.07,-.04),(-.04,-.07),(.04,-.07),(.07,-.04),(.07,.04),(.04,.07),(-.04,.07),(-.07,.04)],.09,'gyre_shell')
    a.ring(.046,.046,.009,.01,'gyre_edge',12,'body',(0,-.048,0))
    a.plate([(-.023,0),(0,-.028),(.023,0),(0,.028)],.012,'gyre_channel','accent',(0,-.052,0))
    install(a)

    # The large environmental encoder shares the same palette as the gameplay hoops.
    # Rebind only these two meshes, leaving the shared warm/cyan materials intact.
    for obj in sf['ASSETS']['environment_orbitGate']['collection'].objects:
        if obj.type=='MESH' and obj.name.endswith(('__detail__warm','__detail__energy')):
            obj.data.materials[0]=M['gyre_channel' if obj.name.endswith('warm') else 'gyre_fastener']
    CHANGED.add('environment_orbitGate')
    a=A('orbit_shutter_blade','GyreRefined',(.72,.16,.13))
    a.plate([(-.36,-.054),(.28,-.065),(.36,-.032),(.36,.032),(.28,.065),(-.36,.054)],.13,'gyre_shell')
    a.box((0,-.07,0),(.61,.015,.077),'gyre_inset',0,'detail')
    a.box((.02,-.079,0),(.53,.008,.014),'gyre_channel',0,'accent')
    for x in [-.28,-.19,.22,.30]:
        a.box((x,-.075,0),(.015,.018,.10),'gyre_edge',0,'detail')
    install(a)
    a=A('orbit_shutter_hub','GyreRefined',(.58,.58,.58))
    for r,y,d,mat in [(.29,0,.22,'gyre_shell'),(.24,-.13,.09,'gyre_edge'),(.205,-.185,.03,'gyre_inset'),(.16,-.21,.03,'gyre_shell')]:
        a.ring(r,r,r*.25,d,mat,40,'body',(0,y,0))
    a.plate([(math.cos(i*math.tau/12)*.115,math.sin(i*math.tau/12)*.115) for i in range(12)],.08,'gyre_edge','body',(0,-.21,0))
    a.ring(.10,.10,.012,.016,'gyre_channel',32,'accent',(0,-.259,0))
    for i in range(8):
        t=i*math.tau/8
        a.ring(.017,.017,.007,.014,'gyre_fastener',6,'fastener',(.22*math.cos(t),-.184,.22*math.sin(t)))
    install(a)


def clone_variant(source,name,mirror=False):
    a=A(name,'EnvironmentVariants')
    for o in sf['ASSETS'][source]['collection'].objects:
        if o.type!='MESH' or o.get('environment_polish_v2'): continue
        mat=o.name.split('__')[2].split('.')[0]
        vertices=[tuple(o.matrix_local@v.co) for v in o.data.vertices]
        faces=[list(p.vertices) for p in o.data.polygons]
        if mirror:
            vertices=[(-x,y,z) for x,y,z in vertices]
            faces=[list(reversed(f)) for f in faces]
        a.add(vertices,faces,mat,o.name.split('__')[1])
    return a


def new_variants():
    for key in KEYS:
        name='wall_'+key+'_3'
        a=clone_variant('wall_'+key+'_1',name,True)
        # Asymmetric front pattern and a different side treatment.
        mat=key+'_pale'
        if key=='ghostGlass': mat=next(k for k,v in M.items() if v.name.startswith('SF_NearInvisible_'))
        for i in range(3):
            a.box((-.21+i*.19,-.344,.50-i*.24),(.12,.008,.045),mat,0,'detail')
        install(a)
    for key in ['emberRun','summitStep','crystalCave','orbitGate']:
        lo,hi=bounds('prop_'+key)
        for variant in [3,4]:
            a=A(f'prop_{key}_{variant}','EnvironmentVariants')
            if key in ['emberRun','summitStep','crystalCave']:
                for i in range(5 if variant==3 else 3):
                    x=(-.32+i*.16) if variant==3 else (i-1)*.32
                    h=[1.1,1.75,1.4,2.1,1.15][i] if variant==3 else [1.35,2.2,1.7][i]
                    radius=.21 if variant==3 else .33
                    mat=key if i%2==0 else key+'_pale'
                    if key=='crystalCave':
                        a.gem((x,(i%2)*.22,h/2),radius,h,mat,5+i%3,tilt=(i-2)*.07)
                    else:
                        # Uneven, grounded rock columns; snow follows their tops.
                        count=6;verts=[]
                        for row,(level,spread) in enumerate([(0,.85),(.65,1),(1,.69)]):
                            for j in range(count):
                                t=j*math.tau/count+i*.31
                                z=h*level-(h*.10*(j%3)/2 if row==2 else 0)
                                verts.append((x+radius*spread*math.cos(t),(i%2)*.22+radius*spread*math.sin(t),z))
                        for row in range(2):
                            for j in range(count):
                                k=row*count+j;q=row*count+(j+1)%count
                                a.add(verts,[[k,q,q+count,k+count]],key+'_pale' if j%3==0 else key)
                        a.add(verts,[list(reversed(range(count))),list(range(12,18))],mat)
                        if key=='summitStep':
                            cap=verts[12:18]+[(v[0],v[1],v[2]-.10) for v in verts[12:18]]
                            faces=[list(range(6))]+[[j,(j+1)%6,(j+1)%6+6,j+6] for j in range(6)]
                            a.add(cap,faces,'archive_snow','detail')
                    if key=='emberRun':
                        a.beam((x-radius*.25,-.17,h*.24),(x+radius*.22,-.17,h*.71),.02,.02,'emberRun_glow','accent')
                a.prism((0,.10,.065),.58,.13,key,7,top=.90,role='body')
            else:
                for x in [-.38,.38]:
                    a.box((x,0,.66),(.15,.30,1.32),'gyre_shell',.025)
                    for z in [.24,.65,1.05]:a.box((x,-.16,z),(.18,.045,.07),'gyre_edge',0,'detail')
                a.box((0,0,.14),(.94,.65,.28),'gyre_inset',.04)
                if variant==3:
                    for z in [.5,.92,1.34]:
                        a.ring(.30,.27,.043,.18,'gyre_edge',24,'body',(0,0,z))
                        a.ring(.255,.225,.015,.025,'gyre_channel',24,'accent',(0,-.10,z))
                else:
                    for i in range(5):
                        a.box((0,-.12,.48+i*.20),(.55,.18,.11),'gyre_shell',.02)
                        a.box((-.13,-.22,.48+i*.20),(.23,.012,.025),'gyre_channel',0,'accent')
            # Fit to a smaller original envelope; ground at exactly the original base.
            vertices=[v for vs,fs in a.parts.values() for v in vs]
            mn=Vector(tuple(min(v[i] for v in vertices) for i in range(3)))
            mx=Vector(tuple(max(v[i] for v in vertices) for i in range(3)))
            size=(hi-lo)*.87
            for vs,fs in a.parts.values():
                for i,v in enumerate(vs):
                    unit=(Vector(v)-mn); unit=Vector(tuple(unit[j]/(mx[j]-mn[j]) for j in range(3)))
                    vs[i]=tuple(Vector(((lo.x+hi.x-size.x)/2,(lo.y+hi.y-size.y)/2,lo.z))+Vector(tuple(unit[j]*size[j] for j in range(3))))
            install(a)


def details():
    for name,record in sf['ASSETS'].items():
        if name.startswith(('wall_','prop_','hazard_','foundry_')):
            for obj in list(record['collection'].objects):
                if obj.get('environment_polish_v2'):
                    bpy.data.objects.remove(obj,do_unlink=True)
    for key in KEYS:
        for variant in range(4):
            name=f'wall_{key}_{variant}'; a=A('detail_'+name,'Polish')
            if key=='ghostGlass':
                # Retain the near-invisible gameplay contract for every added face.
                mat=next(k for k,v in M.items() if v.name.startswith('SF_NearInvisible_'))
            else: mat=key+'_pale'
            if key in ['emberRun','summitStep','crystalCave']:
                for i in range(6):
                    z=-.66+i*.24; x=(-.17 if i%2 else .08)+variant*.018
                    a.plate([(-.11,-.04),(.09,-.06),(.14,.035),(-.035,.083)],.01,
                            mat,'detail',(x,-.343,z))
                for i in range(3):
                    a.beam((-.24,-.342,-.55+i*.42),(.17,-.342,-.38+i*.42),.009,.009,mat,'detail')
            else:
                for x in [-.265,.265]:
                    a.box((x,-.34,0),(.045,.017,1.48),mat,0,'detail')
                    for z in [-.67,0,.67]: a.ring(.029,.029,.009,.012,mat,6,'detail',(x,-.342,z))
                for i in range(7):
                    a.box((-.11+i*.035,-.346,-.52),(.013,.008,.22),mat,0,'detail')
                a.box((.10,-.347,.47),(.12,.006,.028),mat,0,'detail')
            install(a,name)
    for base in ['hazard_duck','hazard_jump']:
        for variant in range(3):
            name=base+('' if variant==0 else '_'+str(variant)); a=A('detail_'+name,'Polish')
            lo,hi=bounds(name); mat='lowCrawl_pale' if base=='hazard_duck' else 'summitStep_pale'
            for i in range(12):
                x=-1.13+i*.205
                a.box((x,lo.y+.006,(lo.z+hi.z)/2),(.065,.010,(hi.z-lo.z)*.55),mat,0,'detail')
            install(a,name)
    name='foundry_door_panel';lo,hi=bounds(name); a=A('detail_'+name,'Polish')
    for i in range(8):
        x=lo.x+(hi.x-lo.x)*(i+1)/9
        a.box((x,lo.y+.006,lo.z+(hi.z-lo.z)*.18),(.016,.008,(hi.z-lo.z)*.14),'vectorFoundry_pale',0,'detail')
    install(a,name)
    # Fine surface strata and cooling seams on existing random scenery.
    for key in KEYS:
        for v in range(1 if key=='lowCrawl' else 3):
            name='prop_'+key+('' if v==0 else '_'+str(v));lo,hi=bounds(name)
            if key=='ghostGlass': continue
            a=A('detail_'+name,'Polish');w=hi.x-lo.x;h=hi.z-lo.z
            for i in range(5):
                x=(lo.x+hi.x)/2+(i-2)*w*.115;z=lo.z+h*(.24+(i%3)*.18)
                a.plate([(-w*.04,-h*.03),(w*.06,-h*.02),(w*.07,h*.02),(-w*.03,h*.035)],.008,
                        key+'_pale','detail',(x,lo.y+.01,z))
            install(a,name)


def environment_detail():
    for key in KEYS:
        if key in ['stormPass','ghostGlass']: continue
        name='environment_'+key;a=A('detail_'+name,'Polish')
        natural=key in ['emberRun','summitStep','crystalCave']
        for i in range(12):
            x=(-1 if i%2 else 1)*(3.30+(i%3)*.17);y=5+(i//2)*3.2
            if natural:
                a.gem((x,y,-1.12),.10+(i%3)*.035,.25+(i%4)*.055,key+'_pale',5,role='detail')
            else:
                a.box((x,y,-1.12),(.25,.58,.20),key+'_dark',.018,'detail')
                a.box((x,y-.22,-1.01),(.16,.08,.025),key+'_pale',0,'detail')
        install(a,name)


def export():
    names=sorted(CHANGED|{'environment_'+k for k in KEYS})
    updates={r['id']:r for r in sf['export_assets'](names)}
    path=sf['RUNTIME']/'manifest.json';manifest=json.loads(path.read_text())
    records={r['id']:r for r in manifest['assets']}; records.update(updates)
    manifest['assets']=list(records.values());path.write_text(json.dumps(manifest,indent=2)+'\n')
    sf['save_source']()
    print('REFINEMENT EXPORTED',len(names),'TOTAL',len(records))


def run():
    bpy.context.window.scene=bpy.data.scenes['Slipframe_ArtLibrary']
    # Remove obsolete experiment copies as well as figures in any retained review.
    for obj in list(bpy.data.objects):
        if '__story_echo' in obj.name or '__story_arm' in obj.name or obj.get('environment_polish_v2'):
            bpy.data.objects.remove(obj,do_unlink=True)
    for scene in list(bpy.data.scenes):
        if scene.name.startswith(('StoryClueReview_','ClueProbe_','ArchiveReview_','EnvironmentPolishReview')):
            objects=list(scene.objects);bpy.data.scenes.remove(scene)
            for o in objects:
                if not o.users_scene: bpy.data.objects.remove(o,do_unlink=True)
    C['run'](refresh=True)
    # The clue builder repoints its material aliases per biome. Restore neutral snow.
    M['archive_snow']=bpy.data.materials['SF_archive_snow']
    gyre();new_variants();details();environment_detail()
    for key in KEYS:
        col=sf['ASSETS']['environment_'+key]['collection']
        triangles=0
        for o in col.objects:
            if o.type=='MESH':o.data.calc_loop_triangles();triangles+=len(o.data.loop_triangles)
        assert triangles<25000,(key,triangles)
        print(key,'triangles',triangles)
    export()


if __name__=='__main__':run()
