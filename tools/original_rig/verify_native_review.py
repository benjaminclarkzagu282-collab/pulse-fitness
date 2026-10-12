"""Reimport the delivered GLB and compare its animation with editable native Skin.

Runs in Blender. Also checks actual hand surface triangles, not just joint
origins or screenshots. Passing is technical fidelity, not coaching approval.
"""
import argparse,json,sys
from pathlib import Path
import bpy,numpy as np
from mathutils import Matrix
from mathutils.kdtree import KDTree
HERE=Path(__file__).resolve().parent;sys.path.insert(0,str(HERE))
from native_upper import NativeUpper,GRIP_CENTER,HANDLE_RADIUS,HALF_HANDLE
from build_native_review import points,fingerprint

def surface_audit(solver):
    body=bpy.data.objects['Man'];xyz=points(body);body.data.calc_loop_triangles()
    triangles=np.array([t.vertices[:] for t in body.data.loop_triangles])
    out={}
    for side in ('L','R'):
        name='Man_'+side+'Hand';hand=solver.rig.matrix_world@solver.rig.pose.bones[name].matrix
        delta=hand.to_quaternion()@solver.reference[name].to_quaternion().inverted()
        frame=delta.to_matrix()@solver.palm(side)[1]
        local=(xyz-np.array(hand.translation))@np.array(frame.inverted()).T
        groups={g.index for g in body.vertex_groups if g.name.startswith(name)}
        mask=np.array([sum(g.weight for g in v.groups if g.group in groups)>.5 for v in body.data.vertices])
        samples=[local[mask]]
        tris=local[triangles[mask[triangles].any(axis=1)]]
        samples.extend([tris.mean(axis=1),(tris[:,0]+tris[:,1])*.5,
                        (tris[:,1]+tris[:,2])*.5,(tris[:,2]+tris[:,0])*.5])
        surface=np.concatenate(samples)
        radial=np.linalg.norm(surface[:,1:3]-np.array(GRIP_CENTER)[1:3],axis=1)
        handle=radial[np.abs(surface[:,0])<HALF_HANDLE]
        plate_depths=[]
        for x in [-.10375,.10375]:
            axial=.0225-np.abs(surface[:,0]-x)
            radial_plate=.06375-radial
            plate_depths.append(np.maximum(0,np.minimum(axial,radial_plate)))
        out[side]={'max_handle_penetration_m':float(max(0,HANDLE_RADIUS-handle.min())),
                   'samples_deeper_than_1mm':int((handle<HANDLE_RADIUS-.001).sum()),
                   'max_plate_penetration_m':float(max(p.max() for p in plate_depths))}
    return out

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--input-dir',required=True,type=Path)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:]);folder=args.input_dir.resolve()
    build=json.loads((folder/'build-report.json').read_text());report={'exercises':{},'passed':True,'coach_review_completed':False}
    times=[0,.5,1.2,1.8,2.4,3.2,4,4.5,5.2,5.99]
    for exercise in ('shoulder_press','curl'):
        bpy.ops.wm.open_mainfile(filepath=str(folder/(exercise+'-native-source.blend')),use_scripts=False)
        rig=bpy.data.objects['Armature'];solver=NativeUpper(rig)
        solver.reference={n:Matrix(m) for n,m in json.loads(rig['native_reference_world_json']).items()}
        entry={'native_bones':len(rig.data.bones),'weights_unchanged':fingerprint(bpy.data.objects['Man'])==build['source_skin_fingerprint'],
               'surfaces':{},'roundtrip_max_error_m':{}}
        expected={name:[] for name in ['Man','Native dumbbell L','Native dumbbell R']}
        for t in times:
            bpy.context.scene.frame_set(int(t*30),subframe=t*30-int(t*30))
            entry['surfaces'][str(t)]=surface_audit(solver)
            for name in expected:expected[name].append(points(bpy.data.objects[name]))
        bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.scene.render.fps=30
        bpy.ops.import_scene.gltf(filepath=str(folder/(exercise+'.glb')))
        bpy.context.scene.frame_set(0)
        objects={name:bpy.data.objects.get('Web '+name) for name in expected}
        if any(o is None for o in objects.values()):raise RuntimeError('Missing delivered mesh: '+str(objects))
        for name,obj in objects.items():
            tree=KDTree(len(expected[name][0]))
            for i,co in enumerate(expected[name][0]):tree.insert(co,i)
            tree.balance();mapping=[tree.find(co)[1] for co in points(obj)]
            maximum=0
            for t,truth in zip(times,expected[name]):
                bpy.context.scene.frame_set(int(t*30),subframe=t*30-int(t*30))
                maximum=max(maximum,float(np.linalg.norm(points(obj)-truth[mapping],axis=1).max()))
            entry['roundtrip_max_error_m'][name]=maximum
        entry['passed']=entry['weights_unchanged'] and entry['native_bones']==81 and max(entry['roundtrip_max_error_m'].values())<.0005
        entry['passed'] &= all(v['samples_deeper_than_1mm']==0 and v['max_plate_penetration_m']<.001 for pose in entry['surfaces'].values() for v in pose.values())
        report['exercises'][exercise]=entry;report['passed'] &= entry['passed']
    (folder/'verification.json').write_text(json.dumps(report,indent=2))
    print(json.dumps(report),flush=True)
    if not report['passed']:raise RuntimeError('Delivery verification failed; see verification.json')

if __name__=='__main__':main()
