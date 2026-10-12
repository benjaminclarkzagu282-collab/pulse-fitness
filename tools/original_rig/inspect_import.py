"""Blender intake: no automatic binding, no app writes, no anatomical claims.

blender --background --factory-startup --disable-autoexec --python-exit-code 1
  --python tools/original_rig/inspect_import.py -- --input export.fbx --output-dir NEW_DIR
Optional --stage saves the imported scene only after structural checks pass.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import bpy

HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
from contract import validate


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--input',required=True,type=Path)
    parser.add_argument('--output-dir',required=True,type=Path)
    parser.add_argument('--stage',action='store_true')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    source=args.input.resolve();output=args.output_dir.resolve()
    if not source.is_file():raise FileNotFoundError(source)
    if source.suffix.lower() not in ('.fbx','.blend','.glb'):
        raise ValueError('Use a native exported FBX, Blender scene, or GLB; MAX is not supported.')
    output.mkdir(parents=True,exist_ok=False)
    digest=hashlib.sha256(source.read_bytes()).hexdigest()
    expected=json.loads((HERE/'expected_source.json').read_text())
    if source.suffix.lower()=='.blend':
        bpy.ops.wm.open_mainfile(filepath=str(source),use_scripts=False)
    else:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        if source.suffix.lower()=='.fbx':
            bpy.ops.import_scene.fbx(filepath=str(source),automatic_bone_orientation=False,
                                     use_prepost_rot=True,ignore_leaf_bones=False)
        else:bpy.ops.import_scene.gltf(filepath=str(source))
    body=bpy.data.objects.get(expected['body_name'])
    modifiers=[m for m in body.modifiers if m.type=='ARMATURE' and m.object] if body else []
    rig=modifiers[0].object if len(modifiers)==1 else None
    names=[b.name for b in rig.data.bones] if rig else []
    rows=[]
    if body and body.type=='MESH':
        groups={g.index:g.name for g in body.vertex_groups}
        rows=[[[groups[g.group],float(g.weight)] for g in v.groups if g.weight!=0]
              for v in body.data.vertices]
    observation={'bone_names':names,'vertex_count':len(rows),
                 'armature_modifier_count':len(modifiers),'weights':rows}
    report=validate(observation,expected['expected_skin_bones'])
    report.update({'input':str(source),'input_sha256':digest,
        'bone_names':names,'body_found':bool(body),
        'shape_keys':[k.name for k in body.data.shape_keys.key_blocks]
            if body and body.type=='MESH' and body.data.shape_keys else [],
        'actions':[a.name for a in bpy.data.actions],
        'source_unchanged':hashlib.sha256(source.read_bytes()).hexdigest()==digest,
        'app_assets_modified':False,'stage_saved':False})
    # Keep raw incoming weights for later comparison with the MAX audit.
    (output/'imported-weights.json').write_text(json.dumps(observation,separators=(',',':')))
    if args.stage and report['structure_passed'] and report['source_unchanged']:
        bpy.ops.wm.save_as_mainfile(filepath=str(output/'original-rig-staging.blend'))
        report['stage_saved']=True
    (output/'inspection.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({k:v for k,v in report.items() if k!='bone_names'},ensure_ascii=False),flush=True)
    if not report['structure_passed']:raise RuntimeError('Original rig intake rejected; see inspection.json')

if __name__=='__main__':main()
