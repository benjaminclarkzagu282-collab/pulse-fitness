"""Read-only environment report; never turns local tests into device acceptance."""
import json
import shutil
import subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def run(args):
    try:
        p=subprocess.run(args,capture_output=True,text=True,timeout=30)
        return {'exit_code':p.returncode,'output':(p.stdout+p.stderr).strip()[:4000]}
    except (OSError,subprocess.TimeoutExpired) as e:
        return {'exit_code':None,'output':str(e)}
report={'xcode':run(['xcodebuild','-version']),
        'active_developer_directory':run(['xcode-select','-p']),
        'cocoapods_available':bool(shutil.which('pod')),
        'ios_project_present':(ROOT/'ios/Runner.xcworkspace').is_dir(),
        'device_acceptance_completed':False,
        'coach_review_completed':False}
report['native_build_ready']=report['xcode']['exit_code']==0
if report['native_build_ready']:
    report['devices']=run(['xcrun','devicectl','list','devices'])
path=ROOT/'docs/reports/ios-readiness.json'
path.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(report,ensure_ascii=False,indent=2))
