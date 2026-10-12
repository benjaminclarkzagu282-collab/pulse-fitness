"""Review candidate: reference-guided, editable bodyweight squat on original skin.

API: pose(rig, seconds). World +X left, -Y anterior, +Z up. Never rescales
bones or edits source skin. ACE bodyweight squat / Mayo squat are qualitative
references, not motion capture, numerical standards, or coaching approval.

Blender -b --factory-startup --python-exit-code 1 --python tools/quality_squat.py
"""
import math, sys, json
from pathlib import Path
import bpy
from mathutils import Matrix,Quaternion,Vector as V
ROOT=Path(__file__).resolve().parents[1];WORK=ROOT/'.build/motion-quality/squat'
sys.path.insert(0,str(ROOT/'tools'))
from animate_athlete import set_bone,finalize_glb
FPS=30;DURATION=6.;END=180
# Depth, shank incline, femur incline from vertical, neutral trunk lean.
# These artist-editable poses share the same foot and knee plane. The final
# pose is a controlled roughly right-angle knee bend, within Mayo's demo range.
KEY_POSES=[(0.,1.,2.,0.),(.18,5.,15.,7.),(.5,14.,35.,17.),(.8,22.,53.,24.),(1.,26.,64.,28.)]

def smooth(t):
    t=min(1.,max(0.,t));return t*t*t*(10+t*(-15+6*t))
def depth_at(t):
    if t<.5:return 0.
    if t<3.:return smooth((t-.5)/2.5)
    if t<3.35:return 1.
    if t<5.5:return 1-smooth((t-3.35)/2.15)
    return 0.
def interpolate(x,column):
    """Monotone cubic Hermite passes through authored poses without extra stops."""
    xs=[v[0] for v in KEY_POSES];ys=[v[column] for v in KEY_POSES]
    ds=[(ys[i+1]-ys[i])/(xs[i+1]-xs[i]) for i in range(len(xs)-1)]
    ms=[ds[0]]+[(0. if ds[i-1]*ds[i]<=0 else 2/(1/ds[i-1]+1/ds[i])) for i in range(1,len(ds))]+[ds[-1]]
    i=next((i for i in range(len(xs)-1) if x<=xs[i+1]),len(xs)-2)
    h=xs[i+1]-xs[i];u=(x-xs[i])/h
    return (2*u**3-3*u*u+1)*ys[i]+(u**3-2*u*u+u)*h*ms[i]+(-2*u**3+3*u*u)*ys[i+1]+(u**3-u*u)*h*ms[i+1]

def calibrated_rotation(rest_bone,target_axis,target_front):
    """Fix both long axis and anterior direction, eliminating free axial twist.

    Using only rotation_difference constrains 2 DOF, leaving skin roll implicit.
    The source anterior direction is the world-space anterior skin axis, not
    a guessed bone local X (the delivered left/right bone rolls differ).
    """
    src_y=(rest_bone.tail_local-rest_bone.head_local).normalized()
    src_z=V((0,-1,0));src_z=(src_z-src_y*src_y.dot(src_z)).normalized()
    src_x=src_y.cross(src_z).normalized()
    dst_y=target_axis.normalized();dst_z=target_front-dst_y*dst_y.dot(target_front);dst_z.normalize();dst_x=dst_y.cross(dst_z).normalized()
    src=Matrix((src_x,src_y,src_z)).transposed();dst=Matrix((dst_x,dst_y,dst_z)).transposed()
    return (dst@src.transposed()).to_quaternion()

def arm_rotation(rig,name,a,b,reference):
    bone=rig.data.bones[name];source=bone.tail_local-bone.head_local
    return (reference@source).rotation_difference(b-a)@reference

def pose(rig,seconds):
    for p in rig.pose.bones:p.matrix_basis=Matrix.Identity(4)
    rest=rig.data.bones;d=depth_at(seconds)
    shin_pitch,thigh_pitch,trunk_pitch=[math.radians(interpolate(d,j)) for j in (1,2,3)]
    torso=Quaternion((1,0,0),trunk_pitch);p0=rest['pelvis'].head_local
    legs={}
    for side,sign in [('l',1),('r',-1)]:
        ankle=V((sign*.16,.035,rest['foot_'+side].head_local.z+.0011))
        forward=rest['foot_'+side].tail_local-rest['foot_'+side].head_local;forward.z=0;forward.normalize()
        # Fade the source resting tibial slope before substantive flexion.
        rest_inset=-sign*.028*(1-smooth(d/.18))
        lateral=V((rest_inset,0,0));effective=math.sqrt(rest['calf_'+side].length**2-lateral.length_squared)
        knee=ankle+lateral+forward*(effective*math.sin(shin_pitch))+V((0,0,effective*math.cos(shin_pitch)))
        hip_offset=torso@(rest['thigh_'+side].head_local-p0)
        sagittal=math.sqrt(rest['thigh_'+side].length**2-(knee.x-hip_offset.x)**2)
        hip=V((hip_offset.x,knee.y+sagittal*math.sin(thigh_pitch),knee.z+sagittal*math.cos(thigh_pitch)))
        legs[side]=(hip,knee,ankle,forward)
    pelvis=legs['l'][0]-torso@(rest['thigh_l'].head_local-p0)
    set_bone(rig,'pelvis',pelvis,q=torso)
    core=[b for b in rest if b.name.startswith(('spine_','clavicle_','neck_')) or b.name=='head']
    for b in sorted(core,key=lambda b:len(b.parent_recursive)):
        parent=rig.pose.bones[b.parent.name];head=parent.matrix@b.parent.matrix_local.inverted()@b.head_local
        # Preserve neutral spine. Mild head counter-rotation maintains forward
        # gaze without levering the whole thorax to hold the face upright.
        factor=.83 if b.name.startswith('neck_') else (.70 if b.name=='head' else 1.)
        set_bone(rig,b.name,head,q=Quaternion((1,0,0),trunk_pitch*factor))
    for side,sign in [('l',1),('r',-1)]:
        hip,knee,ankle,forward=legs[side]
        # Femur/knee hinge is calibrated to the actual bending plane, not the
        # foot's yaw applied as a free rotation to both bones.
        thigh_axis=(knee-hip).normalized();calf_axis=(ankle-knee).normalized()
        hinge=thigh_axis.cross(calf_axis)
        if hinge.length<1e-6:hinge=V((1,0,0))
        hinge.normalize()
        thigh_front=hinge.cross(thigh_axis)
        calf_front=hinge.cross(calf_axis)
        if thigh_front.dot(forward)<0:thigh_front=-thigh_front
        if calf_front.dot(forward)<0:calf_front=-calf_front
        # At near-straight stance, the hinge direction is numerically weak;
        # blend from the stable toe frame during the preparatory knee bend.
        blend=smooth(d/.25)
        thigh_front=forward.lerp(thigh_front,blend)
        calf_front=forward  # Tibial anterior plane remains aligned with fixed foot.
        for name,a,b,front in [('thigh_'+side,hip,knee,thigh_front),('calf_'+side,knee,ankle,calf_front)]:
            set_bone(rig,name,a,q=calibrated_rotation(rest[name],b-a,front))
        set_bone(rig,'foot_'+side,ankle,q=Quaternion((1,0,0),0))
        upper,lower,hand=['%s_%s'%(n,side) for n in ('upperarm','lowerarm','hand')]
        clav=rig.pose.bones['clavicle_'+side];shoulder=clav.matrix@rest['clavicle_'+side].matrix_local.inverted()@rest[upper].head_local
        # Arms travel with the squat rather than remaining raised at setup.
        reach=d;angle=math.radians(15+70*reach)
        u=V((sign*.13,-math.sin(angle),-math.cos(angle))).normalized()
        v=V((sign*.03,-math.sin(angle+math.radians(8)),-math.cos(angle+math.radians(8)))).normalized()
        elbow=shoulder+u*rest[upper].length;wrist=elbow+v*rest[lower].length
        for name,a,b in [(upper,shoulder,elbow),(lower,elbow,wrist)]:set_bone(rig,name,a,q=arm_rotation(rig,name,a,b,torso))
        # Palm axis and cross-palm axis define neutral wrists with palms down
        # near full reach. Keep fingers relaxed in their original local plane.
        palm=(rest['middle_01_'+side].head_local-rest[hand].head_local).normalized()
        across=(rest['index_01_'+side].head_local-rest['pinky_01_'+side].head_local).normalized();across=(across-palm*across.dot(palm)).normalized()
        target_across=V((0,-1,0)).lerp(V((-sign,0,0)),reach);target_across=(target_across-v*target_across.dot(v)).normalized()
        source=Matrix((across,palm,across.cross(palm))).transposed();target=Matrix((target_across,v,target_across.cross(v))).transposed()
        set_bone(rig,hand,wrist,q=(target@source.transposed()).to_quaternion())
        for p in rig.pose.bones:
            if p.name.endswith('_'+side) and p.name.startswith(('index_','middle_','ring_','pinky_')):
                p.rotation_mode='QUATERNION';p.rotation_quaternion=Quaternion((1,0,0),.08)
    bpy.context.view_layer.update()

def animate(rig):
    rig.animation_data_clear();sc=bpy.context.scene;sc.render.fps=FPS;sc.frame_start=0;sc.frame_end=END
    for frame in range(END+1):
        sc.frame_set(frame);pose(rig,frame/FPS)
        for p in rig.pose.bones:
            p.rotation_mode='QUATERNION'
            for channel in ('location','rotation_quaternion','scale'):p.keyframe_insert(channel)
    action=rig.animation_data.action;action.name='Exercise'
    for layer in action.layers:
        for strip in layer.strips:
            for slot in action.slots:
                for curve in strip.channelbag(slot).fcurves:
                    for key in curve.keyframe_points:key.interpolation='LINEAR'
    sc.frame_set(97)

def main():
    WORK.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=str(ROOT/'.build/realistic-character/athlete-source.blend'),use_scripts=False)
    rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');animate(rig)
    bpy.ops.object.select_all(action='DESELECT');rig.select_set(True)
    for ob in bpy.context.scene.objects:
        if ob.type=='MESH':ob.select_set(True)
    bpy.context.view_layer.objects.active=rig
    path=WORK/'base.glb'
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='ACTIVE_ACTIONS',export_force_sampling=True,export_optimize_animation_size=False,export_nla_strips_merged_animation_name='Exercise',export_frame_range=True,export_yup=True,export_morph=False)
    finalize_glb(path);bpy.ops.wm.save_as_mainfile(filepath=str(WORK/'source.blend'))
    (WORK/'references.json').write_text(json.dumps({'references':['https://www.acefitness.org/resources/everyone/exercise-library/135/bodyweight-squat/','https://www.mayoclinic.org/healthy-lifestyle/fitness/multimedia/squat/vid-20084663','https://www.mayoclinic.org/-/media/kcms/gbs/medical-professionals/images/2020/04/30/20/07/bone-health-fig3-imagecollagea-f-632px.jpg'],'scope':'Qualitative reference, human image E observed. Not motion capture or coach approval.','key_poses':KEY_POSES},indent=2))
    print('QUALITY_SQUAT_READY',path,flush=True)
if __name__=='__main__':main()
