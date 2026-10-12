"""Build an isolated, reproducible three-action review delivery (not app assets)."""
import json, sys, shutil, copy
from pathlib import Path
import bpy

ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from build_squat_muscles import overlay
from build_library_muscles import region_mask,patch_glb,color_editable

IDS=('squat','curl','shoulder_press')

def targets(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps=30
    bpy.ops.import_scene.gltf(filepath=str(path))
    rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
    result=[]
    for f in range(181):
        bpy.context.scene.frame_set(f)
        wrist=rig.matrix_world@rig.pose.bones['hand_l'].head
        finger=rig.matrix_world@rig.pose.bones['middle_01_l'].head
        point=(wrist+finger)*.5
        result.append([round(point.x,6),round(point.z,6),round(-point.y,6)])
    return result

def main():
    output=ROOT/'web/review/quality';output.mkdir(parents=True,exist_ok=True)
    catalog=json.loads((ROOT/'assets/muscles/catalog.json').read_text())
    catalog['exercises']={key:catalog['exercises'][key] for key in IDS}
    for entry in catalog['exercises'].values():entry['legacyPhases']=copy.deepcopy(entry['phases'])
    catalog['exercises']['squat']['phases'][2]['end']=3.35
    catalog['exercises']['squat']['phases'][3]['start']=3.35
    for key in IDS:
        work=ROOT/'.build/motion-quality'/key
        bpy.ops.wm.open_mainfile(filepath=str(work/'source.blend'),use_scripts=False)
        rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
        regions=catalog['exercises'][key]['regions']
        for r in regions:
            overlay(bpy.data.objects['Boxers' if r['id']=='glutes' else 'Man'],rig,r['id'],lambda co,region,r=r:region_mask(co,region,r.get('side')))
        bpy.context.scene.frame_set(0)
        bpy.ops.object.select_all(action='DESELECT');rig.select_set(True)
        for ob in bpy.context.scene.objects:
            if ob.type=='MESH':ob.select_set(True)
        bpy.context.view_layer.objects.active=rig
        path=output/f'{key}.glb'
        bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='ACTIVE_ACTIONS',export_force_sampling=True,export_optimize_animation_size=False,export_nla_strips_merged_animation_name='Exercise',export_frame_range=True,export_yup=True,export_morph=False)
        patch_glb(path)
        color_editable(regions)
        bpy.ops.wm.save_as_mainfile(filepath=str(work/'with-muscles.blend'))
        catalog['exercises'][key]['handTargets']={'new':targets(path),'old':targets(ROOT/f'assets/models/athlete_{key}.glb')}
    (output/'catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,separators=(',',':'))+'\n')
    dest=ROOT/'build/web/review/quality';dest.mkdir(parents=True,exist_ok=True)
    for path in output.iterdir():
        if path.is_file():shutil.copy2(path,dest/path.name)
    print('QUALITY_DELIVERY_READY',flush=True)

if __name__=='__main__':main()
