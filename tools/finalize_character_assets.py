"""Losslessly rebuild GLB buffers, compress opaque atlases, crop RGBA thumbnails.
Uses Pillow only for export optimization; does not generate character artwork.
"""
from pathlib import Path
import io,json,struct,math,hashlib,sys
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
IDS=['squat','pushup','lunge','bridge','plank','row','jumping_jack','curl']

def read(path):
 data=path.read_bytes();magic,version,total=struct.unpack_from('<III',data);assert(magic,version,total)==(0x46546c67,2,len(data))
 n=struct.unpack_from('<I',data,12)[0];return json.loads(data[20:20+n]),data[28+n:]

def optimize(path):
 doc,blob=read(path);replacements={}
 for im in doc['images']:
  idx=im['bufferView'];v=doc['bufferViews'][idx];raw=blob[v.get('byteOffset',0):v.get('byteOffset',0)+v['byteLength']]
  image=Image.open(io.BytesIO(raw));name=im.get('name','')
  limit=256 if any(n in name for n in ['eye','brow','lash']) else 1024
  image.thumbnail((limit,limit),Image.Resampling.LANCZOS)
  opaque=any(n in name for n in ['lightskinned','brown_eye','shoes05']);out=io.BytesIO()
  if opaque:image.convert('RGB').save(out,format='JPEG',quality=88,optimize=True);im['mimeType']='image/jpeg'
  else:image.save(out,format='PNG',optimize=True);im['mimeType']='image/png'
  replacements[idx]=out.getvalue()
 chunks=[];offset=0
 for i,v in enumerate(doc['bufferViews']):
  data=replacements.get(i,blob[v.get('byteOffset',0):v.get('byteOffset',0)+v['byteLength']]);v['byteOffset']=offset;v['byteLength']=len(data)
  pad=b'\0'*((-len(data))%4);chunks.extend([data,pad]);offset+=len(data)+len(pad)
 binary=b''.join(chunks);doc['buffers'][0]['byteLength']=len(binary)
 j=json.dumps(doc,separators=(',',':')).encode();j+=b' '*((-len(j))%4)
 path.write_bytes(struct.pack('<III',0x46546c67,2,28+len(j)+len(binary))+struct.pack('<II',len(j),0x4e4f534a)+j+struct.pack('<II',len(binary),0x004e4942)+binary)

def crop(path,avatar=False):
 im=Image.open(path).convert('RGBA');box=im.getbbox();assert box,'Empty image '+str(path)
 im=im.crop(box)
 if avatar:
  # Existing portrait includes shoulders. Crop to a square with face centred.
  side=min(im.size);im=im.crop(((im.width-side)//2,0,(im.width+side)//2,side))
  im=im.resize((384,384),Image.Resampling.LANCZOS)
 else:
  im.thumbnail((660,740) if path.stem.endswith('hero') else (490,490),Image.Resampling.LANCZOS)
  pad=8;canvas=Image.new('RGBA',(im.width+pad*2,im.height+pad*2));canvas.alpha_composite(im,(pad,pad));im=canvas
 im.save(path,optimize=True)

def validate(path, texture_limit=1024, duration=4):
 d,b=read(path);assert len(d.get('skins',[]))==1;assert len(d.get('animations',[]))==1
 assert all('uri' not in x for x in d.get('buffers',[]));assert not d.get('cameras');assert all('KHR_lights_punctual' not in n.get('extensions',{}) for n in d['nodes'])
 types={5120:('b',1),5121:('B',1),5122:('h',2),5123:('H',2),5125:('I',4),5126:('f',4)};count={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}
 def acc(i):
  a=d['accessors'][i];v=d['bufferViews'][a['bufferView']];code,size=types[a['componentType']];n=count[a['type']];start=v.get('byteOffset',0)+a.get('byteOffset',0);stride=v.get('byteStride',n*size)
  vals=[struct.unpack_from('<'+code*n,b,start+k*stride) for k in range(a['count'])];assert all(math.isfinite(x) for row in vals for x in row);return vals
 for i in range(len(d['accessors'])):acc(i)
 clip=d['animations'][0];assert clip['name']=='Exercise';moving=0
 for c in clip['channels']:
  s=clip['samplers'][c['sampler']];ts=acc(s['input']);vs=acc(s['output']);assert len(ts)==len(vs);assert abs(ts[-1][0]-ts[0][0]-duration)<.0001
  assert all(ts[i+1][0]>ts[i][0] for i in range(len(ts)-1))
  error=max(abs(x-y) for x,y in zip(vs[0],vs[-1]));error=min(error,max(abs(x+y) for x,y in zip(vs[0],vs[-1]))) if c['target']['path']=='rotation' else error
  assert error<.0001,(path,c['target'],error)
  moving+=any(abs(x-y)>.00001 for row in vs for x,y in zip(row,vs[0]))
 assert moving>0
 for mesh in d['meshes']:
  for pr in mesh['primitives']:
   assert 'JOINTS_0' in pr['attributes'] and 'WEIGHTS_0' in pr['attributes']
   for w in acc(pr['attributes']['WEIGHTS_0']):assert abs(sum(w)-1)<.002
 images=[]
 for im in d['images']:
  v=d['bufferViews'][im['bufferView']];i=Image.open(io.BytesIO(b[v['byteOffset']:v['byteOffset']+v['byteLength']]));assert max(i.size)<=texture_limit;images.append({'name':im['name'],'size':list(i.size),'bytes':v['byteLength'],'mime':im['mimeType']})
 assert all(m.get('alphaMode') in ['OPAQUE','MASK'] for m in d['materials'])
 return {'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'meshes':len(d['meshes']),'joints':len(d['skins'][0]['joints']),'vertices':sum(d['accessors'][p['attributes']['POSITION']]['count'] for m in d['meshes'] for p in m['primitives']),'triangles':sum(d['accessors'][p['indices']]['count']//3 for m in d['meshes'] for p in m['primitives']),'clip':'Exercise','seconds':duration,'channels':len(clip['channels']),'moving_channels':moving,'closed_loop':True,'normalized_weights':True,'finite_accessors':len(d['accessors']),'images':images}

if __name__=='__main__':
 report=json.loads((ROOT/'assets/models/validation.json').read_text()) if '--squat-only' in sys.argv else {}
 for e in (['squat'] if '--squat-only' in sys.argv else IDS):
  p=ROOT/f'assets/models/athlete_{e}.glb';optimize(p);report[e]=validate(p);crop(ROOT/f'assets/images/athlete_{e}.png')
 for n in ['hero','avatar']:crop(ROOT/f'assets/images/athlete_{n}.png',n=='avatar')
 (ROOT/'assets/models/validation.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({k:{'bytes':v['bytes'],'vertices':v['vertices'],'triangles':v['triangles'],'joints':v['joints'],'loop':v['closed_loop']} for k,v in report.items()},indent=2))
