"""Ensure review packaging preserves tested skin, morphs and all motion tracks."""
import json,struct,hashlib,math
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

def read(path):
    data=path.read_bytes();n=struct.unpack_from('<I',data,12)[0]
    assert struct.unpack_from('<III',data)==(0x46546c67,2,len(data))
    return json.loads(data[20:20+n]),data[28+n:]

def accessor(doc,blob,i):
    a=doc['accessors'][i];n={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']]
    def rows(view_id,offset,count,ctype,width):
        fmt,size={5121:('B',1),5123:('H',2),5125:('I',4),5126:('f',4)}[ctype];v=doc['bufferViews'][view_id]
        start=v.get('byteOffset',0)+offset;stride=v.get('byteStride',width*size)
        return [struct.unpack_from('<'+fmt*width,blob,start+j*stride) for j in range(count)]
    value=rows(a['bufferView'],a.get('byteOffset',0),a['count'],a['componentType'],n) if 'bufferView' in a else [(0,)*n]*a['count']
    if 'sparse' in a:
        s=a['sparse'];index=s['indices'];v=s['values']
        indices=rows(index['bufferView'],index.get('byteOffset',0),s['count'],index['componentType'],1)
        sparse=rows(v['bufferView'],v.get('byteOffset',0),s['count'],a['componentType'],n)
        for (j,),row in zip(indices,sparse):value[j]=row
    assert all(math.isfinite(x) for row in value for x in row)
    return value

def motion(doc,blob):
    assert len(doc['animations'])==1 and doc['animations'][0]['name']=='Exercise'
    result={};a=doc['animations'][0]
    for c in a['channels']:
        s=a['samplers'][c['sampler']];times=accessor(doc,blob,s['input']);assert times[0]==(0.,) and times[-1]==(6.,)
        result[(doc['nodes'][c['target']['node']]['name'],c['target']['path'])]=(s.get('interpolation'),times,accessor(doc,blob,s['output']))
    return result

def verify(ex):
    base,bb=read(ROOT/f'.build/joint-volume/{ex}/base.glb');path=ROOT/f'web/review/quality-v2/{ex}.glb';doc,blob=read(path)
    bm=motion(base,bb);dm=motion(doc,blob)
    for key,v in bm.items():assert dm[key]==v,(ex,key,'motion changed during packaging')
    for a,b in zip(base['skins'],doc['skins']):
        assert [base['nodes'][i]['name'] for i in a['joints']]==[doc['nodes'][i]['name'] for i in b['joints']]
        assert accessor(base,bb,a['inverseBindMatrices'])==accessor(doc,blob,b['inverseBindMatrices'])
    meshes={m['name']:m for m in doc['meshes']}
    for old in base['meshes']:
        new=meshes[old['name']];assert len(old['primitives'])==len(new['primitives'])
        for a,b in zip(old['primitives'],new['primitives']):
            assert accessor(base,bb,a['indices'])==accessor(doc,blob,b['indices'])
            for name,i in a['attributes'].items():assert accessor(base,bb,i)==accessor(doc,blob,b['attributes'][name]),(ex,old['name'],name)
            assert len(a.get('targets',[]))==len(b.get('targets',[]))
            for x,y in zip(a.get('targets',[]),b.get('targets',[])):
                for name,i in x.items():assert accessor(base,bb,i)==accessor(doc,blob,y[name]),(ex,old['name'],'morph',name)
    assert path.read_bytes()==(ROOT/f'build/web/review/quality-v2/{ex}.glb').read_bytes()
    return {'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'bytes':path.stat().st_size,'motion_skin_morphs_preserved':True,'exported_weight_tracks':sum(k[1]=='weights' for k in dm),'seconds':6}

if __name__=='__main__':
    report={ex:verify(ex) for ex in ('curl','shoulder_press')}
    (ROOT/'docs/reports/joint-volume-delivery.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
