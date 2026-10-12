"""Three-sample review: manually specified curl/press key poses on the same skin.

Angles define this character's reference poses, not universal joint limits.
The shoulder girdle moves with elevation; palm frames preserve a neutral wrist.
"""
import math
import bpy
from mathutils import Vector,Quaternion,Matrix
from animate_athlete import set_bone
from motion_library import pose_exercise as baseline_pose
from quality_grip import grip_rotation,pose_grip
from squat_sample import depth_at,smooth

V=Vector
# depth, upper-arm elevation from down, elbow included angle, girdle elevation.
PRESS_KEYS=[(0,88,90,2),(.35,111,112,5),(.72,144,145,9),(1,169,173,12)]
# phase depth, forearm flexion from down. Elbow remains fixed near the ribs.
CURL_KEYS=[(0,24),(.4,65),(.75,105),(1,126)]

def key_values(keys,d):
    for start,end in zip(keys,keys[1:]):
        if d<=end[0]:
            # Linear parameter interpolation preserves monotone arcs; depth_at
            # provides the eased time law and holds for the complete repetition.
            f=max(0,min(1,(d-start[0])/(end[0]-start[0])))
            return tuple(a+(b-a)*f for a,b in zip(start[1:],end[1:]))
    return keys[-1][1:]

def align_segment(rig,name,head,direction,reference):
    rest=rig.data.bones[name]
    rotation=(reference@(rest.tail_local-rest.head_local)).rotation_difference(direction)@reference
    set_bone(rig,name,head,q=rotation)

def pose(rig,exercise,seconds):
    assert exercise in ('curl','shoulder_press')
    # Reuse only the grounded standing base. Both arms and all digits are replaced.
    baseline_pose(rig,'curl',0)
    rest=rig.data.bones;d=depth_at(seconds)
    for side,sign in [('l',1),('r',-1)]:
        cl=rest['clavicle_'+side]
        if exercise=='shoulder_press':
            upper_deg,elbow_deg,girdle=key_values(PRESS_KEYS,d)
            cq=Quaternion((0,-sign,0),math.radians(girdle))@Quaternion((0,0,1),math.radians(-sign*(8-2*d)))
            set_bone(rig,'clavicle_'+side,cl.head_local,q=cq)
            shoulder=cl.head_local+cq@(cl.tail_local-cl.head_local)
            plane=math.radians(22)
            u=math.radians(upper_deg);f=math.radians(upper_deg+180-elbow_deg)
            upper_dir=V((sign*math.sin(u)*math.cos(plane),-math.sin(u)*math.sin(plane),-math.cos(u)))
            forearm_dir=V((sign*math.sin(f)*math.cos(plane),-math.sin(f)*math.sin(plane),-math.cos(f)))
            elbow=shoulder+upper_dir*rest['upperarm_'+side].length
            wrist=elbow+forearm_dir*rest['lowerarm_'+side].length
            palm=V((0,-1,0))
        else:
            cq=Quaternion((1,0,0),0)
            shoulder=rest['upperarm_'+side].head_local.copy()
            upper_dir=V((sign*.23,-.20,-1)).normalized()
            elbow=shoulder+upper_dir*rest['upperarm_'+side].length
            flex=math.radians(key_values(CURL_KEYS,d)[0])
            forearm_dir=V((sign*.02,-math.sin(flex),-math.cos(flex))).normalized()
            wrist=elbow+forearm_dir*rest['lowerarm_'+side].length
            palm=V((0,-math.cos(flex),math.sin(flex)))
        hq=grip_rotation(rig,side,forearm_dir,palm)
        # Solve bone roll from the intended wrist/palm frame, rather than using
        # unrelated minimum rotations for the hand and forearm.
        align_segment(rig,'upperarm_'+side,shoulder,elbow-shoulder,cq)
        align_segment(rig,'lowerarm_'+side,elbow,wrist-elbow,hq)
        pose_grip(rig,side,wrist,hq)
    bpy.context.view_layer.update()
