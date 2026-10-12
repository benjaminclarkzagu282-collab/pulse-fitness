"""Check the actual delivered GLB's animated overlays against its posed skin."""
import argparse,json,sys,hashlib
from pathlib import Path
import bpy
import numpy as np
from mathutils.kdtree import KDTree
sys.path.insert(0,str(Path(__file__).resolve().parent))
from character_mesh import body_mesh

def main():
    p=argparse.ArgumentParser();p.add_argument('--glb',required=True);p.add_argument('--output',required=True)
    args=p.parse_args(sys.argv[sys.argv.index('--')+1:])
    bpy.ops.wm.read_factory_settings(use_empty=True);scene=bpy.context.scene;scene.render.fps=30
    bpy.ops.import_scene.gltf(filepath=args.glb);body=body_mesh()
    assert body.data.shape_keys,'Body corrective animation missing'
    tree=KDTree(len(body.data.vertices))
    for v in body.data.vertices:tree.insert(v.co,v.index)
    tree.balance();regions=[]
    for ob in scene.objects:
        if ob.type!='MESH' or not ob.data.name.startswith('Muscle region '):continue
        assert ob.data.shape_keys,'Overlay corrective animation missing: '+ob.name
        mapping=[]
        for v in ob.data.vertices:
            _,i,d=tree.find(v.co)
            assert .0006<d<.0009,(ob.name,'invalid bind offset',d)
            mapping.append(i)
        regions.append((ob,np.array(mapping)))
    assert regions,'No muscle overlays'
    report={'asset':args.glb,'sha256':hashlib.sha256(Path(args.glb).read_bytes()).hexdigest(),'samples':181,'regions':{ob.data.name:{'max_surface_offset_m':0,'max_weight_difference':0} for ob,_ in regions}}
    for f in range(181):
        scene.frame_set(f);deps=bpy.context.evaluated_depsgraph_get()
        skin=np.array([tuple(body.matrix_world@v.co) for v in body.evaluated_get(deps).data.vertices])
        weights=np.array([k.value for k in body.data.shape_keys.key_blocks[1:]])
        for ob,mapping in regions:
            points=np.array([tuple(ob.matrix_world@v.co) for v in ob.evaluated_get(deps).data.vertices])
            error=float(np.linalg.norm(points-skin[mapping],axis=1).max())
            diff=float(np.max(np.abs(weights-np.array([k.value for k in ob.data.shape_keys.key_blocks[1:]]))))
            result=report['regions'][ob.data.name];result['max_surface_offset_m']=max(result['max_surface_offset_m'],error);result['max_weight_difference']=max(result['max_weight_difference'],diff)
            assert error<.001,(ob.name,f,'overlay detached',error)
            assert diff<.00001,(ob.name,f,'overlay pose weights differ',diff)
    Path(args.output).write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report),flush=True)

if __name__=='__main__':main()
