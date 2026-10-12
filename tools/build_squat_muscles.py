"""Add skinned, feathered surface-region overlays to the approved squat sample.

These are educational regions, not segmented internal muscles or measured force.
Original meshes, weights and motion are not edited. Run inside Blender.
"""
import json
import math
import struct
from pathlib import Path
import bpy

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / '.build/squat-muscles'
OUT = ROOT / 'web/review/squat-muscles.glb'


def ramp(a, b, value):
    t = min(1., max(0., (value-a)/(b-a)))
    return t*t*(3-2*t)


def ellipse(x, z, cx, cz, rx, rz, tilt=0):
    dx = x-cx-tilt*(z-cz)
    distance = math.sqrt((dx/rx)**2+((z-cz)/rz)**2)
    return 1-ramp(.68,1.05,distance)


def mask(co, region):
    x,y,z = co
    x = abs(x)
    if region == 'quads':
        # Broad quadriceps surface region with tapered outer/central/medial lobes.
        shape=max(ellipse(x,z,.117,.605,.043,.148,-.12),
                  ellipse(x,z,.172,.59,.047,.123,-.12),
                  ellipse(x,z,.075,.510,.033,.061,-.2))
        return shape*(1-ramp(-.035,.045,y))*ramp(.428,.46,z)*(1-ramp(.71,.755,z))
    if region == 'glutes':
        return ellipse(x,z,.090,.764,.091,.092)*ramp(.028,.073,y)*ramp(.012,.035,x)
    front=max(ellipse(x,z,0,.982,.082,.125),
              ellipse(x,z,.119,.976,.037,.113,.10))*(1-ramp(-.055,-.005,y))
    back=ellipse(x,z,.047,1.006,.026,.145)*ramp(.048,.085,y)
    return max(front,back)


def overlay(source, rig, region, mask_function=None):
    mesh=source.data
    region_mask=mask_function or mask
    values=[region_mask(v.co,region) for v in mesh.vertices]
    faces=[p for p in mesh.polygons if max(values[v] for v in p.vertices)>.012]
    indices=sorted({i for p in faces for i in p.vertices})
    lookup={old:new for new,old in enumerate(indices)}
    vertices=[mesh.vertices[i].co+mesh.vertices[i].normal*.0008 for i in indices]
    data=bpy.data.meshes.new('Muscle region '+region)
    data.from_pydata(vertices,[],[[lookup[i] for i in p.vertices] for p in faces]);data.update()
    ob=bpy.data.objects.new('PULSE region '+region,data)
    bpy.context.collection.objects.link(ob)
    ob.parent=rig
    for g in source.vertex_groups: ob.vertex_groups.new(name=g.name)
    for i,original in enumerate(indices):
        for g in mesh.vertices[original].groups:
            ob.vertex_groups[g.group].add([i],g.weight,'REPLACE')
    modifier=ob.modifiers.new('Same deformation as source surface','ARMATURE');modifier.object=rig
    # Corrected joint surfaces must carry their pose shapes into the overlay.
    # Reuse the exact face/vertex correspondence and the same animated weights.
    if mesh.shape_keys:
        ob.shape_key_add(name='Basis')
        for original_key in mesh.shape_keys.key_blocks[1:]:
            key=ob.shape_key_add(name=original_key.name)
            for i,original in enumerate(indices):
                key.data[i].co=vertices[i]+original_key.data[original].co-mesh.vertices[original].co
            key.value=original_key.value
        animation=mesh.shape_keys.animation_data
        if animation and animation.action:
            ob.data.shape_keys.animation_data_create()
            ob.data.shape_keys.animation_data.action=animation.action
            ob.data.shape_keys.animation_data.action_slot=animation.action_slot
    colors=data.color_attributes.new(name='MuscleMask',type='FLOAT_COLOR',domain='POINT')
    for i,original in enumerate(indices): colors.data[i].color=(1,1,1,values[original])
    data.color_attributes.active_color=colors
    for p in data.polygons: p.use_smooth=True
    # Copy the source split normals so the overlaid region keeps the body shading.
    data.normals_split_custom_set_from_vertices([mesh.vertices[i].normal for i in indices])
    material=bpy.data.materials.new('PULSE Muscle '+region)
    material.use_nodes=True;material.surface_render_method='DITHERED'
    nodes=material.node_tree.nodes;links=material.node_tree.links
    nodes.clear()
    shader=nodes.new('ShaderNodeBsdfPrincipled')
    output=nodes.new('ShaderNodeOutputMaterial')
    links.new(shader.outputs['BSDF'],output.inputs['Surface'])
    shader.inputs['Base Color'].default_value=(1,1,1,1)
    shader.inputs['Roughness'].default_value=.65
    shader.inputs['Specular IOR Level'].default_value=.12
    shader.inputs['Emission Color'].default_value=(0,0,0,1)
    color=nodes.new('ShaderNodeVertexColor');color.layer_name='MuscleMask'
    links.new(color.outputs['Color'],shader.inputs['Base Color'])
    links.new(color.outputs['Alpha'],shader.inputs['Alpha'])
    data.materials.append(material)
    return {'region':region,'source':source.name,'vertices':len(vertices),'faces':len(faces),
            'alpha_min':min(values[i] for i in indices),'alpha_max':max(values[i] for i in indices)}


def main():
    WORK.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=str(ROOT/'.build/squat-sample/squat-v2.blend'),use_scripts=False)
    rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
    reports=[overlay(bpy.data.objects['Man'],rig,'quads'),
             overlay(bpy.data.objects['Boxers'],rig,'glutes'),
             overlay(bpy.data.objects['Man'],rig,'core')]
    bpy.ops.object.select_all(action='DESELECT');rig.select_set(True)
    for ob in bpy.context.scene.objects:
        if ob.type=='MESH': ob.select_set(True)
    bpy.context.view_layer.objects.active=rig
    bpy.ops.export_scene.gltf(filepath=str(OUT),export_format='GLB',use_selection=True,
        export_animations=True,export_animation_mode='ACTIVE_ACTIONS',export_force_sampling=True,
        export_nla_strips_merged_animation_name='Exercise',export_frame_range=True,export_yup=True,export_morph=False)
    # Hide overlays until the viewer applies its selected mode. Preserve alpha
    # gradients on these materials; the production opaque finalizer cannot do so.
    data=OUT.read_bytes();size=struct.unpack_from('<I',data,12)[0]
    doc=json.loads(data[20:20+size]);binary=data[20+size:]
    for mat in doc['materials']:
        if mat['name'].startswith('PULSE Muscle '):
            mat['alphaMode']='BLEND';mat['doubleSided']=False
            mat.setdefault('pbrMetallicRoughness',{})['baseColorFactor']=[1,1,1,0]
        else:
            mat['alphaMode']='OPAQUE';mat['doubleSided']=True
    encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
    OUT.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(binary))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+binary)
    # Make the editable Blender deliverable show the same static region palette.
    # Browser phase emphasis remains a runtime effect, not muscle-force data.
    palette={'quads':(1,.12,.018),'glutes':(1,.21,.018),'core':(.012,.5,.3)}
    for region, rgb in palette.items():
        material=bpy.data.materials['PULSE Muscle '+region]
        nodes=material.node_tree.nodes;links=material.node_tree.links
        shader=next(n for n in nodes if n.type=='BSDF_PRINCIPLED')
        color=next(n for n in nodes if n.type=='VERTEX_COLOR')
        mix=nodes.new('ShaderNodeMixRGB');mix.blend_type='MULTIPLY'
        mix.inputs[0].default_value=1;mix.inputs[2].default_value=(*rgb,1)
        links.new(color.outputs['Color'],mix.inputs[1])
        links.new(mix.outputs['Color'],shader.inputs['Base Color'])
        alpha=nodes.new('ShaderNodeMath');alpha.operation='MULTIPLY'
        alpha.inputs[1].default_value=.8
        links.new(color.outputs['Alpha'],alpha.inputs[0])
        links.new(alpha.outputs[0],shader.inputs['Alpha'])
        shader.inputs['Emission Color'].default_value=(*(v*.12 for v in rgb),1)
        shader.inputs['Emission Strength'].default_value=1
        material.diffuse_color=(*rgb,.8)
    bpy.ops.wm.save_as_mainfile(filepath=str(WORK/'squat-muscles.blend'))
    (WORK/'regions.json').write_text(json.dumps(reports,indent=2))
    print('REGIONS',json.dumps(reports))


if __name__=='__main__': main()
