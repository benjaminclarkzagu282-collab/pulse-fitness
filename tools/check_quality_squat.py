"""Independent delivered-skin squat QA. Blender --python this-file -- --glb PATH.
Tests geometric regressions as well as knee/foot alignment and skin landmarks;
these are authoring checks, never a fitness certification.
"""
import argparse, hashlib, json, math, sys
from pathlib import Path
import bpy
from mathutils import Matrix, Quaternion, Vector as V
ROOT=Path(__file__).resolve().parents[1]
WORK=ROOT/'.build/motion-quality/squat'
sys.path.insert(0,str(ROOT/'tools'))

def render_views(folder):
    folder.mkdir(parents=True,exist_ok=True)
    sc=bpy.context.scene
    for ob in list(sc.objects):
        if ob.type in ('CAMERA','LIGHT'):bpy.data.objects.remove(ob,do_unlink=True)
    for loc,power,size in [((-3,-4,5),500,4),((3,-1,3),180,3),((0,3,4),400,3)]:
        bpy.ops.object.light_add(type='AREA',location=loc);ob=bpy.context.object
        ob.data.energy=power;ob.data.size=size
        ob.rotation_euler=(V((0,0,.7))-ob.location).to_track_quat('-Z','Y').to_euler()
    bpy.ops.object.camera_add();cam=bpy.context.object;cam.data.type='ORTHO';cam.data.ortho_scale=1.80;sc.camera=cam
    sc.render.engine='CYCLES';sc.cycles.samples=16;sc.cycles.use_denoising=True
    sc.render.resolution_x=540;sc.render.resolution_y=660;sc.render.resolution_percentage=100
    sc.view_settings.view_transform='AgX';sc.view_settings.look='AgX - Medium High Contrast';sc.view_settings.exposure=-.3
    sc.world=sc.world or bpy.data.worlds.new('QA World');sc.world.color=(.13,.13,.13);sc.render.film_transparent=True
    sc.render.image_settings.file_format='PNG';sc.render.image_settings.color_mode='RGBA'
    for label,frame in [('start',0),('middle',53),('bottom',97)]:
        sc.frame_set(frame)
        for view,loc in [('front',(0,-5,.80)),('side',(5,0,.80)),('back',(0,5,.80))]:
            cam.location=loc;cam.rotation_euler=(V((0,0,.80))-cam.location).to_track_quat('-Z','Y').to_euler()
            sc.render.filepath=str(folder/f'{view}-{label}.png');bpy.ops.render.render(write_still=True)

def load(path):
    bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.scene.render.fps=30
    bpy.ops.import_scene.gltf(filepath=str(path))
    return next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')

def degrees(a,b):return math.degrees(a.normalized().angle(b.normalized()))
def signed_planar(a,b,axis):
    a=(a-axis*a.dot(axis)).normalized();b=(b-axis*b.dot(axis)).normalized()
    return math.degrees(math.atan2(axis.dot(a.cross(b)),a.dot(b)))

def inspect(rig,samples=360):
    sc=bpy.context.scene
    end=max(k.co.x for a in bpy.data.actions for slot in a.slots for layer in a.layers for strip in layer.strips for fc in strip.channelbag(slot).fcurves for k in fc.keyframe_points)
    body=next(o for o in sc.objects if o.type=='MESH' and o.name=='Man')
    pairs=[(a+'_'+s,b+'_'+s) for s in ('l','r') for a,b in [('thigh','calf'),('calf','foot'),('upperarm','lowerarm'),('lowerarm','hand')]]
    patches={(side,part):[v.index for v in body.data.vertices if v.co.x*sign>0 and v.co.z<.008 and (v.co.y>0 if part=='heel' else v.co.y<-.05)] for side,sign in [('l',1),('r',-1)] for part in ('heel','forefoot')}
    assert all(patches.values())
    knee_patches={}
    for side in ('l','r'):
        knee=rig.data.bones['calf_'+side].head_local
        candidates=[v for v in body.data.vertices if abs(v.co.z-knee.z)<.025 and abs(v.co.x-knee.x)<.030]
        ymin=min(v.co.y for v in candidates)
        knee_patches[side]=[v.index for v in candidates if v.co.y<ymin+.006]
    maximum={'worst_joint_gap_m':0.,'foot_drift_m':0.,'loop_gap_m':0.,'max_foot_rotation_rad':0.,'max_relative_limb_length_error':0.,'max_sole_contact_height_m':0.,'max_knee_foot_plane_error_deg':0.,'max_distal_twist_deg':0.,'max_patella_plane_error_deg':0.,'max_adjacent_joint_step_m':0.,'max_adjacent_rotation_deg':0.}
    minimum_skin=float('inf');start_feet={};start_rot={};first=None;keyframes=[];previous_points=None;previous_rotations=None;step_peak={};rotation_peak={}
    for i in range(samples+1):
        frame=i/samples*end;sc.frame_set(int(frame),subframe=frame-int(frame))
        if '--inject-root-slide' in sys.argv:
            rig.location.x=.02*math.sin(math.pi*i/samples)**2;bpy.context.view_layer.update()
        if '--inject-twist' in sys.argv:
            calf=rig.pose.bones['calf_l'];foot=rig.pose.bones['foot_l'];foot_matrix=foot.matrix.copy()
            origin=calf.head.copy();axis=(calf.tail-calf.head).normalized()
            delta=Quaternion(axis,math.radians(35)*math.sin(math.pi*i/samples)**2)
            calf.matrix=Matrix.Translation(origin)@delta.to_matrix().to_4x4()@Matrix.Translation(-origin)@calf.matrix
            bpy.context.view_layer.update();foot.matrix=foot_matrix;bpy.context.view_layer.update()
        maximum['worst_joint_gap_m']=max(maximum['worst_joint_gap_m'],*((rig.pose.bones[a].tail-rig.pose.bones[b].head).length for a,b in pairs))
        points=[rig.matrix_world@p.head for p in rig.pose.bones]
        rotations=[p.matrix.to_quaternion() for p in rig.pose.bones]
        if previous_points is not None:
            steps=[(a-b).length for a,b in zip(points,previous_points)];peak=max(steps)
            if peak>maximum['max_adjacent_joint_step_m']:step_peak={'frame':frame,'bone':list(rig.pose.bones)[steps.index(peak)].name};maximum['max_adjacent_joint_step_m']=peak
            for index,(a,b) in enumerate(zip(rotations,previous_rotations)):
                angle=a.rotation_difference(b).angle;angle=math.degrees(min(angle,2*math.pi-angle))
                if angle>maximum['max_adjacent_rotation_deg']:rotation_peak={'frame':frame,'bone':list(rig.pose.bones)[index].name};maximum['max_adjacent_rotation_deg']=angle
        previous_points=points;previous_rotations=rotations
        if first is None:first=points
        if i==samples:maximum['loop_gap_m']=max((a-b).length for a,b in zip(first,points))
        for p in rig.pose.bones:
            assert all(math.isfinite(c) for c in p.head)
            if p.name.startswith(('thigh_','calf_','upperarm_','lowerarm_')):maximum['max_relative_limb_length_error']=max(maximum['max_relative_limb_length_error'],abs(p.length/rig.data.bones[p.name].length-1))
        evaluated=body.evaluated_get(bpy.context.evaluated_depsgraph_get());verts=evaluated.data.vertices
        minimum_skin=min(minimum_skin,min((evaluated.matrix_world@v.co).z for v in verts))
        maximum['max_sole_contact_height_m']=max(maximum['max_sole_contact_height_m'],*(min((evaluated.matrix_world@verts[j].co).z for j in patch) for patch in patches.values()))
        sample={}
        for side in ('l','r'):
            foot=rig.pose.bones['foot_'+side];thigh=rig.pose.bones['thigh_'+side];calf=rig.pose.bones['calf_'+side]
            foot_points=(rig.matrix_world@foot.head,rig.matrix_world@foot.tail);foot_rotation=(rig.matrix_world@foot.matrix).to_quaternion()
            if side not in start_feet:start_feet[side]=foot_points;start_rot[side]=foot_rotation
            maximum['foot_drift_m']=max(maximum['foot_drift_m'],*((a-b).length for a,b in zip(foot_points,start_feet[side])))
            angle=foot_rotation.rotation_difference(start_rot[side]).angle
            maximum['max_foot_rotation_rad']=max(maximum['max_foot_rotation_rad'],min(angle,2*math.pi-angle))
            forward=foot.tail-foot.head;forward.z=0;forward.normalize()
            shin=calf.head-calf.tail;shin_xy=V((shin.x,shin.y,0))
            # Only measure the travel plane once knee flexion is visible; the
            # near-straight source has individual resting varus/valgus.
            flex=180-degrees(thigh.head-thigh.tail,calf.tail-calf.head)
            if flex>30:
                plane_error=degrees(shin_xy,forward)
                maximum['max_knee_foot_plane_error_deg']=max(maximum['max_knee_foot_plane_error_deg'],plane_error)
                axis=(calf.tail-calf.head).normalized()
                rest=rig.data.bones['calf_'+side];q=(calf.matrix@rest.matrix_local.inverted()).to_quaternion()
                front=V((0,-1,0));skin_forward=q@front
                twist=abs(signed_planar(skin_forward,forward,axis))
                maximum['max_distal_twist_deg']=max(maximum['max_distal_twist_deg'],twist)
                centroid=sum((verts[j].co for j in knee_patches[side]),V())/len(knee_patches[side])
                # Actual imported skin follows blended thigh/calf transforms.
                patella=centroid-calf.head
                expected=((thigh.head-thigh.tail).normalized()+(calf.tail-calf.head).normalized()).normalized()
                # anterior bisector points out of the front of the flexed joint.
                if expected.dot(V((0,-1,0)))<0:expected=-expected
                lateral=V((-forward.y,forward.x,0)).normalized()
                patella_error=math.degrees(math.asin(min(1.,abs(patella.normalized().dot(lateral)))))
                maximum['max_patella_plane_error_deg']=max(maximum['max_patella_plane_error_deg'],patella_error)
            sample[side]={'hip':list(thigh.head),'knee':list(calf.head),'ankle':list(calf.tail),'knee_flexion_deg':flex}
        if i in (0,180,195,360):keyframes.append({'frame':frame,'legs':sample})
    result={'samples':samples+1,'minimum_skin_height_m':minimum_skin,**maximum,'keyframes':keyframes,'knee_skin_landmark_counts':{k:len(v) for k,v in knee_patches.items()},'step_peak':step_peak,'rotation_peak':rotation_peak}
    limits={'worst_joint_gap_m':.0005,'foot_drift_m':.0005,'loop_gap_m':.0005,'max_foot_rotation_rad':math.radians(.05),'max_relative_limb_length_error':.002,'max_sole_contact_height_m':.004,'max_knee_foot_plane_error_deg':12.,'max_distal_twist_deg':12.,'max_patella_plane_error_deg':20.,'max_adjacent_joint_step_m':.015,'max_adjacent_rotation_deg':6.}
    result['failures']=[f'{key}: {maximum[key]:.6g} >= {limit}' for key,limit in limits.items() if maximum[key]>=limit]
    if minimum_skin<=-.003:result['failures'].append(f'Skin below floor: {minimum_skin}')
    return result

def main():
    p=argparse.ArgumentParser();p.add_argument('--glb',default=str(WORK/'base.glb'));p.add_argument('--label',default='candidate');p.add_argument('--render',action='store_true');p.add_argument('--diagnose',action='store_true');p.add_argument('--inject-root-slide',action='store_true');p.add_argument('--inject-twist',action='store_true');args=p.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    WORK.mkdir(parents=True,exist_ok=True);rig=load(args.glb);result=inspect(rig)
    result['asset']={'path':str(Path(args.glb).resolve()),'sha256':hashlib.sha256(Path(args.glb).read_bytes()).hexdigest()}
    (WORK/f'{args.label}-verification.json').write_text(json.dumps(result,indent=2))
    print('QUALITY_SQUAT_CHECK',json.dumps(result),flush=True)
    if args.render:render_views(WORK/args.label)
    if not args.diagnose:assert not result['failures'],result['failures']
if __name__=='__main__':main()
