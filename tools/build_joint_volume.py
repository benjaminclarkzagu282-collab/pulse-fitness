"""Build elbow/shoulder review candidates without replacing approved assets."""
import argparse,json,sys
from pathlib import Path
import bpy
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from joint_volume import prepare,pose,author_correctives,set_corrective_weights,linear_keys
from quality_grip import prepare_equipment
from squat_sample import depth_at
from animate_athlete import finalize_glb
from joint_volume_normals import bake as bake_normals,patch as patch_normals

def main():
    p=argparse.ArgumentParser();p.add_argument('--exercise',required=True,choices=['curl','shoulder_press']);a=p.parse_args(sys.argv[sys.argv.index('--')+1:])
    out=ROOT/'.build/joint-volume'/a.exercise;out.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=str(ROOT/'.build/realistic-character/athlete-source.blend'),use_scripts=False)
    rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');prepare_equipment(rig);body=prepare(rig)
    statistics=author_correctives(body,rig,a.exercise)
    bake_normals(body,rig,a.exercise,out/'normals.npz')
    scene=bpy.context.scene;scene.render.fps=30;scene.frame_start=0;scene.frame_end=180;rig.animation_data_clear();previous={}
    for f in range(181):
        scene.frame_set(f);pose(rig,a.exercise,f/30);set_corrective_weights(body,depth_at(f/30),f)
        for b in rig.pose.bones:
            b.rotation_mode='QUATERNION'
            if b.name in previous and previous[b.name].dot(b.rotation_quaternion)<0:b.rotation_quaternion.negate()
            previous[b.name]=b.rotation_quaternion.copy()
            for channel in ('location','rotation_quaternion','scale'):b.keyframe_insert(channel)
    for action in (rig.animation_data.action,body.data.shape_keys.animation_data.action):action.name='Exercise';linear_keys(action)
    scene.frame_set(0)
    bpy.ops.wm.save_as_mainfile(filepath=str(out/'source.blend'))
    bpy.ops.object.select_all(action='DESELECT');rig.select_set(True)
    for ob in scene.objects:
        if ob.type=='MESH':ob.select_set(True)
    bpy.context.view_layer.objects.active=rig
    bpy.ops.export_scene.gltf(filepath=str(out/'base.glb'),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='ACTIVE_ACTIONS',export_force_sampling=True,export_optimize_animation_size=False,export_nla_strips_merged_animation_name='Exercise',export_frame_range=True,export_yup=True,export_morph=True,export_morph_animation=True)
    patch_normals(out/'base.glb',out/'normals.npz')
    finalize_glb(out/'base.glb');(out/'authoring.json').write_text(json.dumps(statistics,indent=2)+'\n')
    print('JOINT_VOLUME_READY',a.exercise,flush=True)

if __name__=='__main__':main()
