"""Portable joint deformation: distributed forearm roll + baked corrective shapes.

Dual-quaternion skinning is an authoring reference only. The delivered GLB uses
ordinary linear skinning and explicit animated morph targets; no custom shader.
"""
import math
import bpy
import numpy as np
from mathutils import Matrix,Vector
from animate_athlete import set_bone
from quality_upper import pose as pose_upper
from squat_sample import depth_at

SAMPLES=np.linspace(0.,1.,9)

def smooth(a,b,x):
    t=np.clip((x-a)/(b-a),0,1);return t*t*(3-2*t)

def prepare(rig):
    """Keep the original joints and add two coaxial roll controls per forearm."""
    bpy.context.view_layer.objects.active=rig
    bpy.ops.object.mode_set(mode='EDIT')
    for side in ('l','r'):
        source=rig.data.edit_bones['lowerarm_'+side]
        for suffix in ('mid','distal'):
            b=rig.data.edit_bones.new(f'forearm_roll_{suffix}_{side}')
            b.head=source.head;b.tail=source.tail;b.roll=source.roll
            b.parent=rig.data.edit_bones['upperarm_'+side];b.use_connect=False
    bpy.ops.object.mode_set(mode='OBJECT')
    body=bpy.data.objects['Man']
    # The source contains fixed split normals. They become a visible seam when
    # a pose corrective moves the shoulder surface; export geometric normals.
    bpy.context.view_layer.objects.active=body
    bpy.ops.mesh.customdata_custom_splitnormals_clear()
    # Replace irregular imported elbow bands with a monotone hinge transition.
    # Leave the wrist, hand, and all unrelated influences untouched.
    for side in ('l','r'):
        up=rig.data.bones['upperarm_'+side];lo=rig.data.bones['lowerarm_'+side]
        axis=((up.tail_local-up.head_local).normalized()+(lo.tail_local-lo.head_local).normalized()).normalized()
        ug=body.vertex_groups[up.name];lg=body.vertex_groups[lo.name]
        for v in body.data.vertices:
            offset=v.co-lo.head_local
            blend=float(1-smooth(.075,.13,offset.length))
            if blend<=0:continue
            weights={g.group:g.weight for g in v.groups}
            uw=weights.get(ug.index,0);lw=weights.get(lg.index,0);total=uw+lw
            if total<.5:continue
            fraction=float(smooth(-.045,.055,offset.dot(axis)))
            lower=lw*(1-blend)+total*fraction*blend
            ug.add([v.index],total-lower,'REPLACE');lg.add([v.index],lower,'REPLACE')
    for side in ('l','r'):
        rest=rig.data.bones['lowerarm_'+side];axis=(rest.tail_local-rest.head_local);length=axis.length;axis.normalize()
        original=body.vertex_groups['lowerarm_'+side]
        groups=[original]+[body.vertex_groups.new(name=f'forearm_roll_{s}_{side}') for s in ('mid','distal')]
        for v in body.data.vertices:
            weight=next((g.weight for g in v.groups if g.group==original.index),0)
            if weight<1e-8:continue
            u=(v.co-rest.head_local).dot(axis)/length
            # Proximal skin follows the hinge; all distal skin retains the old
            # wrist orientation. Thus the existing measured grip is unchanged.
            fraction=float(smooth(.10,.72,u))*2
            i=min(1,int(fraction));mix=fraction-i
            original.remove([v.index])
            for index,w in ((i,weight*(1-mix)),(i+1,weight*mix)):
                if w>1e-8:groups[index].add([v.index],w,'REPLACE')
    # Match the four-influence runtime contract before authoring correctives.
    for v in body.data.vertices:
        weights=sorted([(g.group,g.weight) for g in v.groups if g.weight>1e-8],key=lambda g:g[1],reverse=True)
        kept=weights[:4];total=sum(w for _,w in kept)
        for index,_ in weights[4:]:body.vertex_groups[index].remove([v.index])
        for index,w in kept:body.vertex_groups[index].add([v.index],w/total,'REPLACE')
    return body

def pose(rig,exercise,seconds):
    pose_upper(rig,exercise,seconds)
    for side in ('l','r'):
        lower=rig.pose.bones['lowerarm_'+side];upper=rig.pose.bones['upperarm_'+side];rest=rig.data.bones[lower.name]
        elbow=lower.head.copy();direction=lower.tail-lower.head
        end_q=(lower.matrix@rest.matrix_local.inverted()).to_quaternion()
        upper_q=(upper.matrix@rig.data.bones[upper.name].matrix_local.inverted()).to_quaternion()
        hinge=(upper_q@(rest.tail_local-rest.head_local)).rotation_difference(direction)@upper_q
        retained=[(b.name,b.matrix.copy()) for b in rig.pose.bones if b.name.endswith('_'+side) and b.name.startswith(('hand_','index_','middle_','ring_','pinky_','thumb_'))]
        set_bone(rig,lower.name,elbow,q=hinge)
        for suffix,fraction in [('mid',.5),('distal',1.)]:set_bone(rig,f'forearm_roll_{suffix}_{side}',elbow,q=hinge.slerp(end_q,fraction))
        # Updating the parent must not rotate the already calibrated hand again.
        for name,matrix in retained:rig.pose.bones[name].matrix=matrix;bpy.context.view_layer.update()

def coords(body):
    ev=body.evaluated_get(bpy.context.evaluated_depsgraph_get());mesh=ev.to_mesh()
    a=np.empty(len(mesh.vertices)*3);mesh.vertices.foreach_get('co',a);ev.to_mesh_clear()
    return a.reshape(-1,3)

def inverse_linear_skin(body,rig):
    names={g.index:g.name for g in body.vertex_groups};basis=body.matrix_world.inverted()@rig.matrix_world
    matrices={b.name:np.array((basis@rig.pose.bones[b.name].matrix@b.matrix_local.inverted()@basis.inverted()).to_3x3()) for b in rig.data.bones}
    linear=np.zeros((len(body.data.vertices),3,3))
    for v in body.data.vertices:
        for g in v.groups:
            if names[g.group] in matrices:linear[v.index]+=g.weight*matrices[names[g.group]]
    return np.linalg.inv(linear)

def time_for_depth(d):
    lo=.5;hi=3.
    for _ in range(32):
        mid=(lo+hi)/2
        if depth_at(mid)<d:lo=mid
        else:hi=mid
    return (lo+hi)/2

def relax_elbow(points,body,rig,basis):
    """Remove high-frequency skin folds in the flexed pose, with a Taubin pair.

    This is a local corrective sculpt, not a runtime smoothing modifier. The
    negative pass limits shrinkage and the feathered mask protects both ends.
    """
    weight=np.zeros(len(points))
    for side in ('l','r'):
        up=rig.pose.bones['upperarm_'+side];lo=rig.pose.bones['lowerarm_'+side]
        angle=(up.tail-up.head).angle(lo.tail-lo.head)
        el=np.array(rig.data.bones[lo.name].head_local)
        weight=np.maximum(weight,(1-smooth(.065,.14,np.linalg.norm(basis-el,axis=1)))*smooth(.6,1.7,angle))
    edges=np.array([e.vertices[:] for e in body.data.edges]);a=np.r_[edges[:,0],edges[:,1]];b=np.r_[edges[:,1],edges[:,0]]
    degree=np.bincount(a,minlength=len(points))[:,None]
    result=points.copy()
    for _ in range(10):
        for step in (.5,-.53):
            total=np.zeros_like(result);np.add.at(total,a,result[b])
            result+=step*weight[:,None]*(total/np.maximum(degree,1)-result)
    return result

def author_correctives(body,rig,exercise):
    """Inverse-skin local pose corrections so standard glTF can reproduce them."""
    arm=next(m for m in body.modifiers if m.type=='ARMATURE')
    basis=np.array([v.co[:] for v in body.data.vertices]);mask=np.zeros(len(basis))
    for side in ('l','r'):
        sh=np.array(rig.data.bones['upperarm_'+side].head_local);el=np.array(rig.data.bones['lowerarm_'+side].head_local)
        shoulder=1-smooth(.10,.22,np.linalg.norm(basis-sh,axis=1))
        # Keep the lower torso outside shoulder authoring, including vertices
        # with small inherited upper-arm influences below the armpit.
        shoulder*=smooth(sh[2]-.18,sh[2]-.12,basis[:,2])
        elbow=1-smooth(.07,.125,np.linalg.norm(basis-el,axis=1))
        mask=np.maximum(mask,np.maximum(shoulder,elbow))
        rest=rig.data.bones['lowerarm_'+side];a=np.array(rest.head_local);v=np.array(rest.tail_local)-a
        u=(basis-a)@v/(v@v)
        # Protect all skin close to the grip; only mask this anatomical side.
        mask[(basis[:,0]*(1 if side=='l' else -1)>0)&(u>.72)&(np.linalg.norm(basis-a,axis=1)<.3)]=0
    deltas=[];statistics=[]
    for d in SAMPLES:
        pose(rig,exercise,time_for_depth(float(d)))
        arm.use_deform_preserve_volume=False;bpy.context.view_layer.update();linear=coords(body)
        arm.use_deform_preserve_volume=True;bpy.context.view_layer.update();target=coords(body)
        arm.use_deform_preserve_volume=False;bpy.context.view_layer.update()
        target=linear+(target-linear)*mask[:,None]
        target=relax_elbow(target,body,rig,basis)
        difference=target-linear
        delta=np.einsum('nij,nj->ni',inverse_linear_skin(body,rig),difference)
        assert np.isfinite(delta).all()
        deltas.append(delta);statistics.append({'depth':float(d),'posed_correction_max_mm':float(np.linalg.norm(difference,axis=1).max()*1000),'source_delta_max_mm':float(np.linalg.norm(delta,axis=1).max()*1000)})
    body.shape_key_add(name='Basis')
    for i,delta in enumerate(deltas):
        key=body.shape_key_add(name=f'Joint volume {i:02d}');key.data.foreach_set('co',(basis+delta).ravel());key.value=0
    return statistics

def set_corrective_weights(body,depth,frame=None):
    f=float(np.clip(depth,0,1))*(len(SAMPLES)-1);a=min(len(SAMPLES)-2,int(f));mix=f-a
    for i,k in enumerate(body.data.shape_keys.key_blocks[1:]):
        k.value=(1-mix if i==a else mix if i==a+1 else 0)
        if frame is not None:k.keyframe_insert('value',frame=frame)

def linear_keys(action):
    for layer in action.layers:
        for strip in layer.strips:
            for slot in action.slots:
                bag=strip.channelbag(slot)
                if bag:
                    for fc in bag.fcurves:
                        for k in fc.keyframe_points:k.interpolation='LINEAR'
