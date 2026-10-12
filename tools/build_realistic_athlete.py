"""Prepare the user's realistic man for PULSE, without changing the supplied files.

Blender --factory-startup --background --disable-autoexec --python-exit-code 1
  --python tools/build_realistic_athlete.py [-- --materials-only]
Source and intermediate .blend files stay outside bundled app assets.
"""
import json
import math
import random
import sys
from pathlib import Path

import bpy
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT.parent / 'characters/00_已解压/3D model Realistic Rigged Man Vray & MentalRay'
WORK = ROOT / '.build/realistic-character'
SCALE = .8
V = Vector


def texture(filename, size=2048, data=False):
    source = SOURCE / filename
    if not source.exists():
        # Reuse the already prepared original texture if extracted originals
        # were moved after the first character build.
        cache = ROOT / '.build/realistic-character/textures'
        source = cache / (Path(filename).stem + ('.png' if data else '.jpg'))
    image = bpy.data.images.load(str(source), check_existing=True)
    if data:
        image.colorspace_settings.name = 'Non-Color'
    if max(image.size) > size:
        ratio = size / max(image.size)
        image.scale(round(image.size[0] * ratio), round(image.size[1] * ratio))
    image.file_format = 'PNG' if data else 'JPEG'
    image.filepath_raw = str(WORK / 'textures' / (Path(filename).stem + ('.png' if data else '.jpg')))
    image.save()
    image.pack()
    return image


def material(name, color=(.3, .3, .3, 1), roughness=.5, diffuse=None, normal=None, size=2048):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = color
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = color
    bsdf.inputs['Roughness'].default_value = roughness
    bsdf.inputs['Specular IOR Level'].default_value = .3
    if diffuse:
        node = nodes.new('ShaderNodeTexImage')
        node.image = texture(diffuse, size)
        links.new(node.outputs['Color'], bsdf.inputs['Base Color'])
    if normal:
        node = nodes.new('ShaderNodeTexImage')
        node.image = texture(normal, 1024, True)
        mapping = nodes.new('ShaderNodeNormalMap')
        mapping.inputs['Strength'].default_value = .55
        links.new(node.outputs['Color'], mapping.inputs['Color'])
        links.new(mapping.outputs['Normal'], bsdf.inputs['Normal'])
    return mat


def assign(ob, mat):
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    for polygon in ob.data.polygons:
        polygon.material_index = 0


def simplify(ob, ratio):
    bpy.context.view_layer.objects.active = ob
    modifier = ob.modifiers.new('Mobile detail reduction', 'DECIMATE')
    modifier.ratio = ratio
    bpy.ops.object.modifier_apply(modifier=modifier.name)


def eyebrows(body, mat):
    """Replace the supplied hair emitter (no hair data) with tapered mesh strands."""
    emitter = bpy.data.objects['Eyebrows_root']
    emitter.data.calc_loop_triangles()
    triangles = list(emitter.data.loop_triangles)
    rng = random.Random(52)
    tree = BVHTree.FromObject(body, bpy.context.evaluated_depsgraph_get())
    vertices, faces = [], []
    for triangle in rng.choices(triangles, weights=[t.area for t in triangles], k=620):
        a, b, c = [emitter.data.vertices[i].co for i in triangle.vertices]
        u, v = rng.random(), rng.random()
        if u + v > 1:
            u, v = 1 - u, 1 - v
        point = a + u * (b-a) + v * (c-a)
        point, normal, _, _ = tree.find_nearest(point)
        point += normal * .00065
        sign = 1 if point.x > 0 else -1
        direction = V((sign, 0, -.10 if abs(point.x)<.025 else -.38))
        direction = (direction - normal * direction.dot(normal)).normalized()
        width = direction.cross(normal).normalized()
        length = rng.uniform(.003, .006)
        start = len(vertices)
        for i in range(3):
            t = i / 2
            centre = point + direction * length * t + normal * math.sin(t*math.pi) * .00035
            radius = .00027 * (1 - .85*t)
            for j in range(3):
                angle = j * 2 * math.pi / 3
                vertices.append(centre + radius*(width*math.cos(angle)+normal*math.sin(angle)))
        for i in range(2):
            for j in range(3):
                faces.append((start+i*3+j, start+i*3+(j+1)%3,
                              start+(i+1)*3+(j+1)%3, start+(i+1)*3+j))
    data = bpy.data.meshes.new('Tapered brow hairs')
    data.from_pydata(vertices, [], faces)
    data.uv_layers.new()
    ob = bpy.data.objects.new('Eyebrows', data)
    bpy.context.collection.objects.link(ob)
    assign(ob, mat)
    for polygon in data.polygons:
        polygon.use_smooth = True
    bpy.data.objects.remove(emitter, do_unlink=True)


def prepare():
    (WORK / 'textures').mkdir(parents=True, exist_ok=True)
    (WORK / 'previews').mkdir(exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE / '男人物.blend'), use_scripts=False)
    # The delivered file was saved in multi-object edit mode. Flush its UV data first.
    if bpy.context.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')
    for ob in list(bpy.context.scene.objects):
        if ob.type != 'MESH' or ob.name in ('Backdrop', 'Cornea_L', 'Cornea_R', 'Lens_L', 'Lens_R', 'Tearduct', 'Tearline'):
            bpy.data.objects.remove(ob, do_unlink=True)
            continue
        matrix = ob.matrix_world.copy()
        ob.parent = None
        ob.data.transform(matrix)
        ob.matrix_world = Matrix.Identity(4)
        for v in ob.data.vertices:
            v.co = (v.co - V((0, .045, 0))) * SCALE
        for p in ob.data.polygons:
            p.use_smooth = True
        if 'Eyelashes' in ob.name:
            simplify(ob, .04 if 'top' in ob.name else .25)
        elif 'Gums' in ob.name or 'Teeth' in ob.name:
            simplify(ob, .12)

    body = bpy.data.objects['Man']
    body.data.materials.clear()
    for part in ('Body', 'Head'):
        mat = material('PULSE realistic ' + part.lower(), diffuse=f'{part}_unscattered.png',
                       normal=f'{part}_normal.png', roughness=.5)
        bsdf = mat.node_tree.nodes.get('Principled BSDF')
        bsdf.inputs['Subsurface Weight'].default_value = .055
        bsdf.inputs['Subsurface Radius'].default_value = (1, .35, .2)
        body.data.materials.append(mat)
    # The original uses a body tile at U=0 and a head tile at U=1.
    # Split material assignments and move head UVs to 0..1 for regular glTF textures.
    uv = body.data.uv_layers.active.uv
    for polygon in body.data.polygons:
        head = sum(uv[i].vector.x for i in polygon.loop_indices) / len(polygon.loop_indices) > 1
        polygon.material_index = int(head)
        if head:
            for i in polygon.loop_indices:
                uv[i].vector.x -= 1
    assign(bpy.data.objects['Boxers'], material('PULSE charcoal compression shorts', roughness=.85,
                                               diffuse='Boxers_color.png', normal='Boxers_normal.png', size=1024))
    iris = material('PULSE blue iris', roughness=.22, diffuse='EyeIrisBlue_unscattered.png', size=512)
    eyeball = material('PULSE sclera', roughness=.3, diffuse='Eyeball_unscattered.png', size=512)
    hair = material('PULSE eyebrows and lashes', color=(.035, .019, .012, 1), roughness=.8)
    mouth = material('PULSE mouth', diffuse='Mouth_diffuse.png', roughness=.42, size=512)
    for ob in bpy.context.scene.objects:
        if ob.name.startswith('Iris'):
            assign(ob, iris)
        elif ob.name.lower().startswith('eyeball'):
            assign(ob, eyeball)
        elif ob.name.startswith(('Eyebrow', 'Eyelash')):
            assign(ob, hair)
        elif ob.name in ('UpperTeeth', 'LowerTeeth', 'UpperGums', 'LowerGums', 'Tongue'):
            assign(ob, mouth)
    eyebrows(body, hair)
    return body


def bind(body):
    """Fit the existing compatible bone hierarchy to the new anatomy, then bind it."""
    source = ROOT / '.build/character/athlete-source.blend'
    with bpy.data.libraries.load(str(source), link=False) as (available, loaded):
        loaded.objects = [n for n in available.objects if n == 'PULSE deformation skeleton']
    rig = loaded.objects[0]
    bpy.context.collection.objects.link(rig)
    rig.name = 'PULSE realistic deformation skeleton'
    rig['realistic_character'] = True
    rig['foot_ground_offset'] = .0011
    rig['prone_ankle_height'] = .155
    rig.animation_data_clear()
    rest = {b.name: (b.head_local.copy(), b.tail_local.copy()) for b in rig.data.bones}
    bpy.ops.object.select_all(action='DESELECT')
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode='EDIT')
    bones = rig.data.edit_bones
    points = {
        'Root': ((0,0,0),(0,.025,0)),
        'pelvis': ((0,.025,.78),(0,.035,.85)),
        'spine_01': ((0,.035,.85),(0,.035,.905)),
        'spine_02': ((0,.035,.905),(0,.045,.96)),
        'spine_03': ((0,.045,.96),(0,.055,1.08)),
        'neck_01': ((0,.025,1.255),(0,.003,1.325)),
        'head': ((0,.003,1.325),(0,.01,1.455)),
    }
    for side, sign in [('l',1),('r',-1)]:
        def p(x,y,z): return V((sign*x,y,z))
        wrist = p(.417,-.022,.887)
        points.update({
            'clavicle_'+side: (p(.012,.026,1.21),p(.165,.039,1.185)),
            'upperarm_'+side: (p(.165,.039,1.185),p(.294,.038,.992)),
            'lowerarm_'+side: (p(.294,.038,.992),wrist),
            'thigh_'+side: (p(.083,.035,.778),p(.122,.032,.418)),
            'calf_'+side: (p(.122,.032,.418),p(.16,.035,.073)),
            'foot_'+side: (p(.16,.035,.073),p(.177,-.054,.025)),
            'ball_'+side: (p(.177,-.054,.025),p(.185,-.104,.019)),
        })
        old = rest['hand_'+side][0]
        forward = rest['middle_03_'+side][1] - old
        target = p(.469,-.069,.751) - wrist
        rotation = forward.rotation_difference(target)
        scale = target.length / forward.length
        for name, (head, tail) in rest.items():
            if name.endswith('_'+side) and name.startswith(('hand_','thumb_','index_','middle_','ring_','pinky_')):
                points[name] = (wrist+rotation@(head-old)*scale, wrist+rotation@(tail-old)*scale)
    for name, (head,tail) in points.items():
        bones[name].use_connect = False
        bones[name].head, bones[name].tail = head, tail
    bones['Root'].use_deform = False
    bpy.ops.object.mode_set(mode='OBJECT')
    ankle = rig.data.bones['foot_r'].head_local
    rig['rear_foot_contact_profile'] = [value for v in body.data.vertices
                                       if v.co.x < 0 and v.co.z < .035
                                       for value in (v.co.y-ankle.y,v.co.z-ankle.z)]
    for p in rig.pose.bones:
        p.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    # Bone heat creates smoothly varying body weights; face accessories follow the head.
    bpy.ops.object.select_all(action='DESELECT')
    body.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.parent_set(type='ARMATURE_AUTO')
    if not body.vertex_groups or any(not v.groups for v in body.data.vertices):
        raise RuntimeError('Bone heat binding left unweighted body vertices')
    body.modifiers[-1].use_deform_preserve_volume = False
    # Keep plantar skin with foot/toe bones. Heat binding otherwise lets the calf
    # pull the bare heel through the floor during a bent-knee bridge.
    for vertex in body.data.vertices:
        if vertex.co.z >= .035:
            continue
        side = 'l' if vertex.co.x > 0 else 'r'
        allowed = {'foot_'+side, 'ball_'+side}
        foot_weights = [(g.group,g.weight) for g in vertex.groups
                        if body.vertex_groups[g.group].name in allowed]
        if not foot_weights:
            foot_weights = [(body.vertex_groups['foot_'+side].index,1)]
        for index in [g.group for g in vertex.groups]:
            body.vertex_groups[index].remove([vertex.index])
        total = sum(w for _,w in foot_weights)
        for index,weight in foot_weights:
            body.vertex_groups[index].add([vertex.index],weight/total,'REPLACE')
    for ob in list(bpy.context.scene.objects):
        if ob.type != 'MESH' or ob == body:
            continue
        ob.parent = rig
        modifier = ob.modifiers.new('Deformation', 'ARMATURE')
        modifier.object = rig
        if ob.name == 'Boxers':
            bpy.ops.object.select_all(action='DESELECT')
            ob.select_set(True)
            bpy.context.view_layer.objects.active = ob
            transfer = ob.modifiers.new('Fit clothing weights', 'DATA_TRANSFER')
            transfer.object = body
            transfer.use_vert_data = True
            transfer.data_types_verts = {'VGROUP_WEIGHTS'}
            transfer.vert_mapping = 'POLYINTERP_NEAREST'
            bpy.ops.object.datalayout_transfer(modifier=transfer.name)
            bpy.ops.object.modifier_apply(modifier=transfer.name)
        else:
            group = ob.vertex_groups.new(name='head')
            group.add(list(range(len(ob.data.vertices))), 1, 'REPLACE')
    for ob in [o for o in bpy.context.scene.objects if o.type == 'MESH']:
        # Keep only four normalized influences, matching the glTF/mobile shader contract.
        for vertex in ob.data.vertices:
            groups = sorted([(g.group,g.weight) for g in vertex.groups if g.weight>1e-5],
                            key=lambda x:x[1], reverse=True)[:4]
            if not groups:
                raise RuntimeError(f'Unweighted vertex: {ob.name}/{vertex.index}')
            total = sum(w for _,w in groups)
            # Snapshot integers: Blender's group views become invalid after removal.
            for index in [g.group for g in vertex.groups]:
                ob.vertex_groups[index].remove([vertex.index])
            for index, weight in groups:
                ob.vertex_groups[index].add([vertex.index], weight/total, 'REPLACE')
    return rig


def preview(name='materials', portrait=False):
    sc = bpy.context.scene
    for ob in list(sc.objects):
        if ob.type in ('CAMERA', 'LIGHT'):
            bpy.data.objects.remove(ob, do_unlink=True)
    target = V((0, -.035, .75 if not portrait else 1.32))
    for location, energy, size, color in [
        ((-3, -4, 4), 430, 3, (1, .90, .82)),
        ((3, -2, 2), 180, 3, (.85, .91, 1)),
        ((1, 2, 3), 420, 2, (1, 1, 1)),
    ]:
        bpy.ops.object.light_add(type='AREA', location=location)
        light = bpy.context.object
        light.data.energy, light.data.size, light.data.color = energy, size, color
        light.rotation_euler = (target - light.location).to_track_quat('-Z', 'Y').to_euler()
    bpy.ops.object.camera_add(location=(1.3 if portrait else 2, -6, 1.55))
    camera = bpy.context.object
    camera.rotation_euler = (target - camera.location).to_track_quat('-Z', 'Y').to_euler()
    camera.data.type = 'ORTHO'
    camera.data.ortho_scale = .42 if portrait else 1.62
    sc.camera = camera
    sc.render.engine = 'CYCLES'
    sc.cycles.samples = 24
    sc.cycles.use_denoising = True
    sc.render.resolution_x, sc.render.resolution_y = (640, 640) if portrait else (720, 900)
    sc.render.resolution_percentage = 100
    sc.world.color = (.16, .16, .16)
    sc.view_settings.view_transform = 'AgX'
    sc.view_settings.look = 'AgX - Medium High Contrast'
    sc.view_settings.exposure = -.3
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGBA'
    sc.render.film_transparent = True
    sc.render.filepath = str(WORK / 'previews' / (name + '.png'))
    bpy.ops.render.render(write_still=True)


if __name__ == '__main__':
    body = prepare()
    bpy.context.scene.view_settings.view_transform = 'AgX'
    bpy.context.scene.view_settings.look = 'AgX - Medium High Contrast'
    bpy.context.scene.view_settings.exposure = -.3
    bpy.ops.wm.save_as_mainfile(filepath=str(WORK / 'materials.blend'))
    if '--materials-only' not in sys.argv:
        rig = bind(body)
        bpy.ops.wm.save_as_mainfile(filepath=str(WORK / 'athlete-source.blend'))
    preview()
    preview('face', True)
