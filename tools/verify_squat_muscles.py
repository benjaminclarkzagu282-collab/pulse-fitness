"""Verify actual delivered regions, plus preservation of the original motion/skin."""
import hashlib
import json
import math
import struct
from pathlib import Path
from finalize_character_assets import read

ROOT=Path(__file__).resolve().parents[1]
old,old_blob=read(ROOT/'web/review/squat-v2.glb')
new,new_blob=read(ROOT/'web/review/squat-muscles.glb')


def values(doc,blob,index):
    acc=doc['accessors'][index];view=doc['bufferViews'][acc['bufferView']]
    components={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[acc['type']]
    fmt,size={5121:('B',1),5123:('H',2),5125:('I',4),5126:('f',4)}[acc['componentType']]
    stride=view.get('byteStride',components*size)
    start=view.get('byteOffset',0)+acc.get('byteOffset',0)
    rows=[struct.unpack_from('<'+fmt*components,blob,start+i*stride) for i in range(acc['count'])]
    assert all(math.isfinite(v) for row in rows for v in row)
    if acc.get('normalized'):
        maximum={5121:255,5123:65535}[acc['componentType']]
        rows=[tuple(v/maximum for v in row) for row in rows]
    return rows


def motion(doc,blob):
    assert len(doc['animations'])==1 and doc['animations'][0]['name']=='Exercise'
    clip=doc['animations'][0];result={}
    for channel in clip['channels']:
        sampler=clip['samplers'][channel['sampler']]
        key=(doc['nodes'][channel['target']['node']]['name'],channel['target']['path'])
        result[key]=(values(doc,blob,sampler['input']), values(doc,blob,sampler['output']))
    return result


assert motion(old,old_blob)==motion(new,new_blob), 'Muscle overlays changed the squat motion'
new_meshes={m['name']:m for m in new['meshes']}
for mesh in old['meshes']:
    other=new_meshes[mesh['name']]
    assert len(mesh['primitives'])==len(other['primitives'])
    for a,b in zip(mesh['primitives'],other['primitives']):
        for name,index in a['attributes'].items():
            assert values(old,old_blob,index)==values(new,new_blob,b['attributes'][name]), (mesh['name'],name)
        assert values(old,old_blob,a['indices'])==values(new,new_blob,b['indices'])

regions={}
for key in ('quads','glutes','core'):
    mesh=new_meshes['Muscle region '+key]
    assert len(mesh['primitives'])==1
    primitive=mesh['primitives'][0]
    material=new['materials'][primitive['material']]
    assert material['name']=='PULSE Muscle '+key
    assert material['alphaMode']=='BLEND'
    assert material['pbrMetallicRoughness']['baseColorFactor'][3]==0
    attributes=primitive['attributes']
    colors=values(new,new_blob,attributes['COLOR_0'])
    assert min(c[3] for c in colors)==0 and max(c[3] for c in colors)>.9
    assert any(.1<c[3]<.9 for c in colors), 'Missing feathered edges'
    for weights in values(new,new_blob,attributes['WEIGHTS_0']): assert abs(sum(weights)-1)<.002
    regions[key]={'vertices':len(colors),'triangles':len(values(new,new_blob,primitive['indices']))//3}
report={'source':'squat-v2.glb','sha256':hashlib.sha256((ROOT/'web/review/squat-muscles.glb').read_bytes()).hexdigest(),
        'motion_unchanged':True,'original_mesh_attributes_unchanged':True,
        'regions':regions,'total_added_triangles':sum(r['triangles'] for r in regions.values()),
        'interpretation':'Preset surface regions, not force or EMG measurements.'}
(ROOT/'.build/squat-muscles/verification.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
