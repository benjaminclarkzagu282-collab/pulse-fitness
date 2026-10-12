"""Build the three review samples without overwriting the 24-action library."""
import argparse,sys,json,math
from pathlib import Path
import bpy
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from animate_athlete import finalize_glb

def render(path,view='front',target=(0,0,.86),scale=1.9):
    scene=bpy.context.scene
    for ob in list(scene.objects):
        if ob.type in ('LIGHT','CAMERA'):bpy.data.objects.remove(ob,do_unlink=True)
    target=Vector(target)
    for pos,energy,size in [((-3,-4,4),500,3),((3,-1,2),200,3),((1,3,3),500,3)]:
        bpy.ops.object.light_add(type='AREA',location=pos);ob=bpy.context.object
        ob.data.energy=energy;ob.data.size=size;ob.rotation_euler=(target-ob.location).to_track_quat('-Z','Y').to_euler()
    pos={'front':(0,-5,.86),'side':(5,0,.86),'back':(0,5,.86),'threequarter':(3,-5,1.1)}[view]
    bpy.ops.object.camera_add(location=pos);cam=bpy.context.object
    cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=scale
    scene.camera=cam;scene.render.engine='CYCLES';scene.cycles.samples=24;scene.cycles.use_denoising=True
    scene.render.resolution_x=640;scene.render.resolution_y=720;scene.render.resolution_percentage=100
    scene.world.color=(.15,.15,.15);scene.render.film_transparent=True
    scene.view_settings.view_transform='AgX';scene.view_settings.look='AgX - Medium High Contrast'
    scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGBA';scene.render.filepath=str(path)
    bpy.ops.render.render(write_still=True)

def build(exercise,images=True):
    folder=ROOT/'.build/motion-quality'/exercise;folder.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=str(ROOT/'.build/realistic-character/athlete-source.blend'),use_scripts=False)
    rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
    if exercise=='squat':
        from quality_squat import pose
        pose_at=lambda t:pose(rig,t)
    else:
        from quality_grip import prepare_equipment
        from quality_upper import pose
        prepare_equipment(rig);pose_at=lambda t:pose(rig,exercise,t)
    scene=bpy.context.scene;scene.render.fps=30;scene.frame_start=0;scene.frame_end=180
    rig.animation_data_clear();previous={}
    for f in range(181):
        scene.frame_set(f);pose_at(f/30)
        for bone in rig.pose.bones:
            bone.rotation_mode='QUATERNION'
            if bone.name in previous and previous[bone.name].dot(bone.rotation_quaternion)<0:bone.rotation_quaternion.negate()
            previous[bone.name]=bone.rotation_quaternion.copy()
            for channel in ('location','rotation_quaternion','scale'):bone.keyframe_insert(channel)
    action=rig.animation_data.action;action.name='Exercise'
    for layer in action.layers:
        for strip in layer.strips:
            for slot in action.slots:
                for fc in strip.channelbag(slot).fcurves:
                    for point in fc.keyframe_points:point.interpolation='LINEAR'
    scene.frame_set(0)
    bpy.ops.object.select_all(action='DESELECT');rig.select_set(True)
    for ob in scene.objects:
        if ob.type=='MESH':ob.select_set(True)
    bpy.context.view_layer.objects.active=rig
    bpy.ops.export_scene.gltf(filepath=str(folder/'base.glb'),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='ACTIVE_ACTIONS',export_force_sampling=True,export_optimize_animation_size=False,export_nla_strips_merged_animation_name='Exercise',export_frame_range=True,export_yup=True,export_morph=False)
    finalize_glb(folder/'base.glb')
    bpy.ops.wm.save_as_mainfile(filepath=str(folder/'source.blend'))
    if images:
        for label,frame in [('start',0),('middle',53),('peak',97)]:
            scene.frame_set(frame)
            for view in ('front','side','back'):render(folder/f'{label}-{view}.png',view)
    print('QUALITY_SAMPLE_READY',exercise,flush=True)

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--exercise',required=True,choices=['squat','curl','shoulder_press']);parser.add_argument('--no-render',action='store_true')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:]);build(args.exercise,not args.no_render)
