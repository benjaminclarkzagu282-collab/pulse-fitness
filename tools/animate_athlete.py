"""Pose the MakeHuman game_engine skeleton, export self-contained Exercise loops.
No body geometry is generated here; joint transforms drive authored skin weights.
"""
import bpy,math,sys,json,struct
from pathlib import Path
from mathutils import Vector,Quaternion,Matrix
ROOT=Path(__file__).resolve().parents[1];WORK=ROOT/'.build/character';V=Vector
IDS=['squat','pushup','lunge','bridge','plank','row','jumping_jack','curl'];END=96

def ik(a,b,l1,l2,pole):
 axis=b-a;d=min(axis.length,l1+l2-.00001);axis.normalize()
 x=(l1*l1-l2*l2+d*d)/(2*d);h=math.sqrt(max(0,l1*l1-x*x))
 p=V(pole)-axis*V(pole).dot(axis);p.normalize()
 return a+axis*x+p*h

def set_bone(r,name,head,tail=None,q=None):
 b=r.data.bones[name];p=r.pose.bones[name]
 if q is None:q=(b.tail_local-b.head_local).rotation_difference(tail-head)
 p.matrix=Matrix.Translation(head) @ q.to_matrix().to_4x4() @ b.matrix_local.to_quaternion().to_matrix().to_4x4()
 bpy.context.view_layer.update()

def pose(r,e,t):
 for p in r.pose.bones:p.matrix_basis=Matrix.Identity(4)
 s=(1-math.cos(2*math.pi*t))/2
 rest=r.data.bones;p0=rest['pelvis'].head_local.copy();hip=p0.copy();q=Quaternion((1,0,0),0)
 feet={side:rest['foot_'+side].head_local.copy() for side in ['l','r']}
 for side in feet:
  feet[side].x=.19 if side=='l' else -.19;feet[side].z+=float(r.get('foot_ground_offset',.026))
 if e=='squat':hip+=V((0,.13*s,-.38*s));q=Quaternion((1,0,0),.32*s)
 elif e=='lunge':
  hip+=V((0,-.08*s,-.27*s));q=Quaternion((1,0,0),.05)
  feet['l'].y-=.08;feet['r'].y+=.52*s
  contact=r.get('rear_foot_contact_profile')
  if contact:
   angle=.55*s
   feet['r'].z=.0001-min(contact[i]*math.sin(angle)+contact[i+1]*math.cos(angle) for i in range(0,len(contact),2))
  else:feet['r'].z+=.054*s
 elif e in ['pushup','plank']:
  z=.34-.15*s if e=='pushup' else .24+.002*math.sin(2*math.pi*t)
  hip=V((0,.01,z));q=Quaternion((1,0,0),math.pi/2-.13)
  ankle_height=float(r.get('prone_ankle_height',.174))
  for f in feet.values():f.y=.75;f.z=ankle_height
  off=q@(rest['thigh_l'].head_local-p0);length=(rest['thigh_l'].length+rest['calf_l'].length)*.999
  hip.y=.75-math.sqrt(length**2-(hip.z+off.z-ankle_height)**2-(.19-off.x)**2)-off.y
 elif e=='bridge':
  hip=V((0,.05,.18+.21*s));q=Quaternion((1,0,0),math.pi/2+.18+.60*s) @ Quaternion((0,0,1),math.pi)
  for f in feet.values():f.y=.57;f.x*=-1
 elif e=='row':hip+=V((0,.035,-.07));q=Quaternion((1,0,0),.72)
 elif e=='jumping_jack':
  hop=.035*math.sin(2*math.pi*t)**2;hip.z+=hop
  for side,f in feet.items():f.x=(1 if side=='l' else -1)*(.17+.18*s);f.z+=hop
 def moved(p):return hip+q@(p-p0)
 # Transform pelvis/spine/neck/head together; continuous skin preserves anatomy.
 for p in r.pose.bones:
  n=p.name
  if n=='Root':continue
  if n in ['pelvis','spine_01','spine_02','spine_03','spine_04','spine_05','neck_01','head'] or n.startswith('clavicle'):
   set_bone(r,n,moved(rest[n].head_local),q=q)
 if e=='bridge':
  nq=Quaternion((1,0,0),math.pi/2) @ Quaternion((0,0,1),math.pi)
  nh=moved(rest['neck_01'].head_local);hh=V((0,nh.y-.06,.105))
  set_bone(r,'neck_01',nh,hh,q=(q@(rest['neck_01'].tail_local-rest['neck_01'].head_local)).rotation_difference(hh-nh) @ q)
  set_bone(r,'head',hh,q=nq)
 for side,sign in [('l',1),('r',-1)]:
  thigh='thigh_'+side;calf='calf_'+side;foot='foot_'+side;upper='upperarm_'+side;lower='lowerarm_'+side;hand='hand_'+side
  a=moved(rest[thigh].head_local);ankle=feet[side]
  knee=ik(a,ankle,rest[thigh].length,rest[calf].length,(sign*.12,-1,0) if e=='squat' else ((0,-1,0) if e not in ['pushup','plank','bridge'] else (0,0,1)))
  set_bone(r,thigh,a,knee,q=(q@(rest[thigh].tail_local-rest[thigh].head_local)).rotation_difference(knee-a) @ q);set_bone(r,calf,knee,ankle,q=(q@(rest[calf].tail_local-rest[calf].head_local)).rotation_difference(ankle-knee) @ q)
  fq=Quaternion((1,0,0),math.pi/2-.2) if e in ['pushup','plank'] else Quaternion((1,0,0),0)
  if e=='bridge':fq=Quaternion((0,0,1),math.pi)
  if e=='lunge' and side=='r':fq=Quaternion((1,0,0),.55*s)
  set_bone(r,foot,ankle,q=fq)
  a=moved(rest[upper].head_local)
  wrist=V((sign*.23,-.065,p0.z-.025));pole=V((0,1,0));elbow=None
  if e=='squat':wrist=V((sign*.08,-.37,a.z-.055));pole=V((sign,-.1,-.2))
  elif e=='lunge':wrist=a+V((sign*.065,-.02,-.37))
  elif e=='pushup':wrist=V((sign*.27,-.37,.045));pole=V((sign,0,.4))
  elif e=='plank':
   elbow=V((sign*.22,-.36,.045));wrist=V((sign*.19,-.57,.045));pole=V((sign,0,0))
  elif e=='bridge':
   wrist=V((-sign*.22,a.y+.39,.045))
   pole=V((-sign,0,0)) if r.get('realistic_character',False) else V((0,0,-1))
  elif e=='row':wrist=V((sign*.22,-.29+.12*s,.57+.24*s));pole=V((0,1,.25))
  elif e=='curl':
   elbow=a+V((sign*.04,.02,-rest[upper].length*.99));angle=-math.pi/2+2.35*s
   wrist=elbow+V((0,-rest[lower].length*math.cos(angle),rest[lower].length*math.sin(angle)))
  elif e=='jumping_jack':
   angle=math.pi*.91*s
   elbow=a+V((sign*rest[upper].length*math.sin(angle),0,-rest[upper].length*math.cos(angle)))
   wrist=elbow+V((sign*rest[lower].length*math.sin(angle),0,-rest[lower].length*math.cos(angle)))
  if elbow is None:elbow=ik(a,wrist,rest[upper].length,rest[lower].length,pole)
  set_bone(r,upper,a,elbow,q=(q@(rest[upper].tail_local-rest[upper].head_local)).rotation_difference(elbow-a) @ q);set_bone(r,lower,elbow,wrist,q=(q@(rest[lower].tail_local-rest[lower].head_local)).rotation_difference(wrist-elbow) @ q)
  # Wrist follows forearm for a natural straight hand; ground poses flatten palms.
  if e in ['pushup','plank','bridge']:
   direction=V((0,-1,0)) if e!='bridge' else V((0,1,0))
  else:direction=(wrist-elbow).normalized()
  set_bone(r,hand,wrist,wrist+direction*rest[hand].length)
  if e in ['pushup','plank','bridge']:
   d=(rest['middle_03_'+side].tail_local-rest[hand].head_local).normalized()
   x=(rest['index_01_'+side].head_local-rest['pinky_01_'+side].head_local).normalized();x=(x-d*x.dot(d)).normalized();z=x.cross(d)
   tx=V((-sign if e!='bridge' else sign,0,0));ty=V((0,-1 if e!='bridge' else 1,0));tz=tx.cross(ty)
   source=Matrix((x,d,z)).transposed();target=Matrix((tx,ty,tz)).transposed()
   set_bone(r,hand,wrist,q=(target @ source.inverted()).to_quaternion())
 for p in r.pose.bones:
  if p.name.startswith(('index_','middle_','ring_','pinky_')):
   p.rotation_mode='QUATERNION';p.rotation_quaternion=Quaternion((1,0,0),.30 if e in ['standing','lunge','jumping_jack'] else (.0 if e in ['pushup','plank','bridge'] else .65))
 bpy.context.view_layer.update()

def animate(r,e):
 r.animation_data_clear()
 sc=bpy.context.scene;sc.render.fps=24;sc.frame_start=0;sc.frame_end=END
 for f in range(0,END+1,4):
  sc.frame_set(f);pose(r,e,f/END)
  for p in r.pose.bones:
   p.rotation_mode='QUATERNION';p.keyframe_insert('location');p.keyframe_insert('rotation_quaternion');p.keyframe_insert('scale')
 r.animation_data.action.name='Exercise';sc.frame_set(48)

def stage(e,path,portrait=False):
 sc=bpy.context.scene
 for o in list(sc.objects):
  if o.type in ['LIGHT','CAMERA']:bpy.data.objects.remove(o,do_unlink=True)
 def light(loc,power,size,col):
  bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object;o.data.energy=power;o.data.shape='DISK';o.data.size=size;o.data.color=col;o.rotation_euler=(V((0,0,.8))-o.location).to_track_quat('-Z','Y').to_euler()
 light((-3,-4,4.5),450,4,(1,.91,.82));light((3,-2,2.4),280,3,(.8,.88,1));light((1,3,3),550,3,(.90,1,.86))
 centre=V((0,-.03,.74));size=1.82
 if e=='squat':centre=V((0,-.08,.57));size=1.36
 if e in ['pushup','plank','bridge']:centre=V((0,-.04,.35));size=1.65
 if e=='row':centre.z=.65;size=1.55
 if e=='jumping_jack':centre.z=.80;size=1.9
 if portrait:centre=V((0,-.025,1.32));size=.52
 bpy.ops.object.camera_add(location=(3.6,-5,1.7 if not portrait else 1.8));cam=bpy.context.object;cam.rotation_euler=(centre-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=size;sc.camera=cam
 sc.render.engine='CYCLES';sc.cycles.samples=48;sc.cycles.use_denoising=True;sc.render.resolution_x=700;sc.render.resolution_y=800 if e in ['standing','squat'] else 700;sc.render.resolution_percentage=100
 sc.world.color=(.16,.16,.16);sc.view_settings.view_transform='AgX';sc.render.image_settings.file_format='PNG';sc.render.image_settings.color_mode='RGBA';sc.render.film_transparent=True
 sc.render.filepath=str(path);bpy.ops.render.render(write_still=True)

def equipment(r,e):
 for ob in list(bpy.context.scene.objects):
  if ob.name.startswith('PULSE dumbbell'):bpy.data.objects.remove(ob,do_unlink=True)
 if e not in ['row','curl']:return
 m=bpy.data.materials.get('Dumbbell rubber') or bpy.data.materials.new('Dumbbell rubber');m.diffuse_color=(.05,.06,.07,1);m.use_nodes=True
 bs=m.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(.05,.06,.07,1);bs.inputs['Roughness'].default_value=.46;bs.inputs['Metallic'].default_value=.35
 for side in ['l','r']:
  pieces=[]
  for x,rad,depth in [(0,.013,.15),(-.073,.052,.042),(.073,.052,.042)]:
   bpy.ops.mesh.primitive_cylinder_add(vertices=12,radius=rad,depth=depth,location=(x,.073,0),rotation=(0,math.pi/2,0));ob=bpy.context.object
   bpy.ops.object.transform_apply(location=True,rotation=True,scale=True);pieces.append(ob)
  bpy.ops.object.select_all(action='DESELECT')
  for ob in pieces:ob.select_set(True)
  bpy.context.view_layer.objects.active=pieces[0];bpy.ops.object.join();ob=pieces[0];ob.name='PULSE dumbbell '+side
  for v in ob.data.vertices:v.co=r.data.bones['hand_'+side].matrix_local @ v.co
  ob.data.materials.append(m);group=ob.vertex_groups.new(name='hand_'+side);group.add(list(range(len(ob.data.vertices))),1,'REPLACE')
  mod=ob.modifiers.new('Hand attachment','ARMATURE');mod.object=r;ob.parent=r

def finalize_glb(path):
 data=path.read_bytes();n=struct.unpack_from('<I',data,12)[0];doc=json.loads(data[20:20+n]);binary=data[20+n:]
 for m in doc.get('materials',[]):
  alpha=any(k in m.get('name','') for k in ['short02','eyebrow','eyelashes'])
  m['alphaMode']='MASK' if alpha else 'OPAQUE'
  if alpha:m['alphaCutoff']=.4
  else:m.pop('alphaCutoff',None)
  m['doubleSided']=True
 out=json.dumps(doc,separators=(',',':')).encode();out+=b' '*((-len(out))%4)
 path.write_bytes(struct.pack('<III',0x46546c67,2,20+len(out)+len(binary))+struct.pack('<II',len(out),0x4e4f534a)+out+binary)

def main():
 bpy.ops.wm.open_mainfile(filepath=str(WORK/'athlete-source.blend'));r=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
 preview=WORK/'previews';preview.mkdir(exist_ok=True)
 if '--review' in sys.argv:
  for e in IDS:
   pose(r,e,.5 if e not in ['pushup','plank'] else 0);equipment(r,e);stage(e,preview/f'{e}.png')
  return
 if '--preview' in sys.argv:
  pose(r,'standing',0);stage('standing',preview/'standing.png')
  pose(r,'squat',.5);stage('squat',preview/'squat.png');return
 for e in (['squat'] if '--squat-only' in sys.argv else IDS):
  equipment(r,e);animate(r,e)
  bpy.ops.object.select_all(action='DESELECT');r.select_set(True)
  for ob in bpy.context.scene.objects:
   if ob.type=='MESH':ob.select_set(True)
  bpy.context.view_layer.objects.active=r
  bpy.ops.export_scene.gltf(filepath=str(ROOT/f'assets/models/athlete_{e}.glb'),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='ACTIVE_ACTIONS',export_nla_strips_merged_animation_name='Exercise',export_force_sampling=True,export_frame_range=True,export_yup=True,export_morph=False)
  finalize_glb(ROOT/f'assets/models/athlete_{e}.glb')
  bpy.context.scene.frame_set(48 if e not in ['pushup','plank'] else 0)
  stage(e,ROOT/f'assets/images/athlete_{e}.png')
  if e=='squat':stage(e,ROOT/'assets/images/athlete_hero.png')
 r.animation_data_clear();pose(r,'standing',0);stage('standing',ROOT/'assets/images/athlete_avatar.png',portrait=True)
 bpy.ops.wm.save_as_mainfile(filepath=str(WORK/'athlete-animated.blend'))
if __name__=='__main__':main()
