"""Package only verified native-rig review samples, with correct glTF cameras."""
import argparse,json,math,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]

def viewer_point(world):
    # Blender authoring is Z-up; export_yup transforms to glTF Y-up.
    x,y,z=world
    return [x,z,-y]

def depth(seconds):
    def smooth(x):return x*x*x*(10+x*(-15+6*x))
    if seconds<.5:return 0
    if seconds<3:return smooth((seconds-.5)/2.5)
    if seconds<3.5:return 1
    if seconds<5.5:return 1-smooth((seconds-3.5)/2)
    return 0

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--input-dir',required=True,type=Path);args=parser.parse_args()
    folder=args.input_dir.resolve();report=json.loads((folder/'build-report.json').read_text())
    verified=json.loads((folder/'verification.json').read_text())
    if not verified['passed']:raise RuntimeError('The review sample failed its delivery checks')
    destination=ROOT/'web/review/native';destination.mkdir(parents=True,exist_ok=True)
    catalog=json.loads((ROOT/'web/review/quality-v2/catalog.json').read_text())
    catalog['exercises']={key:value for key,value in catalog['exercises'].items() if key in report['exercises']}
    for exercise,entry in catalog['exercises'].items():
        entry['legacyPhases']=entry['phases'];entry['cameraTargets']['old']=entry['cameraTargets']['new']
        source=report['exercises'][exercise];targets=source['targets'];steps=source['pose_steps']
        cameras={key:[] for key in ['hand','elbow','shoulder']}
        for f in range(181):
            index=depth(f/30)*steps;a=int(index);b=min(steps,a+1);fraction=index-a
            for key,field in [('hand','grip_center'),('elbow','elbow'),('shoulder','shoulder')]:
                world=[x+(y-x)*fraction for x,y in zip(targets[a]['L'][field],targets[b]['L'][field])]
                cameras[key].append(viewer_point(world))
        entry['cameraTargets']['new']=cameras;entry['nativeBones']=81;entry['model']='review/native/'+exercise+'.glb'
        shutil.copy2(folder/(exercise+'.glb'),destination/(exercise+'.glb'))
    catalog.update({'sourceBinding':'original_CAT_Skin','runtime':'baked_mesh_animation_from_all_original_influences','coachReviewed':False})
    (destination/'catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,separators=(',',':')))
    shutil.copy2(ROOT/'web/native-rig-review.html',ROOT/'build/web/native-rig-review.html')
    shutil.copytree(destination,ROOT/'build/web/review/native',dirs_exist_ok=True)
    print('Verified native review packaged for local preview.')

if __name__=='__main__':main()
