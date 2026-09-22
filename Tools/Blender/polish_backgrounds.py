"""Second, incremental art pass: surface relief, asymmetry and local detail.

Operates on environment/prop collections only. Shared portal materials, hazards,
animation pivots and the road footprint are preserved. Run once after pass one.
"""
from pathlib import Path
import hashlib
import json
import math
import random
import runpy
import bpy
import numpy as np
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
first = runpy.run_path(str(ROOT / 'Tools/Blender/refine_backgrounds.py'), run_name='background_helpers_v2')
sf, A, M = first['sf'], first['A'], first['M']
KEYS = first['BIOMES']
FLOOR = -1.25


def detail_material(name, color, strength=.7):
    key = 'detail_' + name
    M[key] = sf['material']('SF_' + key, color, .08, .82, strength)
    return key


def surface_relief(force=False):
    # The first fill used a constant emission color. Bake restrained stone grain
    # and panel wear into that emission so it remains visible without scene lights.
    size = 128
    yy, xx = np.mgrid[0:size, 0:size] / size
    used = {mat for name, entry in sf['ASSETS'].items()
            if name.startswith(('environment_', 'prop_'))
            for obj in entry['collection'].objects if obj.type == 'MESH'
            for mat in obj.data.materials if mat and mat.name.startswith('SF_BG_')}
    for mat in sorted(used, key=lambda m: m.name):
        if (mat.get('surface_relief_v2') and not force) or '_surface_' not in mat.name:
            continue
        key = next(k for k in KEYS if 'SF_BG_'+k+'_' in mat.name)
        node = first['shader'](mat)
        color = np.array(node.inputs['Emission Color'].default_value[:3])
        rng = np.random.default_rng(911 + KEYS.index(key))
        grain = rng.normal(0, .012, (size, size))
        if key in ['summitStep', 'emberRun', 'crystalCave']:
            warp = .09*np.sin(xx*math.tau*2) + .03*np.sin(xx*math.tau*7)
            veins = np.exp(-((np.sin((xx*2 + yy + warp)*math.pi))/.12)**2)
            mottling = np.sin((xx*3 + .3*np.sin(yy*math.tau*2))*math.tau)*np.cos((xx+yy)*math.tau)
            shade = .985 + .018*mottling + .009*np.sin((xx*5-yy*3)*math.tau) - .012*veins + grain*.45
        else:
            seams = ((xx < .018) | (yy < .016)).astype(float)
            brushed = np.sin(yy*math.tau*71)*.025
            shade = .98 - .21*seams + brushed + grain*.5
        pixels = np.ones((size, size, 4), dtype=np.float32)
        pixels[:, :, :3] = np.clip(shade[..., None]*color, 0, 1)
        tex = next((n for n in mat.node_tree.nodes if n.type == 'TEX_IMAGE'
                    and n.image and '_relief' in n.image.name), None)
        previous = tex.image if tex else None
        # Replace this pass's image buffer atomically; changing the color space
        # of a packed FILE image can reload its old dimensions and pixel data.
        image = bpy.data.images.new(mat.name+'_relief', width=size, height=size, alpha=False, float_buffer=True)
        # These texels store linear emission radiance, not display-encoded color.
        # sRGB decoding here would crush the fill and undo the visibility pass.
        assert 'Non-Color' in image.colorspace_settings.bl_rna.properties['name'].enum_items.keys()
        image.colorspace_settings.name = 'Non-Color'
        image.pixels.foreach_set(pixels.ravel())
        image.filepath_raw = str(sf['SOURCE']/'Textures'/(mat.name+'_relief.png'))
        assert 'PNG' in image.bl_rna.properties['file_format'].enum_items.keys()
        image.file_format = 'PNG'
        image.save()
        image.pack()
        if tex is None:
            tex = mat.node_tree.nodes.new('ShaderNodeTexImage')
        tex.image = image
        mat.node_tree.links.new(tex.outputs['Color'], node.inputs['Emission Color'])
        if previous is not None and previous.users == 0:
            bpy.data.images.remove(previous)
        mat['surface_relief_v2'] = True


def shape_cliffs(target, key):
    # One continuous warp across rock and snow meshes keeps shared seams closed.
    # Never deform the road, metal structures, sky, horizons or animated parts.
    if key not in ['summitStep', 'emberRun', 'crystalCave']:
        return
    suffixes = [key, key+'_cut', 'snow']
    if key == 'crystalCave':
        suffixes += [key+'_pale', 'mineral_teal', 'mineral_rose']
    for obj in target['collection'].objects:
        if obj.type != 'MESH' or '__body__' not in obj.name:
            continue
        if obj.name.split('__')[-1] not in suffixes or obj.get('cliff_shape_v2'):
            continue
        obj.data = obj.data.copy()
        for vertex in obj.data.vertices:
            x, y, z = vertex.co
            if abs(x) < 1.95 or z < FLOOR+.03:
                continue
            side = -1 if x < 0 else 1
            h = z-FLOOR
            amount = min(1, (abs(x)-1.95)/1.6)
            height = 1 + amount*(.17*math.sin(y*.43+x*1.31)-.07)
            vertex.co.z = FLOOR + h*height
            vertex.co.x += side*amount*(.24*math.sin(h*1.7+y*.3) + .035*h*math.sin(y*.8))
            vertex.co.y += amount*.34*math.sin(x*1.6 + h*.5)
        obj.data.update()
        # Refresh the baked directional bands after changing face normals.
        light = Vector((-.55, -.70, .85)).normalized()
        if len(obj.data.materials) == 4:
            for face in obj.data.polygons:
                face.material_index = min(3, int(max(0, face.normal.dot(light))*4))
        obj['cliff_shape_v2'] = True


def rock(a, center, size, material, seed, snow=None):
    r = random.Random(seed)
    n = 7
    angles = [i*math.tau/n+r.uniform(-.1, .1) for i in range(n)]
    verts = []
    for z, radius in [(-.5, .7), (-.18, 1), (.26, .82), (.5, .46)]:
        for angle in angles:
            radius_jitter = radius*r.uniform(.82, 1.15)
            verts.append((math.cos(angle)*size[0]*.5*radius_jitter,
                          math.sin(angle)*size[1]*.5*radius_jitter,
                          (z+r.uniform(-.08, .08))*size[2]))
    faces = [list(reversed(range(n)))]
    for row in range(3):
        for i in range(n):
            j = (i+1)%n
            faces.append([row*n+i, row*n+j, (row+1)*n+j, (row+1)*n+i])
    faces.append(list(range(3*n, 4*n)))
    if snow:
        a.add(verts, faces[:-8], material, 'detail', center)
        a.add(verts, faces[-8:], snow, 'detail', center)
    else:
        a.add(verts, faces, material, 'detail', center)


def summit(a, target, r):
    stone = detail_material('alpineStone', (.17, .21, .25))
    pale = detail_material('alpineLedge', (.28, .34, .38))
    snow = detail_material('alpineSnow', (.56, .67, .72), .85)
    cable = detail_material('trailCable', (.17, .105, .06), .7)
    pennant = detail_material('trailOchre', (.53, .25, .065), .8)
    # Broken horizontal shelves and small talus piles interrupt the tall columns.
    for side in [-1, 1]:
        for i in range(8):
            y = i*3.9 + (1.2 if side < 0 else 2.8)
            x = side*r.uniform(3.6, 4.5)
            rock(a, (x, y, -.73), (r.uniform(1.4, 2.4), 1.6, .95), stone, i+int(side)+930, snow if i%3==0 else None)
            if i%2 == 0:
                rock(a, (side*4.3, y+.35, 1.1+r.random()), (2.7, 2.0, .5), pale, i+98, snow)
            for j in range(3):
                rock(a, (side*r.uniform(2.25, 3.0), y+r.uniform(-.7,.7), -1.14),
                     (.22+r.random()*.25, .30, .22), stone if j%2 else pale, i*19+j)
    # Replace the two heavy crossbars with sagging trail cables and a few flags.
    remove_parts(target, ['__body__gold', '__sun__warm'])
    for y in [7, 19]:
        points = [(x, y, 3.72+.07*x-.30*(1-(x/2)**2)) for x in np.linspace(-2, 2, 15)]
        for p, q in zip(points, points[1:]):
            a.beam(p, q, .016, .016, cable, 'detail')
        for x in [-1.35, -.6, .3, 1.15]:
            z = 3.72+.07*x-.30*(1-(x/2)**2)
            a.add([(x-.09,y,z), (x+.09,y,z+.012), (x+.025,y-.03,z-.23)], [[0,1,2]], pennant, 'detail')
    # Substantially smaller, round sun; low-poly crystal geometry read as a token.
    sun = detail_material('alpineSun', (.95, .79, .49), 1.2)
    center = Vector((7, 105, 28))
    normal = -center.normalized()
    right = normal.cross(Vector((0,0,1))).normalized()
    up = normal.cross(right).normalized()
    points = [tuple(center)] + [tuple(center+1.65*(right*math.cos(i*math.tau/64)+up*math.sin(i*math.tau/64))) for i in range(64)]
    a.add(points, [[0,i+1,(i+1)%64+1] for i in range(64)], sun, 'sun')
    # Asymmetric mountain faces beyond the canyon, with readable snow shoulders.
    shadow = detail_material('peakShadow', (.12, .19, .26), 1)
    lit = detail_material('peakLight', (.25, .34, .40), 1)
    ice = detail_material('peakSnow', (.43, .53, .58), 1)
    for x, y, h, w in [(-13,43,12,12),(16,53,16,15),(-23,73,23,21),(30,85,25,26)]:
        peak = (x+w*.08,y,h)
        a.add([(x-w/2,y,-2), (x,y-3,-2), peak], [[0,1,2]], lit, 'detailHorizon')
        a.add([(x,y-3,-2), (x+w/2,y,-2), peak], [[0,1,2]], shadow, 'detailHorizon')
        a.add([peak, (x-w*.13,y-.03,h*.66), (x-.3,y-.85,h*.61),
               (x+w*.1,y-.4,h*.73), (x+w*.22,y-.03,h*.67)],
              [[0,1,2],[0,2,3],[0,3,4]], ice, 'detailHorizon')


def ember(a, r):
    basalt = detail_material('forgeBasalt', (.065, .075, .10), .7)
    rust = detail_material('forgeRust', (.23, .095, .038), .7)
    heat = detail_material('forgeHeat', (.95, .20, .018), 1.25)
    for side in [-1,1]:
        for i in range(8):
            y = i*3.8 + (1.5 if side < 0 else 3)
            rock(a, (side*r.uniform(2.55,3.15),y,-.99), (.9,1.15,.52), basalt, 130+i+int(side))
            # Small recessed furnace mouths sit entirely outside the track.
            if i%3 == 0:
                x = side*3.15
                a.box((x,y,-.4),(.80,.65,1.3),rust,.05,role='detail')
                a.box((x,y-.335,-.3),(.62,.02,.7),heat,0,role='detail')
                for dx in [-.24,-.08,.08,.24]:
                    a.box((x+dx,y-.36,-.3),(.055,.05,.78),basalt,0,role='detail')
            for j in range(3):
                x = side*r.uniform(3.1,3.9)
                rock(a,(x,y+j*.3,-1.17),(.38,.44,.18),rust,i*7+j)
    # Segmented masonry around the existing forge makes it feel supported.
    for side in [-1,1]:
        for z in [-.2,1.0,2.2]:
            rock(a,(side*3.3,27,z),(1.3,2.3,1.5),basalt,int(z*10)+55)


def ghost(a, r):
    slate = detail_material('glassSlate', (.10,.18,.23), .75)
    silver = detail_material('glassSilver', (.23,.36,.40), .8)
    pearl = detail_material('glassPearl', (.46,.68,.72), .8)
    # Slivered floating plinths and occasional shattered fans vary the repeated
    # colonnade without adding transparent full-screen surfaces.
    for side in [-1,1]:
        for i in range(6):
            y = i*5 + (2 if side < 0 else 4.1)
            x = side*(2.8+r.random()*.6)
            a.plate([(-.42,-.15),(.45,-.10),(.35,.09),(-.29,.16)],.7,slate,'detail',(x,y,-.93))
            for j in range(3):
                height = r.uniform(.35,1.15)
                a.gem((x+(j-1)*.22,y,-.65+height/2),.12,height,silver if j%2 else pearl,4,role='detail',tilt=side*(.15+j*.15))
            if i%2 == 0:
                a.plate([(-.11,-.25),(.12,-.07),(.03,.31)],.035,pearl,'motion_float',(side*(3.7+i*.1),y,2.4+r.random()))


def crawl(a):
    steel = detail_material('serviceSteel', (.055,.09,.13), .75)
    trim = detail_material('serviceTrim', (.15,.20,.23), .75)
    amber = detail_material('serviceAmber', (.66,.30,.065), .9)
    cyan = detail_material('serviceStatus', (.08,.40,.54), 1)
    # Asymmetric service panels, conduits and restrained warning bars break the
    # otherwise identical bays. Details attach outside the clearance envelope.
    for i,y in enumerate([3.5,8.8,14.1,20.3,25]):
        side = -1 if i%2 else 1
        x=side*2.83
        a.box((x,y,.20),(.11,1.15,1.45),steel,0,role='detail')
        for z in [-.43,.84]:
            a.box((x-side*.07,y,z),(.025,1.05,.055),trim,0,role='detail')
        a.box((x-side*.075,y-.23,.5),(.025,.28,.18),cyan,0,role='detail')
        for j in range(3):
            a.box((x-side*.075,y+.12+j*.18,-.3),(.025,.08,.12),amber,0,role='detail')
        for z in [-.70,-.82]:
            a.box((side*2.70,y,z),(.06,2.3,.06),trim,0,role='detail')


def storm(a, r):
    metal = detail_material('windSteel', (.085,.14,.19), .75)
    trim = detail_material('windTrim', (.18,.25,.29), .8)
    warm = detail_material('windOchre', (.48,.24,.075), .85)
    # Opposing wind vanes and cable anchors retain a straight open course.
    for i,y in enumerate([3,9,16,24]):
        side=-1 if i%2 else 1
        x=side*(3.4+r.random()*.4)
        a.box((x,y,-.83),(.72,1.1,.78),metal,0,role='detail')
        a.beam((x,y,-.5),(x,y,2.7),.055,.06,trim,'detail')
        a.add([(x,y,2.55),(x+side*.75,y+.12,2.48),(x+side*.55,y+.05,2.18),(x,y,2.37)],
              [[0,1,2,3]],warm,'detail')
        for j in range(3):
            a.box((x,y-.56,-.84+j*.13),(.51,.026,.035),trim,0,role='detail')


def crystal(a, r):
    dark = detail_material('mineralBed', (.095,.05,.17), .75)
    teal = detail_material('mineralVein', (.028,.31,.30), .85)
    pale = detail_material('mineralTips', (.29,.19,.43), .85)
    for side in [-1,1]:
        for i in range(7):
            y=i*4.4 + (1.4 if side<0 else 3.1)
            x=side*r.uniform(2.6,3.25)
            rock(a,(x,y,-1.06),(1.0,1.25,.40),dark,270+i+int(side))
            for j in range(4):
                h=r.uniform(.16,.48)
                a.gem((x+r.uniform(-.35,.35),y+r.uniform(-.4,.4),-1.02+h/2),.07,h,
                      teal if j==0 else pale,5,role='detail',tilt=r.uniform(-.35,.35))
        # Quiet mineral seams meander along the outer bank, away from pickups.
        points=[(side*(3.7+.15*math.sin(i)),i*1.8,-1.0+.15*math.sin(i*.7)) for i in range(17)]
        for p,q in zip(points,points[1:]):
            a.beam(p,q,.018,.023,teal,'detail')


def remove_parts(target, parts):
    for obj in list(target['collection'].objects):
        if any(obj.name.endswith(part) for part in parts):
            mesh=obj.data
            bpy.data.objects.remove(obj,do_unlink=True)
            if mesh.users==0:
                bpy.data.meshes.remove(mesh)


def shade_details(target):
    light=Vector((-.55,-.70,.85)).normalized()
    for obj in target['collection'].objects:
        if obj.type!='MESH' or '__detail__' not in obj.name or obj.get('detail_shading_v2'):
            continue
        source=obj.data.materials[0]
        base=first['shader'](source).inputs['Emission Strength'].default_value
        obj.data.materials.clear()
        for i,weight in enumerate([.48,.70,1.0]):
            name=source.name+'_shade_'+str(i)
            mat=bpy.data.materials.get(name)
            if mat is None:
                mat=source.copy()
                mat.name=name
                first['shader'](mat).inputs['Emission Strength'].default_value=base*weight
            obj.data.materials.append(mat)
        for face in obj.data.polygons:
            face.material_index=min(2,int(max(0,face.normal.dot(light))*3))
        obj['detail_shading_v2']=True


def run():
    scene=bpy.data.scenes[sf['SCENE_NAME']]
    assert scene.get('background_refinement_v1'), 'Apply the visibility/depth pass first.'
    assert not scene.get('background_refinement_v2'), 'Already applied; edit source artwork directly.'
    bpy.context.window.scene=scene
    surface_relief()
    for key in KEYS:
        target=sf['ASSETS']['environment_'+key]
        shape_cliffs(target,key)
        a=A('background_polish_'+key,key)
        r=random.Random(829+KEYS.index(key))
        if key=='summitStep': summit(a,target,r)
        elif key=='emberRun': ember(a,r)
        elif key=='ghostGlass': ghost(a,r)
        elif key=='lowCrawl': crawl(a)
        elif key=='stormPass': storm(a,r)
        else: crystal(a,r)
        # Every ground-level new decoration must stay beyond the 1.85 m corridor.
        # Summit's overhead cables and its distant sky landmarks are exceptions.
        for (role,mat),(verts,faces) in a.parts.items():
            if role not in ['sun','detailHorizon']:
                for x,y,z in verts:
                    assert abs(x)>1.85 or z>2.8, (key,role,'corridor intrusion',x,y,z)
        first['merge_additions'](a,target)
        shade_details(target)
    scene['background_refinement_v2']=True
    sf['save_source']()
    print('Second background refinement saved.')


def verify_protected():
    protected=bpy.app.driver_namespace.get('refinement2_protected')
    if protected:
        changed=[path for path,digest in protected.items() if hashlib.sha256(Path(path).read_bytes()).hexdigest()!=digest]
        assert not changed, 'Protected files changed: '+str(changed)
        print('Protected portal/gameplay files unchanged:',len(protected))


if __name__=='__main__':
    run()
    first['export']()
    verify_protected()
