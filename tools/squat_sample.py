"""Author an isolated, reference-guided squat for visual review, not certification.

Run in Blender. Does not change the eight production animation assets.
"""
import math
import sys
from pathlib import Path
import bpy
from mathutils import Vector, Quaternion, Matrix

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / '.build/squat-sample'
OUT = ROOT / 'web/review'
sys.path.insert(0, str(ROOT / 'tools'))
from animate_athlete import set_bone, finalize_glb
V = Vector
FPS = 30
DURATION = 6.0
END = int(FPS * DURATION)


def smooth(t):
    t = min(1., max(0., t))
    return t*t*t*(10+t*(-15+6*t))


def depth_at(seconds):
    # 0.5 s setup, 2.5 s descent, 0.5 s bottom, 2 s ascent, 0.5 s reset.
    if seconds < .5: return 0.
    if seconds < 3.: return smooth((seconds-.5)/2.5)
    if seconds < 3.5: return 1.
    if seconds < 5.5: return 1-smooth((seconds-3.5)/2.)
    return 0.


def pose_squat(rig, seconds):
    for p in rig.pose.bones: p.matrix_basis = Matrix.Identity(4)
    rest = rig.data.bones
    depth = depth_at(seconds)
    pitch = math.radians(31) * depth
    torso = Quaternion((1,0,0), pitch)
    pelvis_rest = rest['pelvis'].head_local
    legs = {}
    for side, sign in [('l',1),('r',-1)]:
        ankle = V((sign*.18, .035, rest['foot_'+side].head_local.z+.0011))
        # The delivered foot already points out ~11 degrees. Add four degrees.
        foot_q = Quaternion((0,0,1), sign*math.radians(4))
        shin_length = rest['calf_'+side].length
        thigh_length = rest['thigh_'+side].length
        knee_x = sign*(.14+.087*depth)
        shin_sagittal = math.sqrt(shin_length**2-(knee_x-ankle.x)**2)
        shin_pitch = math.radians(.5+30.5*depth)
        knee = V((knee_x, ankle.y-shin_sagittal*math.sin(shin_pitch),
                  ankle.z+shin_sagittal*math.cos(shin_pitch)))
        hip_offset = torso @ (rest['thigh_'+side].head_local-pelvis_rest)
        thigh_sagittal = math.sqrt(thigh_length**2-(knee.x-hip_offset.x)**2)
        thigh_pitch = math.radians(1+85*depth)
        hip_joint = V((hip_offset.x, knee.y+thigh_sagittal*math.sin(thigh_pitch),
                       knee.z+thigh_sagittal*math.cos(thigh_pitch)))
        legs[side] = (hip_joint, knee, ankle, foot_q)
    pelvis = legs['l'][0] - torso @ (rest['thigh_l'].head_local-pelvis_rest)
    set_bone(rig, 'pelvis', pelvis, q=torso)
    # Preserve the source spine's neutral shape; articulate neck separately.
    core = [b for b in rest if b.name.startswith(('spine_', 'clavicle_', 'neck_')) or b.name=='head']
    for b in sorted(core, key=lambda b:len(b.parent_recursive)):
        parent = rig.pose.bones[b.parent.name]
        head = parent.matrix @ b.parent.matrix_local.inverted() @ b.head_local
        angle = pitch * (.9 if b.name.startswith('neck_') else (.75 if b.name=='head' else 1))
        set_bone(rig, b.name, head, q=Quaternion((1,0,0),angle))
    for side, sign in [('l',1),('r',-1)]:
        hip, knee, ankle, foot_q = legs[side]
        for name, a, b in [('thigh_'+side,hip,knee), ('calf_'+side,knee,ankle)]:
            source = rest[name].tail_local-rest[name].head_local
            rotation = (foot_q@source).rotation_difference(b-a) @ foot_q
            set_bone(rig, name, a, q=rotation)
        set_bone(rig,'foot_'+side,ankle,q=foot_q)
        # Reach forward with soft elbows. Endpoints are derived from bone lengths.
        upper, lower, hand = ('upperarm_'+side,'lowerarm_'+side,'hand_'+side)
        clavicle = rig.pose.bones['clavicle_'+side]
        shoulder = clavicle.matrix @ rest['clavicle_'+side].matrix_local.inverted() @ rest[upper].head_local
        upper_direction = V((sign*.07,-1,-.17)).normalized()
        lower_direction = V((sign*.025,-1,-.035)).normalized()
        elbow = shoulder + upper_direction*rest[upper].length
        wrist = elbow + lower_direction*rest[lower].length
        for name,a,b in [(upper,shoulder,elbow),(lower,elbow,wrist)]:
            set_bone(rig,name,a,b)
        # Align the palm's own longitudinal axis; the source wrist is flexed.
        palm_axis = rest['middle_01_'+side].head_local-rest[hand].head_local
        hand_q = palm_axis.rotation_difference(lower_direction)
        set_bone(rig,hand,wrist,q=hand_q)
        for p in rig.pose.bones:
            if p.name.endswith('_'+side) and p.name.startswith(('index_', 'middle_', 'ring_', 'pinky_')):
                p.rotation_mode='QUATERNION'
                p.rotation_quaternion=Quaternion((1,0,0),.12)
    bpy.context.view_layer.update()


def animate(rig):
    rig.animation_data_clear()
    sc = bpy.context.scene
    sc.render.fps = FPS
    sc.frame_start, sc.frame_end = 0, END
    for frame in range(END+1):
        sc.frame_set(frame)
        pose_squat(rig,frame/FPS)
        for bone in rig.pose.bones:
            bone.rotation_mode='QUATERNION'
            bone.keyframe_insert('location')
            bone.keyframe_insert('rotation_quaternion')
            bone.keyframe_insert('scale')
    action=rig.animation_data.action
    action.name='Exercise'
    for layer in action.layers:
        for strip in layer.strips:
            for slot in action.slots:
                for curve in strip.channelbag(slot).fcurves:
                    for key in curve.keyframe_points: key.interpolation='LINEAR'
    sc.frame_set(97)


def render_review(rig):
    sc=bpy.context.scene
    for ob in list(sc.objects):
        if ob.type in ('CAMERA','LIGHT'): bpy.data.objects.remove(ob,do_unlink=True)
    for loc,power,size in [((-3,-4,5),500,4),((3,-1,3),180,3),((0,3,4),400,3)]:
        bpy.ops.object.light_add(type='AREA',location=loc)
        lamp=bpy.context.object;lamp.data.energy=power;lamp.data.size=size
        lamp.rotation_euler=(V((0,0,.7))-lamp.location).to_track_quat('-Z','Y').to_euler()
    bpy.ops.object.camera_add()
    camera=bpy.context.object;camera.data.type='ORTHO';camera.data.ortho_scale=1.68;sc.camera=camera
    sc.render.engine='CYCLES';sc.cycles.samples=24;sc.cycles.use_denoising=True
    sc.render.resolution_x=600;sc.render.resolution_y=700;sc.render.resolution_percentage=100
    sc.view_settings.view_transform='AgX';sc.view_settings.look='AgX - Medium High Contrast';sc.view_settings.exposure=-.3
    sc.world.color=(.13,.13,.13);sc.render.film_transparent=True
    sc.render.image_settings.file_format='PNG';sc.render.image_settings.color_mode='RGBA'
    for label,frame in [('start',0),('middle',53),('bottom',97)]:
        sc.frame_set(frame)
        for view,loc in [('front',(0,-5,.78)),('side',(5,0,.78))]:
            target=V((0,0,.74));camera.location=loc
            camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler()
            sc.render.filepath=str(WORK/f'{view}-{label}.png')
            bpy.ops.render.render(write_still=True)


def main():
    WORK.mkdir(parents=True,exist_ok=True);OUT.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=str(ROOT/'.build/realistic-character/athlete-source.blend'),use_scripts=False)
    rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
    animate(rig)
    bpy.ops.object.select_all(action='DESELECT');rig.select_set(True)
    for ob in bpy.context.scene.objects:
        if ob.type=='MESH': ob.select_set(True)
    bpy.context.view_layer.objects.active=rig
    path=OUT/'squat-v2.glb'
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,
        export_animations=True,export_animation_mode='ACTIVE_ACTIONS',export_force_sampling=True,
        export_nla_strips_merged_animation_name='Exercise',
        export_frame_range=True,export_yup=True,export_morph=False)
    finalize_glb(path)
    bpy.ops.wm.save_as_mainfile(filepath=str(WORK/'squat-v2.blend'))
    if '--render' in sys.argv: render_review(rig)


if __name__=='__main__': main()
