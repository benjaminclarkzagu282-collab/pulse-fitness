"""Reference-authored lower/core poses. See docs/reports/expanded-lower-motion.md."""
import math
import bpy
from mathutils import Matrix, Quaternion, Vector
IDS=['sumo_squat','split_squat','lateral_lunge','calf_raise','dead_bug','bird_dog','side_plank','step_jack']
V=Vector

def prepare_equipment(rig,exercise):
    pass

def alternating(seconds):
    from squat_sample import smooth
    t=seconds%6
    def pulse(x):
        if x<.5 or x>2.5:return 0.
        return smooth((x-.5)) if x<=1.5 else 1-smooth(x-1.5)
    return pulse(t),pulse(t-3)

def _hand_q(rig,side,direction,reference):
    rest=rig.data.bones
    source=rest['middle_03_'+side].tail_local-rest['hand_'+side].head_local
    return (reference@source).rotation_difference(V(direction))@reference

def _side_foot_height(rig,side,q):
    sign=1 if side=='l' else -1;head=rig.data.bones['foot_'+side].head_local
    points=[v.co-head for v in bpy.data.objects['Man'].data.vertices if v.co.x*sign>.1 and v.co.z<.15]
    return .001-min((q@p).z for p in points)

def pose_exercise(rig,exercise,seconds):
    from animate_athlete import set_bone
    from motion_library import rx, solve_joint, limb, hand_rotation, flat_fingers, surface_height
    from squat_sample import depth_at, smooth
    assert exercise in IDS
    for p in rig.pose.bones:p.matrix_basis=Matrix.Identity(4)
    rest=rig.data.bones;p0=rest['pelvis'].head_local.copy();hip=p0.copy();q=rx(0)
    d=depth_at(seconds);left,right=alternating(seconds)
    feet={};fqs={};balls={};jack=0.
    for side,sg in [('l',1),('r',-1)]:
        fqs[side]=rx(0);feet[side]=V((sg*.16,.035,surface_height(rig,side,'foot',fqs[side])))
    if exercise=='sumo_squat':
        q=rx(.17*d);hip=V((0,.025+.075*d,.730-.19*d))
        for side,sg in [('l',1),('r',-1)]:
            fqs[side]=Quaternion((0,0,1),sg*.28)
            feet[side]=V((sg*.29,.035,surface_height(rig,side,'foot',fqs[side])))
    elif exercise=='split_squat':
        q=rx(.04*d);hip=V((0,.035-.025*d,.665-.18*d))
        feet['l'].y=-.18;feet['r'].y=.38;fqs['r']=rx(.72)
        feet['r'].z=surface_height(rig,'r','foot',fqs['r'])
    elif exercise=='lateral_lunge':
        shift=.20*(left-right);active=left+right;q=rx(.28*active)
        hip=V((shift,.025+.235*active,.70))
        for side,sg in [('l',1),('r',-1)]:feet[side].x=sg*.32
        far='r' if shift>=0 else 'l';off=q@(rest['thigh_'+far].head_local-p0)
        planar=(hip.x+off.x-feet[far].x)**2+(hip.y+off.y-feet[far].y)**2
        length=rest['thigh_'+far].length+rest['calf_'+far].length-.008
        hip.z=feet[far].z+math.sqrt(length*length-planar)-off.z
    elif exercise=='calf_raise':
        # Hinge the hindfoot about the metatarsal joint while the toe bones and
        # their weighted skin remain fixed; the forefoot never translates.
        for side,sg in [('l',1),('r',-1)]:
            fqs[side]=rx(.62*d)
            ball=rest['ball_'+side].head_local+V((0,0,.0054));balls[side]=ball
            feet[side]=ball-fqs[side]@(rest['ball_'+side].head_local-rest['foot_'+side].head_local)
        hip+=feet['l']-(rest['foot_l'].head_local+V((0,0,.0011)))
        hip.z-=.003
    elif exercise=='dead_bug':
        q=rx(math.pi/2)@Quaternion((0,0,1),math.pi)
        # Static torso: no lumbar rocking while limbs lower independently.
        points=[v.co for v in bpy.data.objects['Man'].data.vertices if abs(v.co.x)<.13 and v.co.z>.68]
        hip=V((0,.12,.001-min((q@(p-p0)).z for p in points)))
    elif exercise=='bird_dog':
        q=rx(math.pi/2-.06);hip=V((0,.06,.391))
    elif exercise=='side_plank':
        q=rx(math.pi/2-.28)@Quaternion((0,0,1),math.pi/2)
        hip=V((0,.10,.324))
        for side in ('l','r'):
            fqs[side]=q.copy();feet[side]=V((0,.75,_side_foot_height(rig,'r',q)+(0 if side=='r' else .078)))
            joint=hip+q@(rest['thigh_'+side].head_local-p0)
            length=rest['thigh_'+side].length+rest['calf_'+side].length-.0015
            feet[side].y=joint.y+math.sqrt(length*length-(feet[side].z-joint.z)**2-joint.x**2)
    elif exercise=='step_jack':
        t=seconds%6;side='l' if t<3 else 'r';local=t if t<3 else t-3
        if local<.5:jack=0.
        elif local<1.2:jack=smooth((local-.5)/.7)
        elif local<1.8:jack=1.
        elif local<2.5:jack=1-smooth((local-1.8)/.7)
        else:jack=0.
        swing=math.sin(math.pi*((local-.5)/.7))**2 if .5<local<1.2 else (math.sin(math.pi*((local-1.8)/.7))**2 if 1.8<local<2.5 else 0.)
        feet[side].x+=(1 if side=='l' else -1)*.24*jack;feet[side].z+=.05*swing
        hip.x=(-1 if side=='l' else 1)*.035*jack
        hip.z=.753-.09*jack
    def moved(point):return hip+q@(point-p0)
    for b in rest:
        if b.name=='pelvis' or b.name.startswith(('spine_','clavicle_','neck_')) or b.name=='head':set_bone(rig,b.name,moved(b.head_local),q=q)
    for side,sg in [('l',1),('r',-1)]:
        thigh,calf,foot=['%s_%s'%(n,side) for n in ('thigh','calf','foot')]
        upper,lower,hand=['%s_%s'%(n,side) for n in ('upperarm','lowerarm','hand')]
        a=moved(rest[thigh].head_local);ankle=feet[side]
        if exercise=='dead_bug':
            extension=right if side=='l' else left
            theta=1.30*extension
            knee=a+V((0,math.sin(theta),math.cos(theta)))*rest[thigh].length
            ankle=knee+V((0,math.cos(.20*extension),-math.sin(.20*extension)))*rest[calf].length
            fqs[side]=q.copy()
        elif exercise=='bird_dog':
            extension=d if side=='r' else 0.
            theta=1.53*extension
            knee=a+V((0,math.sin(theta),-math.cos(theta)))*rest[thigh].length
            ankle=knee+V((0,math.cos(.13),math.sin(.13)))*rest[calf].length
            fqs[side]=rx(math.pi)
        else:
            pole=(sg*1.2,-1,0) if exercise=='sumo_squat' else ((sg*.2,-1,0) if exercise=='lateral_lunge' else ((1,0,0) if exercise=='side_plank' else (sg*.02,-1,0)))
            knee=solve_joint(a,ankle,rest[thigh].length,rest[calf].length,pole)
        limb(rig,thigh,calf,a,knee,ankle,q);set_bone(rig,foot,ankle,q=fqs[side])
        if exercise=='calf_raise':set_bone(rig,'ball_'+side,balls[side],q=rx(0))
        shoulder=moved(rest[upper].head_local)
        if exercise=='dead_bug':
            extension=left if side=='l' else right;angle=1.35*extension
            direction=V((0,-math.sin(angle),math.cos(angle)))
            elbow=shoulder+direction*rest[upper].length
            wrist=elbow+V((0,-math.sin(angle+.055),math.cos(angle+.055)))*rest[lower].length
            hq=_hand_q(rig,side,wrist-elbow,q)
        elif exercise=='bird_dog':
            hq=hand_rotation(rig,side,(0,-1,0),True)
            ground=surface_height(rig,side,'hand',hq)
            if side=='r':wrist=V((shoulder.x,shoulder.y,ground))
            else:
                angle=math.pi/2*d;length=shoulder.z-ground
                wrist=shoulder+V((0,-math.sin(angle),-math.cos(angle)))*length
            elbow=solve_joint(shoulder,wrist,rest[upper].length,rest[lower].length,(sg*.1,1,0))
        elif exercise=='side_plank':
            if side=='r':
                elbow=shoulder+V((0,0,-rest[upper].length));wrist=elbow+V((rest[lower].length,0,0))
            else:
                wrist=hip+q@V((.15,-.08,.18))
                elbow=solve_joint(shoulder,wrist,rest[upper].length,rest[lower].length,(1,0,1))
            hq=_hand_q(rig,side,wrist-elbow,q)
        elif exercise=='step_jack':
            angle=2.60*jack
            direction=V((sg*math.sin(angle),0,-math.cos(angle)))
            elbow=shoulder+direction*rest[upper].length
            direction2=V((sg*math.sin(angle+.075),-.02,-math.cos(angle+.075))).normalized()
            wrist=elbow+direction2*rest[lower].length;hq=_hand_q(rig,side,wrist-elbow,q)
        elif exercise in ('sumo_squat','lateral_lunge'):
            # Soft arms forward for balance, away from the knees and torso.
            elbow=shoulder+V((sg*.08,-.78,-.62)).normalized()*rest[upper].length
            wrist=elbow+V((-sg*.10,-.97,.15)).normalized()*rest[lower].length
            hq=_hand_q(rig,side,wrist-elbow,q)
        else:
            elbow=shoulder+V((sg*.10,0,-1)).normalized()*rest[upper].length
            wrist=elbow+V((sg*.04,-.14,-1)).normalized()*rest[lower].length
            hq=_hand_q(rig,side,wrist-elbow,q)
        limb(rig,upper,lower,shoulder,elbow,wrist,q);set_bone(rig,hand,wrist,q=hq)
        if exercise=='bird_dog':flat_fingers(rig,side,wrist,hq)
    bpy.context.view_layer.update()
