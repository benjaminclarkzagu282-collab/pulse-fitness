"""Re-imported geometry acceptance and injected negative controls for eight clips."""
import argparse,json,math,sys,struct
from pathlib import Path
import bpy
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1];WORK=ROOT/'.build/motion-library'
IDS=['kneeling_pushup','incline_pushup','floor_press','shoulder_press','lateral_raise','single_arm_row','reverse_fly','romanian_deadlift']

def check(exercise,args):
    path=Path(args.glb) if args.glb else WORK/'base'/f'{exercise}.glb'
    assert path.is_file(),f'Missing delivered clip: {path}'
    data=path.read_bytes();n=struct.unpack_from('<I',data,12)[0];doc=json.loads(data[20:20+n])
    assert len(doc.get('animations',[]))==1 and doc['animations'][0]['name']=='Exercise'
    assert all(s.get('interpolation','LINEAR')=='LINEAR' for s in doc['animations'][0]['samplers'])
    bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.scene.render.fps=30
    bpy.ops.import_scene.gltf(filepath=str(path))
    scene=bpy.context.scene;rig=next(o for o in scene.objects if o.type=='ARMATURE');body=bpy.data.objects['Man']
    end=max(k.co.x for a in bpy.data.actions for layer in a.layers for strip in layer.strips for slot in a.slots for fc in strip.channelbag(slot).fcurves for k in fc.keyframe_points)
    assert abs(end-180)<.001,f'Duration is {end/30}'
    pairs=[(a+'_'+s,b+'_'+s) for s in ('l','r') for a,b in [('thigh','calf'),('calf','foot'),('foot','ball'),('clavicle','upperarm'),('upperarm','lowerarm'),('lowerarm','hand')]]
    pairs += [('neck_01','head'),('pelvis','spine_01'),('spine_01','spine_02'),('spine_02','spine_03')]
    pairs += [(f'{f}_{i:02}_{s}',f'{f}_{i+1:02}_{s}') for s in ('l','r') for f in ('thumb','index','middle','ring','pinky') for i in (1,2)]
    patches={}
    for side,sign in [('l',1),('r',-1)]:
        patches['foot_'+side]=[v.index for v in body.data.vertices if v.co.x*sign>.1 and v.co.z<.035]
        group=body.vertex_groups['hand_'+side].index
        patches['hand_'+side]=[v.index for v in body.data.vertices if any(g.group==group and g.weight>.7 for g in v.groups)]
        knee=rig.data.bones['calf_'+side].head_local
        patches['calf_'+side]=[v.index for v in body.data.vertices if (v.co-knee).length<.10]
    patches['back']=[v.index for v in body.data.vertices if v.co.y>.075 and 1.075<v.co.z<1.265]
    support={'foot_l':0.,'foot_r':0.}
    if exercise=='kneeling_pushup':support={'calf_l':0.,'calf_r':0.,'hand_l':0.,'hand_r':0.}
    if exercise=='incline_pushup':support.update(hand_l=.4,hand_r=.4)
    if exercise=='single_arm_row':support.update(hand_l=.45)
    if exercise=='floor_press':support['back']=0.
    dumbbells=[o for o in scene.objects if o.name.startswith('PULSE dumbbell')]
    assert len(dumbbells)==(0 if exercise in ('kneeling_pushup','incline_pushup') else (1 if exercise=='single_arm_row' else 2)),'Dumbbell count'
    if exercise in ('incline_pushup','single_arm_row'):assert any(o.name=='PULSE support top' for o in scene.objects),'Missing support'
    initial=None;anchor={};drift=gap=length_error=loop=attachment=0.;minimum=1e6;contacts={n:[1e6,-1e6] for n in support};movement={n:[] for n in ('pelvis','upperarm_l','hand_l','hand_r','lowerarm_l')};equipment_local={}
    skin_anchors={};skin_by_support={};skin_drift=0.;skin_loop=0.;skin_initial=None;support_penetration=0.;support_miss=0
    envelope_min=[1e6]*3;envelope_max=[-1e6]*3
    shape={n:[] for n in ('knee_l','knee_r','trunk_pitch','elbow_l','elbow_r')}
    top=bpy.data.objects.get('PULSE support top')
    bounds=None if top is None else [top.matrix_world@Vector(c) for c in top.bound_box]
    if bounds:bx0,bx1,by0,by1,bz0,bz1=min(v.x for v in bounds),max(v.x for v in bounds),min(v.y for v in bounds),max(v.y for v in bounds),min(v.z for v in bounds),max(v.z for v in bounds)
    for ob in scene.objects:
        if ob.name.startswith('PULSE support'):
            for point in [ob.matrix_world@Vector(c) for c in ob.bound_box]:
                for axis in range(3):envelope_min[axis]=min(envelope_min[axis],point[axis]);envelope_max[axis]=max(envelope_max[axis],point[axis])
    root=rig.location.copy()
    for i in range(361):
        frame=i*.5;scene.frame_set(int(frame),subframe=frame-int(frame))
        if args.inject_root_slide:rig.location=root+Vector((.02*math.sin(math.pi*i/360)**2,0,0));bpy.context.view_layer.update()
        if args.inject_joint_gap:
            p=rig.pose.bones['hand_l'];m=p.matrix.copy();m.translation+=Vector((.02*math.sin(math.pi*i/360)**2,0,0));p.matrix=m;bpy.context.view_layer.update()
        gap=max(gap,max((rig.pose.bones[a].tail-rig.pose.bones[b].head).length for a,b in pairs))
        length_error=max(length_error,max(abs(p.length/rig.data.bones[p.name].length-1) for p in rig.pose.bones))
        for side in ('l','r'):
            h,k,f=[rig.pose.bones[n+'_'+side].head for n in ('thigh','calf','foot')]
            sh,el,wr=[rig.pose.bones[n+'_'+side].head for n in ('upperarm','lowerarm','hand')]
            shape['knee_'+side].append(math.degrees((h-k).angle(f-k)))
            shape['elbow_'+side].append(math.degrees((sh-el).angle(wr-el)))
        delta=rig.pose.bones['neck_01'].head-rig.pose.bones['pelvis'].head
        shape['trunk_pitch'].append(math.degrees(math.atan2(-delta.y,delta.z)))
        points=[rig.matrix_world@p.head for p in rig.pose.bones]
        if initial is None:initial=points
        if i==360:loop=max((a-b).length for a,b in zip(initial,points))
        for n in movement:movement[n].append(rig.matrix_world@rig.pose.bones[n].head)
        evaluated=body.evaluated_get(bpy.context.evaluated_depsgraph_get());verts=[evaluated.matrix_world@v.co for v in evaluated.data.vertices]
        if skin_initial is None:skin_initial=[v.copy() for v in verts]
        if i==360:skin_loop=max((a-b).length for a,b in zip(verts,skin_initial))
        minimum=min(minimum,min(v.z for v in verts))
        for a in range(3):envelope_min[a]=min(envelope_min[a],min(v[a] for v in verts));envelope_max[a]=max(envelope_max[a],max(v[a] for v in verts))
        if bounds:
            inside=[v for v in verts if bx0+.004<v.x<bx1-.004 and by0+.004<v.y<by1-.004 and bz0<v.z<bz1]
            support_penetration=max(support_penetration,max((bz1-v.z for v in inside),default=0.))
        for name,height in support.items():
            z=min(verts[j].z for j in patches[name])-height
            if i==0:
                if name=='back':ids=[j for j in patches[name] if abs(body.data.vertices[j].co.x)<.02]
                else:
                    group=body.vertex_groups[name].index
                    candidates=patches[name] if not name.startswith('calf') else [v.index for v in body.data.vertices if (v.co-rig.data.bones[name].head_local).length<.16]
                    ids=[j for j in candidates if any(g.group==group and g.weight>(.9 if name.startswith('hand') else .999) for g in body.data.vertices[j].groups)]
                if name.startswith('hand'):
                    lower_group=body.vertex_groups[name.replace('hand','lowerarm')].index
                    ids=[j for j in patches[name] if not any(g.group==lower_group and g.weight>1e-5 for g in body.data.vertices[j].groups)]
                assert ids,'No rigid skin support witnesses '+name
                skin_anchors[name]=[(j,verts[j].copy()) for j in ids]
            point_drift=max((math.hypot(verts[j].x-p.x,verts[j].y-p.y) if name.startswith('calf') else (verts[j]-p).length) for j,p in skin_anchors[name])
            skin_by_support[name]=max(skin_by_support.get(name,0.),point_drift)
            skin_drift=max(skin_drift,point_drift)
            if height>0 and not any(bx0<=verts[j].x<=bx1 and by0<=verts[j].y<=by1 and abs(verts[j].z-height)<.006 for j in patches[name]):support_miss+=1
            contacts[name][0]=min(contacts[name][0],z);contacts[name][1]=max(contacts[name][1],z)
            if name!='back':
                p=rig.matrix_world@rig.pose.bones[name].head
                if name not in anchor:anchor[name]=p
                drift=max(drift,math.hypot(p.x-anchor[name].x,p.y-anchor[name].y) if name.startswith('calf') else (p-anchor[name]).length)
            else:
                p=rig.matrix_world@rig.pose.bones['spine_03'].head
                if name not in anchor:anchor[name]=p
                drift=max(drift,math.hypot(p.x-anchor[name].x,p.y-anchor[name].y) if name.startswith('calf') else (p-anchor[name]).length)
        for ob in dumbbells:
            side=ob.name[-1];ev=ob.evaluated_get(bpy.context.evaluated_depsgraph_get());inv=(rig.matrix_world@rig.pose.bones['hand_'+side].matrix).inverted()
            world=[ev.matrix_world@v.co for v in ev.data.vertices]
            for a in range(3):envelope_min[a]=min(envelope_min[a],min(v[a] for v in world));envelope_max[a]=max(envelope_max[a],max(v[a] for v in world))
            local=[inv@v for v in world]
            if ob.name not in equipment_local:equipment_local[ob.name]=local
            attachment=max(attachment,max((a-b).length for a,b in zip(local,equipment_local[ob.name])))
    ranges={n:[max(v[a] for v in values)-min(v[a] for v in values) for a in range(3)] for n,values in movement.items()}
    shape={k:[min(v),max(v)] for k,v in shape.items()}
    errors=[]
    if skin_loop>=.0006:errors.append('skin loop gap')
    if skin_drift>=.0006:errors.append('skin support drift')
    if support_penetration>.001:errors.append('skin penetrates support platform')
    if support_miss:errors.append('palm missed support footprint')
    if exercise=='incline_pushup' and min(shape['knee_l'][0],shape['knee_r'][0])<170:errors.append('incline knees flexed')
    if exercise=='romanian_deadlift' and (shape['trunk_pitch'][1]-shape['trunk_pitch'][0]<55 or min(shape['knee_l'][0],shape['knee_r'][0])<140):errors.append('RDL missing hip hinge or overbent knees')
    for test,condition in [('joint gap',gap>=.0005),('support drift',drift>=.0006),('loop gap',loop>=.0006),('bone stretching',length_error>=.002),('skin below floor',minimum<-.001),('equipment slips',attachment>=.0005)]:
        if condition:errors.append(test)
    for name,(low,high) in contacts.items():
        if low<-.001 or high>.006:errors.append('skin support contact '+name)
    required={'kneeling_pushup':('upperarm_l',2,.18),'incline_pushup':('upperarm_l',2,.15),'floor_press':('hand_l',2,.16),'shoulder_press':('hand_l',2,.18),'lateral_raise':('hand_l',0,.28),'single_arm_row':('hand_r',2,.10),'reverse_fly':('hand_l',0,.28),'romanian_deadlift':('pelvis',1,.15)}
    n,a,threshold=required[exercise]
    if ranges[n][a]<threshold:errors.append('insufficient exercise amplitude')
    result=dict(exercise=exercise,samples=361,skin_loop_gap_m=skin_loop,skin_support_drift_m=skin_drift,skin_support_drift_by_patch_m=skin_by_support,support_penetration_m=support_penetration,support_footprint_misses=support_miss,envelope_min_xyz_m=envelope_min,envelope_max_xyz_m=envelope_max,joint_angle_range_deg=shape,worst_joint_gap_m=gap,support_drift_m=drift,loop_gap_m=loop,max_relative_bone_length_error=length_error,minimum_skin_height_m=minimum,support_patch_height_m=contacts,dumbbell_attachment_error_m=attachment,landmark_range_m=ranges,errors=errors)
    print('UPPER_CHECK',json.dumps(result),flush=True);return result

def main():
    p=argparse.ArgumentParser();p.add_argument('--exercise',choices=IDS);p.add_argument('--glb');p.add_argument('--inject-root-slide',action='store_true');p.add_argument('--inject-joint-gap',action='store_true');a=p.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    results=[check(e,a) for e in ([a.exercise] if a.exercise else IDS)]
    suffix='negative-drift' if a.inject_root_slide else ('negative-gap' if a.inject_joint_gap else 'verification')
    (WORK/f'upper-{a.exercise or "all"}-{suffix}.json').write_text(json.dumps(results,indent=2))
    assert not any(r['errors'] for r in results),{r['exercise']:r['errors'] for r in results if r['errors']}
if __name__=='__main__':main()
