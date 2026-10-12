"""Sample exported, re-imported upper-body review clips; not a medical validator."""
import argparse, json, math, sys
from pathlib import Path
import bpy
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from character_mesh import body_mesh

def check(path, exercise):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene=bpy.context.scene;scene.render.fps=30
    bpy.ops.import_scene.gltf(filepath=str(path))
    rig=next(o for o in scene.objects if o.type=='ARMATURE')
    body=body_mesh();bones=rig.pose.bones
    shoulders=[];wrist_angles=[];elbow_angles=[];gaps=[];lengths=[];skin_min=1e9
    anchors={};foot_drift=0;roll_step=0;last={};envelope=[Vector((1e9,)*3),Vector((-1e9,)*3)]
    first=None;loop=0;clav_rot=[]
    for i in range(361):
        f=i/2;scene.frame_set(int(f),subframe=f-int(f))
        shoulders.append(bones['upperarm_l'].head.copy())
        clav_rot.append(bones['clavicle_l'].matrix.to_quaternion())
        pts=[p.head.copy() for p in bones]
        if first is None:first=pts
        if i==360:loop=max((a-b).length for a,b in zip(first,pts))
        for side in ('l','r'):
            sh,el,wr,mc=[bones[n+'_'+side].head for n in ('upperarm','lowerarm','hand','middle_01')]
            wrist_angles.append(math.degrees((wr-el).angle(mc-wr)))
            elbow_angles.append(math.degrees((sh-el).angle(wr-el)))
            for a,b in [('clavicle','upperarm'),('upperarm','lowerarm'),('lowerarm','hand'),('thigh','calf'),('calf','foot')]:
                gaps.append((bones[a+'_'+side].tail-bones[b+'_'+side].head).length)
            for n in ('foot','hand','lowerarm','upperarm'):
                p=bones[n+'_'+side];q=p.matrix.to_quaternion()
                if p.name in last:
                    a=math.degrees(last[p.name].rotation_difference(q).angle)
                    roll_step=max(roll_step,min(a,360-a))
                last[p.name]=q
            foot=bones['foot_'+side].head.copy()
            if side not in anchors:anchors[side]=foot
            foot_drift=max(foot_drift,(foot-anchors[side]).length)
        lengths.extend(abs(p.length/rig.data.bones[p.name].length-1) for p in bones)
        deps=bpy.context.evaluated_depsgraph_get()
        for ob in scene.objects:
            if ob.type!='MESH' or ob.hide_render or (ob!=body and not ob.name.startswith('PULSE dumbbell') and ob.name!='Boxers'):continue
            ev=ob.evaluated_get(deps)
            for v in ev.data.vertices:
                co=ev.matrix_world@v.co
                if ob==body:skin_min=min(skin_min,co.z)
                for a in range(3):envelope[0][a]=min(envelope[0][a],co[a]);envelope[1][a]=max(envelope[1][a],co[a])
    travel=max(v.z for v in shoulders)-min(v.z for v in shoulders)
    rotation=max(math.degrees(clav_rot[0].rotation_difference(q).angle) for q in clav_rot)
    errors=[]
    if max(wrist_angles)>3:errors.append('palm longitudinal axis not neutral to forearm')
    if max(gaps)>.0005:errors.append('joint disconnected')
    if max(lengths)>.002:errors.append('bone stretched')
    if foot_drift>.0006:errors.append('feet slide')
    if skin_min<-.001:errors.append('skin below floor')
    if loop>.0006:errors.append('loop does not close')
    if roll_step>6:errors.append('abrupt orientation step')
    if exercise=='shoulder_press' and (travel<.015 or rotation<5):errors.append('shoulder girdle frozen during overhead press')
    result=dict(exercise=exercise,path=str(path),samples=361,wrist_axis_error_max_deg=max(wrist_angles),elbow_angle_range_deg=[min(elbow_angles),max(elbow_angles)],shoulder_vertical_travel_m=travel,clavicle_rotation_deg=rotation,joint_gap_max_m=max(gaps),bone_length_error=max(lengths),foot_drift_m=foot_drift,skin_min_m=skin_min,loop_m=loop,orientation_step_max_deg=roll_step,envelope_min=list(envelope[0]),envelope_max=list(envelope[1]),errors=errors)
    print(json.dumps(result,ensure_ascii=False),flush=True)
    return result

def main():
    p=argparse.ArgumentParser();p.add_argument('--exercise',required=True,choices=['curl','shoulder_press']);p.add_argument('--glb',required=True);p.add_argument('--output',required=True)
    a=p.parse_args(sys.argv[sys.argv.index('--')+1:]);r=check(Path(a.glb),a.exercise)
    Path(a.output).write_text(json.dumps(r,indent=2)+'\n')
    assert not r['errors'],r['errors']

if __name__=='__main__':main()
