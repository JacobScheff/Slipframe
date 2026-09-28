"""Slipframe dimensional art pass. Run in the saved source via Blender MCP."""
import bpy, bmesh, math, runpy, json
from pathlib import Path
from mathutils import Vector, Matrix
ROOT=Path(r'C:\Users\jacob\Documents\VSC\Slipframe')
sf=runpy.run_path(str(ROOT/'Tools/Blender/build_slipframe.py'),run_name='upgrade_base')
for col in bpy.data.collections:
    root=next((o for o in col.objects if o.get('asset_id')),None)
    if root:sf['ASSETS'][root['asset_id']]=dict(root=root,collection=col,family=col.name)
for o in bpy.data.scenes['Slipframe_ArtLibrary'].objects:
    if o.type=='MESH' and '__' in o.name and o.data.materials:
        sf['MATS'].setdefault(o.name.split('__')[-1],o.data.materials[0])
sf['MATS']['snow']=bpy.data.materials['SF_SummitSnow']
sf['MATS']['lava']=bpy.data.materials['SF_MoltenLava']
bpy.app.driver_namespace['slipframe_art']=sf
H=runpy.run_path(str(ROOT/'Tools/Blender/refine_slipframe.py'),run_name='upgrade_helpers')
sf=H['sf']; A=sf['Asset']; M=sf['MATS']
KEYS=['emberRun','summitStep','ghostGlass','lowCrawl','stormPass','crystalCave','vectorFoundry','orbitGate']
for o in bpy.data.scenes['Slipframe_ArtLibrary'].objects:
    if o.type=='MESH' and '__' in o.name and o.data.materials:
        M.setdefault(o.name.split('__')[-1],o.data.materials[0])

def mat(key,color,metal=.4,rough=.4,emission=.5):
    M[key]=sf['material']('SF_V3_'+key,color,metal,rough,emission)

def append(a):
    entry=sf['ASSETS'][a.name]
    for (role,m),(verts,faces) in a.parts.items():
        name=a.name+'__'+role+'__'+m
        mesh=bpy.data.meshes.new(name); mesh.from_pydata(verts,[],faces); mesh.update()
        bm=bmesh.new(); bm.from_mesh(mesh); bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces)); bm.to_mesh(mesh); bm.free()
        obj=bpy.data.objects.new(name,mesh); entry['collection'].objects.link(obj)
        obj.parent=entry['root']; mesh.materials.append(M[m]); obj['dimensional_pass']=True

def rotated_box(a,pos,size,m,rotation,bevel=.006,role='body'):
    v,f=sf['bevel_box_geometry'](size,bevel); a.add(v,f,m,role,pos,rotation)

def tube(a,r,t,m,rotation=None,pos=(0,0,0),role='body',segments=48):
    v=[]; f=[]
    for i in range(segments):
        u=i*math.tau/segments
        for j in range(6):
            w=j*math.tau/6
            v.append(((r+t*math.cos(w))*math.cos(u),t*math.sin(w),(r+t*math.cos(w))*math.sin(u)))
    for i in range(segments):
        for j in range(6): f.append([i*6+j,((i+1)%segments)*6+j,((i+1)%segments)*6+(j+1)%6,i*6+(j+1)%6])
    a.add(v,f,m,role,pos,rotation)

def shapes():
    mat('ceramic',(.10,.155,.18),.38,.3,.45)
    mat('recess',(.018,.026,.035),.25,.64,.4)
    mat('titanium',(.40,.49,.52),.7,.28,.45)
    mat('bronze',(.43,.235,.09),.7,.32,.5)
    mat('conduit',(.035,.72,.62),.2,.22,1.2)
    mat('lens',(.42,.90,.84),.3,.22,.9)
    for kind in ['sphere','cube','diamond']:
        aid='foundry_shape_'+kind
        entry=sf['ASSETS'][aid]
        for o in list(entry['collection'].objects):
            if o.type=='MESH': bpy.data.objects.remove(o,do_unlink=True)
        a=A(aid,'vectorFoundry')
        if kind=='sphere':
            # Separate curved ceramic armor panels reveal deep meridian grooves.
            for row in range(6):
                p0=-math.pi/2+row*math.pi/6+.025; p1=-math.pi/2+(row+1)*math.pi/6-.025
                for col in range(12):
                    t0=col*math.tau/12+.027; t1=(col+1)*math.tau/12-.027
                    v=[]
                    for i in range(4):
                        p=p0+(p1-p0)*i/3
                        for j in range(4):
                            t=t0+(t1-t0)*j/3
                            v.append((.147*math.cos(p)*math.cos(t),.147*math.cos(p)*math.sin(t),.147*math.sin(p)))
                    f=[[i*4+j,i*4+j+1,(i+1)*4+j+1,(i+1)*4+j] for i in range(3) for j in range(3)]
                    a.add(v,f,'ceramic' if (row+col)%3 else 'titanium')
            bm=bmesh.new(); bmesh.ops.create_uvsphere(bm,u_segments=24,v_segments=12,radius=.138)
            bm.verts.ensure_lookup_table(); bm.verts.index_update()
            a.add([tuple(v.co) for v in bm.verts],[[v.index for v in f.verts] for f in bm.faces],'recess'); bm.free()
            for angle in [-.48,.48]: tube(a,.157,.009,'bronze',Matrix.Rotation(angle,3,'Z'))
            tube(a,.148,.0035,'conduit',Matrix.Rotation(math.pi/2,3,'X'),role='tint_pickup')
            for y in [-.146,.146]:
                a.ring(.050,.050,.012,.014,'titanium',32,pos=(0,y,0))
                a.ring(.034,.034,.017,.017,'conduit',24,role='tint_pickup',pos=(0,y*1.055,0))
                a.box((0,y*1.09,0),(.016,.016,.016),'lens',.003)
        elif kind=='cube':
            rot=Matrix.Rotation(.28,3,'Z')@Matrix.Rotation(.18,3,'X')
            rotated_box(a,(0,0,0),(.232,.232,.232),'recess',rot,.02)
            # Six inset face cassettes, corner guards and luminous seams.
            for axis in range(3):
                for sign in [-1,1]:
                    orient=Vector(tuple(sign if k==axis else 0 for k in range(3))).to_track_quat('Z','Y').to_matrix()
                    R=rot@orient
                    for z,size,key in [(.119,(.202,.202,.023),'ceramic'),(.133,(.142,.142,.012),'bronze'),(.141,(.112,.112,.012),'recess')]:
                        rotated_box(a,rot@orient@Vector((0,0,z)),size,key,R,.008)
                    for x in [-.038,.038]:
                        rotated_box(a,R@Vector((x,0,.149)),(.008,.071,.005),'conduit',R,.002,'tint_pickup')
                    for x in [-.084,.084]:
                        for y in [-.084,.084]: rotated_box(a,R@Vector((x,y,.136)),(.018,.018,.012),'titanium',R,.003)
            for x in [-.113,.113]:
                for y in [-.113,.113]:
                    for z in [-.113,.113]: rotated_box(a,rot@Vector((x,y,z)),(.047,.047,.047),'titanium',rot,.009)
        else:
            # Split triangular armor leaves a true pointed diamond silhouette.
            ring=[Vector((.135*math.cos(i*math.tau/8),.135*math.sin(i*math.tau/8),0)) for i in range(8)]
            for i in range(8):
                for sign in [-1,1]:
                    face=[ring[i],ring[(i+1)%8],Vector((0,0,sign*.19))]
                    center=sum(face,Vector())/3
                    a.add([center+(v-center)*.87 for v in face],[[0,1,2]],'ceramic' if i%2 else 'titanium')
            v=[tuple(p*.86) for p in ring]+[(0,0,.17),(0,0,-.17)]
            a.add(v,[[i,(i+1)%8,8] for i in range(8)]+[[(i+1)%8,i,9] for i in range(8)],'conduit','tint_pickup')
            for i in range(8):
                t=i*math.tau/8
                mid=Vector((.142*math.cos(t),.142*math.sin(t),0))
                for s in [-1,1]:
                    a.beam((0,0,s*.194),mid,.011,.012,'bronze')
                    p=mid*.86+Vector((0,0,s*.04))
                    a.beam(p,p*.55+Vector((0,0,s*.065)),.008,.008,'conduit','tint_pickup')
            tube(a,.132,.008,'titanium',Matrix.Rotation(math.pi/2,3,'X'))
            for z in [-.185,.185]: a.prism((0,0,z),.016,.026,'titanium',8)
            for s in [-1,1]: a.ring(.033,.033,.009,.014,'conduit',24,role='tint_pickup',pos=(0,s*.115,0))
        # Keep the original interaction envelope; display tilt is baked into art.
        limits={'sphere':(.38,.30,.38),'cube':(.27,.27,.27),'diamond':(.42,.36,.42)}[kind]
        vertices=[v for vs,fs in a.parts.values() for v in vs]
        spans=[max(v[k] for v in vertices)-min(v[k] for v in vertices) for k in range(3)]
        scale=min(1,*[limits[k]/spans[k] for k in range(3)])
        for part,(vs,fs) in list(a.parts.items()):a.parts[part]=([tuple(c*scale for c in v) for v in vs],fs)
        append(a)

def environment_detail():
    for key in KEYS:
        a=A('environment_'+key,key)
        surface=key; dark=key+'_dark'; glow=key+'_glow'; pale=key+'_pale'
        for side in [-1,1]:
            for i,y in enumerate([5.5,13.5,22.5]):
                x=side*(2.6+i*.18)
                if key=='emberRun':
                    a.prism((x,y,-.85),.46,.8,'recess',8)
                    for j in range(5):
                        z=-.65+j*.16
                        a.ring(.28,.19,.028,.07,'bronze',16,pos=(x,y-.40,z))
                    a.gem((x,y,-.35),.18,.75,'lava',6,role='accent')
                    for j in range(3): H['rock'](a,(x+side*.45,y+j*.45,-1.03),(.7,.6,.42),surface,81+i+j)
                elif key=='summitStep':
                    H['rock'](a,(x,y,-.55),(.92,.9,1.6),surface,101+i,snow=True)
                    a.beam((x,y,-.6),(x,y,1.5),.075,.075,'bronze')
                    a.box((x,y,1.4),(.19,.16,.28),'recess',.018)
                    a.box((x,y-.092,1.4),(.11,.012,.17),'warm',.006,role='accent')
                    if i<2:a.beam((x,y,1.05),(side*(2.6+(i+1)*.18),[13.5,22.5][i],.86),.018,.018,'bronze')
                elif key=='lowCrawl':
                    a.box((x,y,.55),(.8,1.2,3.6),dark,.06)
                    for j in range(9): a.box((x-side*.44,y,-.9+j*.32),(.12,.98,.09),pale,.014)
                    a.box((x-side*.51,y,.8),(.026,.7,.055),glow,.007,role='accent')
                    for z in [1.7,2.0]:a.beam((x,y-3,z),(x,y+3,z),.13,.13,'titanium')
                elif key=='stormPass':
                    a.beam((x,y,-1.25),(x,y,3.6),.22,.24,dark)
                    a.ring(.46,.46,.085,.24,pale,28,pos=(x,y,2.7))
                    for j in range(6):
                        t=j*math.tau/6
                        a.beam((x,y-.08,2.7),(x+.34*math.cos(t),y-.08,2.7+.34*math.sin(t)),.08,.05,surface)
                    a.gem((x,y-.16,2.7),.10,.16,glow,8,role='accent')
                    a.beam((x,y,3.6),(x+side*.8,y,3.85),.06,.08,'bronze')
                elif key=='crystalCave':
                    H['rock'](a,(x,y,-.93),(.95,1.1,.65),surface,501+i)
                    for j in range(5):
                        a.gem((x+side*(j-2)*.14,y+(j%2)*.19,-.12+j*.08),.12+(j%2)*.035,1.1+(j%3)*.3,'mineral_teal' if j%2 else 'mineral_rose',6,tilt=side*(j-2)*.14)
                    for j in range(3): a.gem((x-side*.3,y+j*.38,-1.05),.08,.19,pale,5)
                elif key=='ghostGlass':
                    # Thin opaque frame outlines retain the intentionally near-invisible glass.
                    for j in range(3):
                        xx=x+side*j*.27
                        a.beam((xx,y,-1.1),(xx,y,1.5+j*.4),.018,.035,'titanium')
                        a.beam((xx,y,1.5+j*.4),(xx+side*.22,y+.35,1.8+j*.4),.018,.025,pale)
                    a.ring(.33,.53,.014,.055,pale,6,pos=(x,y,2.6),start=.2,end=5.6)
                elif key=='vectorFoundry':
                    a.box((x,y,-.55),(.8,.85,1.4),'recess',.055)
                    for z in [-.9,-.65,-.4]:a.box((x,y-.44,z),(.62,.07,.07),'bronze',.012)
                    a.beam((x,y,.0),(x+side*.20,y,1.4),.18,.22,'ceramic')
                    a.beam((x+side*.20,y,1.4),(x-side*.40,y,1.8),.15,.18,'titanium')
                    a.ring(.25,.25,.050,.18,'bronze',24,pos=(x-side*.4,y,1.55))
                    a.gem((x-side*.4,y,1.55),.13,.37,'conduit',6,role='accent')
                else:
                    a.prism((x,y,-.65),.38,1.2,dark,8)
                    for j in range(3):a.ring(.38+j*.07,.38+j*.07,.025,.07,pale if j%2 else glow,28,pos=(x,y+j*.10,1.0),start=.3+j*.3,end=5.7+j*.3)
                    a.gem((x,y,1.0),.16,.6,surface,8)
        append(a)

def dimensional_materials():
    # Portable baked directional fill: readable even in an isolated unlit portal.
    # Preserve texture-driven emission, transparency and all runtime tint roles.
    cache={}; count=0
    light=Vector((-.45,-.65,.75)).normalized()
    for entry in sf['ASSETS'].values():
        for o in entry['collection'].objects:
            if o.type!='MESH' or o.get('directional_fill_v3'):continue
            role=o.name.split('__')[1] if '__' in o.name else ''
            if role.startswith(('tint','story','motion')) or role in ['sky','sun','accent','lane','distanceLane','ghost_body','ghost_edge','backdrop']:continue
            if 'aperture' in o.name or 'ghostGlass' in o.name:continue
            originals=list(o.data.materials)
            mapping={}
            for idx,m in enumerate(originals):
                n=next((n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None) if m and m.node_tree else None
                if not n or n.inputs['Alpha'].default_value<.99 or n.inputs['Emission Color'].is_linked:continue
                base=tuple(n.inputs['Base Color'].default_value)[:3]
                if max(base)<.012:continue
                slots=[]
                for band in range(6):
                    ck=(m.name,band)
                    if ck not in cache:
                        copy=m.copy();copy.name='SF_V3_Form_'+m.name+'_'+str(band)
                        nn=next(n for n in copy.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
                        shade=.20+band*.16
                        nn.inputs['Emission Color'].default_value=(*[c*shade for c in base],1)
                        nn.inputs['Emission Strength'].default_value=.85
                        cache[ck]=copy
                    slots.append(len(o.data.materials));o.data.materials.append(cache[ck])
                mapping[idx]=slots
            for p in o.data.polygons:
                if p.material_index in mapping:
                    intensity=(p.normal.dot(light)+1)*.5
                    p.material_index=mapping[p.material_index][min(5,int(intensity*6))]
            o['directional_fill_v3']=True;count+=1
    print('Dimensional shading:',count,'meshes;',len(cache),'material variants')

def run():
    scene=bpy.data.scenes['Slipframe_ArtLibrary'];bpy.context.window.scene=scene
    assert not scene.get('dimensional_pass_v3'),'Already applied; edit source directly.'
    shapes();environment_detail();dimensional_materials();optimize_environments()
    scene['dimensional_pass_v3']=True
    print('Authored all 8 environments and 3 magnetic artifacts')

def optimize_environments():
    bpy.context.window.scene=bpy.data.scenes['Slipframe_ArtLibrary']
    for key in KEYS:
        col=bpy.data.collections['environment_'+key]
        def triangles(o):return sum(len(p.vertices)-2 for p in o.data.polygons)
        def total():return sum(triangles(o) for o in col.objects if o.type=='MESH')
        candidates=sorted([o for o in col.objects if o.type=='MESH' and '__body__' in o.name],key=triangles,reverse=True)
        for o in candidates:
            if total()<24000:break
            if triangles(o)<600:continue
            # Keep original pivots, animated parts, clues and sky untouched.
            o.data=o.data.copy()
            mod=o.modifiers.new('Reduce hidden bevel detail','DECIMATE')
            assert 'COLLAPSE' in [i.identifier for i in mod.bl_rna.properties['decimate_type'].enum_items]
            mod.decimate_type='COLLAPSE';mod.ratio=.60
            bpy.context.view_layer.objects.active=o
            bpy.ops.object.modifier_apply(modifier=mod.name)
        assert total()<25000,(key,total())
        print(key,total(),'triangles')

if __name__=='__main__':run()
