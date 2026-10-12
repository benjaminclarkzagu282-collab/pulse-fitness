"""Build a continuously skinned MakeHuman athlete. See docs/assets/character-sources.json.
Run Blender --factory-startup --background --python tools/build_athlete.py.
Authoring dependencies and .blend remain in ignored .build/character.
"""
import bpy, sys, math, json, bmesh
from pathlib import Path
from mathutils import Vector, Quaternion, Matrix
ROOT=Path(__file__).resolve().parents[1]
WORK=ROOT/'.build/character'; ASSETS=WORK/'assets'
sys.path.insert(0,str(WORK/'mpfb2/src'))
bpy.utils.extension_path_user=lambda package,path='',create=False: str(WORK/'user'/path)
import addon_utils
addon_utils.enable('mpfb',default_set=True)
from mpfb.services.humanservice import HumanService
from mpfb.services.targetservice import TargetService
V=Vector

def material(name,color):
 m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
 p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*color,1);p.inputs['Roughness'].default_value=.78
 return m

def asset(name,h,kind='Clothes'):
 path=next(ASSETS.rglob(name))
 return HumanService.add_mhclo_asset(str(path),h,asset_type=kind,material_type='GAMEENGINE',subdiv_levels=0)

def build():
 bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
 d=TargetService.get_default_macro_info_dict();d.update(gender=1.,age=.5,muscle=.85,weight=.45,height=.65,proportions=.65);d['race']={'asian':.7,'caucasian':.3,'african':0.}
 h=HumanService.create_human(macro_detail_dict=d);h.name='PULSE athletic male | MakeHuman CC0'
 skin=next(ASSETS.rglob('young_asian_male.mhmat'))
 HumanService.set_character_skin(str(skin),h,skin_type='GAMEENGINE')
 rig=HumanService.add_builtin_rig(h,'game_engine');rig.name='PULSE deformation skeleton'
 eyes=asset('low-poly.mhclo',h,'Eyes')
 em=material('Brown iris',(.3,.2,.12));eyes.data.materials.clear();eyes.data.materials.append(em)
 tex=em.node_tree.nodes.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(str(ASSETS/'eyes/materials/brown_eye.png'));em.node_tree.links.new(tex.outputs['Color'],em.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])
 asset('eyebrow001.mhclo',h,'Eyebrows');asset('eyelashes01.mhclo',h,'Eyelashes')
 hair=asset('short02.mhclo',h,'Hair')
 for m in hair.data.materials:
  m.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value=.55
  for n in m.node_tree.nodes:
   if n.type=='TEX_IMAGE' and n.image and 'diffuse' in n.image.name:
    im=n.image;pix=list(im.pixels)
    for i in range(0,len(pix),4):
     v=.14*(.25*pix[i]+.55*pix[i+1]+.20*pix[i+2]);pix[i:i+3]=[v*.82,v*.88,v]
    im.pixels[:]=pix;im.pack()
 shirt=asset('toigo_basic_tucked_t-shirt.mhclo',h)
 lo=min(v.co.z for v in shirt.data.vertices);hi=max(v.co.z for v in shirt.data.vertices)
 for v in shirt.data.vertices:
  t=(v.co.z-lo)/(hi-lo);v.co.z-=.095*(1-t)**3;v.co.x*=1+.12*(1-t)**3;v.co.y*=1+.16*(1-t)**3
 shirt.data.materials.clear();shirt.data.materials.append(material('Graphite technical jersey',(.095,.115,.125)))
 shorts=asset('cortu_cargo_pants.mhclo',h)
 shorts.data.materials.clear();shorts.data.materials.append(material('Charcoal training shorts',(.039,.048,.056)))
 shoe=asset('shoes05.mhclo',h)
 # Crop the existing CC0 cargo-trouser mesh into knee-above sports shorts.
 bm=bmesh.new();bm.from_mesh(shorts.data)
 cut=rig.data.bones['thigh_l'].head_local.z-.23
 bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=.00001,plane_co=(0,0,cut),plane_no=(0,0,1),clear_inner=True,clear_outer=False)
 bm.to_mesh(shorts.data);bm.free()
 # Keep shoelaces, sole and fabric detail from the supplied white sneaker atlas.
 # Freeze macro morphs before masks, keep authored per-vertex bone weights.
 for ob in list(bpy.context.scene.objects):
  if ob.type!='MESH':continue
  bpy.context.view_layer.objects.active=ob
  if ob.data.shape_keys:
   bpy.ops.object.select_all(action='DESELECT');ob.select_set(True)
   bpy.ops.object.shape_key_remove(all=True,apply_mix=True)
  for mod in list(ob.modifiers):
   if mod.type=='MASK':
    bpy.ops.object.modifier_apply(modifier=mod.name);continue
   if mod.type=='ARMATURE':mod.use_deform_preserve_volume=True
  for p in ob.data.polygons:p.use_smooth=True
  # Body subdivision improves curved silhouettes but remains moderate (~60k triangles).
  if ob==h or ob==hair:
   sub=ob.modifiers.new('Smooth anatomical surface','SUBSURF');sub.levels=1
   # Apply before rig so GLB carries continuous smoothed skin weights.
   bpy.ops.object.modifier_move_up(modifier=sub.name)
   bpy.ops.object.modifier_apply(modifier=sub.name)
 # Normalize authoring dimensions for the motion solver while preserving adult proportions.
 factor=.78/rig.data.bones['pelvis'].head_local.z
 for ob in bpy.context.scene.objects:
  if ob.type=='MESH':
   for v in ob.data.vertices:v.co*=factor
 bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);bpy.context.view_layer.objects.active=rig
 bpy.ops.object.mode_set(mode='EDIT')
 for b in rig.data.edit_bones:b.head*=factor;b.tail*=factor
 bpy.ops.object.mode_set(mode='OBJECT')
 # Remove occluded torso/upper-thigh skin as for standard clothed game characters.
 # The visible neck, arms, legs and hands remain authored continuous skin surfaces.
 torso_groups={g.index for g in h.vertex_groups if g.name in ['pelvis','spine_01','spine_02','spine_03']}
 hidden_indices={v.index for v in h.data.vertices if .66<v.co.z<1.16 and sum(g.weight for g in v.groups if g.group in torso_groups)>.97}
 bm=bmesh.new();bm.from_mesh(h.data);bm.verts.ensure_lookup_table()
 bmesh.ops.delete(bm,geom=[v for v in bm.verts if v.index in hidden_indices],context='VERTS');bm.to_mesh(h.data);bm.free()
 # Keep realistic detail at a phone-appropriate texture resolution.
 for im in bpy.data.images:
  limit=256 if 'eye' in im.name and 'eyebrow' not in im.name and 'eyelash' not in im.name else 1024
  if im.size[0]>limit or im.size[1]>limit:
   factor=min(limit/im.size[0],limit/im.size[1]);im.scale(round(im.size[0]*factor),round(im.size[1]*factor))
  if any(n in im.name for n in ['lightskinned','brown_eye','shoes05_diffuse']):
   (WORK/'textures').mkdir(exist_ok=True);im.filepath_raw=str(WORK/'textures'/(im.name.split('.')[0]+'.jpg'));im.file_format='JPEG';im.save();im.pack()
 bpy.ops.file.pack_all()
 bpy.ops.wm.save_as_mainfile(filepath=str(WORK/'athlete-source.blend'))
 return rig

if __name__=='__main__':build()
