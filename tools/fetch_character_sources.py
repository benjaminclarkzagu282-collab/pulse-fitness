"""Fetch pinned official character authoring inputs into ignored .build/character.
Run with Python3, curl and git. No account, paid API, or Blender add-on installation.
"""
import hashlib,subprocess,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];WORK=ROOT/'.build/character';WORK.mkdir(parents=True,exist_ok=True)
REV='3edf9df0551765be43563d047888cf7877eb89b4'
PACKS={
 'system':('makehuman_system_assets','b542127a8e25547c7c29c19f2d1d2adb9a664c80396ecd694095dbc8028a0107'),
 'shirts':('shirts01','a5a723b0e84a109bb190fcfeac7f1de4138d875da3e30fe5b3340eac9f38bcd3'),
 'pants':('pants01','e4e0ec60db34f279be291a83cfd7b342a7c5cf09bb7676682a5f39f4f6ac4ad9'),
}
repo=WORK/'mpfb2'
if not repo.exists():subprocess.run(['git','clone','https://github.com/makehumancommunity/mpfb2.git',str(repo)],check=True)
subprocess.run(['git','-C',str(repo),'checkout',REV],check=True)
for short,(pack,sha) in PACKS.items():
 path=WORK/(short+'.zip')
 if not path.exists() or hashlib.sha256(path.read_bytes()).hexdigest()!=sha:
  for host in ['files.makehumancommunity.org','files2.makehumancommunity.org']:
   result=subprocess.run(['curl','-L','--fail','--retry','3','--retry-all-errors','--connect-timeout','20',f'https://{host}/asset_packs/{pack}/{pack}_cc0.zip','-o',str(path)])
   if result.returncode==0 and hashlib.sha256(path.read_bytes()).hexdigest()==sha:break
 assert hashlib.sha256(path.read_bytes()).hexdigest()==sha,f'Checksum failed: {path}'
 with zipfile.ZipFile(path) as z:z.extractall(WORK/'assets')
print('Verified official inputs in',WORK)
