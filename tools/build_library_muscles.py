"""Add educational surface regions to each corrected exercise; keep skin/motion.

Run inside Blender after tools/motion_library.py. No force data is produced.
"""
import json
import struct
import sys
from pathlib import Path
import bpy

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from build_squat_muscles import overlay, mask as squat_mask, ellipse, ramp


def region_mask(co, region, side=None):
    if side is not None:
        if side not in ('left','right'):raise ValueError('Unknown anatomical side: '+side)
        return region_mask(co,region)*ramp(-.01,.01,co[0]*(1 if side=='left' else -1))
    if region in ('quads','glutes','core'):
        return squat_mask(co,region)
    x,y,z=co;x=abs(x)
    front=1-ramp(-.035,.035,y)
    rear=ramp(.04,.085,y)
    if region=='chest':
        return ellipse(x,z,.088,1.13,.084,.077)*front*ramp(.009,.028,x)
    if region=='deltoids':
        return ellipse(x,z,.182,1.18,.058,.075,-.25)*ramp(.123,.155,x)
    if region=='biceps':
        return ellipse(x,z,.232,1.084,.043,.079,-.67)*front
    if region=='triceps':
        return ellipse(x,z,.237,1.079,.044,.081,-.67)*rear
    if region=='lats':
        return ellipse(x,z,.123,1.074,.049,.108,.13)*rear
    if region=='upper_back':
        return ellipse(x,z,.059,1.165,.080,.066)*rear*ramp(.009,.025,x)
    if region=='hamstrings':
        return ellipse(x,z,.125,.592,.058,.142,-.12)*rear*ramp(.428,.455,z)
    if region=='calves':
        return ellipse(x,z,.146,.253,.053,.117,-.11)*rear
    raise ValueError('Unknown region: '+region)


def patch_glb(path):
    raw=path.read_bytes();size=struct.unpack_from('<I',raw,12)[0]
    doc=json.loads(raw[20:20+size]);binary=raw[20+size:]
    for material in doc['materials']:
        overlay_layer=material['name'].startswith('PULSE Muscle ')
        material['alphaMode']='BLEND' if overlay_layer else 'OPAQUE'
        material['doubleSided']=not overlay_layer
        if overlay_layer:
            material.setdefault('pbrMetallicRoughness',{})['baseColorFactor']=[1,1,1,0]
    encoded=json.dumps(doc,separators=(',',':')).encode()
    encoded+=b' '*((-len(encoded))%4)
    path.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(binary))+
                    struct.pack('<II',len(encoded),0x4e4f534a)+encoded+binary)


def color_editable(regions):
    for region in regions:
        rgb=(1,.12,.018) if region['role']=='primary' else (.012,.5,.3)
        material=bpy.data.materials['PULSE Muscle '+region['id']]
        nodes=material.node_tree.nodes;links=material.node_tree.links
        shader=next(n for n in nodes if n.type=='BSDF_PRINCIPLED')
        color=next(n for n in nodes if n.type=='VERTEX_COLOR')
        mix=nodes.new('ShaderNodeMixRGB');mix.blend_type='MULTIPLY'
        mix.inputs[0].default_value=1;mix.inputs[2].default_value=(*rgb,1)
        links.new(color.outputs['Color'],mix.inputs[1]);links.new(mix.outputs['Color'],shader.inputs['Base Color'])
        alpha=nodes.new('ShaderNodeMath');alpha.operation='MULTIPLY';alpha.inputs[1].default_value=.8
        links.new(color.outputs['Alpha'],alpha.inputs[0]);links.new(alpha.outputs[0],shader.inputs['Alpha'])
        shader.inputs['Emission Color'].default_value=(*(v*.12 for v in rgb),1)
        shader.inputs['Emission Strength'].default_value=1
        material.diffuse_color=(*rgb,.8)


def main():
    catalog=json.loads((ROOT/'assets/muscles/catalog.json').read_text())['exercises']
    ids=[sys.argv[sys.argv.index('--exercise')+1]] if '--exercise' in sys.argv else list(catalog)
    work=ROOT/'.build/motion-library/muscles';work.mkdir(parents=True,exist_ok=True)
    for key in ids:
        bpy.ops.wm.open_mainfile(filepath=str(ROOT/f'.build/motion-library/{key}.blend'),use_scripts=False)
        rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
        regions=catalog[key]['regions']
        reports=[overlay(bpy.data.objects['Boxers' if r['id']=='glutes' else 'Man'],rig,r['id'],
                         lambda co,region,r=r:region_mask(co,region,r.get('side'))) for r in regions]
        bpy.ops.object.select_all(action='DESELECT');rig.select_set(True)
        for ob in bpy.context.scene.objects:
            if ob.type=='MESH':ob.select_set(True)
        bpy.context.view_layer.objects.active=rig
        path=ROOT/f'assets/models/athlete_{key}.glb'
        bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,
            export_animations=True,export_animation_mode='ACTIVE_ACTIONS',export_force_sampling=True,
            export_optimize_animation_size=False,
            export_nla_strips_merged_animation_name='Exercise',export_frame_range=True,export_yup=True,export_morph=False)
        patch_glb(path)
        color_editable(regions)
        bpy.ops.wm.save_as_mainfile(filepath=str(work/f'{key}.blend'))
        (work/f'{key}-regions.json').write_text(json.dumps(reports,indent=2))
        print('MUSCLES_READY',key,flush=True)


if __name__=='__main__':main()
