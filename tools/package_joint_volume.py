"""Package the two corrected review clips, preserving the previous comparison."""
import json,sys,shutil
from pathlib import Path
import bpy
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from build_squat_muscles import overlay
from build_library_muscles import region_mask,patch_glb,color_editable
from joint_volume_normals import patch as patch_normals

def targets(path):
    bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.scene.render.fps=30
    bpy.ops.import_scene.gltf(filepath=str(path));rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
    result={k:[] for k in ('hand','elbow','shoulder')}
    for f in range(181):
        bpy.context.scene.frame_set(f)
        points={'hand':(rig.pose.bones['hand_l'].head+rig.pose.bones['middle_01_l'].head)*.5,
                'elbow':rig.pose.bones['lowerarm_l'].head,
                'shoulder':rig.pose.bones['upperarm_l'].head.lerp(rig.pose.bones['upperarm_l'].tail,.15)}
        for key,p in points.items():
            p=rig.matrix_world@p;result[key].append([round(p.x,6),round(p.z,6),round(-p.y,6)])
    return result

def main():
    output=ROOT/'web/review/quality-v2';output.mkdir(parents=True,exist_ok=True)
    catalog=json.loads((ROOT/'web/review/quality/catalog.json').read_text())
    for ex in ('curl','shoulder_press'):
        work=ROOT/'.build/joint-volume'/ex
        bpy.ops.wm.open_mainfile(filepath=str(work/'source.blend'),use_scripts=False)
        rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');regions=catalog['exercises'][ex]['regions']
        # Build surface regions in bind coordinates, with animated morphs copied.
        for region in regions:
            overlay(bpy.data.objects['Man'],rig,region['id'],lambda co,key,r=region:region_mask(co,key,r.get('side')))
        bpy.context.scene.frame_set(0)
        bpy.ops.object.select_all(action='DESELECT');rig.select_set(True)
        for ob in bpy.context.scene.objects:
            if ob.type=='MESH':ob.select_set(True)
        bpy.context.view_layer.objects.active=rig;path=output/f'{ex}.glb'
        bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='ACTIVE_ACTIONS',export_force_sampling=True,export_optimize_animation_size=False,export_nla_strips_merged_animation_name='Exercise',export_frame_range=True,export_yup=True,export_morph=True,export_morph_animation=True)
        patch_normals(path,work/'normals.npz');patch_glb(path)
        color_editable(regions);bpy.ops.wm.save_as_mainfile(filepath=str(work/'with-muscles.blend'))
        entry=catalog['exercises'][ex];entry['cameraTargets']={'new':targets(path),'old':targets(ROOT/f'web/review/quality/{ex}.glb')}
        entry['legacyPhases']=entry['phases']
    (output/'catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,separators=(',',':'))+'\n')
    dest=ROOT/'build/web/review/quality-v2';dest.mkdir(parents=True,exist_ok=True)
    for path in output.iterdir():
        if path.is_file():shutil.copy2(path,dest/path.name)
    print('JOINT_VOLUME_PACKAGED',flush=True)

if __name__=='__main__':main()
