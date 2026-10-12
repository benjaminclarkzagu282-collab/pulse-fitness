"""Blender geometry/GLB evidence for quality_grip; never writes production assets."""
import argparse,json,math,sys
from pathlib import Path
import bpy
from mathutils import Vector,Matrix
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
import quality_grip as grip
from character_mesh import body_mesh
from animate_athlete import equipment,set_bone,finalize_glb
from motion_library import pose_exercise
OUT=ROOT/'.build/motion-quality/grip';V=Vector


def hand_vertices(body,side):
    names={g.index:g.name for g in body.vertex_groups}
    result={}
    for v in body.data.vertices:
        groups=[(names[g.group],g.weight) for g in v.groups if names[g.group].endswith('_'+side) and names[g.group].startswith(('hand_','index_','middle_','ring_','pinky_','thumb_'))]
        if sum(g[1] for g in groups)>.5:result[v.index]=max(groups,key=lambda g:g[1])[0].split('_')[0]
    return result


def cylinder_sdf(point,radius,half_depth):
    radial=math.hypot(point.y,point.z)-radius;axial=abs(point.x)-half_depth
    return math.hypot(max(radial,0),max(axial,0))+min(max(radial,axial),0)


_cache={}

def evaluate_grip(rig,side,legacy=False,exact=False):
    """Measure evaluated hand skin against evaluated full-sized equipment.

    This works after glTF reimport: equipment center/axis are recovered from
    its actual evaluated vertices, without trusting pre-export bone frames.
    exact=True additionally clips every hand triangle to each finite cylinder
    and tests its projected face/edges, detecting between-vertex intersections.
    The regular result uses every vertex and four triangle-interior samples.
    """
    import numpy as np
    body=body_mesh()
    deps=bpy.context.evaluated_depsgraph_get();ev=body.evaluated_get(deps);mesh=ev.to_mesh();mesh.calc_loop_triangles()
    ids=hand_vertices(body,side)
    coordinates=np.empty(len(mesh.vertices)*3);mesh.vertices.foreach_get('co',coordinates);coordinates=coordinates.reshape(-1,3)
    body_world=np.array(body.matrix_world);coordinates=coordinates@body_world[:3,:3].T+body_world[:3,3]
    equipment=bpy.data.objects['PULSE dumbbell '+side];eq=equipment.evaluated_get(deps);em=eq.to_mesh()
    pts=np.empty(len(em.vertices)*3);em.vertices.foreach_get('co',pts);pts=pts.reshape(-1,3);ew=np.array(equipment.matrix_world);pts=pts@ew[:3,:3].T+ew[:3,3];eq.to_mesh_clear()
    # glTF duplicates vertices at UV/material boundaries. Deduplicate before
    # PCA so seam multiplicity cannot bias the measured cylinder center/axis.
    pts=np.unique(np.round(pts,6),axis=0)
    center=pts.mean(axis=0);eigen,axes=np.linalg.eigh(np.cov((pts-center).T));axis=axes[:,-1]
    # An orthonormal cylinder basis; radial axes have no physical preference.
    aux=np.array((0.,0.,1.)) if abs(axis[2])<.9 else np.array((0.,1.,0.));radial=np.cross(axis,aux);radial/=np.linalg.norm(radial);other=np.cross(axis,radial);basis=np.array((axis,radial,other)).T
    coordinates=(coordinates-center)@basis
    selected=np.array(list(ids));tris=np.array([list(t.vertices) for t in mesh.loop_triangles if all(i in ids for i in t.vertices)],dtype=int);ev.to_mesh_clear()
    vs=coordinates[tris];samples=np.concatenate((coordinates[selected],vs.mean(axis=1),vs[:,0]*.6+vs[:,1]*.2+vs[:,2]*.2,vs[:,0]*.2+vs[:,1]*.6+vs[:,2]*.2,vs[:,0]*.2+vs[:,1]*.2+vs[:,2]*.6))
    labels=np.array([ids[i] for i in selected]+[ids[t[0]] for t in tris]*4)
    radius,half,offset,pr,pd=(.013,.075,.073,.052,.021) if legacy else (grip.HANDLE_RADIUS,grip.HANDLE_HALF_LENGTH,grip.PLATE_OFFSET,grip.PLATE_RADIUS,grip.PLATE_HALF_DEPTH)
    def sdf(points,rad,h):
        radial=np.linalg.norm(points[:,1:],axis=1)-rad;axial=np.abs(points[:,0])-h
        return np.hypot(np.maximum(radial,0),np.maximum(axial,0))+np.minimum(np.maximum(radial,axial),0)
    shaft=sdf(samples,radius,half);plates=np.minimum(sdf(samples-np.array((offset,0,0)),pr,pd),sdf(samples+np.array((offset,0,0)),pr,pd))
    contact={finger:float(shaft[(labels==finger)&(np.abs(samples[:,0])<half-.002)].min()) for finger in ('hand','index','middle','ring','pinky','thumb')}
    result={'side':side,'samples':len(samples),'handle_min_clearance_m':float(shaft.min()),'handle_penetrating_samples':int((shaft<-.0005).sum()),'plate_min_clearance_m':float(plates.min()),'plate_penetrating_samples':int((plates<-.0005).sum()),'contact_min_m':contact,'pass':bool(shaft.min()>=-.0005 and plates.min()>=-.0005 and all(-.0005<=contact[f]<=.0025 for f in ('index','middle','ring','pinky','thumb')))}
    if exact:
        def radial_min(polygons):
            p=polygons[:,:,1:];edge=np.roll(p,-1,axis=1)-p;denom=(edge*edge).sum(axis=2);t=np.clip(-(p*edge).sum(axis=2)/np.maximum(denom,1e-20),0,1);distance=np.linalg.norm(p+edge*t[:,:,None],axis=2).min(axis=1);cross=p[:,:,0]*np.roll(p[:,:,1],-1,axis=1)-p[:,:,1]*np.roll(p[:,:,0],-1,axis=1);inside=(cross>=0).all(axis=1)|(cross<=0).all(axis=1);distance[inside]=0;return distance
        def cylinders(rad,h,offset):
            faces=vs-np.array((offset,0,0));inside=(np.abs(faces[:,:,0])<=h).all(axis=1);outside=(faces[:,:,0].min(axis=1)>h)|(faces[:,:,0].max(axis=1)<-h);clearances=radial_min(faces[inside])-rad if inside.any() else np.empty(0)
            clipped=[]
            for face in faces[~(inside|outside)]:
                poly=list(face)
                for limit,sgn in ((h,1),(-h,-1)):
                    new=[]
                    for i,a in enumerate(poly):
                        b=poly[(i+1)%len(poly)];ia=(a[0]-limit)*sgn<=0;ib=(b[0]-limit)*sgn<=0
                        if ia:new.append(a)
                        if ia!=ib:new.append(a+(b-a)*((limit-a[0])/(b[0]-a[0])))
                    poly=new
                    if not poly:break
                if len(poly)>=3:
                    for i in range(1,len(poly)-1):clipped.append((poly[0],poly[i],poly[i+1]))
            if clipped:clearances=np.concatenate((clearances,radial_min(np.array(clipped))-rad))
            return {'overlap_triangles':int((clearances<-.00005).sum()),'min_radial_clearance_m':float(clearances.min()) if len(clearances) else None}
        result['exact_handle']=cylinders(radius,half,0);result['exact_plates']=[cylinders(pr,pd,x) for x in (-offset,offset)]
        result['pass']=result['pass'] and result['exact_handle']['overlap_triangles']==0 and all(p['overlap_triangles']==0 for p in result['exact_plates'])
    return result


def inspect(rig,side,legacy=False):
    return evaluate_grip(rig,side,legacy=legacy,exact=True)


def render_close(rig,side,tag):
    origin,frame=grip.palm_frame(rig,side);bone=rig.pose.bones['hand_'+side]
    deformation=bone.matrix@rig.data.bones['hand_'+side].matrix_local.inverted()
    center=deformation@(origin+frame@V(grip.GRIP_CENTER));axis=deformation.to_3x3()@frame
    sc=bpy.context.scene
    for ob in list(sc.objects):
        if ob.type in ('LIGHT','CAMERA'):bpy.data.objects.remove(ob,do_unlink=True)
    for loc,power,size in [((.4,-.4,.6),65,.5),((-.3,.4,.4),50,.4)]:
        bpy.ops.object.light_add(type='AREA',location=center+V(loc));light=bpy.context.object;light.data.energy=power;light.data.shape='DISK';light.data.size=size;light.rotation_euler=(center-light.location).to_track_quat('-Z','Y').to_euler()
    bpy.ops.object.camera_add();cam=bpy.context.object;cam.data.type='ORTHO';cam.data.ortho_scale=.25;sc.camera=cam
    sc.render.engine='CYCLES';sc.cycles.samples=32;sc.cycles.use_denoising=True;sc.render.resolution_x=700;sc.render.resolution_y=700;sc.render.resolution_percentage=100;sc.world.color=(.2,.2,.2);sc.render.film_transparent=False;sc.view_settings.view_transform='AgX'
    for name,direction in [('palm',(0,.5,1)),('back',(0,.2,-1)),('side',(.15,1,.2))]:
        cam.location=center+axis@V(direction).normalized()*.7
        cam.rotation_euler=(center-cam.location).to_track_quat('-Z','Y').to_euler()
        sc.render.filepath=str(OUT/f'{tag}-{side}-{name}.png');bpy.ops.render.render(write_still=True)


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--legacy',action='store_true');parser.add_argument('--render',action='store_true');parser.add_argument('--export',action='store_true');args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    OUT.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=str(ROOT/'.build/realistic-character/athlete-source.blend'),use_scripts=False)
    rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');pose_exercise(rig,'curl',2)
    if args.legacy:equipment(rig,'curl')
    else:
        grip.prepare_equipment(rig)
        for side in ('l','r'):
            wrist=rig.pose.bones['hand_'+side].head.copy();elbow=rig.pose.bones['lowerarm_'+side].head.copy()
            direction=(wrist-elbow).normalized();palm=V((0,direction.z,-direction.y))
            hand_q=grip.grip_rotation(rig,side,direction,palm)
            lower=rig.data.bones['lowerarm_'+side];source=hand_q@(lower.tail_local-lower.head_local)
            lower_q=source.rotation_difference(wrist-elbow)@hand_q
            set_bone(rig,'lowerarm_'+side,elbow,q=lower_q)
            grip.pose_grip(rig,side,wrist,hand_q)
    tag='legacy' if args.legacy else 'candidate';report={'tag':tag,'sides':[inspect(rig,s,args.legacy) for s in ('l','r')]}
    (OUT/f'{tag}-report.json').write_text(json.dumps(report,indent=2));print('GRIP_REPORT',json.dumps(report),flush=True)
    if args.render:render_close(rig,'l',tag)
    if args.export:
        scene=bpy.context.scene;scene.frame_start=0;scene.frame_end=1;scene.render.fps=30
        for frame in (0,1):
            scene.frame_set(frame)
            for bone in rig.pose.bones:
                bone.rotation_mode='QUATERNION'
                for channel in ('location','rotation_quaternion','scale'):bone.keyframe_insert(channel)
        rig.animation_data.action.name='Grip verification'
        scene.frame_set(0)
        bpy.ops.object.select_all(action='DESELECT');rig.select_set(True)
        for ob in bpy.context.scene.objects:
            if ob.type=='MESH':ob.select_set(True)
        bpy.context.view_layer.objects.active=rig
        bpy.ops.export_scene.gltf(filepath=str(OUT/'grip-candidate.glb'),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='ACTIVE_ACTIONS',export_force_sampling=True,export_frame_range=True,export_optimize_animation_size=False,export_yup=True,export_morph=False)
        finalize_glb(OUT/'grip-candidate.glb')
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/f'{tag}.blend'))


_body_mask_cache={}

def _equipment_geometry(side):
    """Recover actual cylinder axis after skinning, including GLB seam splits."""
    import numpy as np
    ob=bpy.data.objects['PULSE dumbbell '+side];evaluated=ob.evaluated_get(bpy.context.evaluated_depsgraph_get());mesh=evaluated.to_mesh()
    points=np.empty(len(mesh.vertices)*3);mesh.vertices.foreach_get('co',points);points=points.reshape(-1,3);world=np.array(ob.matrix_world);points=points@world[:3,:3].T+world[:3,3];evaluated.to_mesh_clear()
    points=np.unique(np.round(points,6),axis=0);center=points.mean(axis=0);_,axes=np.linalg.eigh(np.cov((points-center).T));axis=axes[:,-1]
    aux=np.array((0.,0.,1.)) if abs(axis[2])<.9 else np.array((0.,1.,0.));radial=np.cross(axis,aux);radial/=np.linalg.norm(radial)
    return center,np.array((axis,radial,np.cross(axis,radial))).T


def _finite_cylinder_triangles(faces,radius,half_depth,offset):
    """Conservative solid-cylinder intersection for complete triangle surfaces."""
    import numpy as np
    faces=faces-np.array((offset,0,0))
    outside=(faces[:,:,0].min(axis=1)>half_depth)|(faces[:,:,0].max(axis=1)<-half_depth)
    outside|=(faces[:,:,1].min(axis=1)>radius)|(faces[:,:,1].max(axis=1)<-radius)|(faces[:,:,2].min(axis=1)>radius)|(faces[:,:,2].max(axis=1)<-radius)
    faces=faces[~outside]
    if len(faces)==0:return {'overlap_triangles':0,'min_radial_clearance_m':None}
    inside=(np.abs(faces[:,:,0])<=half_depth).all(axis=1)
    polys=list(faces[inside])
    for face in faces[~inside]:
        poly=list(face)
        for boundary,sign in ((half_depth,1),(-half_depth,-1)):
            clipped=[]
            for i,a in enumerate(poly):
                b=poly[(i+1)%len(poly)];ia=(a[0]-boundary)*sign<=0;ib=(b[0]-boundary)*sign<=0
                if ia:clipped.append(a)
                if ia!=ib:clipped.append(a+(b-a)*((boundary-a[0])/(b[0]-a[0])))
            poly=clipped
            if not poly:break
        for i in range(1,len(poly)-1):polys.append((poly[0],poly[i],poly[i+1]))
    if not polys:return {'overlap_triangles':0,'min_radial_clearance_m':None}
    p=np.array(polys)[:,:,1:];edge=np.roll(p,-1,axis=1)-p;denom=(edge*edge).sum(axis=2)
    t=np.clip(-(p*edge).sum(axis=2)/np.maximum(denom,1e-20),0,1);d=np.linalg.norm(p+edge*t[:,:,None],axis=2).min(axis=1)
    cross=p[:,:,0]*np.roll(p[:,:,1],-1,axis=1)-p[:,:,1]*np.roll(p[:,:,0],-1,axis=1);inside=(cross>=0).all(axis=1)|(cross<=0).all(axis=1);d[inside]=0;d-=radius
    return {'overlap_triangles':int((d<-.00005).sum()),'min_radial_clearance_m':float(d.min())}


def evaluate_body_clearance(rig,side,exact=True):
    """Check dumbbell against every other skinned body/clothing surface.

    Only triangles belonging entirely to this hand are excluded. The opposite
    hand, wrist/forearm, legs, torso, head, face meshes, and Boxers are included.
    Every vertex plus four interior points per triangle is sampled. exact=True
    clips complete triangles to the finite handle/plate cylinders, then checks
    face/edge intersections. A full-body solid-angle test additionally catches
    equipment entirely contained inside the body without crossing its surface.
    Returns pass, minimum sampled clearance, counts, and per-mesh diagnostics.
    """
    import numpy as np,time
    started=time.perf_counter();center,basis=_equipment_geometry(side);deps=bpy.context.evaluated_depsgraph_get();results=[];skin=body_mesh()
    components=(('handle',0,grip.HANDLE_RADIUS,grip.HANDLE_HALF_LENGTH),('plate_a',-grip.PLATE_OFFSET,grip.PLATE_RADIUS,grip.PLATE_HALF_DEPTH),('plate_b',grip.PLATE_OFFSET,grip.PLATE_RADIUS,grip.PLATE_HALF_DEPTH))
    for ob in bpy.context.scene.objects:
        if ob.type!='MESH' or ob.name.startswith('PULSE dumbbell'):continue
        if not any(mod.type=='ARMATURE' and mod.object==rig for mod in ob.modifiers):continue
        evaluated=ob.evaluated_get(deps);mesh=evaluated.to_mesh();mesh.calc_loop_triangles()
        coords=np.empty(len(mesh.vertices)*3);mesh.vertices.foreach_get('co',coords);coords=coords.reshape(-1,3)
        triangles=np.empty(len(mesh.loop_triangles)*3,dtype=np.int32);mesh.loop_triangles.foreach_get('vertices',triangles);triangles=triangles.reshape(-1,3)
        world=np.array(ob.matrix_world);coords=(coords@world[:3,:3].T+world[:3,3]-center)@basis
        key=(ob.as_pointer(),ob.data.as_pointer(),len(mesh.vertices),side)
        if key not in _body_mask_cache:
            mask=np.zeros(len(mesh.vertices),dtype=bool)
            if ob.vertex_groups.get('hand_'+side):
                # Only actual character body groups carry mixed hand weights.
                for i in hand_vertices(ob,side):mask[i]=True
            _body_mask_cache[key]=mask
        excluded=_body_mask_cache[key];all_faces=coords[triangles];faces=all_faces[~excluded[triangles].all(axis=1)]
        evaluated.to_mesh_clear()
        selected=coords[~excluded]
        if not len(selected) or not len(faces):continue
        samples=np.concatenate((selected,faces.mean(axis=1),faces[:,0]*.6+faces[:,1]*.2+faces[:,2]*.2,faces[:,0]*.2+faces[:,1]*.6+faces[:,2]*.2,faces[:,0]*.2+faces[:,1]*.2+faces[:,2]*.6))
        part_results={};minimum=float('inf');sample_count=0;intersection_count=0
        for name,offset,radius,half in components:
            points=samples-np.array((offset,0,0));r=np.linalg.norm(points[:,1:],axis=1)-radius;a=np.abs(points[:,0])-half
            d=np.hypot(np.maximum(r,0),np.maximum(a,0))+np.minimum(np.maximum(r,a),0)
            info={'min_clearance_m':float(d.min()),'penetrating_samples':int((d<-.0005).sum())}
            minimum=min(minimum,info['min_clearance_m']);sample_count+=info['penetrating_samples']
            if exact:
                info['exact']=_finite_cylinder_triangles(faces,radius,half,offset);intersection_count+=info['exact']['overlap_triangles']
            part_results[name]=info
        contained=[]
        if ob==skin:
            for name,offset,_,_ in components:
                q=all_faces-np.array((offset,0,0));a,b,c=q[:,0],q[:,1],q[:,2];la=np.linalg.norm(a,axis=1);lb=np.linalg.norm(b,axis=1);lc=np.linalg.norm(c,axis=1)
                numerator=np.einsum('ij,ij->i',a,np.cross(b,c));denominator=la*lb*lc+np.einsum('ij,ij->i',a,b)*lc+np.einsum('ij,ij->i',b,c)*la+np.einsum('ij,ij->i',c,a)*lb
                winding=float(np.arctan2(numerator,denominator).sum()/(2*math.pi))
                if abs(winding)>.5:contained.append({'component':name,'winding_number':winding})
        results.append({'mesh':ob.name,'samples':len(samples),'min_clearance_m':minimum,'penetrating_samples':sample_count,'exact_intersecting_triangles':intersection_count,'contained_centers':contained,'components':part_results,'pass':sample_count==0 and intersection_count==0 and not contained})
    return {'side':side,'pass':all(r['pass'] for r in results),'min_clearance_m':min((r['min_clearance_m'] for r in results),default=None),'penetrating_samples':sum(r['penetrating_samples'] for r in results),'exact_intersecting_triangles':sum(r['exact_intersecting_triangles'] for r in results),'meshes':results,'elapsed_seconds':time.perf_counter()-started}


if __name__=='__main__':main()
