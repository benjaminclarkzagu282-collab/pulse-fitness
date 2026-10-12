"""Compare delivered assets against corrected baselines, including all bindings."""
import hashlib
import itertools
import json
import math
import struct
from pathlib import Path
from finalize_character_assets import read

ROOT=Path(__file__).resolve().parents[1]


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
        times=values(doc,blob,sampler['input'])
        assert abs(times[0][0])<1e-6 and abs(times[-1][0]-6)<1e-6
        result[key]=(sampler.get('interpolation','LINEAR'),times,values(doc,blob,sampler['output']))
    return result


def validate_overlay_binding(doc,blob,region):
    nodes={n.get('name'):n for n in doc['nodes']}
    node=nodes['PULSE region '+region]
    source=nodes['Boxers' if region=='glutes' else 'Man']
    assert 'skin' in node and node['skin']==source['skin'],(region,'overlay detached from source skin')
    for transform in ('translation','rotation','scale','matrix'):
        assert node.get(transform)==source.get(transform),(region,'different source transform')
    skin=doc['skins'][node['skin']]
    attrs=doc['meshes'][node['mesh']]['primitives'][0]['attributes']
    joints=values(doc,blob,attrs['JOINTS_0']);weights=values(doc,blob,attrs['WEIGHTS_0'])
    assert all(0<=j<len(skin['joints']) for row in joints for j in row),(region,'invalid joint index')
    # Match underlying source vertices in bind pose, accounting for the 0.8 mm
    # normal offset. Seam duplicates can occur; at least one must have the exact
    # same retained skin weights. A valid-but-wrong joint must not pass.
    scale=20000
    def cell(position):return tuple(round(c*scale) for c in position)
    def weight_map(js,ws):
        return {j:sum(w for k,w in zip(js,ws) if k==j) for j in set(js) if sum(w for k,w in zip(js,ws) if k==j)>1e-6}
    candidates={}
    for primitive in doc['meshes'][source['mesh']]['primitives']:
        a=primitive['attributes']
        for position,js,ws in zip(values(doc,blob,a['POSITION']),values(doc,blob,a['JOINTS_0']),values(doc,blob,a['WEIGHTS_0'])):
            candidates.setdefault(cell(position),[]).append((position,weight_map(js,ws)))
    for position,normal,js,ws in zip(values(doc,blob,attrs['POSITION']),values(doc,blob,attrs['NORMAL']),joints,weights):
        underlying=tuple(p-.0008*n for p,n in zip(position,normal));origin=cell(underlying)
        actual=weight_map(js,ws);matched=False
        for delta in itertools.product((-1,0,1),repeat=3):
            for point,expected in candidates.get(tuple(a+b for a,b in zip(origin,delta)),[]):
                if max(abs(a-b) for a,b in zip(point,underlying))<.00006 and all(abs(actual.get(j,0)-expected.get(j,0))<.002 for j in set(actual)|set(expected)):
                    matched=True;break
            if matched:break
        assert matched,(region,'source vertex/weight mismatch',underlying)


def verify(key,expected_regions):
    old,ob=read(ROOT/f'.build/motion-library/base/{key}.glb')
    path=ROOT/f'assets/models/athlete_{key}.glb';new,nb=read(path)
    assert motion(old,ob)==motion(new,nb),key+' motion changed by overlay authoring'
    new_nodes={n.get('name'):n for n in new['nodes']}
    for node in old['nodes']:
        other=new_nodes[node.get('name')]
        for attr in ('translation','rotation','scale','matrix'):
            assert node.get(attr)==other.get(attr),(key,node.get('name'),attr)
    assert len(old.get('skins',[]))==len(new.get('skins',[]))
    for a,b in zip(old.get('skins',[]),new.get('skins',[])):
        assert [old['nodes'][i]['name'] for i in a['joints']]==[new['nodes'][i]['name'] for i in b['joints']]
        assert values(old,ob,a['inverseBindMatrices'])==values(new,nb,b['inverseBindMatrices'])
    meshes={m['name']:m for m in new['meshes']}
    for original in old['meshes']:
        other=meshes[original['name']]
        assert len(original['primitives'])==len(other['primitives'])
        for a,b in zip(original['primitives'],other['primitives']):
            for attr,index in a['attributes'].items():
                assert values(old,ob,index)==values(new,nb,b['attributes'][attr]),(key,original['name'],attr)
            assert values(old,ob,a['indices'])==values(new,nb,b['indices'])
    region_report={}
    found={m['name'].removeprefix('PULSE Muscle ') for m in new['materials'] if m['name'].startswith('PULSE Muscle ')}
    assert found==set(expected_regions),(key,found,expected_regions)
    for region in expected_regions:
        validate_overlay_binding(new,nb,region)
        mesh=meshes['Muscle region '+region];assert len(mesh['primitives'])==1
        primitive=mesh['primitives'][0];attrs=primitive['attributes']
        mat=new['materials'][primitive['material']]
        assert mat['name']=='PULSE Muscle '+region and mat['alphaMode']=='BLEND'
        assert mat['pbrMetallicRoughness']['baseColorFactor'][3]==0
        colors=values(new,nb,attrs['COLOR_0'])
        assert min(c[3] for c in colors)==0 and max(c[3] for c in colors)>.6,(key,region,'mask range')
        assert any(.1<c[3]<.6 for c in colors),(key,region,'no feathering')
        assert all(abs(sum(w)-1)<.002 for w in values(new,nb,attrs['WEIGHTS_0']))
        region_report[region]={'vertices':len(colors),'triangles':len(values(new,nb,primitive['indices']))//3}
    return {'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'bytes':path.stat().st_size,
            'motion_and_original_skin_unchanged':True,'regions':region_report}


def main():
    catalog=json.loads((ROOT/'assets/muscles/catalog.json').read_text())
    result={key:verify(key,[r['id'] for r in exercise['regions']]) for key,exercise in catalog['exercises'].items()}
    output=ROOT/'docs/reports/all-exercise-muscles-verification.json'
    output.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({k:{'bytes':v['bytes'],'regions':list(v['regions']),'preserved':True} for k,v in result.items()},indent=2))


if __name__=='__main__':main()
