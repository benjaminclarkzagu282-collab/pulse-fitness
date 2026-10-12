"""Check actual reimported animated hand and body surfaces against equipment."""
import argparse,json,sys,hashlib
from pathlib import Path
import bpy
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from check_quality_grip import evaluate_grip,evaluate_body_clearance

def main():
    p=argparse.ArgumentParser();p.add_argument('--glb',required=True);p.add_argument('--output',required=True);a=p.parse_args(sys.argv[sys.argv.index('--')+1:])
    bpy.ops.wm.read_factory_settings(use_empty=True);scene=bpy.context.scene;scene.render.fps=30
    bpy.ops.import_scene.gltf(filepath=a.glb);rig=next(o for o in scene.objects if o.type=='ARMATURE')
    report={'asset':a.glb,'sha256':hashlib.sha256(Path(a.glb).read_bytes()).hexdigest(),'samples':361,'hand_min_clearance_m':1e9,'plate_min_clearance_m':1e9,'body_min_clearance_m':1e9,'max_finger_contact_gap_m':0,'failures':[]}
    for i in range(361):
        frame=i/2;scene.frame_set(int(frame),subframe=frame%1)
        for side in ('l','r'):
            hand=evaluate_grip(rig,side,exact=True);body=evaluate_body_clearance(rig,side,exact=True)
            report['hand_min_clearance_m']=min(report['hand_min_clearance_m'],hand['handle_min_clearance_m'])
            report['plate_min_clearance_m']=min(report['plate_min_clearance_m'],hand['plate_min_clearance_m'])
            report['body_min_clearance_m']=min(report['body_min_clearance_m'],body['min_clearance_m'])
            report['max_finger_contact_gap_m']=max(report['max_finger_contact_gap_m'],max(v for k,v in hand['contact_min_m'].items() if k!='hand'))
            if not hand['pass'] or not body['pass']:report['failures'].append({'frame':frame,'side':side,'hand':hand,'body':body})
        if i%60==0:print('CHECKED',frame,flush=True)
    Path(a.output).write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report),flush=True)
    assert not report['failures'],f"{len(report['failures'])} failing samples"

if __name__=='__main__':main()
