"""Regression: exported joint correctives must exist and actually animate skin."""
import argparse,json,sys
from pathlib import Path
import bpy
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parent))
from character_mesh import body_mesh

def main():
    p=argparse.ArgumentParser();p.add_argument('--glb',required=True);p.add_argument('--output',required=True);a=p.parse_args(sys.argv[sys.argv.index('--')+1:])
    bpy.ops.wm.read_factory_settings(use_empty=True);scene=bpy.context.scene;scene.render.fps=30
    bpy.ops.import_scene.gltf(filepath=a.glb);body=body_mesh();keys=body.data.shape_keys
    report={'asset':a.glb,'errors':[],'sampled_effect_mm':[]}
    if not keys or len(keys.key_blocks)<2:report['errors'].append('export lost joint volume corrective shapes')
    else:
        all_weights=[]
        for frame in (0,24,53,77,97,119,151,180):
            scene.frame_set(frame);weights=[k.value for k in keys.key_blocks[1:]];all_weights.append(weights)
            deps=bpy.context.evaluated_depsgraph_get();on=np.array([v.co[:] for v in body.evaluated_get(deps).data.vertices])
            for k in keys.key_blocks[1:]:k.value=0
            bpy.context.view_layer.update();off=np.array([v.co[:] for v in body.evaluated_get(deps).data.vertices])
            report['sampled_effect_mm'].append(float(np.linalg.norm(on-off,axis=1).max()*1000))
        report['targets']=len(keys.key_blocks)-1
        if np.max(np.ptp(np.array(all_weights),axis=0))<.5:report['errors'].append('export lost pose-driven corrective animation')
        if max(report['sampled_effect_mm'])<2:report['errors'].append('corrective weights do not affect rendered skin')
        if abs(report['sampled_effect_mm'][0]-report['sampled_effect_mm'][-1])>.05:report['errors'].append('corrective cycle discontinuity')
    Path(a.output).write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report),flush=True)
    assert not report['errors'],report['errors']

if __name__=='__main__':main()
