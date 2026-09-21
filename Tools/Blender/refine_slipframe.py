"""Second art pass: natural silhouettes, machinery detail and world landmarks.

Operates exclusively on this project's generated collections. The editable .blend
is retained between iterations; runtime USDZ exports are regenerated from it.
"""
import bpy
import math
import random
import runpy
from mathutils import Vector
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
sf=bpy.app.driver_namespace.get('slipframe_art')
if sf is None:
    sf=runpy.run_path(str(ROOT/'Tools'/'Blender'/'build_slipframe.py'),run_name='slipframe_art')
    for col in bpy.data.collections:
        root=next((o for o in col.objects if o.get('asset_id')),None)
        if root:
            sf['ASSETS'][root['asset_id']]=dict(root=root,collection=col,family=col.name)
    for key in ['alloy','dark','silver','energy','warm','white','gold','red','blue']:
        names={'alloy':'RiftAlloy','dark':'DarkSubstrate','silver':'BrushedEdges','energy':'Energy','warm':'WarmSignal','white':'HotSignal','gold':'TokenGold','red':'CrystalCoral','blue':'CrystalAzure'}
        sf['MATS'][key]=bpy.data.materials['SF_'+names[key]]
    for key in sf['BIOMES']:
        for suffix,name in [('', 'surface'),('_dark','substrate'),('_glow','emission'),('_sky','horizon'),('_pale','highlight')]:
            sf['MATS'][key+suffix]=bpy.data.materials.get('SF_'+key+'_'+name) or sf['material'](
                'SF_'+key+'_'+name,sf['BIOMES'][key]['color'],.25,.5,.16)
    sf['MATS']['ghost_body']=bpy.data.materials['SF_GhostPane']
    # Recover extra material keys from saved asset-part names after a Blender reload.
    for obj in bpy.data.objects:
        if obj.type=='MESH' and '__' in obj.name and obj.data.materials:
            sf['MATS'][obj.name.split('__')[-1]]=obj.data.materials[0]
    bpy.app.driver_namespace['slipframe_art']=sf
A=sf['Asset']; M=sf['MATS']; BIOMES=sf['BIOMES']


def replace(name):
    entry=sf['ASSETS'].pop(name,None)
    if not entry: return
    for obj in list(entry['collection'].objects):
        data=obj.data
        bpy.data.objects.remove(obj,do_unlink=True)
        if isinstance(data,bpy.types.Mesh) and data.users==0: bpy.data.meshes.remove(data)
    bpy.data.collections.remove(entry['collection'])


def material_pass():
    colors={'emberRun':(.065,.046,.035),'summitStep':(.27,.30,.31),'ghostGlass':(.22,.39,.47),
            'lowCrawl':(.032,.075,.13),'stormPass':(.048,.088,.12),'crystalCave':(.12,.043,.23)}
    pale={'emberRun':(.16,.084,.035),'summitStep':(.49,.58,.63),'ghostGlass':(.35,.53,.61),
          'lowCrawl':(.13,.20,.28),'stormPass':(.12,.22,.28),'crystalCave':(.33,.14,.52)}
    for key,color in colors.items():
        mat=M[key]; n=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
        # Keep portable image-textured surfaces, using each original texture as a trim sheet.
        image=sf['surface_texture'](key,color,key in ('emberRun','summitStep','crystalCave'))
        for tex in mat.node_tree.nodes:
            if tex.type=='TEX_IMAGE': tex.image=image
        n.inputs['Base Color'].default_value=(*color,1)
        n.inputs['Emission Color'].default_value=(*color,1)
        n.inputs['Emission Strength'].default_value=.24
        mat.diffuse_color=(*color,1)
        n=next(n for n in M[key+'_pale'].node_tree.nodes if n.type=='BSDF_PRINCIPLED')
        n.inputs['Base Color'].default_value=(*pale[key],1)
        n.inputs['Emission Color'].default_value=(*pale[key],1)
        n.inputs['Emission Strength'].default_value=.18
        M[key+'_pale'].diffuse_color=(*pale[key],1)
        M[key+'_cut']=sf['material']('SF_'+key+'_cut',tuple(c*.60 for c in color),.25,.64,.15)
    M['snow']=sf['material']('SF_SummitSnow',(.64,.76,.79),.08,.87,.18)
    M['lava']=sf['material']('SF_MoltenLava',(.95,.115,.006),.18,.42,1.7)
    M['copper']=sf['material']('SF_ForgeCopper',(.30,.125,.040),.78,.34,.08)
    M['mineral_teal']=sf['material']('SF_MineralTeal',(.018,.37,.32),.24,.20,.3)
    M['mineral_rose']=sf['material']('SF_MineralRose',(.42,.045,.24),.22,.22,.3)
    n=next(n for n in M['silver'].node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    n.inputs['Base Color'].default_value=(.22,.29,.35,1)
    n.inputs['Emission Color'].default_value=(.22,.29,.35,1)


def rock(a,pos,size,mat,seed=1,role='body',snow=False):
    rng=random.Random(seed); sides=7; verts=[]
    # Broken strata with changing footprints. Folds and chipped caps replace cube silhouettes.
    angle=rng.uniform(0,.5)
    for row,(z,r) in enumerate([(-.5,.79),(-.31,1),(.30,.94),(.5,.72)]):
        for i in range(sides):
            t=i*math.tau/sides+angle
            radius=r*rng.uniform(.90,1.08)
            verts.append((math.cos(t)*size[0]*.5*radius,math.sin(t)*size[1]*.5*radius,
                          (z+rng.uniform(-.07,.07))*size[2]))
    faces=[list(reversed(range(sides)))]
    for row in range(3):
        for i in range(sides):
            j=(i+1)%sides; k=row*sides
            faces.append([k+i,k+j,k+sides+j,k+sides+i])
    faces.append(list(range(sides*3,sides*4)))
    if snow:
        a.add(verts,faces[:-8],mat,role,pos)
        a.add(verts,faces[-8:],'snow',role,pos)
    else:
        a.add(verts,faces[:-1],mat,role,pos)
        a.add(verts,[faces[-1]],mat+'_cut' if mat+'_cut' in M else mat,role,pos)


def rivets(a,xs,zs,y,mat='silver'):
    for x in xs:
        for z in zs: a.gem((x,y,z),.014,.023,mat,6)


def wall(key,variant):
    name=f'wall_{key}_{variant}'; replace(name)
    a=A(name,key,nominal=(.70,.70,1.8)); r=random.Random(140+variant)
    glow=key+'_glow'; dark=key+'_dark'; cut=key+'_cut'
    if key=='emberRun':
        rock(a,(0,.07,-.04),(.64,.45,1.70),key,variant+80)
        for i in [-1,0,1]:
            rock(a,(i*.19,-.095,.02+(1-abs(i))*.065),(.29,.42,1.75-abs(i)*.13),key,variant*10+i+10)
        for sign in [-1,1]:
            points=[(sign*.105,-.325,-.71),(sign*.135,-.325,-.25),(sign*.072,-.333,.05),(sign*.125,-.325,.36),(sign*.095,-.28,.78)]
            for p,q in zip(points,points[1:]): a.beam(p,q,.020,.022,'lava','accent')
        for z in [-.65,.57]:
            a.box((0,-.315,z),(.62,.075,.075),'copper',.012)
            rivets(a,[-.24,.24],[z],-.36)
        a.plate([(-.08,-.14),(.08,-.14),(.12,.07),(0,.16),(-.12,.07)],.025,'copper',pos=(0,-.335,0))
        a.gem((0,-.37,.016),.047,.12,'lava',5,role='accent')
        for i in range(4):
            a.plate([(-.018,-.05),(.018,-.04),(.015,.05),(-.008,.025)],.012,glow,'accent',((i-1.5)*.10,-.29,.73+r.uniform(-.02,.035)))
    elif key=='summitStep':
        rock(a,(0,.08,0),(.68,.54,1.72),key,variant+13)
        for i in range(4):
            rock(a,(((-1)**i)*.055,-.11,-.65+i*.43),(.70,.61,.48),key,variant*7+i+33,snow=i==3)
        a.box((.20,-.36,-.1),(.052,.043,1.28),'copper',.008,rot=.04)
        for z in [-.62,.46]:
            a.box((-.1,-.34,z),(.44,.05,.035),'summitStep_pale',.006,rot=-.05)
        a.gem((-.13,-.39,.40),.055,.14,'summitStep_glow',4,role='accent')
        for i in [-1,1]: rock(a,(i*.25,-.02,-.77),(.26,.53,.22),key,variant+i+65)
    elif key=='lowCrawl':
        # Armored shutter: deep hood, service plate, layered cooling vanes, readable lower sill.
        outline=[(-.32,-.87),(.32,-.87),(.35,-.65),(.35,.57),(.24,.85),(-.25,.85),(-.35,.59),(-.35,-.65)]
        a.plate(outline,.43,dark)
        a.box((0,-.235,0),(.53,.07,1.37),key,.038)
        for i in range(8):
            z=-.56+i*.166
            a.box((0,-.298,z),(.45,.092,.07),'silver',.011,rot=(variant-1)*.025)
            a.box((0,-.252,z+.06),(.42,.032,.022),glow,.003,role='accent')
        for s in [-1,1]:
            a.beam((s*.27,-.26,-.75),(s*.27,-.26,.63),.075,.11,key)
            a.box((s*.27,-.33,.41),(.021,.026,.27),glow,.004,role='accent')
        a.box((0,-.24,.77),(.49,.26,.13),key,.025)
        a.box((0,-.28,-.79),(.62,.18,.12),key,.018)
        for x in [-.20,-.10,0,.1,.2]: a.box((x,-.38,-.79),(.034,.014,.074),'warm',.004,rot=-.4)
        rivets(a,[-.27,.27],[-.63,.63],-.335)
    elif key=='stormPass':
        outline=[(-.3,-.9),(.27,-.86),(.33,-.6),(.29,.22),(.35,.60),(.19,.88),(-.25,.85),(-.34,.5)]
        a.plate(outline,.42,dark)
        a.ring(.30,.30,.052,.095,key,32,pos=(0,-.28,.45))
        a.ring(.25,.25,.014,.11,glow,32,role='accent',pos=(0,-.31,.45))
        a.prism((0,-.10,.45),.18,.22,dark,8)
        for i in range(9):
            t=i*math.tau/9+variant*.15
            a.beam((math.cos(t)*.065,-.33,.45+math.sin(t)*.065),
                   (math.cos(t+.3)*.235,-.29,.45+math.sin(t+.3)*.235),.038,.025,'silver')
        a.gem((0,-.36,.45),.065,.13,glow,8,role='accent')
        for i in range(4):
            z=-.70+i*.235
            a.plate([(-.28,-.10),(.25,-.07),(.30,.08),(-.25,.11)],.07,key,pos=(0,-.26,z))
            a.beam((-.26,-.31,z-.08),(.27,-.31,z+.07),.021,.018,'silver')
        for s in [-1,1]: a.beam((s*.28,-.1,-.7),(s*.35,-.11,.6),.039,.08,key)
    elif key=='ghostGlass':
        outline=[(-.30,-.89),(.16,-.90),(.32,-.73),(.33,.33),(.26,.36),(.34,.78),(.12,.9),(-.29,.85),(-.35,.32),(-.30,.05)]
        a.plate(outline,.16,'ghost_body','ghost_body')
        for i in range(len(outline)):
            x,z=outline[i]; xx,zz=outline[(i+1)%len(outline)]
            a.beam((x,-.09,z),(xx,-.09,zz),.014,.022,glow,'ghost_edge')
        centers=[(-.08,-.15),(.11,.35),(-.15,.66)]
        for x,z in centers:
            a.beam((x-.1,-.095,z-.28),(x+.09,-.095,z+.13),.006,.009,glow,'ghost_edge')
            a.beam((x+.09,-.095,z+.13),(x+.20,-.095,z+.16),.006,.009,glow,'ghost_edge')
        # Suspended shards remain within the nominal volume, without inventing extra collision.
        for i in range(4):
            x=(-1 if i%2 else 1)*(.25+r.uniform(0,.05)); z=-.65+i*.4
            a.plate([(-.07,-.11),(.055,-.05),(.03,.13)],.023,'ghost_body','ghost_body',(x,-.18-i*.025,z))
        a.beam((-.21,.08,-.76),(.22,.08,.79),.017,.017,'ghostGlass_pale','ghost_edge')
    else:
        rock(a,(0,.02,-.10),(.68,.59,1.55),key,variant+96)
        for i in range(7):
            x=(i-3)*.083; height=1.5-abs(i-3)*.14+r.uniform(-.10,.1)
            a.gem((x,-.13-(i%2)*.09,-.74+height/2),.115,height,key+'_pale' if i%3==0 else key,5+i%2,tilt=(i-3)*.045)
        for i in [-1,1]:
            a.gem((i*.25,-.13,-.48),.115,.69,'mineral_teal' if i<0 else 'mineral_rose',5,tilt=i*.23)
            a.gem((i*.09,-.34,-.20),.044,.63,glow,5,role='accent',tilt=i*.07)
        for i in range(3): rock(a,((i-1)*.22,-.08,-.79),(.28,.62,.25),key,variant+i+400)
    a.finish()


def prop(a,key,pos,s=1,seed=1):
    x,y,z=pos; glow=key+'_glow'; dark=key+'_dark'; r=random.Random(seed)
    if key in ['emberRun','summitStep']:
        for i in range(4):
            h=(1.1+r.random()*1.4)*s
            rock(a,(x+(i-1.5)*.27*s,y+r.uniform(-.25,.25)*s,z+h*.5),(.5*s,.65*s,h),key,seed*4+i,snow=key=='summitStep' and i%2==0)
        if key=='emberRun':
            a.beam((x-.12*s,y-.35*s,z+.13*s),(x+.08*s,y-.3*s,z+1.62*s),.028*s,.02*s,'lava','accent')
    elif key=='crystalCave':
        rock(a,(x,y,z+.12*s),(1.4*s,1.0*s,.4*s),key,seed)
        for i in range(8):
            t=i*2.4; h=(.8+(i%4)*.5)*s
            mat=key if i%3==0 else key+'_pale' if i%3==1 else 'mineral_teal'
            a.gem((x+math.cos(t)*.44*s,y+math.sin(t)*.35*s,z+h*.5),(.15+i*.016)*s,h,mat,6,tilt=(i-4)*.10)
        a.gem((x-.2*s,y-.43*s,z+.4*s),.07*s,.8*s,glow,5,role='accent')
    elif key=='stormPass':
        a.box((x,y,z+.40*s),(.75*s,.8*s,.8*s),dark,.08)
        for i in range(4): a.box((x,y-.15*s,z+(.9+i*.23)*s),(.72*s,.40*s,.095*s),key,.025,rot=-.18)
        a.beam((x,y,z+.3*s),(x+.18*s,y,z+2.4*s),.11*s,.11*s,'silver')
        a.ring(.38*s,.4*s,.06*s,.12*s,key,24,pos=(x+.18*s,y,z+2.1*s))
        for i in range(5):
            t=i*math.tau/5
            a.beam((x+.18*s,y-.06*s,z+2.1*s),(x+(.18+math.cos(t)*.31)*s,y-.06*s,z+(2.1+math.sin(t)*.31)*s),.06*s,.025*s,'silver')
        a.gem((x+.18*s,y-.09*s,z+2.1*s),.045*s,.12*s,glow,5,role='accent')
    elif key=='lowCrawl':
        a.box((x,y,z+1.05*s),(.82*s,.72*s,2.1*s),dark,.08)
        for i in range(7): a.box((x,y-.38*s,z+(.27+i*.25)*s),(.69*s,.09*s,.075*s),key,.014)
        for dx in [-.28,.28]: a.beam((x+dx*s,y-.40*s,z+.22*s),(x+dx*s,y-.40*s,z+1.90*s),.07*s,.085*s,'silver')
        a.box((x,y-.46*s,z+1.83*s),(.26*s,.03*s,.07*s),glow,.008,role='accent')
    else:
        for i in range(4):
            h=(1.4+i*.3)*s; dx=(i-1.5)*.23*s
            a.plate([(-.10*s,-h*.5),(.10*s,-h*.4),(.14*s,h*.33),(.02*s,h*.5),(-.14*s,h*.39)],.05*s,key+'_pale',pos=(x+dx,y+i*.08*s,z+h*.5+.05*s))
            a.beam((x+dx-.12*s,y+i*.08*s-.03*s,z+.18*s),(x+dx+.08*s,y+i*.08*s-.03*s,z+h*.92),.012*s,.015*s,glow,'accent')


def world(key):
    for prefix in ['environment_','prop_','preview_']: replace(prefix+key)
    a=A('prop_'+key,key); prop(a,key,(0,0,0)); a.finish()
    a=A('preview_'+key,key)
    a.box((0,.17,0),(.73,.035,1.77),key+'_sky',.02,role='backdrop')
    for s in [-1,1]: prop(a,key,(s*.18,0,-.7),.23,seed=10)
    a.box((0,0,-.69),(.7,.45,.025),key,.01)
    for x in [-.17,0,.17]: a.box((x,-.03,-.67),(.008,.39,.007),key+'_glow',.001,role='accent')
    if key=='emberRun': a.ring(.22,.22,.025,.03,'copper',24,pos=(0,0,.49))
    if key=='summitStep': a.gem((0,.04,.38),.15,.7,'snow',4)
    if key=='lowCrawl': a.box((0,-.01,.50),(.7,.16,.13),key,.02)
    if key=='stormPass': a.ring(.23,.23,.025,.04,key,24,pos=(0,0,.45))
    if key=='crystalCave': a.gem((0,0,.37),.075,.5,'mineral_teal',6)
    a.finish()

    a=A('environment_'+key,key); floor=-1.25; r=random.Random(40+list(BIOMES).index(key))
    # Close the horizon well outside the portal's field of view; never expose a stage edge.
    sky=key+'_sky'
    a.box((0,42,8),(92,.1,48),sky,.005,role='backdrop')
    for s in [-1,1]: a.box((s*43,15,8),(.1,55,48),sky,.005,role='backdrop')
    a.box((0,15,30),(88,55,.1),sky,.005,role='backdrop')
    a.box((0,14,floor-.17),(24,30,.25),key+'_dark',.05)
    for i in range(15):
        y=i*1.8+.9
        if key=='summitStep':
            a.box((0,y,floor),(3.1,1.76,.045),key,.02)
        elif key=='ghostGlass':
            a.box((0,y,floor),(3.06,1.66,.045),key+'_pale',.016)
            for x in [-1.42,1.42]: a.box((x,y,floor+.026),(.013,1.62,.012),key+'_glow',.003,role='lane')
        else: a.box((0,y,floor),(3.05,1.73,.035),key,.018)
        for x in [-.75,0,.75]: a.box((x,y,floor+.03),(.020,1.55,.01),key+'_glow',.002,role='lane')
        for s in [-1,1]:
            a.box((s*1.63,y,floor+.025),(.10,1.76,.08),'alloy',.012)
            if i%3==0: prop(a,key,(s*(2.3+r.random()*.6),y,floor),.85+r.random()*.45,seed=i+20)

    if key=='emberRun':
        # Obsidian banks, molten channels and a massive suspended forge at the horizon.
        for s in [-1,1]:
            a.box((s*3.7,14,floor-.01),(1.7,28,.025),'lava',.01,role='lava')
            for i in range(12):
                y=i*2.5; h=1.5+r.random()*3.0
                rock(a,(s*(4.2+r.random()),y,floor+h*.5),(2,2.8,h),key,i+int(s)*11+66)
        for y in [4,10,17,24]:
            for s in [-1,1]:
                rock(a,(s*3.0,y,1.25),(1.1,1.3,5.2),key,int(y)+int(s)+44)
                a.beam((s*3,y,3.6),(s*1.8,y,5),.26,.35,'copper')
                a.box((s*2.7,y-.5,2.3),(.045,.035,1.6),'lava',.006,role='accent')
        a.ring(3.0,3.0,.32,.6,'copper',64,pos=(0,26,4.5))
        a.ring(2.65,2.65,.045,.2,'lava',64,role='accent',pos=(0,25.6,4.5))
        for i in range(12):
            t=i*math.tau/12
            a.box((math.cos(t)*2.9,25.6,4.5+math.sin(t)*2.9),(.22,.38,.55),'alloy',.04,rot=t)
    elif key=='summitStep':
        # Alpine canyon with snow caps, distant peaks and an open sky.
        for layer in range(3):
            for s in [-1,1]:
                for i in range(7):
                    h=4+r.random()*6+layer*2
                    rock(a,(s*(5+layer*4+r.random()),i*5+2,floor+h*.45),
                         (4+layer*1.5,5.5,h),key,layer*30+i+int(s)+63,snow=True)
        for y in [7,19]:
            for s in [-1,1]: a.beam((s*2.5,y,floor),(s*2.0,y,3.7),.13,.22,'silver')
            a.beam((-2.0,y,3.7),(2.0,y,4.1),.08,.12,'gold')
        a.gem((.6,39,9),2.5,5,'warm',48,role='sun')
    elif key=='lowCrawl':
        # Deep recessed machinery walls, low load-bearing ribs, parallel overhead services.
        for s in [-1,1]:
            a.box((s*3.1,14,.9),(.4,30,4.4),key+'_dark',.06)
            for x in [1.8,2.05]: a.beam((s*x,-.5,1.9),(s*x,28,1.9),.11,.14,'silver')
        for y in range(2,28,3):
            for s in [-1,1]:
                a.box((s*2.2,y,.05),(.23,.38,2.62),key,.035)
                a.beam((s*2.2,y,1.34),(s*1.55,y,1.95),.23,.38,key)
                a.box((s*2.04,y-.22,.70),(.045,.027,.52),key+'_glow',.007,role='accent')
            a.box((0,y,1.95),(3.14,.38,.18),key,.035)
            a.box((0,y-.21,1.85),(2.1,.03,.028),key+'_glow',.004,role='accent')
            a.box((0,y+1.5,2.20),(6.2,2.98,.25),key+'_dark',.015)
            for j in range(6): a.box(((j-2.5)*.30,y+1.5,2.02),(.035,2.65,.06),'alloy',.01)
    elif key=='ghostGlass':
        # Suspended fragments make a discontinuous colonnade; no fog or haze.
        for y in [4,10,17,25]:
            for s in [-1,1]:
                for j in range(3):
                    x=s*(2.6+j*.42)
                    a.plate([(-.18,-2.1),(.22,-1.9),(.28,1.6),(-.12,2.2),(-.23,.7)],.15,key+'_pale',pos=(x,y,1.8+j*.25))
                    a.beam((x-.12,y-.10,-.1),(x+.16,y-.10,3.5+j*.4),.018,.02,key+'_glow','accent')
            a.beam((-2.8,y,4.05),(-.35,y,4.55),.10,.19,key+'_pale')
            a.beam((.05,y,4.64),(2.8,y,4.22),.1,.19,key+'_pale')
        for i in range(18):
            s=(-1 if i%2 else 1); y=3+i*1.4
            a.plate([(-.18,-.30),(.22,-.12),(.06,.33)],.06,key+'_pale',role='motion_float',pos=(s*(2.0+r.random()*2.4),y,1+r.random()*4))
        a.ring(2.3,3.2,.045,.04,key+'_glow',64,role='accent',pos=(0,30,2.2))
    elif key=='stormPass':
        # Wind-swept gantries with suspended turbine machinery; rain stays off the lanes.
        for y in [5,13,22]:
            for s in [-1,1]:
                a.beam((s*3,y,floor),(s*2.5,y,4.9),.22,.34,key)
                a.beam((s*2.5,y,4.9),(s*.65,y,5.4),.17,.28,'silver')
                for j in range(4):
                    a.plate([(-.6,-.14),(.5,-.05),(.67,.12),(-.5,.24)],.05,key,pos=(s*(3+j*.30),y,2.2+j*.48))
        a.ring(3.4,3.4,.25,.60,key,64,pos=(0,28,4.2))
        a.ring(3.08,3.08,.04,.20,key+'_glow',64,role='accent',pos=(0,27.6,4.2))
        for i in range(12):
            t=i*math.tau/12
            a.beam((math.cos(t)*.55,27.8,4.2+math.sin(t)*.55),
                   (math.cos(t+.24)*2.96,28,4.2+math.sin(t+.24)*2.96),.34,.08,'silver','motion_rotor')
        a.gem((0,27.5,4.2),.50,1,key+'_glow',12,role='accent')
        for i in range(45):
            x=(-1 if i%2 else 1)*(2.7+r.random()*5); y=2+r.random()*26; z=r.random()*7
            a.beam((x,y,z),(x+.12,y+.05,z-.35),.007,.008,key+'_pale','rain')
        for s in [-1,1]:
            path=[(s*6,25,12),(s*5,25,9),(s*5.6,25,9.2),(s*4.5,25,6.5)]
            for p,q in zip(path,path[1:]): a.beam(p,q,.045,.03,key+'_glow','accent')
    else:
        # Mineral vault: rock banks and interlocking crystals that rise around an open course.
        for i,y in enumerate([1,6,12,19,26]):
            for s in [-1,1]:
                rock(a,(s*5,y,1.3),(5,5,6),key,i+int(s)+88)
                for j in range(3):
                    h=4+j*1.3
                    a.gem((s*(3.4+j*.7),y+j*.2,floor+h*.5),.55+j*.15,h,key+'_pale' if j%2 else key,6,tilt=-s*.24)
                a.gem((s*2.8,y,4.5),.42,3.1,'mineral_teal' if i%2 else 'mineral_rose',6,tilt=s*.55)
            a.gem((.5,y,6.3),.42,2.8,key+'_pale',5,role='motion_float',tilt=.2)
        for i in range(9):
            t=i*math.pi/8
            a.gem((math.cos(t)*3,28,1+math.sin(t)*4),.40,2.2,'mineral_teal',6,tilt=math.pi/2-t)
    a.finish()


def portals():
    replace('rift_frame'); replace('junction_frame')
    for name in ['rift_energy','rift_aperture','junction_aperture']: replace(name)
    a=A('rift_frame','01_Shared_RiftKit')
    # A recessed annulus, alternating armor plates, clamps and a luminous throat.
    a.ring(2.08,1.49,.25,.34,'dark',80)
    a.ring(1.84,1.28,.025,.045,'white',80,role='tint_hot',pos=(0,-.18,0))
    for i in range(24):
        t=i*math.tau/24; gap=.030
        a.ring(2.09+(i%3)*.025,1.5+(i%3)*.022,.145,.16,'alloy',5,
               pos=(0,-.19,0),start=t+gap,end=t+math.tau/24-gap)
        a.ring(1.94,1.36,.024,.022,'energy',4,role='tint_rim',
               pos=(0,-.285,0),start=t+.055,end=t+.15)
        for offset in [.06,.17]:
            angle=t+offset
            a.gem((2.01*math.cos(angle),-.293,1.43*math.sin(angle)),.018,.031,'silver',6)
    for s in [-1,1]:
        for z in [-.64,.64]:
            a.plate([(-.16,-.24),(.14,-.19),(.20,.08),(.08,.26),(-.14,.22)],.30,'alloy',pos=(s*1.93,-.14,z))
            a.box((s*1.93,-.313,z),(.10,.055,.31),'dark',.012)
            for dz in [-.09,0,.09]: a.box((s*1.93,-.35,z+dz),(.07,.018,.022),'energy',.004,role='tint_rim')
        a.beam((s*1.92,.1,-1.12),(s*2.2,.14,-.72),.09,.11,'silver')
    a.plate([(-.42,-.05),(.42,-.05),(.30,.12),(-.3,.12)],.30,'alloy',pos=(0,-.06,1.47))
    a.gem((0,-.235,1.49),.071,.10,'energy',4,role='tint_hot')
    a.finish()

    # Mask overlaps the opaque throat slightly; no passthrough sliver at the seam.
    a=A('rift_aperture','01_Shared_RiftKit')
    v=[(0,0,0)]+[(1.84*math.cos(i*math.tau/64),0,1.28*math.sin(i*math.tau/64)) for i in range(64)]
    a.add(v,[[0,i+1,(i+1)%64+1] for i in range(64)],'dark'); a.finish()

    # Circular energy geometry is scaled by an elliptical parent in RealityKit.
    # Rotating the child then moves the accents around the rim without distorting the opening.
    a=A('rift_energy','01_Shared_RiftKit')
    for i in range(16):
        t=i*math.tau/16
        a.ring(1,1,.011,.012,'energy',6,role='tint_rim',start=t+.06,end=t+.25)
        a.gem((math.cos(t),-.012,math.sin(t)),.012,.025,'white',4,role='tint_hot',tilt=-t)
    a.finish()

    a=A('junction_frame','01_Shared_RiftKit')
    a.ring(.46,1.025,.080,.20,'dark',64)
    a.ring(.389,.945,.013,.035,'white',64,role='tint_hot',pos=(0,-.125,0))
    for i in range(14):
        t=i*math.tau/14
        a.ring(.485,1.057,.051,.08,'alloy',5,pos=(0,-.15,0),start=t+.03,end=t+.40)
        a.ring(.45,1.02,.009,.018,'energy',4,role='tint_rim',pos=(0,-.2,0),start=t+.12,end=t+.28)
    for s in [-1,1]:
        a.box((s*.425,-.09,0),(.12,.27,.46),'alloy',.025)
        for z in [-.14,0,.14]: a.box((s*.43,-.235,z),(.058,.025,.029),'energy',.004,role='tint_rim')
    for z in [-1.06,1.07]: a.box((0,-.035,z),(.33,.22,.085),'silver',.018)
    a.finish()
    a=A('junction_aperture','01_Shared_RiftKit')
    v=[(0,0,0)]+[(.390*math.cos(i*math.tau/64),0,.947*math.sin(i*math.tau/64)) for i in range(64)]
    a.add(v,[[0,i+1,(i+1)%64+1] for i in range(64)],'dark'); a.finish()


def run(keys=None):
    bpy.context.window.scene=bpy.data.scenes['Slipframe_ArtLibrary']
    for key in keys or BIOMES:
        for variant in range(3): wall(key,variant)
        world(key)
    # Re-layout source racks after replacements. Large environment assemblies are
    # kept on their own row, clear of the prop/obstacle review area.
    for i,(name,entry) in enumerate(sf['ASSETS'].items()):
        entry['root'].location=((i%8)*5,-(i//8)*7,0)
        if name.startswith('environment_'):
            entry['root'].location=(list(BIOMES).index(name[12:])*100,50,0)
    sf['save_source']()


if __name__=='__main__':
    material_pass(); run(); portals(); sf['export_assets'](); sf['save_source']()
