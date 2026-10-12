"""Eight reference-authored strength loops, preserving the original athlete mesh.

The shared motion_library runner provides 181 LINEAR keys over six seconds.
Official movement references and validation are in docs/reports/expanded-upper-motion.md.
"""
import math
import bpy
from mathutils import Matrix,Quaternion,Vector
IDS=['kneeling_pushup','incline_pushup','floor_press','shoulder_press','lateral_raise','single_arm_row','reverse_fly','romanian_deadlift']
V=Vector


def prepare_equipment(rig,exercise):
    from animate_athlete import equipment
    material=bpy.data.materials.get('Dumbbell rubber') or bpy.data.materials.new('Dumbbell rubber')
    material.use_nodes=True
    next(n for n in material.node_tree.nodes if n.type=='BSDF_PRINCIPLED').name='Principled BSDF'
    equipment(rig,'row' if exercise not in ('kneeling_pushup','incline_pushup') else exercise)
    if exercise=='single_arm_row':bpy.data.objects.remove(bpy.data.objects['PULSE dumbbell l'],do_unlink=True)
    for ob in list(bpy.context.scene.objects):
        if ob.name.startswith('PULSE support'):bpy.data.objects.remove(ob,do_unlink=True)
    if exercise not in ('incline_pushup','single_arm_row'):return
    top=.4 if exercise=='incline_pushup' else .45
    center=V((0,-.53,top-.035)) if exercise=='incline_pushup' else V((.255,-.30,top-.035))
    size=(.82,.36,.07) if exercise=='incline_pushup' else (.28,.28,.07)
    material=bpy.data.materials.new('Support upholstery');material.diffuse_color=(.07,.09,.11,1);material.use_nodes=True
    next(n for n in material.node_tree.nodes if n.type=='BSDF_PRINCIPLED').inputs['Base Color'].default_value=(.07,.09,.11,1)
    next(n for n in material.node_tree.nodes if n.type=='BSDF_PRINCIPLED').inputs['Roughness'].default_value=.65
    def box(name,location,dimensions):
        bpy.ops.mesh.primitive_cube_add(size=1,location=location);o=bpy.context.object;o.name=name;o.dimensions=dimensions
        bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(material)
        bevel=o.modifiers.new('Soft edges','BEVEL');bevel.width=.008;bevel.segments=3
    box('PULSE support top',center,size)
    for x in (-1,1):
        for y in (-1,1):box(f'PULSE support leg {x} {y}',(center.x+x*(size[0]/2-.055),center.y+y*(size[1]/2-.06),(top-.07)/2),(.055,.055,top-.07))


def pose_exercise(rig,exercise,seconds,_floor_offset=None,_knee_offset=None):
    # Lazy helpers avoid a circular import when the shared runner dispatches here.
    from motion_library import rx,solve_joint,set_bone,hand_rotation,flat_fingers,limb,surface_height
    from squat_sample import depth_at
    assert exercise in IDS,exercise
    if exercise=='floor_press' and _floor_offset is None:
        if 'upper_floor_offset' not in rig:
            pose_exercise(rig,exercise,0,0.)
            body=bpy.data.objects['Man'];ev=body.evaluated_get(bpy.context.evaluated_depsgraph_get())
            patch=[v.index for v in body.data.vertices if v.co.y>.075 and 1.075<v.co.z<1.265]
            rig['upper_floor_offset']=.001-min(ev.data.vertices[j].co.z for j in patch)
        _floor_offset=float(rig['upper_floor_offset'])
    for p in rig.pose.bones:p.matrix_basis=Matrix.Identity(4)
    rest=rig.data.bones;p0=rest['pelvis'].head_local.copy();hip=p0.copy();q=rx(0);d=depth_at(seconds)
    feet={s:V((sign*.16,.035,rest['foot_'+s].head_local.z+.0011)) for s,sign in [('l',1),('r',-1)]}
    feet_q={s:rx(0) for s in feet};knees={}
    if exercise=='incline_pushup':
        q=rx(math.pi/2-math.radians(33-11*d))
        for s in feet:
            feet_q[s]=rx(math.pi/2-.2);feet[s].y=.75;feet[s].z=surface_height(rig,s,'foot',feet_q[s])
        hip=feet['l']-q@(rest['foot_l'].head_local-p0)
    elif exercise=='kneeling_pushup':
        q=rx(math.pi/2-math.radians(28-15.5*d))
        knee_l=V((.122,.37,.057+(_knee_offset or 0)))
        hip=knee_l-q@(rest['calf_l'].head_local-p0)
        for s,sign in [('l',1),('r',-1)]:
            knees[s]=V((sign*.122,.37,.057+(_knee_offset or 0)))
            feet[s]=knees[s]+V((sign*.038,.29,.186)).normalized()*rest['calf_'+s].length
            feet_q[s]=rx(.8)
    elif exercise=='floor_press':
        q=rx(math.pi/2)@Quaternion((0,0,1),math.pi)
        hip=V((0,.03,.125+(_floor_offset or 0)))
        for s,sign in [('l',1),('r',-1)]:
            feet_q[s]=Quaternion((0,0,1),math.pi);feet[s]=V((-sign*.16,.56,surface_height(rig,s,'foot',feet_q[s])))
    elif exercise in ('single_arm_row','reverse_fly'):
        q=rx(1.12 if exercise=='single_arm_row' else 1.15);hip+=V((0,.16,-.125 if exercise=='single_arm_row' else -.085))
        for s in feet:feet[s].x*=1.125
    elif exercise=='romanian_deadlift':
        q=rx(1.12*d);hip+=V((0,.235*d,-.075*d))
    def moved(point):return hip+q@(point-p0)
    for b in rest:
        if b.name=='pelvis' or b.name.startswith(('spine_','clavicle_','neck_')) or b.name=='head':set_bone(rig,b.name,moved(b.head_local),q=q)
    for s,sign in [('l',1),('r',-1)]:
        thigh,calf,foot=[n+'_'+s for n in ('thigh','calf','foot')]
        upper,lower,hand=[n+'_'+s for n in ('upperarm','lowerarm','hand')]
        a=moved(rest[thigh].head_local);ankle=feet[s]
        if exercise=='incline_pushup':knee=moved(rest[calf].head_local)
        elif exercise=='kneeling_pushup':knee=knees[s]
        else:knee=solve_joint(a,ankle,rest[thigh].length,rest[calf].length,(0,0,1) if exercise=='floor_press' else (sign*.05,-1,0))
        limb(rig,thigh,calf,a,knee,ankle,q)
        if exercise=='kneeling_pushup':
            # Shin orientation is fixed; pitching torso must not twist calves.
            set_bone(rig,calf,knee,q=(rest[calf].tail_local-rest[calf].head_local).rotation_difference(ankle-knee))
        set_bone(rig,foot,ankle,q=feet_q[s])
        shoulder=moved(rest[upper].head_local);hand_q=None;open_hand=False
        if exercise in ('kneeling_pushup','incline_pushup'):
            hand_q=hand_rotation(rig,s,(0,-1,0),True);open_hand=True
            wrist=V((sign*.235,-.35,(.4 if exercise=='incline_pushup' else 0)+surface_height(rig,s,'hand',hand_q)))
            elbow=solve_joint(shoulder,wrist,rest[upper].length,rest[lower].length,(sign*.5,1,.05))
        elif exercise=='floor_press':
            sw=-sign
            bottom_elbow=shoulder+V((sw*.18,.13,-.025)).normalized()*rest[upper].length
            low=bottom_elbow+V((0,0,rest[lower].length))
            high=shoulder+V((sw*.015,0,.397))
            wrist=low.lerp(high,d)
            elbow=solve_joint(shoulder,wrist,rest[upper].length,rest[lower].length,(sw,.65,-.05))
        elif exercise=='shoulder_press':
            wrist=V((sign*(.35-.17*d),-.035,1.39+.192*d))
            elbow=solve_joint(shoulder,wrist,rest[upper].length,rest[lower].length,(sign,-.3,-.1))
        elif exercise=='lateral_raise':
            angle=.12+1.4*d
            elbow=shoulder+V((sign*math.sin(angle),-.06,-math.cos(angle))).normalized()*rest[upper].length
            wrist=elbow+V((sign*math.sin(angle-.09),-.10,-math.cos(angle-.09))).normalized()*rest[lower].length
        elif exercise=='single_arm_row' and s=='l':
            hand_q=hand_rotation(rig,s,(0,-1,0),True);open_hand=True
            wrist=V((.255,-.21,.45+surface_height(rig,s,'hand',hand_q)))
            elbow=solve_joint(shoulder,wrist,rest[upper].length,rest[lower].length,(.5,1,0))
        elif exercise=='single_arm_row':
            angle=-.08+1.16*d
            elbow=shoulder+V((sign*.06,math.sin(angle),-math.cos(angle))).normalized()*rest[upper].length
            wrist=elbow+V((0,-.05-.32*d,-1)).normalized()*rest[lower].length
        elif exercise=='reverse_fly':
            angle=.10+1.38*d
            elbow=shoulder+V((sign*math.sin(angle),0,-math.cos(angle))).normalized()*rest[upper].length
            wrist=elbow+V((sign*math.sin(angle-.20),-.055,-math.cos(angle-.20))).normalized()*rest[lower].length
        else:
            elbow=shoulder+V((sign*.085,-.035,-1)).normalized()*rest[upper].length
            wrist=elbow+V((sign*.045,-.05,-1)).normalized()*rest[lower].length
        limb(rig,upper,lower,shoulder,elbow,wrist,q)
        if hand_q is None:hand_q=hand_rotation(rig,s,wrist-elbow)
        set_bone(rig,hand,wrist,q=hand_q)
        if open_hand:flat_fingers(rig,s,wrist,hand_q)
        else:
            for p in rig.pose.bones:
                if p.name.endswith('_'+s) and p.name.startswith(('index_','middle_','ring_','pinky_')):
                    p.rotation_mode='QUATERNION';p.rotation_quaternion=rx(.68)
    bpy.context.view_layer.update()

    if exercise=='kneeling_pushup' and _knee_offset is None:
        # A knee rolls on its anterior skin as the thigh pitches. Keep its XY
        # anchor fixed and resolve the actual patellar envelope vertically.
        body=bpy.data.objects['Man'];ev=body.evaluated_get(bpy.context.evaluated_depsgraph_get())
        patch=[v.index for v in body.data.vertices if any((v.co-rest['calf_'+s].head_local).length<.10 for s in ('l','r'))]
        pose_exercise(rig,exercise,seconds,_knee_offset=.001-min(ev.data.vertices[j].co.z for j in patch))
