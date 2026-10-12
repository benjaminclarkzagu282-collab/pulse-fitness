"""Check geometry on re-imported delivered clips; not a coaching certification.

Blender -b --python tools/check_motion_library.py -- [--exercise pushup]
--legacy reproduces old geometry failures. --inject-root-slide is a negative
control which must fail world-space support checks.
"""
import argparse
import json
import math
import struct
import sys
from pathlib import Path
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / '.build/motion-library'
IDS = ['squat', 'pushup', 'lunge', 'bridge', 'plank', 'row', 'jumping_jack', 'curl']
PAIRS = [(a+'_'+s,b+'_'+s) for s in ('l','r') for a,b in
         [('thigh','calf'),('calf','foot'),('upperarm','lowerarm'),('lowerarm','hand')]]
PAIRS += [('neck_01','head'), ('pelvis','spine_01'), ('spine_01','spine_02'), ('spine_02','spine_03')]
PAIRS += [(f'{finger}_{segment:02}_{side}',f'{finger}_{segment+1:02}_{side}')
          for side in ('l','r') for finger in ('thumb','index','middle','ring','pinky') for segment in (1,2)]


def check(exercise, args):
    if args.legacy:
        bpy.ops.wm.open_mainfile(filepath=str(ROOT/'.build/realistic-character/athlete-source.blend'),use_scripts=False)
        sys.path.insert(0,str(ROOT/'tools'))
        from animate_athlete import pose
    else:
        path = Path(args.glb) if args.glb else WORK/'base'/f'{exercise}.glb'
        assert path.is_file(), f'Missing delivered clip: {path}'
        blob=path.read_bytes();size=struct.unpack_from('<I',blob,12)[0];doc=json.loads(blob[20:20+size])
        assert len(doc.get('animations',[])) == 1, 'Expected one animation'
        assert doc['animations'][0]['name'] == 'Exercise', 'Clip must be Exercise'
        assert all(s.get('interpolation','LINEAR')=='LINEAR' for s in doc['animations'][0]['samplers']), 'Non-linear export'
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.context.scene.render.fps=30
        bpy.ops.import_scene.gltf(filepath=str(path))
    rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
    scene=bpy.context.scene
    end = 180
    if not args.legacy:
        end=max(k.co.x for a in bpy.data.actions for layer in a.layers for strip in layer.strips
                for slot in a.slots for fc in strip.channelbag(slot).fcurves for k in fc.keyframe_points)
        assert abs(end/scene.render.fps-6)<.001, f'Duration {end/scene.render.fps}'
    body=next(o for o in scene.objects if o.name=='Man')
    root=rig.location.copy();initial=None;support_start={};worst=(0,'',0)
    motion={name:[] for name in ('pelvis','upperarm_l','hand_l','foot_l','foot_r')}
    if exercise in ('row','curl') and not args.legacy:
        assert len([o for o in scene.objects if o.name.startswith('PULSE dumbbell')])==2,'Missing dumbbells'
    drift=0.;loop=0.;length_error=0.;minimum=1e9;contact_max=-1e9
    last_feet=None;ground_slide=0.;extra_contact_max=-1e9;back_minimum=1e9
    bridge_hip_above_line=-1e9;bridge_peak=[]
    # Distal foot/palm support patches are selected in the imported rest mesh.
    patches={}
    for side,sign in [('l',1),('r',-1)]:
        patches['foot_'+side]=[v.index for v in body.data.vertices if v.co.x*sign>.1 and v.co.z<.035]
        hand=rig.data.bones['hand_'+side].head_local
        palm_group=body.vertex_groups['hand_'+side].index
        patches['hand_'+side]=[v.index for v in body.data.vertices if any(g.group==palm_group and g.weight>.7 for g in v.groups)]
        elbow=rig.data.bones['lowerarm_'+side].head_local
        patches['lowerarm_'+side]=[v.index for v in body.data.vertices if (v.co-elbow).length<.06]
    back_patch=[v.index for v in body.data.vertices if v.co.y>.075 and 1.075<v.co.z<1.265]
    for i in range(361):
        t=i/60
        if args.legacy: pose(rig,exercise,t/6)
        else: scene.frame_set(int(t*30),subframe=t*30-int(t*30))
        if args.inject_root_slide:
            rig.location=root+Vector((.02*math.sin(math.pi*t/6)**2,0,0));bpy.context.view_layer.update()
        if args.inject_joint_gap:
            matrix=rig.pose.bones['hand_l'].matrix.copy()
            matrix.translation+=Vector((.02*math.sin(math.pi*t/6)**2,0,0))
            rig.pose.bones['hand_l'].matrix=matrix;bpy.context.view_layer.update()
        for a,b in PAIRS:
            gap=(rig.pose.bones[a].tail-rig.pose.bones[b].head).length
            if gap>worst[0]:worst=(gap,a+' -> '+b,t)
        for p in rig.pose.bones:
            assert all(math.isfinite(v) for v in p.head),p.name
            length_error=max(length_error,abs(p.length/rig.data.bones[p.name].length-1))
        points=[rig.matrix_world@p.head for p in rig.pose.bones]
        for name in motion:motion[name].append(rig.matrix_world@rig.pose.bones[name].head)
        if initial is None:initial=points
        if i==360:loop=max((a-b).length for a,b in zip(points,initial))
        support=['foot_l','foot_r']
        if exercise=='lunge':support=['foot_l']
        if exercise=='jumping_jack':support=[]
        if exercise in ('pushup','bridge'):support+=['hand_l','hand_r']
        if exercise=='plank':support+=['lowerarm_l','lowerarm_r']
        for name in support:
            p=rig.pose.bones[name];position=rig.matrix_world@p.head
            if name not in support_start:support_start[name]=position
            drift=max(drift,(position-support_start[name]).length)
        evaluated=body.evaluated_get(bpy.context.evaluated_depsgraph_get())
        verts=[evaluated.matrix_world@v.co for v in evaluated.data.vertices]
        minimum=min(minimum,min(v.z for v in verts))
        for name in support:
            if name in patches:contact_max=max(contact_max,min(verts[j].z for j in patches[name]))
        if exercise=='bridge':
            height=min(verts[j].z for j in back_patch)
            back_minimum=min(back_minimum,height);extra_contact_max=max(extra_contact_max,height)
            for side in ('l','r'):
                shoulder=rig.matrix_world@rig.pose.bones['upperarm_'+side].head
                hip=rig.matrix_world@rig.pose.bones['thigh_'+side].head
                knee=rig.matrix_world@rig.pose.bones['calf_'+side].head
                line_height=shoulder.z+(knee.z-shoulder.z)*(hip.y-shoulder.y)/(knee.y-shoulder.y)
                above=hip.z-line_height;bridge_hip_above_line=max(bridge_hip_above_line,above)
                if i==195:
                    angle=math.degrees((shoulder-hip).angle(knee-hip))
                    line=knee-shoulder;distance=(hip-shoulder-line*(hip-shoulder).dot(line)/line.length_squared).length
                    shoulder.x=hip.x=knee.x=0
                    bridge_peak.append(dict(side=side,angle_3d_deg=angle,angle_sagittal_deg=math.degrees((shoulder-hip).angle(knee-hip)),
                                            hip_above_line_m=above,hip_line_distance_m=distance))
        if exercise in ('jumping_jack','lunge'):
            feet=[rig.matrix_world@rig.pose.bones['foot_'+s].head for s in ('l','r')]
            heights=[min(verts[j].z for j in patches['foot_'+s]) for s in ('l','r')]
            if last_feet:
                for j,(a,b) in enumerate(zip(feet,last_feet)):
                    if heights[j]<.0015 and last_heights[j]<.0015:
                        ground_slide=max(ground_slide,math.hypot(a.x-b.x,a.y-b.y))
            last_feet=feet;last_heights=heights
    ranges={name:[max(v[axis] for v in values)-min(v[axis] for v in values) for axis in range(3)] for name,values in motion.items()}
    result=dict(exercise=exercise,legacy=args.legacy,samples=361,worst_joint_gap_m=worst,
                support_drift_m=drift,loop_gap_m=loop,max_relative_bone_length_error=length_error,
                minimum_skin_height_m=minimum,max_support_patch_height_m=None if contact_max<0 else contact_max,
                grounded_foot_step_m=ground_slide,
                upper_back_min_m=None if exercise!='bridge' else back_minimum,
                upper_back_max_m=None if exercise!='bridge' else extra_contact_max,
                landmark_range_m=ranges,
                bridge_max_hip_above_line_m=None if exercise!='bridge' else bridge_hip_above_line,
                bridge_peak=bridge_peak or None)
    print('MOTION_CHECK',json.dumps(result),flush=True)
    errors=[]
    if worst[0]>=.0005:errors.append(f'Disconnected joint: {worst}')
    if drift>=.0006:errors.append(f'Support slide: {drift}')
    if loop>=.0006:errors.append(f'Loop jump: {loop}')
    if length_error>=.002:errors.append(f'Bone stretching: {length_error}')
    if minimum<-.001:errors.append(f'Skin below floor: {minimum}')
    if contact_max>.006:errors.append(f'Support lifted: {contact_max}')
    if ground_slide>.0005:errors.append(f'Grounded foot moved: {ground_slide}')
    if extra_contact_max>.004:errors.append(f'Upper back lifted: {extra_contact_max}')
    # Visual regression for this particular model, not a prescribed human angle.
    if bridge_hip_above_line>.015:errors.append(f'Bridge hip visibly above shoulder-knee line: {bridge_hip_above_line}')
    required={'squat':('pelvis',2,.20),'pushup':('upperarm_l',2,.15),
              'lunge':('foot_r',1,.45),'bridge':('pelvis',2,.10),
              'row':('hand_l',2,.10),'curl':('hand_l',2,.25),
              'jumping_jack':('foot_l',0,.15)}
    if exercise in required:
        name,axis,threshold=required[exercise]
        if ranges[name][axis]<threshold:errors.append(f'Missing exercise travel: {name} {ranges[name]}')
    if exercise=='jumping_jack' and ranges['foot_l'][2]<.06:errors.append('Jump never leaves ground')
    if exercise=='plank' and max(max(v) for v in ranges.values())>.001:errors.append('Plank is not a stable hold')
    result['errors']=errors
    return result


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--exercise',choices=IDS);parser.add_argument('--glb')
    parser.add_argument('--legacy',action='store_true');parser.add_argument('--inject-root-slide',action='store_true')
    parser.add_argument('--inject-joint-gap',action='store_true')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    results=[check(e,args) for e in ([args.exercise] if args.exercise else IDS)]
    WORK.mkdir(parents=True,exist_ok=True)
    filename='legacy-check.json' if args.legacy else ('negative-joint-check.json' if args.inject_joint_gap else ('negative-check.json' if args.inject_root_slide else 'verification.json'))
    (WORK/filename).write_text(json.dumps(results,indent=2))
    assert not any(r['errors'] for r in results), json.dumps({r['exercise']:r['errors'] for r in results if r['errors']})


if __name__=='__main__':main()
