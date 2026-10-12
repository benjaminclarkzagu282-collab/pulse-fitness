"""Retarget the reference-authored library to the unmodified native CAT Skin.

Only pose matrices are authored. Native bind matrices, 81 bone names and every
source influence remain unchanged. CAT joint origins (not Blender Y tails)
define lengths. Legacy rigs are sampled then removed from the delivery scene.
"""
import math
from pathlib import Path
import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector
from native_upper import NativeUpper, GRIP_CENTER

ROOT = Path(__file__).resolve().parents[2]
V = Vector
IDS = ('squat','pushup','lunge','bridge','plank','row','jumping_jack',
       'kneeling_pushup','incline_pushup','floor_press','lateral_raise',
       'single_arm_row','reverse_fly','romanian_deadlift','sumo_squat',
       'split_squat','lateral_lunge','calf_raise','dead_bug','bird_dog',
       'side_plank','step_jack')
WEIGHTS = ('row','floor_press','lateral_raise','single_arm_row',
           'reverse_fly','romanian_deadlift')
FLOOR = ('pushup','plank','bridge','kneeling_pushup','incline_pushup',
         'floor_press','dead_bug','bird_dog','side_plank')
CORE = {'Man_Pelvis':'pelvis','Man_Spine1':'spine_01',
        'Man_Spine2':'spine_02','Man_Spine3':'spine_03',
        'Man_Spine4':'spine_03','Man_Ribcage':'spine_03',
        'Man_Neck1':'neck_01','Man_Neck2':'neck_01','Man_Head':'head',
        'Man_LCollarbone':'clavicle_l','Man_RCollarbone':'clavicle_r'}
_TRAJECTORIES = {}


def _unit(v, fallback=(0,0,1)):
    return v.normalized() if v.length > 1e-9 else V(fallback)


def _joint(a,b,l1,l2,pole):
    """Two-link IK with endpoint projection only at geometric reach limits."""
    axis = b-a
    distance = axis.length
    limit = max(abs(l1-l2)+1e-5, min(l1+l2-1e-5, distance))
    axis = _unit(axis)
    b = a+axis*limit
    x = (l1*l1-l2*l2+limit*limit)/(2*limit)
    perpendicular = V(pole)-axis*V(pole).dot(axis)
    if perpendicular.length < 1e-6:
        perpendicular = axis.cross(V((1,0,0)))
        if perpendicular.length < 1e-6: perpendicular = axis.cross(V((0,1,0)))
    return a+axis*x+perpendicular.normalized()*math.sqrt(max(0,l1*l1-x*x)), b, abs(distance-limit)


def _load_trajectory(exercise):
    if exercise in _TRAJECTORIES: return _TRAJECTORIES[exercise]
    path = ROOT/'.build/motion-library'/f'{exercise}.blend'
    if not path.is_file(): raise FileNotFoundError('Missing motion reference: '+str(path))
    scene = bpy.context.scene
    previous = scene.frame_current
    with bpy.data.libraries.load(str(path),link=False) as (source,target):
        target.objects = [n for n in source.objects if n=='PULSE realistic deformation skeleton']
    old = next((o for o in target.objects if o and o.type=='ARMATURE'),None)
    if old is None: raise RuntimeError('Reference armature missing in '+str(path))
    scene.collection.objects.link(old)
    rest = {b.name:(old.matrix_world@b.matrix_local).copy() for b in old.data.bones}
    poses = []
    for frame in range(181):
        scene.frame_set(frame)
        poses.append({p.name:(old.matrix_world@p.matrix).copy() for p in old.pose.bones})
    source_action = old.animation_data.action.name if old.animation_data else None
    bpy.data.objects.remove(old,do_unlink=True)
    scene.frame_set(previous)
    _TRAJECTORIES[exercise] = {'rest':rest,'poses':poses,'source':str(path),'action':source_action}
    return _TRAJECTORIES[exercise]


class NativeMotion(NativeUpper):
    def __init__(self,rig,exercise):
        if exercise not in IDS and exercise not in ('shoulder_press','curl'):
            raise ValueError('Unknown native exercise: '+exercise)
        super().__init__(rig)
        self.exercise = exercise
        self.trajectory = None if exercise in ('shoulder_press','curl') else _load_trajectory(exercise)
        self.scale = 1.25
        self._surfaces = {}
        self._body_reference = None
        self._contact_patches = {}
        self._equipment_ready = False
        self._correction_cache = {}
        self._accessory_reference = {}
        self._foot_lift = {'L':0.,'R':0.}
        self._toe_lift = {'L':0.,'R':0.}
        body = bpy.data.objects.get('Man')
        if body:
            self.reset()
            evaluated = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
            mesh = evaluated.to_mesh()
            self._body_reference = [body.matrix_world@v.co for v in mesh.vertices]
            evaluated.to_mesh_clear()
            self._body_groups = [{body.vertex_groups[g.group].name:g.weight for g in v.groups}
                                 for v in body.data.vertices]
            self._contact_patches['back'] = [i for i,p in enumerate(self._body_reference)
                if abs(p.x)<.14 and 1.12<p.z<1.75 and p.y>.065]
            for side in ('L','R'):
                knee = self.origin('Man_'+side+'Calf')
                self._contact_patches['knee_'+side] = [i for i,p in enumerate(self._body_reference)
                    if (p-knee).length<.13]
                elbow = self.origin('Man_'+side+'Forearm1')
                self._contact_patches['elbow_'+side] = [i for i,p in enumerate(self._body_reference)
                    if (p-elbow).length<.09 or sum(w for n,w in self._body_groups[i].items() if n.startswith('Man_'+side+'Forearm'))>.65]
                foot='Man_'+side+'Foot'
                footmask=[i for i,g in enumerate(self._body_groups) if sum(w for n,w in g.items() if n.startswith(foot))>.65]
                self._toe_lift[side]=.001-min(self._body_reference[i].z for i in footmask)
            for side in ('L','R'):
                self._open_hand(side,self.origin('Man_'+side+'Hand'),Quaternion())
                native_open=self._body_points();name='Man_'+side+'Hand';origin=self.origin(name)
                mask=[i for i,g in enumerate(self._body_groups) if sum(w for n,w in g.items() if n.startswith(name))>.65]
                self._surfaces[(side,'hand')]=[native_open[i]-origin for i in mask]
            self.reset()

    def _sample(self,seconds):
        frame = max(0.,min(180.,float(seconds)*30))
        low = min(180,int(math.floor(frame)));high=min(180,low+1);frac=frame-low
        poses = self.trajectory['poses']
        if frac<1e-8: return poses[low]
        result = {}
        for name,m in poses[low].items():
            other=poses[high][name]
            q=m.to_quaternion().slerp(other.to_quaternion(),frac)
            result[name]=Matrix.Translation(m.translation.lerp(other.translation,frac))@q.to_matrix().to_4x4()
        return result

    def _delta(self,source,name):
        return (source[name].to_quaternion()@self.trajectory['rest'][name].to_quaternion().inverted()).normalized()

    def _world(self,name):
        return self.rig.matrix_world@self.rig.pose.bones[name].matrix

    def _point(self,name):
        return self._world(name).translation.copy()

    def _body_points(self):
        body=bpy.data.objects['Man'];ev=body.evaluated_get(bpy.context.evaluated_depsgraph_get())
        mesh=ev.to_mesh();points=[body.matrix_world@v.co for v in mesh.vertices]
        ev.to_mesh_clear();return points

    def _surface(self,side,part,q):
        key=(side,part)
        if key not in self._surfaces:
            name='Man_'+side+('Hand' if part=='hand' else 'Foot')
            origin=self.origin(name)
            prefix=name
            selected=[i for i,groups in enumerate(self._body_groups)
                if sum(w for n,w in groups.items() if n.startswith(prefix))>.65]
            self._surfaces[key]=[self._body_reference[i]-origin for i in selected]
        points=self._surfaces[key]
        return .001-min((q@p).z for p in points)

    def _open_hand(self,side,wrist,rotation):
        name='Man_'+side+'Hand';origin,frame=self.palm(side)
        self.place(name,wrist,rotation)
        # Project physical phalanx X axes into the native palm plane. Preserve
        # spread and source roll; the native display tails are never used.
        normal=frame.col[2].normalized()
        for finger in ('Index','Middle','Ring','Pinky','Thumb'):
            head=wrist+rotation@(self.origin(name+finger+'1')-origin)
            for segment in range(1,4):
                bone=name+finger+str(segment)
                if segment<3:
                    source=self.origin(name+finger+str(segment+1))-self.origin(bone)
                else:
                    source=self.reference[bone].to_3x3().col[0]
                flat=_unit(source-normal*source.dot(normal))
                axis=self.reference[bone].to_3x3().col[0].normalized()
                delta=(rotation@axis).rotation_difference(rotation@flat)@rotation
                self.place(bone,head,delta)
                if segment<3:head+=rotation@flat*source.length

    def _relaxed_hand(self,side,wrist,rotation):
        name='Man_'+side+'Hand';origin=self.origin(name)
        self.place(name,wrist,rotation)
        for p in self.rig.pose.bones:
            if p.name.startswith(name) and p.name!=name:
                self.place(p.name,wrist+rotation@(self.origin(p.name)-origin),rotation)

    def _arm(self,side,shoulder,elbow,wrist,core_q,hand_q,gripped,opened):
        pre='Man_'+side;upper=pre+'Upperarm';lower=pre+'Forearm'
        ud=_unit(elbow-shoulder);fd=_unit(wrist-elbow)
        source_u=self.origin(lower+'1')-self.origin(upper)
        source_f=self.origin(pre+'Hand')-self.origin(lower+'1')
        uq=(core_q@source_u).rotation_difference(ud)@core_q
        fq=(core_q@source_f).rotation_difference(fd)@core_q
        relative=hand_q@fq.inverted()
        component=V((relative.x,relative.y,relative.z)).dot(fd)
        twist=Quaternion((relative.w,*(fd*component)))
        if twist.magnitude<1e-8:twist=Quaternion()
        twist.normalize()
        self.place(upper,shoulder,uq)
        for i in range(1,4):
            name=lower+str(i)
            head=elbow+fq@(self.origin(name)-self.origin(lower+'1'))
            self.place(name,head,Quaternion().slerp(twist,(i-1)/3)@fq)
        if gripped:self.grip(side,wrist,hand_q)
        elif opened:self._open_hand(side,wrist,hand_q)
        else:self._relaxed_hand(side,wrist,hand_q)

    def _leg(self,side,hip,knee,ankle,body_q,foot_q,calf_raise=False):
        pre='Man_'+side
        for name,source_end,start,end in [
                (pre+'Thigh',pre+'Calf',hip,knee),
                (pre+'Calf',pre+'Foot',knee,ankle)]:
            direction=self.origin(source_end)-self.origin(name)
            delta=(body_q@direction).rotation_difference(end-start)@body_q
            self.place(name,start,delta)
        foot=pre+'Foot';self.place(foot,ankle,foot_q)
        for p in self.rig.pose.bones:
            if p.name.startswith(foot) and p.name!=foot:
                self.place(p.name,ankle+foot_q@(self.origin(p.name)-self.origin(foot)),foot_q)
        if calf_raise:
            # Native metatarsals are separate two-link toe chains, with no
            # legacy ball bone. Solve Foot -> Toe1 -> Toe2 to planted distal
            # toes rather than translating their roots and stretching spans.
            for finger in ('ExtraFinger','Index','Middle','Ring','Pinky'):
                first=foot+finger+'1';last=foot+finger+'2'
                root=self.origin(first);tip=self.origin(last)
                l0=(root-self.origin(foot)).length;l1=(tip-root).length
                goal=tip+V((0,0,self._toe_lift[side]))
                pole=foot_q@(root-self.origin(foot))
                head,tip_point,projection=_joint(ankle,goal,l0,l1,pole)
                axis=self.reference[first].to_3x3().col[0].normalized()
                toe_q=axis.rotation_difference(tip_point-head)
                self.place(first,head,toe_q)
                self.place(last,tip_point,Quaternion())

    def _core(self,source,offset):
        root='Man_Pelvis';old=source['pelvis'].translation
        hip=old*self.scale+V((0,.01,0))+offset
        if self.exercise not in FLOOR:
            rest=self.trajectory['rest'];old_root=rest['pelvis'].translation
            old_leg=sum((rest[b+'_l'].translation-rest[a+'_l'].translation).length for a,b in [('thigh','calf'),('calf','foot')])
            native_leg=sum((self.origin('Man_L'+b)-self.origin('Man_L'+a)).length for a,b in [('Thigh','Calf'),('Calf','Foot')])
            hip=self.origin(root)+(old-old_root)*self.scale+offset
            hip.z=self.origin(root).z+(old.z-old_root.z)*(native_leg/old_leg)+offset.z+sum(self._toe_lift.values())/2
        deltas={name:self._delta(source,mapped) for name,mapped in CORE.items()}
        if self.exercise in ('pushup','plank','incline_pushup'):
            if self.exercise=='plank' and abs(offset.z)>1e-10:
                extra=Quaternion((1,0,0),-offset.z/1.40)
                deltas={name:extra@q for name,q in deltas.items()}
            qfoot=self._delta(source,'foot_l')
            anchor=source['foot_l'].translation*self.scale+V((0,.01,0))
            anchor.z=self._surface('L','foot',qfoot)
            hip=anchor-deltas[root]@(self.origin('Man_LFoot')-self.origin(root))
        positions={root:hip}
        self.place(root,hip,deltas[root])
        for p in self.rig.pose.bones:
            name=p.name
            if name not in CORE or name==root:continue
            parent=p.parent.name
            positions[name]=positions[parent]+deltas[parent]@(self.origin(name)-self.origin(parent))
            self.place(name,positions[name],deltas[name])
        return hip,deltas

    def _apply(self,source,seconds,offset):
        self.reset();hip,deltas=self._core(source,offset)
        body_q=deltas['Man_Pelvis'];diagnostics={};contacts=[];reach=[]
        feet={};foot_qs={}
        for side,sg in [('L',1),('R',-1)]:
            oldside=side.lower();pre='Man_'+side
            a=self.origin(pre+'Thigh');l1=(self.origin(pre+'Calf')-a).length
            l2=(self.origin(pre+'Foot')-self.origin(pre+'Calf')).length
            oldhip=source['thigh_'+oldside].translation
            oldknee=source['calf_'+oldside].translation
            oldankle=source['foot_'+oldside].translation
            q=self._delta(source,'foot_'+oldside);foot_qs[side]=q
            target=oldankle*self.scale+V((0,.01,0))
            if self.exercise not in FLOOR:
                target=self.origin(pre+'Foot')+(oldankle-self.trajectory['rest']['foot_'+oldside].translation)*self.scale
            native_hip=hip+body_q@(a-self.origin('Man_Pelvis'))
            floating=self.exercise in ('dead_bug','bird_dog')
            if self.exercise in ('pushup','plank','incline_pushup'):
                knee=hip+body_q@(self.origin(pre+'Calf')-self.origin('Man_Pelvis'))
                ankle=hip+body_q@(self.origin(pre+'Foot')-self.origin('Man_Pelvis'))
            elif floating:
                knee=native_hip+_unit(oldknee-oldhip)*l1
                ankle=knee+_unit(oldankle-oldknee)*l2
            else:
                # Preserve legacy flight height above its own posed foot skin.
                # All source contact states are explicit in the authored loops.
                if self.exercise=='jumping_jack':
                    t=seconds;air=.8<t<1.4 or 3.8<t<4.4
                    target.z=self._surface(side,'foot',q)+(max(0,.095*math.sin(math.pi*(t-(.8 if t<2 else 3.8))/.6))*self.scale if air else 0)
                elif self.exercise=='step_jack':
                    t=seconds%3;active=(side=='L' if seconds%6<3 else side=='R')
                    swing=math.sin(math.pi*(t-.5)/.7)**2 if .5<t<1.2 else (math.sin(math.pi*(t-1.8)/.7)**2 if 1.8<t<2.5 else 0)
                    target.z=self._surface(side,'foot',q)+(.05*self.scale*swing if active else 0)
                elif self.exercise=='lunge':
                    t=seconds;swing=math.sin(math.pi*(t-.5)/.5)*.07 if .5<t<1 else (math.sin(math.pi*(t-5)/.5)*.07 if 5<t<5.5 else 0)
                    target.z=self._surface(side,'foot',q)+(swing*self.scale if side=='R' else 0)
                elif self.exercise=='calf_raise':
                    toe_center=sum((self.origin(pre+'Foot'+f+'1') for f in ('ExtraFinger','Index','Middle','Ring','Pinky')),V())/5
                    ankle=toe_center-q@(toe_center-self.origin(pre+'Foot'))+V((0,0,self._toe_lift[side]+self._foot_lift[side]))
                    target=ankle
                elif self.exercise=='side_plank':
                    target.z=self._surface('R','foot',q)+(0 if side=='R' else .095)
                elif self.exercise=='kneeling_pushup':
                    target=oldankle*self.scale+V((0,.01,0))+offset
                else:target.z=self._surface(side,'foot',q)
                pole=(oldknee-oldhip)-_unit(oldankle-oldhip)*(oldknee-oldhip).dot(_unit(oldankle-oldhip))
                knee,ankle,projected=_joint(native_hip,target,l1,l2,pole)
                reach.append(projected)
                if self.exercise=='kneeling_pushup':
                    knee=oldknee*self.scale+V((0,.01,0))+offset
                    knee=native_hip+_unit(knee-native_hip)*l1
                    ankle=knee+_unit(oldankle-oldknee)*l2
            self._leg(side,native_hip,knee,ankle,body_q,q,self.exercise=='calf_raise')
            feet[side]=ankle
            diagnostics[side]={'hip':list(native_hip),'knee':list(knee),'ankle':list(ankle),
                'thigh_length':(knee-native_hip).length,'calf_length':(ankle-knee).length}

        # The native shorts and body share three pelvic soft-tissue controls.
        # Their neutral downward orientation must fold with hip/knee flexion;
        # retaining it on a deep squat produces a dangling crotch envelope.
        # Articulate the existing controls; their binds and weights stay exact.
        flexion=0.
        for side in ('L','R'):
            leg=diagnostics[side]
            upper=_unit(V(leg['knee'])-V(leg['hip']))
            lower=_unit(V(leg['ankle'])-V(leg['knee']))
            flexion=max(flexion,math.acos(max(-1.,min(1.,upper.dot(lower)))))
        fold=min(1.,max(0.,(flexion-math.radians(15))/math.radians(100)))*math.radians(95)
        pelvic_q=body_q@Quaternion((1,0,0),fold)
        first='Man_PelvisBone002';child=first+'Bone001';third=first+'.001'
        head=hip+body_q@(self.origin(first)-self.origin('Man_Pelvis'))
        self.place(first,head,pelvic_q)
        self.place(child,head+pelvic_q@(self.origin(child)-self.origin(first)),pelvic_q)
        self.place(third,hip+body_q@(self.origin(third)-self.origin('Man_Pelvis')),pelvic_q)

        for side,sg in [('L',1),('R',-1)]:
            oldside=side.lower();pre='Man_'+side
            shoulder=self._point(pre+'Upperarm')
            # Native shoulder originates at the transported collarbone endpoint.
            clav=pre+'Collarbone'
            shoulder=self._point(clav)+deltas[clav]@(self.origin(pre+'Upperarm')-self.origin(clav))
            oldshoulder=source['upperarm_'+oldside].translation
            oldelbow=source['lowerarm_'+oldside].translation
            oldwrist=source['hand_'+oldside].translation
            ud=_unit(oldelbow-oldshoulder);fd=_unit(oldwrist-oldelbow)
            l1=(self.origin(pre+'Forearm1')-self.origin(pre+'Upperarm')).length
            l2=(self.origin(pre+'Hand')-self.origin(pre+'Forearm1')).length
            elbow=shoulder+ud*l1;wrist=elbow+fd*l2
            support=self.exercise in ('pushup','kneeling_pushup','incline_pushup','bridge','plank') or (self.exercise=='single_arm_row' and side=='L') or (self.exercise=='bird_dog' and side=='R')
            opened=support or self.exercise=='bird_dog' or (self.exercise=='side_plank' and side=='R')
            gripped=self.exercise in WEIGHTS and not(self.exercise=='single_arm_row' and side=='L')
            oldhandq=self._delta(source,'hand_'+oldside)
            oldrest=self.trajectory['rest']
            oldpalm=oldrest['middle_01_'+oldside].translation-oldrest['hand_'+oldside].translation
            direction=oldhandq@oldpalm
            # Fitted grip follows the forearm. Preserve longitudinal hand twist
            # via the source palm normal where it is well conditioned.
            oldacross=oldrest['index_01_'+oldside].translation-oldrest['pinky_01_'+oldside].translation
            normal=(oldhandq@oldacross).cross(_unit(direction))*(-1 if side=='L' else 1)
            if self.exercise in ('jumping_jack','step_jack'):
                # The reference hand frame projects world X across the palm,
                # which flips its roll when a lateral arm passes horizontal.
                # A frontal palm plane remains well conditioned throughout
                # the whole overhead arc and keeps wrist/forearm twist smooth.
                hand_q=self.hand_rotation(side,fd,V((0,-1,0)))
            elif gripped:
                normal=V((0,-1,0))
                if self.exercise=='floor_press':normal=V((0,-1,0))
                hand_q=self.hand_rotation(side,fd,normal)
            elif opened:
                hand_q=self.hand_rotation(side,V((1,0,0)) if self.exercise=='side_plank' else (V((0,1,0)) if self.exercise=='bridge' else V((0,-1,0))),V((0,0,-1)))
            else:hand_q=self.hand_rotation(side,_unit(direction),normal)
            if self.exercise=='side_plank' and side=='R':
                height=self._surface(side,'hand',hand_q)
                dz=height-elbow.z
                wrist=elbow+V((math.sqrt(max(1e-8,l2*l2-dz*dz)),0,dz))
                contacts.append({'kind':'hand','side':side,'target_height':height,'support_height':0})
            if self.exercise=='bird_dog' and side=='L':
                ground=self._surface(side,'hand',hand_q)
                wrist=shoulder+_unit(oldwrist-oldshoulder)*(shoulder.z-ground)
                pole=(oldelbow-oldshoulder)-_unit(oldwrist-oldshoulder)*(oldelbow-oldshoulder).dot(_unit(oldwrist-oldshoulder))
                elbow,wrist,projected=_joint(shoulder,wrist,l1,l2,pole);reach.append(projected)
            if support:
                wrist=oldwrist*self.scale+V((0,.01,0))
                height=self._surface(side,'hand',hand_q)
                wrist.z=height+(.5 if self.exercise=='incline_pushup' else (.5625 if self.exercise=='single_arm_row' else 0))
                if self.exercise=='bird_dog':wrist.x=shoulder.x;wrist.y=shoulder.y
                pole=(oldelbow-oldshoulder)-_unit(oldwrist-oldshoulder)*(oldelbow-oldshoulder).dot(_unit(oldwrist-oldshoulder))
                elbow,wrist,projected=_joint(shoulder,wrist,l1,l2,pole)
                reach.append(projected)
                contacts.append({'kind':'hand','side':side,'target_height':height,'support_height':(.5 if self.exercise=='incline_pushup' else (.5625 if self.exercise=='single_arm_row' else 0))})
            self._arm(side,shoulder,elbow,wrist,deltas[clav],hand_q,gripped,opened)
            diagnostics[side].update({'shoulder':list(shoulder),'elbow':list(elbow),'wrist':list(wrist),
                'upper_length':(elbow-shoulder).length,'forearm_length':(wrist-elbow).length,
                'grip_center':list(wrist+hand_q@(self.palm(side)[1]@GRIP_CENTER)),
                'gripped':gripped,'open_hand':opened})
        bpy.context.view_layer.update()
        diagnostics['contacts']=contacts
        diagnostics['max_reach_projection_m']=max(reach,default=0.)
        diagnostics['source']=self.trajectory['source']
        return diagnostics

    def pose_time(self,seconds):
        seconds=max(0.,min(6.,float(seconds)))
        if self.exercise in ('shoulder_press','curl'):
            from squat_sample import depth_at
            return super().pose(self.exercise,depth_at(seconds))
        source=self._sample(seconds)
        self._foot_lift={'L':0.,'R':0.}
        # Ground support is solved from the native skin, then limbs are solved
        # again against the same fixed XY contact trajectories.
        offset=V((0,0,0))
        diagnostic=self._apply(source,seconds,offset)
        if self.exercise in ('bridge','floor_press','dead_bug','kneeling_pushup','bird_dog','plank','side_plank'):
            if self.exercise in ('bridge','floor_press','dead_bug'):
                patch=self._contact_patches['back']
            elif self.exercise in ('kneeling_pushup','bird_dog'):
                sides=('L','R') if self.exercise=='kneeling_pushup' else ('L',)
                patch=sum((self._contact_patches['knee_'+s] for s in sides),[])
            else:
                sides=('L','R') if self.exercise=='plank' else ('R',)
                patch=sum((self._contact_patches['elbow_'+s] for s in sides),[])
            for iteration in range(8):
                points=self._body_points()
                correction=.001-min(points[i].z for i in patch)
                if abs(correction)<.00001:break
                # A grounded wrist constrains an elbow to a circular IK arc;
                # its skin rises slower than the shoulder/root displacement.
                offset.z+=correction*(1.65 if self.exercise=='plank' else 1.)
                diagnostic=self._apply(source,seconds,offset)
            diagnostic['support_vertical_correction_m']=offset.z
            points=self._body_points()
            diagnostic['native_support_skin_error_m']=.001-min(points[i].z for i in patch)
        if self.exercise=='calf_raise':
            for _ in range(2):
                points=self._body_points()
                for side in ('L','R'):
                    name='Man_'+side+'Foot'
                    mask=[i for i,g in enumerate(self._body_groups) if sum(w for n,w in g.items() if n.startswith(name))>.65]
                    index=min(mask,key=lambda i:points[i].z)
                    error=.001-points[index].z
                    if abs(error)>.00001:
                        self._foot_lift[side]+=error/max(.1,self._body_groups[index].get(name,1.))
                diagnostic=self._apply(source,seconds,offset)
            diagnostic['native_hindfoot_skin_fit_m']=dict(self._foot_lift)
        # The original open Skin envelopes blend palm and phalanx influences.
        # Fit actual open-hand skin after the first IK solve, not just a wrist.
        open_support=[c for c in diagnostic['contacts'] if c['kind']=='hand']
        if open_support:
            points=self._body_points()
            for contact in open_support:
                side=contact['side'];name='Man_'+side+'Hand'
                mask=[i for i,g in enumerate(self._body_groups) if sum(w for n,w in g.items() if n.startswith(name))>.65]
                contact['skin_min_z']=min(points[i].z for i in mask)
                contact['skin_contact_error_m']=contact['skin_min_z']-contact['support_height']-.001
        return diagnostic

    def pose(self,exercise,depth):
        if exercise!=self.exercise:raise ValueError('Solver exercise differs: '+exercise)
        if exercise in ('shoulder_press','curl'):return super().pose(exercise,depth)
        # Compatibility for preview callers; production uses pose_time.
        from squat_sample import smooth
        target=max(0.,min(1.,float(depth)));lo=0.;hi=1.
        for _ in range(30):
            mid=(lo+hi)/2
            if smooth(mid)<target:lo=mid
            else:hi=mid
        return self.pose_time(.5+2.5*(lo+hi)/2)

    def equipment(self):
        if self._equipment_ready:return
        self._equipment_ready=True
        self.reset()
        # Original face meshes are rigid accessories. Attach using the same
        # reference-to-bind mapping as the approved native dumbbells.
        for obj in list(bpy.context.scene.objects):
            if obj.type!='MESH' or any(m.type=='ARMATURE' for m in obj.modifiers):continue
            if obj.name.startswith(('Native support','Native dumbbell','Web ','PULSE region')):continue
            original=obj.matrix_world.copy();bone='Man_Head'
            obj.data.transform(self.rig.data.bones[bone].matrix_local@self.reference[bone].inverted()@original)
            obj.parent=self.rig;obj.matrix_world=self.rig.matrix_world.copy()
            group=obj.vertex_groups.get(bone) or obj.vertex_groups.new(name=bone)
            group.add(list(range(len(obj.data.vertices))),1,'REPLACE')
            mod=obj.modifiers.new('Native head attachment','ARMATURE');mod.object=self.rig
            self._accessory_reference[obj.name]=[list(row) for row in original]
        if self.exercise in WEIGHTS or self.exercise in ('shoulder_press','curl'):
            super().equipment()
            if self.exercise=='single_arm_row':
                obj=bpy.data.objects.get('Native dumbbell L')
                if obj:bpy.data.objects.remove(obj,do_unlink=True)
        if self.exercise not in ('incline_pushup','single_arm_row'):return
        height=.5 if self.exercise=='incline_pushup' else .5625
        center=V((0,-.6625,height-.04375)) if self.exercise=='incline_pushup' else V((.31875,-.375,height-.04375))
        size=(1.025,.45,.0875) if self.exercise=='incline_pushup' else (.35,.35,.0875)
        material=bpy.data.materials.new('Native support upholstery');material.use_nodes=True
        bs=material.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(.07,.09,.11,1);bs.inputs['Roughness'].default_value=.65
        def box(name,loc,dimensions):
            bpy.ops.mesh.primitive_cube_add(size=1,location=loc);obj=bpy.context.object
            obj.name=name;obj.dimensions=dimensions
            bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
            obj.data.materials.append(material)
            bevel=obj.modifiers.new('Soft edges','BEVEL');bevel.width=.01;bevel.segments=3
        box('Native support top',center,size)
        for x in (-1,1):
            for y in (-1,1):box(f'Native support leg {x} {y}',(center.x+x*(size[0]/2-.06875),center.y+y*(size[1]/2-.075),(height-.0875)/2),(.06875,.06875,height-.0875))
