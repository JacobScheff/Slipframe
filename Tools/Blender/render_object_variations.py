"""Inspect actual exported-source variants side by side, including ghost alpha."""
from pathlib import Path
import bpy
import runpy

ROOT=Path(__file__).resolve().parents[2]
H=runpy.run_path(str(ROOT/'Tools/Blender/render_previews.py'),run_name='object_review_helpers')


def label(scene,text,x,z,size=.14):
    data=bpy.data.curves.new('VariantLabel','FONT')
    data.body=text; data.size=size
    material=bpy.data.materials.get('VariantReviewLabel')
    if material is None:
        material=bpy.data.materials.new('VariantReviewLabel')
        node=next(n for n in material.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
        node.inputs['Emission Color'].default_value=(.75,.86,1,1)
        node.inputs['Emission Strength'].default_value=1
    data.materials.append(material)
    obj=bpy.data.objects.new('VariantLabel',data)
    scene.collection.objects.link(obj)
    obj.location=(x,-.60,z)
    # Blender camera looks along +Y; the text face points toward -Y.
    obj.rotation_euler.x=1.57079632679


def setup():
    scene=H['studio']('ObjectVariationReview',(800,1800))
    try: scene.render.engine='BLENDER_EEVEE'
    except TypeError: scene.render.engine='CYCLES'
    for i,key in enumerate(H['BIOMES']):
        z=11-i*2.1
        label(scene,key,-3.1,z+.73)
        for v in range(3):
            H['copy_asset'](scene,f'wall_{key}_{v}',((v-1)*1.3,0,z))
    for i,kind in enumerate(['duck','jump']):
        z=-2.6-i*1.1
        label(scene,kind+' gate',-3.1,z+.34)
        for v in range(3):
            suffix='' if v==0 else '_'+str(v)
            H['copy_asset'](scene,'hazard_'+kind+suffix,((v-1)*1.8,0,z),.62)
    for i,base in enumerate(['token','crystal_azure','crystal_coral']):
        z=-4.9-i*.8
        label(scene,base,-3.1,z+.15)
        for v in range(3):
            suffix='' if v==0 else '_'+str(v)
            H['copy_asset'](scene,base+suffix,((v-1)*1.3,0,z),2.5)
    for v in range(3): label(scene,'VARIANT '+str(v+1),(v-1)*1.3-.40,12.25)
    H['camera_at'](scene,(0,-26,3),(0,0,3),50,ortho=20)
    return scene


if __name__=='__main__':
    scene=setup()
    scene.render.filepath=str(ROOT/'Art/Previews/object-variations.png')
    bpy.ops.render.render(write_still=True)
