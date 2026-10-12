"""Reference-authored six-second exercise loops on the user's existing skin.

Blender -b --factory-startup --python-exit-code 1 --python tools/motion_library.py
  -- [--exercise pushup] [--render]
These are animation references, not motion capture or coach certification.
"""
import argparse
import math
import sys
from pathlib import Path
import bpy
from mathutils import Matrix, Quaternion, Vector

ROOT=Path(__file__).resolve().parents[1]
WORK=ROOT/'.build/motion-library'
sys.path.insert(0,str(ROOT/'tools'))
from animate_athlete import set_bone, equipment, finalize_glb
from squat_sample import pose_squat, depth_at, smooth

BASE_IDS=['squat','pushup','lunge','bridge','plank','row','jumping_jack','curl']
UPPER_IDS=['kneeling_pushup','incline_pushup','floor_press','shoulder_press','lateral_raise','single_arm_row','reverse_fly','romanian_deadlift']
LOWER_IDS=['sumo_squat','split_squat','lateral_lunge','calf_raise','dead_bug','bird_dog','side_plank','step_jack']
IDS=BASE_IDS+UPPER_IDS+LOWER_IDS
FPS=30;END=180;V=Vector
_surface={}


def extension(exercise):
    if exercise in UPPER_IDS:
        import motion_upper
        return motion_upper
    if exercise in LOWER_IDS:
        import motion_lower
        return motion_lower
    return None


def prepare_equipment(rig,exercise):
    module=extension(exercise)
    if module is not None:module.prepare_equipment(rig,exercise)
    else:equipment(rig,exercise)


def rx(angle):return Quaternion((1,0,0),angle)


def solve_joint(a,b,l1,l2,pole):
    """Rigid two-link solve. Unreachable endpoints are an authoring error."""
    axis=b-a;distance=axis.length
    assert abs(l1-l2)+1e-6<distance<l1+l2-1e-6, ('Unreachable endpoint',tuple(a),tuple(b),distance,l1+l2)
    axis.normalize();x=(l1*l1-l2*l2+distance*distance)/(2*distance)
    perpendicular=V(pole)-axis*V(pole).dot(axis)
    assert perpendicular.length>1e-6,'Degenerate joint pole'
    return a+axis*x+perpendicular.normalized()*math.sqrt(max(0,l1*l1-x*x))


def surface_height(rig,side,part,q):
    """Ground the posed rigid distal surface, not the bone centre."""
    key=(side,part)
    if key not in _surface:
        body=bpy.data.objects['Man'];sign=1 if side=='l' else -1
        head=rig.data.bones[part+'_'+side].head_local
        if part=='foot':points=[v.co-head for v in body.data.vertices if v.co.x*sign>.1 and v.co.z<.035]
        else:
            group=body.vertex_groups['hand_'+side].index
            points=[v.co-head for v in body.data.vertices if any(g.group==group and g.weight>.7 for g in v.groups)]
        _surface[key]=points
    # Palm border vertices blend with newly straightened phalanges; allow the
    # measured 3.5 mm skin envelope instead of grounding only a rigid hand bone.
    return .001+(.0035 if part=='hand' else 0)-min((q@p).z for p in _surface[key])


def hand_rotation(rig,side,direction,palm_down=False):
    rest=rig.data.bones;origin=rest['hand_'+side].head_local
    longitudinal=((rest['middle_01_'+side].head_local if palm_down else rest['middle_03_'+side].tail_local)-origin).normalized()
    across=(rest['index_01_'+side].head_local-rest['pinky_01_'+side].head_local).normalized()
    across=(across-longitudinal*across.dot(longitudinal)).normalized()
    target_y=V(direction).normalized()
    if palm_down:
        target_x=V(((1 if side=='l' else -1)*(1 if target_y.y>0 else -1),0,0))
    else:
        target_x=V((1 if side=='l' else -1,0,0))
    target_x=(target_x-target_y*target_x.dot(target_y)).normalized()
    source=Matrix((across,longitudinal,across.cross(longitudinal))).transposed()
    target=Matrix((target_x,target_y,target_x.cross(target_y))).transposed()
    return (target@source.inverted()).to_quaternion()


def flat_fingers(rig,side,wrist,hand_q):
    """Open each phalanx in the palm plane, preserving its actual bone length."""
    rest=rig.data.bones;origin=rest['hand_'+side].head_local
    for finger in ('index','middle','ring','pinky','thumb'):
        head=None
        for segment in range(1,4):
            name=f'{finger}_{segment:02}_{side}';bone=rest[name]
            if head is None:head=wrist+hand_q@(bone.head_local-origin)
            source=hand_q@(bone.tail_local-bone.head_local)
            direction=V((source.x,source.y,0)).normalized()
            rotation=source.rotation_difference(direction)@hand_q
            set_bone(rig,name,head,q=rotation)
            head=head+direction*bone.length


def limb(rig,first,second,a,joint,b,reference):
    for name,start,end in [(first,a,joint),(second,joint,b)]:
        source=rig.data.bones[name].tail_local-rig.data.bones[name].head_local
        rotation=(reference@source).rotation_difference(end-start)@reference
        set_bone(rig,name,start,q=rotation)


def pose_exercise(rig,exercise,seconds,_bridge_raise=None):
    module=extension(exercise)
    if module is not None:
        module.pose_exercise(rig,exercise,seconds);return
    if exercise not in BASE_IDS:raise ValueError('Unknown exercise: '+exercise)
    if exercise=='squat':
        pose_squat(rig,seconds);return
    for p in rig.pose.bones:p.matrix_basis=Matrix.Identity(4)
    rest=rig.data.bones;p0=rest['pelvis'].head_local.copy();hip=p0.copy();q=rx(0)
    depth=depth_at(seconds);feet={};foot_q={};swing=0.;jack=0.
    for side,sign in [('l',1),('r',-1)]:
        foot_q[side]=rx(0)
        feet[side]=V((sign*.16,.035,rest['foot_'+side].head_local.z+.0011))
    if exercise=='lunge':
        step=smooth((seconds-.5)/.5) if seconds<1 else (1-smooth((seconds-5)/.5) if seconds>5 else 1.)
        lower=smooth((seconds-1)/2) if seconds<3 else (1-smooth((seconds-3.5)/1.5) if seconds>3.5 else 1.)
        foot_q['r']=rx(.72*step)
        feet['r'].y+=.50*step
        if .5<seconds<1:swing=math.sin(math.pi*(seconds-.5)/.5)*.07
        if 5<seconds<5.5:swing=math.sin(math.pi*(seconds-5)/.5)*.07
        feet['r'].z=surface_height(rig,'r','foot',foot_q['r'])+swing
        hip+=V((0,-.035*lower,-.155*step-.16*lower));q=rx(.08*lower)
    elif exercise in ('pushup','plank'):
        incline=math.radians(12.7-11.2*depth) if exercise=='pushup' else math.asin((.034+rest['upperarm_l'].length-.155)/(rest['upperarm_l'].head_local.z-rest['foot_l'].head_local.z))
        q=rx(math.pi/2-incline)
        for side in feet:
            foot_q[side]=rx(math.pi/2-.2)
            feet[side].y=.75;feet[side].z=surface_height(rig,side,'foot',foot_q[side])
        # The complete neutral trunk and nearly straight legs rotate about toes.
        hip=feet['l']-q@(rest['foot_l'].head_local-p0)
    elif exercise=='bridge':
        q=rx(math.pi/2+.08+.354*depth)@Quaternion((0,0,1),math.pi)
        # Rotate the torso around a fixed upper-back surface support point.
        pivot=V((0,.104,1.205));anchor=V((0,-.39,.005+(_bridge_raise or 0.)))
        hip=anchor-q@(pivot-p0)
        for side,sign in [('l',1),('r',-1)]:
            foot_q[side]=Quaternion((0,0,1),math.pi)
            feet[side]=V((-sign*.16,.38,surface_height(rig,side,'foot',foot_q[side])))
    elif exercise=='row':
        hip+=V((0,.075,-.075));q=rx(.9)
        for side in feet:feet[side].x*=1.125
    elif exercise=='jumping_jack':
        if seconds<.8:jack=0.
        elif seconds<1.4:jack=smooth((seconds-.8)/.6)
        elif seconds<3.8:jack=1.
        elif seconds<4.4:jack=1-smooth((seconds-3.8)/.6)
        else:jack=0.
        airborne=.8<seconds<1.4 or 3.8<seconds<4.4
        flight=(seconds-(.8 if seconds<2 else 3.8))/.6
        hop=.095*math.sin(math.pi*flight) if airborne else 0.
        soft=0.
        for start,end in [(.5,.8),(1.4,1.7),(3.5,3.8),(4.4,4.7)]:
            if start<seconds<end:soft=.04*math.sin(math.pi*(seconds-start)/(end-start))**2
        width=.16+.17*jack
        for side,sign in [('l',1),('r',-1)]:feet[side].x=sign*width;feet[side].z+=hop
        leg_length=rest['thigh_l'].length+rest['calf_l'].length
        hip.z=.0741+math.sqrt((leg_length-.006)**2-(width-.083)**2)+.002+hop-soft
    def moved(point):return hip+q@(point-p0)
    for bone in rest:
        if bone.name=='pelvis' or bone.name.startswith(('spine_','clavicle_','neck_')) or bone.name=='head':
            set_bone(rig,bone.name,moved(bone.head_local),q=q)
    if exercise=='bridge':
        # Keep the head near the mat, with an intact neck/head connection.
        neck=rest['neck_01'];head=rest['head'];neck_head=moved(neck.head_local)
        neck_q=rx(math.pi/2)@Quaternion((0,0,1),math.pi)
        set_bone(rig,'neck_01',neck_head,q=neck_q)
        set_bone(rig,'head',neck_head+neck_q@(neck.tail_local-neck.head_local),q=neck_q)
    for side,sign in [('l',1),('r',-1)]:
        thigh,calf,foot=['%s_%s'%(name,side) for name in ('thigh','calf','foot')]
        upper,lower,hand=['%s_%s'%(name,side) for name in ('upperarm','lowerarm','hand')]
        a=moved(rest[thigh].head_local);ankle=feet[side]
        if exercise in ('pushup','plank'):
            knee=moved(rest[calf].head_local)
        else:
            pole=(0,0,1) if exercise=='bridge' else (sign*.05,-1,0)
            knee=solve_joint(a,ankle,rest[thigh].length,rest[calf].length,pole)
        limb(rig,thigh,calf,a,knee,ankle,q);set_bone(rig,foot,ankle,q=foot_q[side])
        shoulder=moved(rest[upper].head_local);elbow=None
        if exercise=='pushup':
            hand_q=hand_rotation(rig,side,(0,-1,0),True)
            wrist=V((sign*.235,-.35,surface_height(rig,side,'hand',hand_q)))
            elbow=solve_joint(shoulder,wrist,rest[upper].length,rest[lower].length,(sign*.5,1,.05))
        elif exercise=='plank':
            elbow=shoulder+V((0,0,-rest[upper].length))
            hand_q=hand_rotation(rig,side,(0,-1,0),True)
            wrist_z=surface_height(rig,side,'hand',hand_q)
            forearm_y=math.sqrt(rest[lower].length**2-(elbow.z-wrist_z)**2)
            wrist=elbow+V((0,-forearm_y,wrist_z-elbow.z))
        elif exercise=='bridge':
            hand_q=hand_rotation(rig,side,(0,1,0),True)
            wrist=V((-sign*.255,-.09,surface_height(rig,side,'hand',hand_q)))
            elbow=solve_joint(shoulder,wrist,rest[upper].length,rest[lower].length,(-sign,0,.2))
        elif exercise=='row':
            angle=-.08+1.16*depth
            elbow=shoulder+V((sign*.06,math.sin(angle),-math.cos(angle))).normalized()*rest[upper].length
            wrist=elbow+V((0,-.05-.32*depth,-1)).normalized()*rest[lower].length
        elif exercise=='curl':
            elbow=shoulder+V((sign*.09,.025,-1)).normalized()*rest[upper].length
            angle=-math.pi/2+2.30*depth
            wrist=elbow+V((0,-math.cos(angle),math.sin(angle)))*rest[lower].length
        elif exercise=='jumping_jack':
            raise_amount=smooth((seconds-.5)/.9) if seconds<1.4 else (1-smooth((seconds-3.5)/.9) if seconds>3.5 else 1.)
            angle=.08+math.radians(158)*raise_amount
            elbow=shoulder+V((sign*math.sin(angle),0,-math.cos(angle)))*rest[upper].length
            wrist=elbow+V((sign*math.sin(angle-.06),-.025,-math.cos(angle-.06))).normalized()*rest[lower].length
        else:
            elbow=shoulder+V((sign*.12,0,-1)).normalized()*rest[upper].length
            wrist=elbow+V((sign*.03,-.18,-1)).normalized()*rest[lower].length
        limb(rig,upper,lower,shoulder,elbow,wrist,q)
        if exercise not in ('pushup','plank','bridge'):hand_q=hand_rotation(rig,side,wrist-elbow)
        set_bone(rig,hand,wrist,q=hand_q)
        if exercise in ('pushup','plank','bridge'):flat_fingers(rig,side,wrist,hand_q)
    for p in rig.pose.bones:
        if p.name.startswith(('index_','middle_','ring_','pinky_')) and exercise not in ('pushup','plank','bridge'):
            p.rotation_mode='QUATERNION';p.rotation_quaternion=rx(.68 if exercise in ('row','curl') else (0 if exercise in ('pushup','plank','bridge') else .12))
    bpy.context.view_layer.update()
    if exercise=='bridge' and _bridge_raise is None:
        # Weighted skin is not a rigid cylinder: calibrate its upper-back contact,
        # then solve the limbs again against unchanged foot and hand supports.
        body=bpy.data.objects['Man'];evaluated=body.evaluated_get(bpy.context.evaluated_depsgraph_get())
        back=[v.index for v in body.data.vertices if v.co.y>.075 and 1.075<v.co.z<1.265]
        minimum=min(evaluated.data.vertices[j].co.z for j in back)
        pose_exercise(rig,exercise,seconds,.001-minimum)


def animate(rig,exercise):
    rig.animation_data_clear();scene=bpy.context.scene
    scene.render.fps=FPS;scene.frame_start=0;scene.frame_end=END
    for frame in range(END+1):
        scene.frame_set(frame);pose_exercise(rig,exercise,frame/FPS)
        for bone in rig.pose.bones:
            bone.rotation_mode='QUATERNION'
            for channel in ('location','rotation_quaternion','scale'):bone.keyframe_insert(channel)
    action=rig.animation_data.action;action.name='Exercise'
    for layer in action.layers:
        for strip in layer.strips:
            for slot in action.slots:
                for curve in strip.channelbag(slot).fcurves:
                    for key in curve.keyframe_points:key.interpolation='LINEAR'
    scene.frame_set(97)


def render_review(exercise):
    from export_realistic_athlete import render
    folder=WORK/'renders';folder.mkdir(exist_ok=True)
    for name,frame in [('start',0),('middle',53),('end',97)]:
        bpy.context.scene.frame_set(frame)
        render(folder/f'{exercise}-{name}.png',exercise)


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--exercise',choices=IDS);parser.add_argument('--render',action='store_true')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    (WORK/'base').mkdir(parents=True,exist_ok=True)
    for exercise in ([args.exercise] if args.exercise else IDS):
        _surface.clear()
        bpy.ops.wm.open_mainfile(filepath=str(ROOT/'.build/realistic-character/athlete-source.blend'),use_scripts=False)
        rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
        prepare_equipment(rig,exercise);animate(rig,exercise)
        bpy.ops.object.select_all(action='DESELECT');rig.select_set(True)
        for ob in bpy.context.scene.objects:
            if ob.type=='MESH':ob.select_set(True)
        bpy.context.view_layer.objects.active=rig
        path=WORK/'base'/f'{exercise}.glb'
        bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,
            export_animations=True,export_animation_mode='ACTIVE_ACTIONS',export_force_sampling=True,
            export_optimize_animation_size=False,
            export_nla_strips_merged_animation_name='Exercise',export_frame_range=True,export_yup=True,export_morph=False)
        finalize_glb(path)
        bpy.ops.wm.save_as_mainfile(filepath=str(WORK/f'{exercise}.blend'))
        print('MOTION_READY',exercise,str(path),flush=True)
        if args.render:render_review(exercise)


if __name__=='__main__':main()
