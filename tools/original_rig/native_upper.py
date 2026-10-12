"""Review poses on the imported native CAT Skin, without editing bind matrices.

Bone display tails in this FBX follow Blender's Y convention, while the actual
CAT length axis is X. Use native joint origins and matrix columns instead.
These authored poses are visual review samples; they are not coach-certified.
"""
import math
import bpy
from mathutils import Vector, Matrix, Quaternion

V=Vector
GRIP_CENTER=V((0,.0865385913,.0452461269))
HANDLE_RADIUS=.014
HALF_HANDLE=.0825
PITCHES={'Index':(61.63248469,98.13267601,126.99100752),
         'Middle':(58.56057249,112.09920758,130.45718819),
         'Ring':(58.44909087,84.72927556,135.19722824),
         'Pinky':(44.08510081,61.50168931,87.73474659)}
# The native thumb MCP is on the palm side, unlike the earlier fitted rig.
# Opposition must approach the handle longitudinally before crossing it.
def thumb_direction(azimuth,elevation):
    az,el=math.radians(azimuth),math.radians(elevation)
    return (math.sin(az)*math.cos(el),math.cos(az)*math.cos(el),math.sin(el))
THUMB=tuple(thumb_direction(a,e) for a,e in [(41.44063636,14.97796413),(-31.07024384,48.87370885),(-44.42212583,-4.61034681)])

class NativeUpper:
    def __init__(self,rig):
        self.rig=rig
        self.reference={p.name:(rig.matrix_world@p.matrix).copy() for p in rig.pose.bones}
        self.inverse=rig.matrix_world.inverted()

    def origin(self,name):return self.reference[name].translation.copy()

    def place(self,name,head,delta):
        original=self.reference[name]
        world=Matrix.Translation(head)@delta.to_matrix().to_4x4()@Matrix.Translation(-original.translation)@original
        self.rig.pose.bones[name].matrix=self.inverse@world
        bpy.context.view_layer.update()

    def reset(self):
        for p in self.rig.pose.bones:
            p.matrix=self.inverse@self.reference[p.name]
            bpy.context.view_layer.update()

    def palm(self,side):
        pre='Man_'+side+'Hand'
        wrist=self.origin(pre)
        d=(self.origin(pre+'Middle1')-wrist).normalized()
        a=self.origin(pre+'Index1')-self.origin(pre+'Pinky1')
        a=(a-d*a.dot(d)).normalized()
        p=a.cross(d)*(-1 if side=='L' else 1)
        return wrist,Matrix((a,d,p)).transposed()

    def hand_rotation(self,side,direction,palm_normal):
        _,source=self.palm(side)
        d=direction.normalized();p=palm_normal-d*palm_normal.dot(d);p.normalize()
        a=d.cross(p)*(-1 if side=='L' else 1)
        return (Matrix((a,d,p)).transposed()@source.inverted()).to_quaternion()

    def grip(self,side,wrist,rotation):
        name='Man_'+side+'Hand';origin,frame=self.palm(side)
        self.place(name,wrist,rotation)
        for finger in (*PITCHES,'Thumb'):
            head=wrist+rotation@(self.origin(name+finger+'1')-origin)
            for i in range(1,4):
                bone=name+finger+str(i)
                if finger=='Thumb':local=V(THUMB[i-1]).normalized()
                else:
                    pitch=math.radians(PITCHES[finger][i-1])
                    local=V((0,math.cos(pitch),math.sin(pitch)))
                direction=rotation@(frame@local)
                # Preserve the source roll and only align its physical X axis.
                physical_axis=self.reference[bone].to_3x3().col[0].normalized()
                # Transport source roll with the palm first. A shortest world
                # rotation alone twists the skin when the forearm turns.
                delta=(rotation@physical_axis).rotation_difference(direction)@rotation
                self.place(bone,head,delta)
                if i<3:head+=direction*(self.origin(name+finger+str(i+1))-self.origin(bone)).length

    def pose(self,exercise,depth):
        if exercise not in ('curl','shoulder_press'):raise ValueError(exercise)
        self.reset()
        diagnostics={}
        for side,sign in [('L',1),('R',-1)]:
            pre='Man_'+side;cl=pre+'Collarbone';upper=pre+'Upperarm';lower=pre+'Forearm';hand=pre+'Hand'
            clav=Quaternion((0,-sign,0),math.radians(2+10*depth if exercise=='shoulder_press' else 0))
            self.place(cl,self.origin(cl),clav)
            shoulder=self.origin(cl)+clav@(self.origin(upper)-self.origin(cl))
            if exercise=='shoulder_press':
                a=math.radians(88+81*depth);elbowangle=math.radians(90+83*depth)
                f=a+math.pi-elbowangle;plane=math.radians(22)
                ud=V((sign*math.sin(a)*math.cos(plane),-math.sin(a)*math.sin(plane),-math.cos(a)))
                fd=V((sign*math.sin(f)*math.cos(plane),-math.sin(f)*math.sin(plane),-math.cos(f)))
                normal=V((0,-1,0))
            else:
                ud=V((sign*.23,-.20,-1)).normalized()
                f=math.radians(24+102*depth)
                fd=V((sign*.02,-math.sin(f),-math.cos(f))).normalized()
                normal=V((0,-math.cos(f),math.sin(f)))
            elbow=shoulder+ud*(self.origin(lower+'1')-self.origin(upper)).length
            wrist=elbow+fd*(self.origin(hand)-self.origin(lower+'1')).length
            uq=(self.origin(lower+'1')-self.origin(upper)).rotation_difference(ud)
            fq=(self.origin(hand)-self.origin(lower+'1')).rotation_difference(fd)
            hq=self.hand_rotation(side,fd,normal)
            relative=hq@fq.inverted()
            component=V((relative.x,relative.y,relative.z)).dot(fd)
            twist=Quaternion((relative.w,*(fd*component)))
            twist.normalize()
            self.place(upper,shoulder,uq)
            for i in range(1,4):
                n=lower+str(i)
                head=elbow+fq@(self.origin(n)-self.origin(lower+'1'))
                partial=Quaternion().slerp(twist,(i-1)/3)
                self.place(n,head,partial@fq)
            self.grip(side,wrist,hq)
            diagnostics[side]={'shoulder':list(shoulder),'elbow':list(elbow),'wrist':list(wrist),
                'upper_length':(elbow-shoulder).length,'forearm_length':(wrist-elbow).length,
                'grip_center':list(wrist+hq@(self.palm(side)[1]@GRIP_CENTER))}
        return diagnostics

    def equipment(self):
        def material(name,color,metal,rough):
            m=bpy.data.materials.new(name);m.use_nodes=True
            bs=m.node_tree.nodes.get('Principled BSDF')
            bs.inputs['Base Color'].default_value=(*color,1);bs.inputs['Metallic'].default_value=metal;bs.inputs['Roughness'].default_value=rough
            return m
        steel=material('Native grip steel',(.34,.38,.42),.86,.27)
        rubber=material('Native grip rubber',(.025,.032,.042),.15,.42)
        for side in ('L','R'):
            origin,frame=self.palm(side);pieces=[]
            for x,rad,length,mat in [(0,HANDLE_RADIUS,HALF_HANDLE*2,steel),(-.10375,.06375,.045,rubber),(.10375,.06375,.045,rubber)]:
                bpy.ops.mesh.primitive_cylinder_add(vertices=32,radius=rad,depth=length,location=(x,0,0),rotation=(0,math.pi/2,0))
                o=bpy.context.object;bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
                o.data.materials.append(mat)
                for p in o.data.polygons:p.use_smooth=True
                pieces.append(o)
            bpy.ops.object.select_all(action='DESELECT')
            for o in pieces:o.select_set(True)
            bpy.context.view_layer.objects.active=pieces[0];bpy.ops.object.join();o=pieces[0];o.name='Native dumbbell '+side
            for v in o.data.vertices:v.co=origin+frame@(v.co+GRIP_CENTER)
            if frame.determinant()<0:
                import bmesh
                bm=bmesh.new();bm.from_mesh(o.data);bmesh.ops.reverse_faces(bm,faces=list(bm.faces));bm.to_mesh(o.data);bm.free()
            # Rigid equipment has its own bind coordinates. Reference pose and
            # imported bind pose differ slightly; using only rig inverse would
            # apply that offset twice and move the handle through the palm.
            bone='Man_'+side+'Hand'
            bind=self.rig.data.bones[bone].matrix_local@self.reference[bone].inverted()
            o.data.transform(bind);o.matrix_world=self.rig.matrix_world.copy()
            group=o.vertex_groups.new(name='Man_'+side+'Hand');group.add(list(range(len(o.data.vertices))),1,'REPLACE')
            mod=o.modifiers.new('Native hand attachment','ARMATURE');mod.object=self.rig
            o.parent=self.rig;o.matrix_world=self.rig.matrix_world.copy()
