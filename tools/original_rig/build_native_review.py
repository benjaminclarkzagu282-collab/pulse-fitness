"""Native rig review delivery. Source Skin remains editable with all influences.

The current model-viewer reads JOINTS_0 only. The web review therefore uses
mesh animation baked from the complete original Skin, never top-four weights.
"""
import argparse, hashlib, json, math, sys
from pathlib import Path
import bpy
import numpy as np
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'));sys.path.insert(0,str(Path(__file__).parent))
import build_realistic_athlete as materials
from native_upper import NativeUpper,GRIP_CENTER,HANDLE_RADIUS,HALF_HANDLE
from squat_sample import depth_at

def fingerprint(body):
    rows=[[(g.group,float(g.weight)) for g in v.groups] for v in body.data.vertices]
    return hashlib.sha256(json.dumps(rows,separators=(',',':')).encode()).hexdigest()

def prepare(output):
    materials.WORK=output;(output/'textures').mkdir(exist_ok=True)
    body=bpy.data.objects['Man'];body.data.materials.clear()
    for part in ['Body','Head']:
        body.data.materials.append(materials.material('Original '+part,diffuse=part+'_unscattered.png',normal=part+'_normal.png'))
    uv=body.data.uv_layers.active.uv
    for p in body.data.polygons:
        head=sum(uv[i].vector.x for i in p.loop_indices)/len(p.loop_indices)>1
        p.material_index=int(head);p.use_smooth=True
        if head:
            for i in p.loop_indices:uv[i].vector.x-=1
    materials.assign(bpy.data.objects['Boxers'],materials.material('Original shorts',diffuse='Boxers_color.png',normal='Boxers_normal.png',roughness=.85,size=1024))
    iris=materials.material('Original iris',diffuse='EyeIrisBlue_unscattered.png',roughness=.25,size=512)
    eyeball=materials.material('Original sclera',diffuse='Eyeball_unscattered.png',roughness=.3,size=512)
    hair=materials.material('Original hair',color=(.03,.017,.009,1),roughness=.85)
    mouth=materials.material('Original mouth',diffuse='Mouth_diffuse.png',size=512)
    for o in list(bpy.context.scene.objects):
        if o.type!='MESH':continue
        if o.name.startswith(('Cornea','Lens','Tear')):bpy.data.objects.remove(o,do_unlink=True);continue
        if o.name.startswith('Iris'):materials.assign(o,iris)
        if o.name.lower().startswith('eyeball'):materials.assign(o,eyeball)
        if o.name.startswith('Eyelash'):materials.assign(o,hair);materials.simplify(o,.08 if 'top' in o.name else .25)
        if o.name in ['Tongue','UpperGums','LowerGums','UpperTeeth','LowerTeeth']:
            materials.assign(o,mouth);materials.simplify(o,.15)
        for p in o.data.polygons:p.use_smooth=True
    # The imported mesh is in centimetres with object scale .01. Generate brow
    # hairs in world metres, which is the material helper's actual contract.
    emitter=bpy.data.objects['Eyebrows_root']
    emitter.data.transform(emitter.matrix_world);emitter.parent=None;emitter.matrix_world.identity()
    deps=bpy.context.evaluated_depsgraph_get()
    proxy_mesh=bpy.data.meshes.new_from_object(body.evaluated_get(deps),depsgraph=deps)
    proxy_mesh.transform(body.matrix_world)
    proxy=bpy.data.objects.new('Brow projection proxy',proxy_mesh);bpy.context.collection.objects.link(proxy)
    materials.eyebrows(proxy,hair);bpy.data.objects.remove(proxy,do_unlink=True)

def points(o):
    evaluated=o.evaluated_get(bpy.context.evaluated_depsgraph_get());mesh=evaluated.to_mesh()
    xyz=np.array([list(o.matrix_world@v.co) for v in mesh.vertices],dtype=np.float32)
    evaluated.to_mesh_clear();return xyz

def grip_audit(solver):
    body=bpy.data.objects['Man'];xyz=points(body);records={}
    for side in ('L','R'):
        name='Man_'+side+'Hand'
        hand=solver.rig.matrix_world@solver.rig.pose.bones[name].matrix
        delta=hand.to_quaternion()@solver.reference[name].to_quaternion().inverted()
        frame=delta.to_matrix()@solver.palm(side)[1]
        local=(xyz-np.array(hand.translation))@np.array(frame.inverted()).T
        selected={g.index for g in body.vertex_groups if g.name.startswith(name)}
        mask=np.array([sum(g.weight for g in v.groups if g.group in selected)>.5 for v in body.data.vertices])
        radial=np.linalg.norm(local[:,1:3]-np.array(GRIP_CENTER)[1:3],axis=1)
        in_length=np.abs(local[:,0]-GRIP_CENTER.x)<HALF_HANDLE
        penetration=np.maximum(0,HANDLE_RADIUS-radial)
        inspected=penetration[mask&in_length]
        records[side]={'hand_vertices':int(mask.sum()),'max_handle_surface_penetration_m':float(inspected.max()),
            'vertices_deeper_than_2mm':int((inspected>.002).sum())}
    return records

def regions(solver,exercise):
    from build_squat_muscles import overlay
    from build_library_muscles import region_mask
    catalog=json.loads((ROOT/'web/review/quality-v2/catalog.json').read_text())
    solver.reset();body=bpy.data.objects['Man']
    created=[]
    for region in catalog['exercises'][exercise]['regions']:
        def mask(co,key):
            world=body.matrix_world@co
            # Same authored surface masks, transformed back to the previous
            # display scale. This is an educational surface area, not anatomy.
            world=(world-Vector((0,.045,0)))*.8
            return region_mask(world,key)
        overlay(body,solver.rig,region['id'],mask)
        obj=bpy.data.objects['PULSE region '+region['id']]
        obj.matrix_world=body.matrix_world.copy()
        # The helper's metre offset is only 8 microns in imported centimetres.
        for v in obj.data.vertices:
            offset=v.normal*.0792
            v.co+=offset
            if obj.data.shape_keys:
                for key in obj.data.shape_keys.key_blocks:key.data[v.index].co+=offset
        created.append(obj)
    return created

def render(output,name,solver,close=False):
    sc=bpy.context.scene
    for o in list(sc.objects):
        if o.type in ['CAMERA','LIGHT']:bpy.data.objects.remove(o,do_unlink=True)
    def light(loc,power,size):
        bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object
        o.data.energy=power;o.data.size=size
        o.rotation_euler=(Vector((0,0,1))-o.location).to_track_quat('-Z','Y').to_euler()
    light((-3,-4,4.5),450,4);light((3,-2,3),350,3);light((1,2,4),450,3)
    centre=Vector((0,0,1.05));location=Vector((0,-6,1.2));size=2.5
    if close:
        world=solver.rig.matrix_world@solver.rig.pose.bones['Man_LHand'].matrix
        reference=solver.reference['Man_LHand']
        q=world.to_quaternion()@reference.to_quaternion().inverted()
        centre=world.translation+q@(solver.palm('L')[1]@GRIP_CENTER)
        location=centre+Vector((.28,-.45,.16));size=.35
    bpy.ops.object.camera_add(location=location);cam=bpy.context.object
    cam.rotation_euler=(centre-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=size;sc.camera=cam
    sc.render.engine='CYCLES';sc.cycles.samples=32;sc.cycles.use_denoising=True
    sc.render.resolution_x=700;sc.render.resolution_y=800 if not close else 650;sc.render.resolution_percentage=100
    if sc.world is None:sc.world=bpy.data.worlds.new('Review world')
    sc.world.color=(.12,.12,.12);sc.view_settings.view_transform='AgX'
    sc.render.image_settings.file_format='PNG';sc.render.film_transparent=True
    sc.render.filepath=str(output/(name+'.png'));bpy.ops.render.render(write_still=True)

def bake(solver,exercise,output,report,steps=40):
    # Dense pose samples keep skin interpolation error measurable. All samples
    # are evaluated from the native Armature modifier before any web conversion.
    sources=[o for o in bpy.context.scene.objects if o.type=='MESH']
    moving=[o for o in sources if any(m.type=='ARMATURE' for m in o.modifiers)]
    frames={o.name:[] for o in moving};targets=[]
    for i in range(steps+1):
        diagnostic=solver.pose(exercise,i/steps);targets.append(diagnostic)
        checked=grip_audit(solver)
        if any(c['vertices_deeper_than_2mm'] for c in checked.values()):
            raise RuntimeError('Grip penetration gate failed at '+str(i/steps)+': '+str(checked))
        for o in moving:frames[o.name].append(points(o))
    errors={}
    for i in range(steps):
        solver.pose(exercise,(i+.5)/steps)
        for o in moving:
            error=np.linalg.norm(points(o)-(frames[o.name][i]+frames[o.name][i+1])*.5,axis=1)
            errors[o.name]=max(errors.get(o.name,0),float(error.max()))
    if max(errors.values())>.0005:raise RuntimeError('Web pose interpolation error exceeds 0.5 mm: '+str(errors))
    solver.pose(exercise,0)
    deps=bpy.context.evaluated_depsgraph_get();baked=[]
    for source in sources:
        mesh=bpy.data.meshes.new_from_object(source.evaluated_get(deps),preserve_all_data_layers=True,depsgraph=deps)
        mesh.transform(source.matrix_world)
        obj=bpy.data.objects.new('Web '+source.name,mesh);bpy.context.collection.objects.link(obj);baked.append(obj)
        if source.name not in frames or all(np.array_equal(frames[source.name][0],f) for f in frames[source.name][1:]):continue
        obj.shape_key_add(name='Basis')
        for i in range(1,steps+1):
            key=obj.shape_key_add(name='Pose '+str(i));key.data.foreach_set('co',frames[source.name][i].ravel())
        keys=obj.data.shape_keys.key_blocks
        obj.data.shape_keys.animation_data_create()
        for f in range(181):
            d=depth_at(f/30)*steps;lo=int(math.floor(d));hi=min(steps,lo+1);frac=d-lo
            for i,key in enumerate(keys):
                if i==0:continue
                key.value=((1-frac) if i==lo else 0)+(frac if i==hi else 0)
                key.keyframe_insert('value',frame=f)
        obj.data.shape_keys.animation_data.action.name='Exercise'
    sc=bpy.context.scene;sc.render.fps=30;sc.frame_start=0;sc.frame_end=180;sc.frame_set(0)
    bpy.ops.object.select_all(action='DESELECT')
    for o in baked:o.select_set(True)
    bpy.context.view_layer.objects.active=baked[0]
    path=output/(exercise+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,
        export_animations=True,export_animation_mode='ACTIVE_ACTIONS',export_nla_strips_merged_animation_name='Exercise',
        export_force_sampling=True,export_frame_range=True,export_morph=True,export_morph_normal=True,
        export_morph_tangent=False,export_try_sparse_sk=True,export_yup=True,export_skins=False)
    from build_library_muscles import patch_glb
    patch_glb(path)
    # Blender suffixes repeated material names between the two scene variants.
    # The runtime muscle controller identifies a region by its material name.
    import re,struct
    raw=path.read_bytes();length=struct.unpack_from('<I',raw,12)[0]
    doc=json.loads(raw[20:20+length]);binary=raw[20+length:]
    for material in doc['materials']:
        if material['name'].startswith('PULSE Muscle '):
            material['name']=re.sub(r'\.\d{3}$','',material['name'])
    encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
    path.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(binary))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+binary)
    report[exercise]={'glb_bytes':path.stat().st_size,'glb_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
        'pose_steps':steps,'midpoint_max_error_m':errors,'native_influences_used':8,
        'runtime':'baked_mesh_morph_animation','targets':targets}
    for o in baked:bpy.data.objects.remove(o,do_unlink=True)

def author_source(solver,exercise):
    rig=solver.rig;rig.animation_data_clear();sc=bpy.context.scene
    sc.render.fps=30;sc.frame_start=0;sc.frame_end=180
    for p in rig.pose.bones:p.rotation_mode='QUATERNION'
    for f in range(181):
        sc.frame_set(f);solver.pose(exercise,depth_at(f/30))
        for p in rig.pose.bones:
            for property in ['location','rotation_quaternion','scale']:p.keyframe_insert(property,frame=f)
    rig.animation_data.action.name='Native '+exercise
    sc.frame_set(0)

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--output-dir',required=True,type=Path);parser.add_argument('--render-only',action='store_true')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:]);output=args.output_dir.resolve();output.mkdir(parents=True,exist_ok=False)
    source=ROOT/'.build/original-rig/native-import-04/original-rig-staging.blend'
    bpy.ops.wm.open_mainfile(filepath=str(source),use_scripts=False);bpy.context.scene.frame_set(0)
    body=bpy.data.objects['Man'];before=fingerprint(body);rig=bpy.data.objects['Armature'];solver=NativeUpper(rig)
    for o in bpy.context.scene.objects:o.animation_data_clear()
    prepare(output);solver.equipment()
    rig['native_reference_world_json']=json.dumps({n:[list(row) for row in m] for n,m in solver.reference.items()})
    report={'source':str(source),'source_skin_fingerprint':before,'bones':len(rig.data.bones),'exercises':{},'ready_for_production':False}
    for e in ['shoulder_press','curl']:
        solver.pose(e,0);report[e+'-bottom-grip']=grip_audit(solver);render(output,e+'-bottom',solver)
        solver.pose(e,1);report[e+'-top-grip']=grip_audit(solver);render(output,e+'-top',solver)
        render(output,e+'-grip',solver,True)
        overlays=regions(solver,e)
        if not args.render_only:bake(solver,e,output,report['exercises'])
        solver.pose(e,0)
        # Store an editable rig rather than baked geometry as the source artifact.
        author_source(solver,e)
        bpy.ops.wm.save_as_mainfile(filepath=str(output/(e+'-native-source.blend')))
        rig.animation_data_clear()
        for o in overlays:bpy.data.objects.remove(o,do_unlink=True)
    report['source_weights_unchanged']=fingerprint(body)==before
    if not report['source_weights_unchanged']:raise RuntimeError('Original Skin weights changed')
    (output/'build-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
    print(json.dumps({k:v for k,v in report.items() if k!='exercises'}),flush=True)

if __name__=='__main__':main()
