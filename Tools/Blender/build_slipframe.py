"""Offline art source authoring for Slipframe. Run in Blender, never in the app.

Builds editable, UV-mapped mesh collections, then exports self-contained USDZ.
Blender uses X right, Y into the course, Z up; export converts to X/Y/-Z meters.
Existing user scenes are preserved. Only collections in our dedicated scene are rebuilt.
"""
from pathlib import Path
import bpy
import bmesh
import json
import math
import random
import tempfile
import zipfile
import gc
import numpy as np
from mathutils import Vector, Matrix

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'Art' / 'Blender'
RUNTIME = ROOT / 'Endless Runner' / 'ArtAssets'
PREVIEWS = ROOT / 'Art' / 'Previews'
for directory in (SOURCE, RUNTIME, PREVIEWS, SOURCE / 'Textures'):
    directory.mkdir(parents=True, exist_ok=True)

BIOMES = {
    'emberRun': dict(title='EMBER / THE FORGE', color=(.30,.115,.045), secondary=(.105,.065,.055), accent=(1,.37,.065), sky=(.055,.025,.021), metal=.7, rough=.48),
    'summitStep': dict(title='SUMMIT / SUNWARD', color=(.57,.42,.24), secondary=(.20,.26,.27), accent=(1,.80,.36), sky=(.19,.30,.38), metal=.12, rough=.83),
    'ghostGlass': dict(title='GHOST / THE GALLERY', color=(.39,.58,.65), secondary=(.16,.23,.30), accent=(.64,.94,1), sky=(.035,.06,.10), metal=.32, rough=.19),
    'lowCrawl': dict(title='CRAWL / UNDERSTRUCTURE', color=(.075,.18,.31), secondary=(.035,.062,.085), accent=(.10,.65,1), sky=(.012,.026,.049), metal=.78, rough=.49),
    'stormPass': dict(title='STORM / THE ARRAY', color=(.19,.29,.38), secondary=(.065,.095,.14), accent=(.42,.76,1), sky=(.026,.038,.085), metal=.83, rough=.31),
    'crystalCave': dict(title='CRYSTAL / RESONANCE', color=(.24,.12,.37), secondary=(.055,.048,.13), accent=(.66,.40,1), sky=(.025,.013,.060), metal=.23, rough=.30),
}
MATS = {}
ASSETS = {}
SCENE_NAME = 'Slipframe_ArtLibrary'


def material(name, color, metal=0, rough=.6, emission=0, alpha=1, texture=None):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_fake_user = True
    m.use_nodes = True
    n = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    n.inputs['Base Color'].default_value = (*color,1)
    n.inputs['Metallic'].default_value = metal
    n.inputs['Roughness'].default_value = rough
    n.inputs['Alpha'].default_value = alpha
    n.inputs['Emission Color'].default_value = (*color,1)
    n.inputs['Emission Strength'].default_value = emission
    m.diffuse_color = (*color,alpha)
    if texture:
        tex = m.node_tree.nodes.new('ShaderNodeTexImage')
        tex.image = texture
        m.node_tree.links.new(tex.outputs['Color'], n.inputs['Base Color'])
    return m


def surface_texture(key, rgb, stone=False):
    # Authored offline trim sheet: seams, fasteners, grain and inset mineral veins.
    size = 512
    yy,xx=np.mgrid[0:size,0:size]
    rng=np.random.default_rng(117 + list(BIOMES).index(key))
    grain=rng.normal(0,.018,(size,size))
    if stone:
        # Low-contrast mineral mottling, not repetitive wood-grain waves.
        bands=(np.sin(xx*.19+yy*.063)+np.cos(yy*.127-xx*.11))*0.014
        flecks=rng.random((size,size))<.025
        shade=.94+grain+bands-flecks*.09
    else:
        seam=((xx % 128)<3)|((yy % 256)<3)
        inset=((xx % 128)==6)|((yy % 256)==6)
        bolt=(((xx % 128)-14)**2+((yy % 128)-14)**2)<7
        shade=.94+grain-seam*.32+inset*.10-bolt*.35
    pixels=np.ones((size,size,4),dtype=np.float32)
    # Blender image pixels are linear; PNG output is encoded by Blender.
    pixels[:,:,:3]=np.clip(shade[:,:,None]*np.array(rgb)[None,None,:],0,1)
    img=bpy.data.images.new('SF_'+key+'_surface',width=size,height=size,alpha=False)
    img.pixels.foreach_set(pixels.ravel())
    img.filepath_raw=str(SOURCE/'Textures'/f'{key}_surface.png')
    img.file_format='PNG'
    img.save()
    return img


def setup():
    scene=bpy.data.scenes.get(SCENE_NAME)
    if scene:
        raise RuntimeError('Art library already exists. Open the saved source and edit it; do not overwrite authored work.')
    scene=bpy.data.scenes.new(SCENE_NAME)
    bpy.context.window.scene=scene
    scene.unit_settings.system='METRIC'
    scene.unit_settings.scale_length=1
    scene.world=bpy.data.worlds.new('SF_StudioWorld')
    scene.world.use_nodes=True
    bg=next(n for n in scene.world.node_tree.nodes if n.type=='BACKGROUND')
    bg.inputs['Color'].default_value=(.11,.14,.20,1)
    bg.inputs['Strength'].default_value=.5
    MATS['alloy']=material('SF_RiftAlloy',(.18,.23,.28),.82,.36,.06)
    MATS['dark']=material('SF_DarkSubstrate',(.026,.04,.062),.5,.68,.10)
    MATS['silver']=material('SF_BrushedEdges',(.44,.54,.61),.8,.3,.08)
    MATS['energy']=material('SF_Energy',(.20,.84,1),.25,.26,2.5)
    MATS['warm']=material('SF_WarmSignal',(1,.69,.21),.38,.28,2.2)
    MATS['white']=material('SF_HotSignal',(.71,.91,1),.2,.2,3)
    MATS['gold']=material('SF_TokenGold',(.75,.40,.055),.8,.24,.24)
    MATS['red']=material('SF_CrystalCoral',(.94,.18,.31),.24,.22,.4)
    MATS['blue']=material('SF_CrystalAzure',(.10,.60,.95),.30,.2,.4)
    for key,p in BIOMES.items():
        tex=surface_texture(key,p['color'],key in ('summitStep','crystalCave','emberRun'))
        MATS[key]=material('SF_'+key+'_surface',p['color'],p['metal'],p['rough'],.16,texture=tex)
        MATS[key+'_dark']=material('SF_'+key+'_substrate',p['secondary'],.35,.7,.12)
        MATS[key+'_glow']=material('SF_'+key+'_emission',p['accent'],.25,.26,1.8)
        MATS[key+'_sky']=material('SF_'+key+'_horizon',p['sky'],0,1,1)
        MATS[key+'_pale']=material('SF_'+key+'_highlight',tuple(min(1,c*1.4+.08) for c in p['color']),.25,.36,.18)
    MATS['ghost_body']=material('SF_GhostPane',(.40,.66,.73),.20,.17,.14,.35)


BOX_CACHE={}
def bevel_box_geometry(size, bevel=.02):
    cache=tuple(size)+(bevel,)
    if cache in BOX_CACHE: return BOX_CACHE[cache]
    bm=bmesh.new()
    bmesh.ops.create_cube(bm,size=1)
    for v in bm.verts:
        v.co.x*=size[0]; v.co.y*=size[1]; v.co.z*=size[2]
    if bevel>0:
        bmesh.ops.bevel(bm,geom=list(bm.edges),offset=min(bevel,min(size)*.24),segments=2,affect='EDGES')
    bm.verts.ensure_lookup_table(); bm.verts.index_update()
    result=([tuple(v.co) for v in bm.verts], [[v.index for v in f.verts] for f in bm.faces])
    bm.free(); BOX_CACHE[cache]=result
    return result


class Asset:
    def __init__(self, name, family, nominal=None):
        self.name=name; self.family=family; self.parts={}; self.nominal=nominal

    def add(self, verts, faces, mat, role='body', pos=(0,0,0), rotation=None):
        vs,fs=self.parts.setdefault((role,mat),([],[]))
        offset=len(vs); p=Vector(pos)
        for v in verts:
            q=Vector(v); q=rotation@q if rotation else q
            vs.append(tuple(q+p))
        fs.extend([[i+offset for i in f] for f in faces])

    def box(self, pos, size, mat, bevel=.02, role='body', rot=0):
        v,f=bevel_box_geometry(size,bevel)
        self.add(v,f,mat,role,pos,Matrix.Rotation(rot,3,'Y') if rot else None)

    def beam(self, a, b, width, depth, mat, role='body'):
        a,b=Vector(a),Vector(b)
        v,f=bevel_box_geometry((width,depth,(b-a).length),min(width,depth)*.18)
        self.add(v,f,mat,role,(a+b)/2,(b-a).to_track_quat('Z','Y').to_matrix())

    def prism(self,pos,radius,height,mat,sides=6,top=.82,role='body',rot=0):
        verts=[]
        for z,r in [(-height/2,radius),(height/2,radius*top)]:
            verts.extend([(r*math.cos(rot+i*2*math.pi/sides),r*math.sin(rot+i*2*math.pi/sides),z) for i in range(sides)])
        faces=[list(reversed(range(sides))),list(range(sides,sides*2))]
        faces += [[i,(i+1)%sides,(i+1)%sides+sides,i+sides] for i in range(sides)]
        self.add(verts,faces,mat,role,pos)

    def gem(self,pos,radius,height,mat,sides=6,role='body',tilt=0):
        verts=[(0,0,-height*.5)]
        for z,r in [(-height*.29,radius*.78),(height*.12,radius),(height*.33,radius*.78)]:
            verts.extend([(r*math.cos(i*2*math.pi/sides),r*math.sin(i*2*math.pi/sides),z) for i in range(sides)])
        verts.append((0,0,height*.5)); end=len(verts)-1
        faces=[]
        for i in range(sides):
            j=(i+1)%sides
            faces.append([0,1+j,1+i]); faces.append([1+2*sides+i,1+2*sides+j,end])
            for row in range(2):
                k=1+row*sides
                faces.append([k+i,k+j,k+sides+j,k+sides+i])
        self.add(verts,faces,mat,role,pos,Matrix.Rotation(tilt,3,'Y') if tilt else None)

    def ring(self,rx,rz,width,depth,mat,segments=48,role='body',pos=(0,0,0),start=0,end=math.tau):
        verts=[];faces=[]
        for i in range(segments+1):
            t=start+(end-start)*i/segments
            for y in [-depth/2,depth/2]:
                for inset in [0,width]:
                    verts.append(((rx-inset)*math.cos(t),y,(rz-inset)*math.sin(t)))
        for i in range(segments):
            k=i*4
            faces.extend([[k,k+4,k+5,k+1],[k+2,k+3,k+7,k+6],[k,k+2,k+6,k+4],[k+1,k+5,k+7,k+3]])
        faces.extend([[0,1,3,2],[segments*4,segments*4+2,segments*4+3,segments*4+1]])
        self.add(verts,faces,mat,role,pos)

    def plate(self,outline,depth,mat,role='body',pos=(0,0,0)):
        n=len(outline)
        verts=[(x,y,z) for y in [-depth/2,depth/2] for x,z in outline]
        faces=[list(reversed(range(n))),list(range(n,n*2))]
        faces += [[i,(i+1)%n,(i+1)%n+n,i+n] for i in range(n)]
        self.add(verts,faces,mat,role,pos)

    def finish(self):
        scene=bpy.data.scenes[SCENE_NAME]
        family=bpy.data.collections.get('SF_'+self.family)
        if not family:
            family=bpy.data.collections.new('SF_'+self.family); scene.collection.children.link(family)
        col=bpy.data.collections.new(self.name); family.children.link(col)
        root=bpy.data.objects.new('asset_'+self.name,None); col.objects.link(root)
        root['asset_id']=self.name; root['source']='Blender / Slipframe'; root['coordinate_contract']='X right, Y forward, Z up; export Y up meters'
        # Hazard extents are baked to exact nominal volumes, independent of decorations.
        if self.nominal:
            allv=np.array([v for verts,_ in self.parts.values() for v in verts])
            low=allv.min(axis=0); high=allv.max(axis=0); center=(low+high)/2
            factor=np.array(self.nominal)/(high-low)
        for (role,mat),(verts,faces) in self.parts.items():
            if self.nominal: verts=[tuple((np.array(v)-center)*factor) for v in verts]
            mesh=bpy.data.meshes.new(self.name+'__'+role+'__'+mat)
            mesh.from_pydata(verts,[],faces); mesh.update()
            # Recalculate outside normals; projection is stable for individual material chunks.
            bm=bmesh.new(); bm.from_mesh(mesh); bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces)); bm.to_mesh(mesh); bm.free()
            uv=mesh.uv_layers.new(name='st')
            for poly in mesh.polygons:
                axis=max(range(3),key=lambda i:abs(poly.normal[i]))
                axes=[i for i in range(3) if i!=axis]
                for li in poly.loop_indices:
                    co=mesh.vertices[mesh.loops[li].vertex_index].co
                    uv.data[li].uv=(co[axes[0]]*1.5,co[axes[1]]*1.5)
            obj=bpy.data.objects.new(self.name+'__'+role+'__'+mat,mesh)
            col.objects.link(obj); obj.parent=root; mesh.materials.append(MATS[mat])
        # Display the source library on labeled racks; export removes this offset.
        index=len(ASSETS); root.location=((index%8)*5, -(index//8)*8,0)
        ASSETS[self.name]=dict(root=root,collection=col,family=self.family)
        return root


def shared():
    a=Asset('rift_frame','01_Shared_RiftKit')
    for i in range(16):
        start=i*math.tau/16+.025; end=(i+1)*math.tau/16-.025
        a.ring(2.02,1.48,.18,.24,'alloy',6,pos=(0,0,0),start=start,end=end)
        a.ring(1.84,1.30,.045,.08,'energy',6,role='tint_rim',pos=(0,-.14,0),start=start,end=end)
        t=(start+end)/2
        a.gem((2.06*math.cos(t),0,1.51*math.sin(t)),.06,.19,'silver',4,tilt=t)
    # Lower clamps and mechanical crown.
    for s in [-1,1]:
        a.box((s*1.77,.015,-.88),(.23,.40,.65),'dark',.035)
        a.box((s*1.77,-.205,-.88),(.10,.025,.39),'energy',.008,role='tint_rim')
    a.box((0,0,1.43),(.62,.30,.17),'alloy',.035)
    a.box((0,-.16,1.44),(.30,.025,.045),'white',.005,role='tint_hot')
    a.finish()
    # Actual planar mask follows the inside edge of the authored ring.
    a=Asset('rift_aperture','01_Shared_RiftKit')
    v=[(0,0,0)]+[(1.79*math.cos(i*math.tau/64),0,1.245*math.sin(i*math.tau/64)) for i in range(64)]
    a.add(v,[[0,i+1,(i+1)%64+1] for i in range(64)],'dark'); a.finish()
    a=Asset('junction_frame','01_Shared_RiftKit')
    for s in [-1,1]:
        a.beam((s*.43,0,-.90),(s*.43,0,.87),.08,.16,'alloy')
        a.beam((s*.38,-.095,-.85),(s*.38,-.095,.83),.015,.025,'energy','tint_rim')
        a.beam((s*.43,0,.87),(s*.25,0,1.04),.08,.16,'silver')
        a.beam((s*.43,0,-.90),(s*.25,0,-1.02),.08,.16,'silver')
    a.box((0,0,1.015),(.56,.18,.08),'alloy'); a.box((0,0,-1),(.56,.18,.11),'alloy')
    a.finish()
    a=Asset('track_segment','02_Shared_TrackKit')
    a.box((0,0,-.025),(3.2,1,.05),'dark',.012)
    for x in [-1.2,-.75,0,.75,1.2]:
        w=.31 if abs(x)>1 else .67
        a.box((x,0,.004),(w,.94,.018),'alloy',.009)
    for x in [-.75,0,.75]:
        a.box((x,0,.017),(.022,.89,.006),'energy',.002,role='tint_lane')
    for s in [-1,1]:
        a.box((s*1.55,0,.018),(.055,.93,.032),'silver',.008)
        for y in [-.35,.35]: a.box((s*1.47,y,.016),(.055,.06,.009),'warm',.002)
    a.finish()
    a=Asset('rail_segment','02_Shared_TrackKit')
    a.box((0,0,0),(.075,1,.055),'dark',.012)
    a.box((0,0,.03),(.026,.98,.016),'energy',.005,role='tint_lane')
    for y in [-.38,0,.38]: a.box((0,y,0),(.14,.15,.11),'alloy',.018)
    a.finish()
    a=Asset('track_endcap','02_Shared_TrackKit')
    a.box((0,0,0),(3.2,.12,.045),'alloy',.015)
    for x in [-.75,0,.75]: a.box((x,-.02,.027),(.15,.07,.008),'energy',.002,role='tint_lane')
    a.finish()
    a=Asset('start_pad','02_Shared_TrackKit')
    a.box((0,0,-.002),(2.5,.64,.022),'dark',.035)
    for s in [-1,1]:
        a.beam((s*1.20,-.22,.014),(s*1.20,.22,.014),.025,.025,'warm')
        a.beam((s*.9,-.24,.014),(s*1.20,-.24,.014),.025,.025,'warm')
    for y in [-.12,.12]:
        a.beam((-.16,y-.075,.016),(0,y+.035,.016),.025,.025,'white')
        a.beam((0,y+.035,.016),(.16,y-.075,.016),.025,.025,'white')
    a.finish()
    a=Asset('token','03_Shared_Pickups')
    a.gem((0,0,0),.060,.16,'gold',8)
    a.gem((0,0,0),.041,.145,'warm',6,role='tint_pickup')
    a.ring(.086,.086,.012,.018,'gold',32)
    for s in [-1,1]: a.gem((s*.083,0,0),.017,.035,'white',4,role='tint_hot')
    a.finish()
    for kind in ['azure','coral']:
        for charged in [False,True]:
            name='crystal_'+kind+('_charged' if charged else '')
            a=Asset(name,'03_Shared_Pickups')
            mat='blue' if kind=='azure' else 'red'
            # Opposing halves: pointed blue crown and broad coral fork, identifiable without hue.
            outline=([(-.065,0),(-.060,.10),(-.028,.15),(0,.19),(.048,.10),(.065,0)] if kind=='azure' else [(-.067,0),(-.07,.13),(-.035,.18),(0,.12),(.035,.18),(.07,.10),(.065,0)])
            a.plate(outline,.08,mat,pos=(0,0,-.06))
            a.box((0,0,-.061),(.108,.07,.014),'silver',.007)
            a.gem((0,-.045,.02),.020,.085,'white' if charged else mat,5,role='charged_core' if charged else 'body')
            if charged:
                a.ring(.087,.115,.006,.01,'warm',32,role='charged_orbit',pos=(0,0,.028))
            a.finish()
    a=Asset('crystal_combined','03_Shared_Pickups')
    a.gem((0,0,0),.095,.29,'blue',6); a.gem((0,-.02,.025),.063,.23,'red',6)
    a.ring(.145,.16,.008,.018,'white',32); a.finish()
    a=Asset('fx_shard','03_Shared_Pickups')
    a.gem((0,0,0),1,2,'white',4); a.finish()
    a=Asset('gust_ribbon','04_Shared_Signals')
    for z in [-.025,0,.025]:
        a.beam((-.5,0,z),(.36,0,z),.009,.014,'energy','tint_gust')
    a.beam((.34,0,-.09),(.50,0,0),.015,.014,'white','tint_gust')
    a.beam((.50,0,0),(.34,0,.09),.015,.014,'white','tint_gust'); a.finish()
    for name,outline in {
        'risk':[(-.5,0),(0,.5),(.5,0),(0,-.5)],
        'aegis':[(-.42,.5),(.42,.5),(.35,-.15),(0,-.5),(-.35,-.15)],
        'overdrive':[(-.1,.55),(-.4,-.05),(-.05,-.05),(-.20,-.55),(.40,.15),(.05,.15)],
        'precision':[(-.5,-.13),(-.13,-.13),(-.13,-.5),(.13,-.5),(.13,-.13),(.5,-.13),(.5,.13),(.13,.13),(.13,.5),(-.13,.5),(-.13,.13),(-.5,.13)],
        'lock':[(-.4,-.45),(.4,-.45),(.4,.12),(.25,.12),(.25,.5),(-.25,.5),(-.25,.12),(-.4,.12)],
    }.items():
        a=Asset('glyph_'+name,'04_Shared_Signals'); a.plate(outline,.08,'energy',role='tint_glyph'); a.finish()
    a=Asset('glyph_magnet','04_Shared_Signals')
    a.ring(.45,.5,.15,.08,'energy',24,role='tint_glyph',start=math.pi,end=math.tau)
    for s in [-1,1]: a.box((s*.375,0,.22),(.15,.08,.44),'energy',.01,role='tint_glyph')
    a.finish()


def obstacle(key,variant):
    a=Asset(f'wall_{key}_{variant}',key,nominal=(.70,.70,1.8))
    dark=key+'_dark'; glow=key+'_glow'; pale=key+'_pale'
    rng=random.Random(901+variant)
    # Every family has a solid core spanning the gameplay volume: no false gaps.
    if key=='emberRun':
        a.box((0,0,0),(.60,.55,1.70),dark,.045)
        for i in [-1,0,1]:
            a.prism((i*.20,-.08,.02+rng.uniform(-.02,.02)),.155,1.8,key,5,top=.90,rot=variant*.12)
            a.box((i*.20,-.232,.12),(.020,.035,1.24),glow,.006,role='accent')
        for z in [-.64,.54]: a.box((0,-.285,z),(.68,.075,.11),'gold',.017)
        a.gem((0,-.335,.36),.075,.23,glow,4,role='accent')
    elif key=='summitStep':
        a.box((0,.015,0),(.67,.60,1.8),dark,.065)
        for i in range(5):
            z=-.72+i*.36
            a.box((rng.uniform(-.025,.025),-.03,z),(.70,.65,.355),key,.035,rot=rng.uniform(-.018,.018))
            a.box((-.22,-.369,z),(.045,.014,.14),pale,.006)
        for z in [-.68,.70]: a.box((0,-.364,z),(.56,.02,.025),glow,.006,role='accent')
        a.box((.22,-.365,.05),(.055,.023,.62),'gold',.009)
    elif key=='lowCrawl':
        a.box((0,0,0),(.70,.61,1.8),dark,.04)
        a.box((0,-.326,0),(.58,.045,1.62),key,.03)
        for i in range(9): a.box((0,-.371,-.69+i*.174),(.53,.07,.048),'alloy',.009)
        for x in [-.3,.3]:
            a.beam((x,-.33,-.82),(x,-.33,.82),.044,.09,key)
            a.box((x,-.388,.5),(.018,.016,.44),glow,.004,role='accent')
        a.box((0,-.422,.68),(.18,.016,.052),glow,.006,role='accent')
    elif key=='stormPass':
        a.box((0,.02,0),(.64,.55,1.75),dark,.035)
        for i in range(5):
            a.box((0,-.11,-.70+i*.35),(.65,.53,.31),key,.025,rot=(-1 if i%2 else 1)*.08)
        for s in [-1,1]:
            a.beam((s*.22,-.40,-.77),(-s*.22,-.40,.72),.045,.034,'silver')
        for z in [-.48,.16,.65]: a.box((.23,-.37,z),(.052,.025,.10),glow,.008,role='accent')
        a.plate([(-.20,-.16),(.0,.03),(-.04,.03),(.20,.28),(.055,.045),(.10,.045)],.018,glow,'accent',(0,-.417,.10))
    elif key=='ghostGlass':
        a.box((0,0,0),(.67,.15,1.78),'ghost_body',.035,role='ghost_body')
        for s in [-1,1]:
            a.box((s*.32,0,0),(.025,.19,1.8),pale,.006,role='ghost_edge')
            a.box((0,0,s*.885),(.65,.19,.022),glow,.005,role='ghost_edge')
        paths=[((-.29,-.10,-.50),(.12,-.10,.05)),((.12,-.10,.05),(.30,-.10,.38)),((.12,-.10,.05),(-.20,-.10,.58)),((-.20,-.10,.58),(-.06,-.10,.88))]
        for start,end in paths: a.beam(start,end,.009,.012,glow,'ghost_edge')
        a.box((0,.035,0),(.54,.37,1.5),'ghost_body',.018,role='ghost_body')
    elif key=='crystalCave':
        a.box((0,.02,0),(.64,.56,1.75),dark,.055)
        for i in [-1,0,1]:
            a.prism((i*.20,-.06,0),.16,1.65,key,6,top=.95,rot=i*.25)
            a.gem((i*.18,-.25,.18+rng.uniform(-.16,.16)),.13,1.15,pale,5,tilt=i*.065)
        for i in [-1,1]: a.gem((i*.20,-.29,-.48),.066,.52,glow,5,role='accent',tilt=i*.2)
        a.box((0,.0,-.85),(.68,.60,.1),dark,.025)
    return a.finish()


def hazards():
    a=Asset('hazard_duck','lowCrawl',nominal=(2.5,.595,.75))
    a.box((0,0,0),(2.5,.52,.72),'lowCrawl_dark',.045)
    for x in [-1.05,-.7,-.35,0,.35,.7,1.05]:
        a.box((x,-.29,.03),(.27,.07,.62),'lowCrawl',.028)
        for z in [-.16,-.02,.12]: a.box((x,-.337,z),(.21,.025,.035),'alloy',.007)
    # Continuous luminous lower lip is the actual duck-under clearance.
    a.box((0,-.33,-.358),(2.5,.05,.026),'lowCrawl_glow',.006,role='accent')
    for x in [-1.1,0,1.1]:
        a.beam((x-.08,-.35,.22),(x,-.35,.11),.028,.018,'white','accent')
        a.beam((x,-.35,.11),(x+.08,-.35,.22),.028,.018,'white','accent')
    a.finish()
    a=Asset('hazard_jump','summitStep',nominal=(2.5,.22,.14))
    a.box((0,0,-.012),(2.5,.22,.115),'summitStep_dark',.012)
    for i in range(7): a.box((-.99+i*.33,-.005,.017),(.32,.21,.105),'summitStep',.015)
    a.box((0,-.111,.046),(2.5,.015,.023),'summitStep_glow',.004,role='accent')
    a.finish()


def scenery_prop(a,key,pos,scale=1,seed=1):
    x,y,z=pos; dark=key+'_dark'; pale=key+'_pale'; glow=key+'_glow'
    if key=='emberRun':
        for i in range(3): a.prism((x+(i-1)*.35*scale,y,z+scale*(.7+i*.2)),.40*scale,scale*(1.4+i*.4),key,5,top=.65,rot=i*.3)
        a.box((x,y-.36*scale,z+.75*scale),(.035*scale,.045*scale,1.2*scale),glow,.006,role='accent')
    elif key=='summitStep':
        for i in range(3): a.box((x+(i%2)*.12*scale,y,z+(.20+i*.35)*scale),(1.1*scale,.95*scale,.38*scale),key,.08,rot=(i-1)*.05)
        a.prism((x+.25*scale,y,z+1.65*scale),.32*scale,1.5*scale,pale,4,top=.08)
    elif key=='lowCrawl':
        a.box((x,y,z+scale),(.7*scale,.65*scale,2*scale),dark,.06)
        for i in range(6): a.box((x,y-.36*scale,z+(.25+i*.3)*scale),(.66*scale,.07*scale,.11*scale),key,.015)
        a.box((x,y-.41*scale,z+1.7*scale),(.12*scale,.025*scale,.31*scale),glow,.008,role='accent')
    elif key=='ghostGlass':
        for i in range(3):
            a.box((x+(i-1)*.28*scale,y+i*.16*scale,z+(1+i*.15)*scale),(.32*scale,.09*scale,(1.8+i*.2)*scale),pale,.02,rot=(i-1)*.07)
            a.box((x+(i-1)*.28*scale,y+i*.16*scale-.055,z+(1+i*.15)*scale),(.014*scale,.01*scale,(1.8+i*.2)*scale),glow,.003,role='accent')
    elif key=='stormPass':
        a.box((x,y,z+.9*scale),(.72*scale,.8*scale,1.8*scale),dark,.05,rot=.08)
        for i in range(4): a.box((x,y-.20*scale,z+(.35+i*.42)*scale),(1.1*scale,.20*scale,.14*scale),key,.025,rot=-.16)
        a.prism((x,y,z+2.2*scale),.045*scale,.9*scale,'silver',8,top=1)
        a.gem((x,y,z+2.7*scale),.075*scale,.23*scale,glow,4,role='accent')
    else:
        a.prism((x,y,z+.15*scale),.70*scale,.30*scale,dark,7,top=.85)
        for i in range(5):
            theta=i*2.4; h=(1.1+(i%3)*.48)*scale
            a.gem((x+math.cos(theta)*.34*scale,y+math.sin(theta)*.3*scale,z+h*.5),(.15+i*.022)*scale,h,pale if i%2 else key,6,tilt=(i-2)*.11)
        a.gem((x-.25*scale,y-.32*scale,z+.32*scale),.14*scale,.7*scale,glow,5,role='accent')


def biome_assets(key):
    for i in range(3): obstacle(key,i)
    a=Asset('prop_'+key,key); scenery_prop(a,key,(0,0,0)); a.finish()
    a=Asset('floor_'+key,key)
    for i in [-1,0,1]:
        a.box((i*.75,0,.009),(.65,.93,.012),key,.006)
        # Slots preserve sight of the common lane spine.
        a.box((i*.75,0,.018),(.020,.85,.006),key+'_glow',.002,role='tint_lane')
    a.finish()
    a=Asset('environment_'+key,key)
    # Portal-local origin is the aperture center; move the scene floor to -1.25m.
    floor=-1.25
    a.box((0,12,floor-.10),(14,25,.18),key+'_dark',.06)
    a.box((0,26,4),(32,.15,14),key+'_sky',.015,role='backdrop')
    for i in range(12):
        y=1+i*2
        a.box((0,y,floor),(3.05,1.92,.035),key,.01)
        for x in [-.75,0,.75]: a.box((x,y,floor+.022),(.025,1.8,.012),key+'_glow',.003,role='lane')
        for s in [-1,1]:
            a.box((s*1.62,y,floor+.03),(.12,1.92,.09),'alloy',.015)
            if i%2==0: scenery_prop(a,key,(s*(2.35+(i%3)*.3),y,floor),1+(i%3)*.22,seed=i)
    # Environment silhouettes: open summit, compressed service tunnel, monumental forge,
    # floating gallery, charged exposed array, or asymmetric mineral vault.
    for i,y in enumerate([3,7.5,12,17,22]):
        if key=='emberRun':
            for s in [-1,1]:
                a.prism((s*3,y,floor+2.2),.48,4.4,key,6,top=.72)
                a.beam((s*3,y,3.1),(s*1.65,y,4.2),.28,.40,'alloy')
            a.ring(1.4,1.4,.12,.24,key+'_glow',32,role='accent',pos=(0,y,4.2))
        elif key=='summitStep':
            for s in [-1,1]:
                a.prism((s*(4+i*.30),y,1.2),1.8,5+i*.5,key,5,top=.08,rot=i*.6)
                a.prism((s*(5.8+i*.2),y+1.5,2),1.4,7+i*.35,key+'_pale',4,top=.05,rot=i*.4)
            if i%2==0:
                a.beam((-2.6,y,2.3),(-1.9,y,3.8),.22,.32,'silver')
                a.beam((2.6,y,2.3),(1.9,y,3.8),.22,.32,'silver')
        elif key=='lowCrawl':
            for s in [-1,1]:
                a.box((s*2.20,y,.12),(.22,.35,2.75),key,.04)
                a.beam((s*2.2,y,1.50),(s*1.65,y,1.95),.22,.35,key)
            a.box((0,y,1.99),(3.35,.38,.2),key,.03)
            a.box((0,y-.22,1.87),(2.85,.035,.026),key+'_glow',.006,role='accent')
            a.box((0,y+2,2.25),(5,4,.3),key+'_dark',.025)
            for x in [-1.7,1.7]: a.beam((x,y-1,1.72),(x,y+3,1.72),.085,.085,'silver')
        elif key=='ghostGlass':
            for s in [-1,1]:
                a.box((s*2.6,y,1.6),(.13,.20,5.6),key+'_pale',.025,rot=s*.035)
                a.box((s*2.67,y,1.6),(.018,.23,5.7),key+'_glow',.003,role='accent')
            a.box((0,y,4.38),(5.3,.25,.13),key+'_pale',.02)
            a.box((0,y+.5,floor+.08),(2.7,.8,.025),key+'_pale',.01)
        elif key=='stormPass':
            for s in [-1,1]:
                a.beam((s*3,y,floor),(s*2.4,y,4.0),.2,.30,key)
                a.beam((s*2.4,y,4),(s*4,y,5),.17,.24,'silver')
                for j in range(3): a.box((s*(3+j*.33),y+.15,2.7+j*.45),(.7,.06,.3),key,.02,rot=s*-.3)
            # Lightning stays high and beyond the playable corridor.
            a.beam((-1.4,y,6),(-.9,y,5.3),.022,.022,key+'_glow','accent')
            a.beam((-.9,y,5.3),(-1.2,y,4.9),.022,.022,key+'_glow','accent')
        else:
            for s in [-1,1]:
                a.gem((s*3.2,y,2.7),.62,6,key,6,tilt=-s*.34)
                a.gem((s*2.5,y+.4,4.6),.37,3.0,key+'_pale',5,tilt=s*.45)
            a.gem((.8,y,5.6),.32,2.2,key+'_pale',6,tilt=.10)
    if key=='summitStep': a.gem((-.8,25,7.4),1.5,2.2,'warm',32,role='sun')
    a.finish()
    # Small physical diorama for each wordless choice gate, derived from its full kit.
    a=Asset('preview_'+key,key)
    a.box((0,.15,0),(.70,.04,1.75),key+'_sky',.03,role='backdrop')
    for s in [-1,1]: scenery_prop(a,key,(s*.19,0,-.64),.24)
    a.box((0,-.01,-.68),(.70,.45,.05),key,.012)
    for x in [-.18,0,.18]: a.box((x,-.04,-.65),(.008,.4,.008),key+'_glow',.002,role='accent')
    if key in ['lowCrawl','ghostGlass']: a.box((0,0,.68),(.68,.16,.075),key,.012)
    if key=='emberRun': a.ring(.23,.25,.018,.024,key+'_glow',24,pos=(0,.01,.41),role='accent')
    if key=='stormPass': a.beam((-.19,0,.45),(.18,0,.58),.012,.01,key+'_glow','accent')
    if key=='crystalCave': a.gem((0,0,.28),.095,.55,key+'_glow',6,role='accent')
    a.finish()


def bake_usd_transforms(path):
    """Bake the axis conversion into mesh data; runtime pivots stay identity/Y-up."""
    from pxr import Usd, UsdGeom, UsdUtils, Gf, Vt
    with tempfile.TemporaryDirectory(prefix='slipframe_usd_') as folder:
        with zipfile.ZipFile(path) as archive:
            archive.extractall(folder)
            layer=Path(folder)/archive.namelist()[0]
        stage=Usd.Stage.Open(str(layer))
        cache=UsdGeom.XformCache()
        for prim in stage.Traverse():
            if prim.IsA(UsdGeom.Mesh):
                mesh=UsdGeom.Mesh(prim); matrix=cache.GetLocalToWorldTransform(prim)
                points=[Gf.Vec3f(matrix.Transform(Gf.Vec3d(p))) for p in mesh.GetPointsAttr().Get()]
                mesh.GetPointsAttr().Set(Vt.Vec3fArray(points))
                normals=mesh.GetNormalsAttr().Get()
                if normals:
                    normal_matrix=matrix.GetInverse().GetTranspose()
                    mesh.GetNormalsAttr().Set(Vt.Vec3fArray([Gf.Vec3f(normal_matrix.TransformDir(Gf.Vec3d(n)).GetNormalized()) for n in normals]))
                mesh.GetExtentAttr().Set(UsdGeom.PointBased.ComputeExtent(points))
        for prim in stage.Traverse():
            if prim.IsA(UsdGeom.Xformable): UsdGeom.Xformable(prim).ClearXformOpOrder()
        stage.GetRootLayer().Save()
        ready=path.with_name(path.stem+'.ready.usdz')
        if not UsdUtils.CreateNewUsdzPackage(str(layer),str(ready)):
            raise RuntimeError('USDZ packaging failed: '+str(path))
        ready.replace(path)


def export_assets(names=None):
    from pxr import Usd, UsdGeom
    scene=bpy.data.scenes[SCENE_NAME]; bpy.context.window.scene=scene
    manifest=[]
    gc.collect()
    for name,entry in ASSETS.items():
        if names and name not in names: continue
        root=entry['root']; original=root.location.copy(); root.location=(0,0,0)
        bpy.context.view_layer.update()
        bpy.ops.object.select_all(action='DESELECT')
        root.select_set(True)
        for obj in entry['collection'].objects:
            obj.select_set(True)
            # RealityKit can keep the Mesh prim rather than its object Xform as
            # the ModelComponent owner. Put the role on BOTH exported names.
            if obj.type=='MESH': obj.data.name=obj.name
        path=RUNTIME/(name+'.usdz')
        try:
            bpy.ops.wm.usd_export(filepath=str(path),selected_objects_only=True,
                export_animation=False,export_lights=False,export_cameras=False,
                export_materials=True,generate_preview_surface=True,generate_materialx_network=False,
                convert_orientation=True,export_global_forward_selection='NEGATIVE_Z',export_global_up_selection='Y',
                convert_scene_units='METERS',triangulate_meshes=True,export_textures_mode='NEW',
                overwrite_textures=True,relative_paths=True,root_prim_path='/Slipframe',
                export_custom_properties=False)
            bake_usd_transforms(path)
            stage=Usd.Stage.Open(str(path))
            cache=UsdGeom.BBoxCache(Usd.TimeCode.Default(),[UsdGeom.Tokens.default_,UsdGeom.Tokens.render])
            bound=cache.ComputeWorldBound(stage.GetDefaultPrim()).ComputeAlignedRange()
            triangles=sum(len(p.vertices)-2 for o in entry['collection'].objects if o.type=='MESH' for p in o.data.polygons)
            manifest.append(dict(id=name,file=name+'.usdz',family=entry['family'],
                triangles=triangles,meshCount=sum(o.type=='MESH' for o in entry['collection'].objects),
                boundsMin=list(bound.GetMin()),boundsMax=list(bound.GetMax()),
                metersPerUnit=UsdGeom.GetStageMetersPerUnit(stage),upAxis=str(UsdGeom.GetStageUpAxis(stage)),
                bytes=path.stat().st_size))
            # Release USD file mappings before the next export/re-export on Windows.
            del bound, cache, stage
            gc.collect()
        finally:
            root.location=original
    if not names:
        (RUNTIME/'manifest.json').write_text(json.dumps(dict(version=1,source='Art/Blender/Slipframe_ArtSource.blend',assets=manifest),indent=2)+'\n')
        print('Exported',len(manifest),'assets;',sum(m['triangles'] for m in manifest),'triangles total')
    return manifest


def save_source():
    for image in bpy.data.images:
        if image.name.startswith('SF_') and image.source=='FILE':
            if not image.packed_file: image.pack()
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'Slipframe_ArtSource.blend'))


if __name__=='__main__':
    setup(); shared(); hazards()
    for key in BIOMES: biome_assets(key)
    export_assets(); save_source()
