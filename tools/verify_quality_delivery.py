"""Prove packaging retained the tested motion, original skin and joint binding."""
import hashlib,json
from pathlib import Path
from finalize_character_assets import read
from verify_library_muscles import motion,values,validate_overlay_binding
ROOT=Path(__file__).resolve().parents[1]

def verify(key,regions):
    base,bb=read(ROOT/f'.build/motion-quality/{key}/base.glb')
    path=ROOT/f'web/review/quality/{key}.glb';doc,blob=read(path)
    assert motion(base,bb)==motion(doc,blob),(key,'animation changed')
    for a,b in zip(base['skins'],doc['skins']):
        assert [base['nodes'][i]['name'] for i in a['joints']]==[doc['nodes'][i]['name'] for i in b['joints']]
        assert values(base,bb,a['inverseBindMatrices'])==values(doc,blob,b['inverseBindMatrices'])
    meshes={m['name']:m for m in doc['meshes']}
    for old in base['meshes']:
        new=meshes[old['name']];assert len(old['primitives'])==len(new['primitives'])
        for a,b in zip(old['primitives'],new['primitives']):
            for attr,index in a['attributes'].items():assert values(base,bb,index)==values(doc,blob,b['attributes'][attr]),(key,old['name'],attr)
            assert values(base,bb,a['indices'])==values(doc,blob,b['indices'])
    for region in regions:validate_overlay_binding(doc,blob,region)
    assert (ROOT/f'build/web/review/quality/{key}.glb').read_bytes()==path.read_bytes()
    return {'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'bytes':path.stat().st_size,'motion_and_skin_preserved':True,'regions':regions}

if __name__=='__main__':
    catalog=json.loads((ROOT/'web/review/quality/catalog.json').read_text())
    reports={key:verify(key,[r['id'] for r in data['regions']]) for key,data in catalog['exercises'].items()}
    (ROOT/'docs/reports/quality-delivery-verification.json').write_text(json.dumps(reports,indent=2)+'\n')
    print(json.dumps(reports,indent=2))
