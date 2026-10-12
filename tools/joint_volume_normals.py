"""Bake posed surface normals into glTF morphs for standard linear skinning.

Normals computed on inverse-skinned corrective meshes are not the normals of
the final posed surface. Inverse-transform the final geometric normal instead.
Blender's importer does not retain animated split normals; inspect in glTF too.
"""
import json,struct
import numpy as np
import bpy
from mathutils.kdtree import KDTree
from joint_volume import SAMPLES,pose,set_corrective_weights,time_for_depth,coords,inverse_linear_skin

def unit(v):
    return v/np.maximum(np.linalg.norm(v,axis=-1,keepdims=True),1e-12)

def surface_normals(points,triangles):
    p=points[triangles];normal=unit(np.cross(p[:,1]-p[:,0],p[:,2]-p[:,0]));result=np.zeros_like(points)
    for i in range(3):
        a=unit(p[:,(i+1)%3]-p[:,i]);b=unit(p[:,(i+2)%3]-p[:,i])
        angle=np.arccos(np.clip(np.sum(a*b,axis=1),-1,1))
        np.add.at(result,triangles[:,i],normal*angle[:,None])
    return unit(result)

def bake(body,rig,exercise,path):
    body.data.calc_loop_triangles();triangles=np.array([t.vertices[:] for t in body.data.loop_triangles])
    basis=np.array([v.co[:] for v in body.data.vertices]);normals=[]
    for d in SAMPLES:
        pose(rig,exercise,time_for_depth(float(d)));set_corrective_weights(body,d);bpy.context.view_layer.update()
        target=surface_normals(coords(body),triangles)
        normals.append(unit(np.einsum('nij,nj->ni',inverse_linear_skin(body,rig),target)))
    np.savez_compressed(path,basis=basis,normals=np.array(normals))

def patch(path,normal_file):
    data=path.read_bytes();n=struct.unpack_from('<I',data,12)[0];doc=json.loads(data[20:20+n]);blob=bytearray(data[28+n:])
    saved=np.load(normal_file)
    def yup(v):return v[..., [0,2,1]]*np.array([1,1,-1])
    basis=yup(saved['basis']);normals=yup(saved['normals']);tree=KDTree(len(basis))
    for i,p in enumerate(basis):tree.insert(p,i)
    tree.balance()
    def get(index):
        a=doc['accessors'][index];v=doc['bufferViews'][a['bufferView']]
        assert a['type']=='VEC3' and a['componentType']==5126 and not a.get('sparse')
        return np.ndarray((a['count'],3),dtype='<f4',buffer=blob,offset=v.get('byteOffset',0)+a.get('byteOffset',0),strides=(v.get('byteStride',12),4))
    for mesh in doc['meshes']:
        for pr in mesh['primitives']:
            if not pr.get('targets'):continue
            positions=get(pr['attributes']['POSITION']).copy();base=get(pr['attributes']['NORMAL']).copy()
            overlay=mesh['name'].startswith('Muscle region ')
            mapping=[]
            for p,norm in zip(positions,base):
                _,i,dist=tree.find(p-.0008*norm if overlay else p)
                assert dist<.00006,(mesh['name'],dist)
                mapping.append(i)
            for i,target in enumerate(pr['targets']):
                normal_data=np.asarray(normals[i,mapping]-base,dtype='<f4').tobytes()
                # Zero morphs may have no buffer view; sparse accessors also
                # cannot be overwritten as dense data. Write a dense accessor.
                offset=len(blob);blob.extend(normal_data)
                view=len(doc['bufferViews']);doc['bufferViews'].append({'buffer':0,'byteOffset':offset,'byteLength':len(normal_data),'target':34962})
                target['NORMAL']=len(doc['accessors']);doc['accessors'].append({'bufferView':view,'componentType':5126,'count':len(mapping),'type':'VEC3'})
    doc['buffers'][0]['byteLength']=len(blob)
    encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
    path.write_bytes(struct.pack('<III',0x46546c67,2,28+len(encoded)+len(blob))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+struct.pack('<II',len(blob),0x004e4942)+blob)
