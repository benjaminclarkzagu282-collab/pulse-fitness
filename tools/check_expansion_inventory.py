"""Acceptance inventory for the approved 8 -> 24 exercise expansion."""
import hashlib
import json
from pathlib import Path
from verify_library_muscles import read, motion, values

ROOT=Path(__file__).resolve().parents[1]
EXPECTED={
    'squat','pushup','lunge','bridge','plank','row','jumping_jack','curl',
    'kneeling_pushup','incline_pushup','floor_press','shoulder_press',
    'lateral_raise','single_arm_row','reverse_fly','romanian_deadlift',
    'sumo_squat','split_squat','lateral_lunge','calf_raise',
    'dead_bug','bird_dog','side_plank','step_jack',
}


def main():
    catalog=json.loads((ROOT/'assets/muscles/catalog.json').read_text())['exercises']
    assert set(catalog)==EXPECTED, f'Catalog mismatch: missing {EXPECTED-set(catalog)}, extra {set(catalog)-EXPECTED}'
    originals=json.loads((ROOT/'docs/reports/expanded-24-original-assets.json').read_text())
    fingerprints={};assets=[]
    for key in catalog:
        model=ROOT/f'assets/models/athlete_{key}.glb'
        thumb=ROOT/f'assets/images/athlete_{key}.png'
        assert model.is_file(),f'{key}: missing model'
        assert thumb.is_file(),f'{key}: missing thumbnail'
        assert thumb.read_bytes().startswith(b'\x89PNG\r\n\x1a\n'),f'{key}: invalid PNG'
        sha=hashlib.sha256(model.read_bytes()).hexdigest()
        if model.name in originals:
            assert sha==originals[model.name],f'{key}: original approved model changed'
        doc,blob=read(model)
        tracks=motion(doc,blob)
        # Names and file bytes are insufficient: compare actual node transforms
        # and complete keyframe samples to reject relabelled duplicate actions.
        clip=repr(sorted(tracks.items())).encode()
        motion_sha=hashlib.sha256(clip).hexdigest()
        assert motion_sha not in fingerprints,f'{key}: duplicate movement of {fingerprints.get(motion_sha)}'
        fingerprints[motion_sha]=key
        names=[m.get('name','') for m in doc['materials']]
        for region in catalog[key]['regions']:
            assert 'PULSE Muscle '+region['id'] in names,f'{key}: missing region {region["id"]}'
            if region.get('side'):
                node=next(n for n in doc['nodes'] if n.get('name')=='PULSE region '+region['id'])
                attrs=doc['meshes'][node['mesh']]['primitives'][0]['attributes']
                positions=values(doc,blob,attrs['POSITION']);colors=values(doc,blob,attrs['COLOR_0'])
                active=[p[0] for p,c in zip(positions,colors) if c[3]>.05]
                assert active,f'{key}: empty unilateral region'
                assert max(active)<.012 if region['side']=='right' else min(active)>-.012, f'{key}: region on wrong side'
        if key=='incline_pushup':
            assert any('support' in n.get('name','').lower() or 'platform' in n.get('name','').lower() for n in doc['nodes']), 'Incline support platform missing'
        assets.append(dict(id=key,name=catalog[key]['name'],sha256=sha,bytes=model.stat().st_size,motion_sha256=motion_sha))
    report=dict(count=len(assets),original_eight_preserved=True,unique_movements=len(fingerprints),assets=assets)
    (ROOT/'docs/reports/expanded-24-inventory.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
    print(json.dumps({k:v for k,v in report.items() if k!='assets'},indent=2))


if __name__=='__main__':main()
