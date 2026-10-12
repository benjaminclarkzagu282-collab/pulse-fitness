"""Measured five-finger grip for the existing MakeHuman 53-bone athlete.

All inputs use rig coordinates. hand_q is a rest-to-pose rotation, exactly the
rotation accepted by animate_athlete.set_bone (not a bone-local quaternion).
The palm frame is A=toward thumb, D=wrist->middle MCP, P=outward from palm.
P=-A.cross(D) on the left and +A.cross(D) on the right. Its reflected right-hand
coordinate system is intentional; only points/vectors are mapped with it.
Call prepare_equipment once; call pose_grip after positioning the forearm and
before inserting bone keys. Equipment has a single 100% hand-bone skin group,
so ordinary glTF skin export preserves attachment without constraints/empties.
"""
import math
import bpy
from mathutils import Matrix, Quaternion, Vector
from animate_athlete import set_bone
V=Vector
GRIP_CENTER=(0.0,.073,.034)
HANDLE_RADIUS=.013
HANDLE_HALF_LENGTH=.066
PLATE_OFFSET=.083
PLATE_RADIUS=.051
PLATE_HALF_DEPTH=.018
# Absolute segment directions in the physical D/P plane, degrees from D.
FINGER_PITCHES={'index': (72.43533, 106.56112, 126.18941), 'middle': (59.28224, 128.77481, 128.73562), 'ring': (66.57678, 93.64107, 129.59238), 'pinky': (54.8921, 65.48013, 109.81885)}
THUMB_DIRECTIONS=((0.49925019, -0.10573122, 0.85998265), (0.03994242, 0.64357785, 0.76433772), (-0.21787371, 0.83176276, 0.51058963))


def palm_frame(rig,side):
    rest=rig.data.bones;origin=rest['hand_'+side].head_local.copy()
    d=(rest['middle_01_'+side].head_local-origin).normalized()
    a=(rest['index_01_'+side].head_local-rest['pinky_01_'+side].head_local).normalized()
    a=(a-d*a.dot(d)).normalized()
    p=a.cross(d)*(-1 if side=='l' else 1)
    return origin,Matrix((a,d,p)).transposed()


def grip_rotation(rig,side,direction,palm_normal):
    """Neutral wrist with D along forearm, and P toward palm_normal.

    Curl: at forearms pointing forward, palm_normal=(0,0,1). Shoulder press:
    at vertical forearms, palm_normal=(0,-1,0) for palms facing forward.
    The requested palm normal is projected perpendicular to direction.
    """
    _,source=palm_frame(rig,side)
    d=V(direction).normalized();p=V(palm_normal)-d*V(palm_normal).dot(d)
    if p.length<1e-5:raise ValueError('Palm normal parallel to hand direction')
    p.normalize();a=d.cross(p)*(-1 if side=='l' else 1)
    return (Matrix((a,d,p)).transposed()@source.inverted()).to_quaternion()


def prepare_equipment(rig):
    """Create a full-sized pair: 20.2 cm length, 10.2 cm plates, 26 mm grip."""
    for ob in list(bpy.context.scene.objects):
        if ob.name.startswith('PULSE dumbbell'):bpy.data.objects.remove(ob,do_unlink=True)
    def material(name,color,metal,rough):
        m=bpy.data.materials.get(name) or bpy.data.materials.new(name)
        m.diffuse_color=(*color,1);m.use_nodes=True
        bs=m.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(*color,1)
        bs.inputs['Metallic'].default_value=metal;bs.inputs['Roughness'].default_value=rough
        return m
    rubber=material('PULSE grip rubber',(.025,.032,.042),.15,.42)
    steel=material('PULSE grip brushed steel',(.34,.38,.42),.86,.27)
    for side in ('l','r'):
        origin,frame=palm_frame(rig,side);pieces=[]
        for x,radius,depth,mat in ((0,HANDLE_RADIUS,HANDLE_HALF_LENGTH*2,steel),(-PLATE_OFFSET,PLATE_RADIUS,PLATE_HALF_DEPTH*2,rubber),(PLATE_OFFSET,PLATE_RADIUS,PLATE_HALF_DEPTH*2,rubber)):
            bpy.ops.mesh.primitive_cylinder_add(vertices=32,radius=radius,depth=depth,location=(x,0,0),rotation=(0,math.pi/2,0))
            ob=bpy.context.object;bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
            ob.data.materials.append(mat)
            bevel=ob.modifiers.new('Soft machined edges','BEVEL');bevel.width=.0014 if x else .0005;bevel.segments=2
            bpy.context.view_layer.objects.active=ob;bpy.ops.object.modifier_apply(modifier=bevel.name)
            for p in ob.data.polygons:p.use_smooth=True
            pieces.append(ob)
        bpy.ops.object.select_all(action='DESELECT')
        for ob in pieces:ob.select_set(True)
        bpy.context.view_layer.objects.active=pieces[0];bpy.ops.object.join();ob=pieces[0];ob.name='PULSE dumbbell '+side
        for vertex in ob.data.vertices:vertex.co=origin+frame@(vertex.co+V(GRIP_CENTER))
        # Frame is a reflection on one side; correct winding after mirroring.
        if frame.determinant()<0:
            import bmesh
            bm=bmesh.new();bm.from_mesh(ob.data);bmesh.ops.reverse_faces(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free()
        group=ob.vertex_groups.new(name='hand_'+side);group.add(list(range(len(ob.data.vertices))),1,'REPLACE')
        mod=ob.modifiers.new('Rigid hand attachment','ARMATURE');mod.object=rig;ob.parent=rig
        ob['quality_grip_version']=1
        ob['grip_center']=list(GRIP_CENTER)


def pose_grip(rig,side,wrist,hand_q):
    """Position the hand and all 15 digit bones without moving the forearm."""
    wrist=V(wrist);origin,frame=palm_frame(rig,side);rest=rig.data.bones
    set_bone(rig,'hand_'+side,wrist,q=hand_q)
    for finger in ('index','middle','ring','pinky','thumb'):
        head=wrist+hand_q@(rest[finger+'_01_'+side].head_local-origin)
        for segment in range(1,4):
            name=f'{finger}_{segment:02}_{side}';bone=rest[name]
            if finger=='thumb':local=V(THUMB_DIRECTIONS[segment-1]).normalized()
            else:
                pitch=math.radians(FINGER_PITCHES[finger][segment-1])
                local=V((0,math.cos(pitch),math.sin(pitch)))
            direction=hand_q@(frame@local)
            source=hand_q@(bone.tail_local-bone.head_local)
            rotation=source.rotation_difference(direction)@hand_q
            set_bone(rig,name,head,q=rotation)
            head+=direction*bone.length
    bpy.context.view_layer.update()
