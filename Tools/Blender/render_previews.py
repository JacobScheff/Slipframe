"""Render the authored library, environments and menu thumbnails in Blender."""
from pathlib import Path
import bpy
import math
import sys
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'Art'/'Previews'
BIOMES=['emberRun','summitStep','ghostGlass','lowCrawl','stormPass','crystalCave']
OUT.mkdir(parents=True,exist_ok=True)


def copy_asset(scene,name,position=(0,0,0),scale=1):
    source=bpy.data.collections[name]
    root=bpy.data.objects.new('preview_'+name,None)
    scene.collection.objects.link(root)
    root.location=position; root.scale=(scale,scale,scale)
    for obj in source.objects:
        if obj.type!='MESH': continue
        clone=obj.copy(); clone.data=obj.data
        scene.collection.objects.link(clone)
        clone.parent=root; clone.location=obj.location; clone.rotation_euler=obj.rotation_euler
    return root


def studio(name,size=(1000,700)):
    scene=bpy.data.scenes.new(name)
    bpy.context.window.scene=scene
    scene.render.engine='CYCLES'
    scene.cycles.samples=24
    scene.cycles.use_denoising=True
    scene.render.resolution_x=size[0]; scene.render.resolution_y=size[1]; scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG'
    scene.world=bpy.data.worlds.new(name+'_world'); scene.world.use_nodes=True
    bg=next(n for n in scene.world.node_tree.nodes if n.type=='BACKGROUND')
    bg.inputs['Color'].default_value=(.16,.21,.30,1); bg.inputs['Strength'].default_value=.4
    for label,pos,power,color,spread in [('Key',(1,-4,6),1500,(.77,.86,1),7),('Fill',(-4,2,3),1100,(.35,.65,1),6),('Rim',(3,8,5),1800,(1,.57,.28),5)]:
        data=bpy.data.lights.new(name+label,'AREA'); data.energy=power; data.color=color; data.shape='DISK'; data.size=spread
        light=bpy.data.objects.new(name+label,data); scene.collection.objects.link(light); light.location=pos
        light.rotation_euler=(Vector((0,3,0))-light.location).to_track_quat('-Z','Y').to_euler()
    camera=bpy.data.cameras.new(name+'_camera'); obj=bpy.data.objects.new(name+'_camera',camera)
    scene.collection.objects.link(obj); scene.camera=obj
    return scene


def camera_at(scene,position,target,lens=40,ortho=None):
    camera=scene.camera; camera.location=position
    camera.rotation_euler=(Vector(target)-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.data.lens=lens
    if ortho: camera.data.type='ORTHO'; camera.data.ortho_scale=ortho


def render_environments():
    for key in BIOMES:
        scene=studio('Preview_'+key,(1000,700))
        copy_asset(scene,'environment_'+key)
        copy_asset(scene,'wall_'+key+'_0',(-.75,2.9,-.35))
        copy_asset(scene,'wall_'+key+'_1',(.75,7,-.35))
        if key=='lowCrawl': copy_asset(scene,'hazard_duck',(0,11,.125))
        if key=='summitStep': copy_asset(scene,'hazard_jump',(0,10,-1.18))
        pickup='crystal_azure_charged' if key=='crystalCave' else 'token'
        for y in [2.6,3.3,4]: copy_asset(scene,pickup,(.75,y,.05))
        camera_at(scene,(2.5,-6.3,2.2),(0,6,.5),36)
        scene.render.filepath=str(OUT/(key+'.png')); bpy.ops.render.render(write_still=True)
        # Same render is shipped as UI art, with text rendered natively by SwiftUI.
        dest=ROOT/'Endless Runner'/'Assets.xcassets'/('Biome_'+key+'.imageset')
        dest.mkdir(parents=True,exist_ok=True)
        image=bpy.data.images.get('Render Result')
        image.save_render(str(dest/(key+'.png')),scene=scene)


def render_lineup():
    scene=studio('Preview_ObstacleLineup',(1600,900))
    for i,key in enumerate(BIOMES):
        x=(i-2.5)*1.5
        copy_asset(scene,'wall_'+key+'_0',(x,0,.90))
        copy_asset(scene,'floor_'+key,(x,0,0),.44)
        data=bpy.data.curves.new('label_'+key,'FONT'); data.body=key.replace('Run',' RUN').replace('Step',' STEP').replace('Glass',' GLASS').replace('Crawl',' CRAWL').replace('Pass',' PASS').replace('Cave',' CAVE').upper()
        data.align_x='CENTER'; data.size=.12; data.extrude=.001
        obj=bpy.data.objects.new('label_'+key,data); scene.collection.objects.link(obj)
        obj.location=(x,-.64,-.14); obj.rotation_euler=(math.pi/2,0,0)
    camera_at(scene,(3.5,-13,5.6),(0,0,.70),45,ortho=10.3)
    scene.render.filepath=str(OUT/'obstacle-lineup.png'); bpy.ops.render.render(write_still=True)


def render_portals():
    """Art review, not a simulation of RealityKit portal clipping."""
    scene=studio('Preview_PortalKit',(1600,900))
    copy_asset(scene,'rift_frame',(-1.05,0,1.52))
    copy_asset(scene,'rift_aperture',(-1.05,.025,1.52))
    for rx,rz,y,angle in [(1.930,1.355,-.30,.2),(1.854,1.292,-.23,-.15)]:
        energy=copy_asset(scene,'rift_energy')
        holder=bpy.data.objects.new('elliptical_motion_pivot',None)
        scene.collection.objects.link(holder)
        holder.location=(-1.05,y,1.52); holder.scale=(rx,1,rz)
        energy.parent=holder; energy.rotation_euler.y=angle
    copy_asset(scene,'junction_frame',(1.78,0,1.12))
    copy_asset(scene,'junction_aperture',(1.78,.025,1.12))
    energy=copy_asset(scene,'rift_energy',(1.78,-.22,1.12))
    energy.scale=(.422,1,.985)
    # Native biome preview assembly sits in the gate for scale reference.
    copy_asset(scene,'preview_crystalCave',(1.78,-.01,1.12),.94)
    for x in [1.64,1.78,1.92]: copy_asset(scene,'glyph_risk',(x,-.12,2.35),.09)
    copy_asset(scene,'glyph_aegis',(1.78,-.27,.41),.25)
    camera_at(scene,(1,-9,4.7),(-.40,0,1.45),45,ortho=7.4)
    scene.render.filepath=str(OUT/'portal-kit.png'); bpy.ops.render.render(write_still=True)


if __name__=='__main__':
    if '--portals-only' in sys.argv:
        render_portals()
    else:
        render_lineup()
        render_environments()
        render_portals()
