"""Build the 22 remaining demonstrations from the complete original Skin.

The approved shoulder/curl GLBs are copied byte-for-byte. All new actions are
sampled in time (including alternating limbs), rather than forced into one
depth parameter. Compact morphs are bounded by a per-vertex error gate.
"""
import argparse
import hashlib
import json
import re
import shutil
import struct
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector
from mathutils.kdtree import KDTree

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'tools'))
sys.path.insert(0, str(Path(__file__).parent))
from build_native_review import prepare, points, fingerprint
from mesh_animation import compress_frames, unsigned_components
from build_squat_muscles import overlay
from build_library_muscles import region_mask, patch_glb
from motion_library import IDS

# Position error stays 0.15 mm; smooth lighting normals may differ by at most
# approximately 0.06 (about 3.4 degrees before normalization).
NORMAL_SCALE = .0025


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_report(path, report):
    temporary = path.with_name(path.name+'.pending')
    temporary.write_text(json.dumps(report, ensure_ascii=False, indent=2))
    temporary.replace(path)


def linear(action):
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for curve in bag.fcurves:
                    for key in curve.keyframe_points:
                        key.interpolation = 'LINEAR'


def normals(obj):
    evaluated = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh = evaluated.to_mesh()
    transform = obj.matrix_world.to_3x3().inverted().transposed()
    result = np.array([list((transform@v.normal).normalized()) for v in mesh.vertices], dtype=np.float32)
    evaluated.to_mesh_clear()
    return result


def rigid_bone(obj, rig):
    if not any(mod.type=='ARMATURE' and mod.object==rig for mod in obj.modifiers):
        return None
    group = None
    for vertex in obj.data.vertices:
        assigned = [g for g in vertex.groups if g.weight>1e-6]
        if len(assigned)!=1 or abs(assigned[0].weight-1)>1e-6:
            return None
        if group is None:
            group = assigned[0].group
        elif group!=assigned[0].group:
            return None
    if group is None:
        return None
    name = obj.vertex_groups[group].name
    return name if name in rig.pose.bones else None


def create_regions(solver, exercise, catalog):
    solver.reset()
    created = []
    for region in catalog[exercise]['regions']:
        source = bpy.data.objects['Boxers' if region['id']=='glutes' else 'Man']
        def mask(co, key, source=source, region=region):
            world = (source.matrix_world@co-Vector((0, .045, 0)))*.8
            return region_mask(world, key, region.get('side'))
        overlay(source, solver.rig, region['id'], mask)
        obj = bpy.data.objects['PULSE region '+region['id']]
        obj.matrix_world = source.matrix_world.copy()
        obj['source_surface'] = source.name
        for vertex in obj.data.vertices:
            offset = vertex.normal*.0792
            vertex.co += offset
            if obj.data.shape_keys:
                for key in obj.data.shape_keys.key_blocks:
                    key.data[vertex.index].co += offset
        created.append(obj)
    return created


def decode_accessor(doc, binary, index):
    entry = doc['accessors'][index]
    view = doc['bufferViews'][entry['bufferView']]
    if entry['componentType']!=5126 or entry['type']!='VEC3':
        raise ValueError('Expected floating XYZ vertex data')
    start = view.get('byteOffset', 0)+entry.get('byteOffset', 0)
    stride = view.get('byteStride', 12)
    return np.ndarray((entry['count'], 3), dtype='<f4', buffer=binary, offset=start, strides=(stride, 4)).copy()


def add_exact_morph_normals(path, compressed):
    """Export the same signed components for actual source Skin normals.

    Recomputing normals on a fictitious PCA target shape is nonlinear and does
    not reproduce source lighting. glTF accepts normal deltas directly.
    """
    raw = path.read_bytes(); size = struct.unpack_from('<I', raw, 12)[0]
    doc = json.loads(raw[20:20+size])
    bin_size = struct.unpack_from('<I', raw, 20+size)[0]
    binary = bytearray(raw[28+size:28+size+bin_size])
    names = {node['mesh']: node.get('name', '') for node in doc['nodes'] if 'mesh' in node}
    for index, mesh in enumerate(doc['meshes']):
        name = names.get(index, '')
        if name not in compressed:
            continue
        reference, normal_targets = compressed[name]
        tree = KDTree(len(reference))
        for i, co in enumerate(reference):
            tree.insert(co, i)
        tree.balance()
        for primitive in mesh['primitives']:
            positions = decode_accessor(doc, binary, primitive['attributes']['POSITION'])
            world = positions[:, [0, 2, 1]].copy(); world[:, 1] *= -1
            mapping = [tree.find(co)[1] for co in world]
            if len(primitive.get('targets', []))!=len(normal_targets):
                raise RuntimeError('Morph target count changed during export')
            for target, delta in zip(primitive['targets'], normal_targets):
                gltf = delta[mapping][:, [0, 2, 1]].copy(); gltf[:, 2] *= -1
                payload = gltf.astype('<f4').tobytes()
                binary += b'\x00'*((-len(binary))%4)
                view = len(doc['bufferViews'])
                doc['bufferViews'].append({'buffer': 0, 'byteOffset': len(binary), 'byteLength': len(payload), 'target': 34962})
                binary += payload
                accessor = len(doc['accessors'])
                doc['accessors'].append({'bufferView': view, 'componentType': 5126, 'count': len(gltf), 'type': 'VEC3'})
                target['NORMAL'] = accessor
    for material in doc.get('materials', []):
        if material.get('name', '').startswith('PULSE Muscle '):
            material['name'] = re.sub(r'\.\d{3}$', '', material['name'])
    doc['buffers'][0]['byteLength'] = len(binary)
    encoded = json.dumps(doc, separators=(',', ':')).encode()
    encoded += b' '*((-len(encoded))%4)
    binary += b'\x00'*((-len(binary))%4)
    path.write_bytes(struct.pack('<III', 0x46546c67, 2, 28+len(encoded)+len(binary))+
                     struct.pack('<II', len(encoded), 0x4e4f534a)+encoded+
                     struct.pack('<II', len(binary), 0x004e4942)+binary)


def author_source(solver, exercise):
    rig = solver.rig; rig.animation_data_clear()
    scene = bpy.context.scene
    fps = getattr(solver, '_delivery_fps', 30)
    frame_count = fps*6+1
    scene.render.fps = fps; scene.frame_start = 0; scene.frame_end = frame_count-1
    for bone in rig.pose.bones:
        bone.rotation_mode = 'QUATERNION'
    for frame in range(frame_count):
        scene.frame_set(frame)
        cached = getattr(solver, '_delivery_pose_basis', None)
        if cached is None:
            solver.pose_time(frame/fps)
        else:
            for bone in rig.pose.bones:
                bone.matrix_basis = cached[frame][bone.name]
        for bone in rig.pose.bones:
            for prop in ('location', 'rotation_quaternion', 'scale'):
                bone.keyframe_insert(prop, frame=frame)
    rig.animation_data.action.name = 'Native '+exercise
    linear(rig.animation_data.action)
    scene.frame_set(0)


def bake(solver, exercise, output, fps=30):
    sources = [obj for obj in bpy.context.scene.objects if obj.type=='MESH']
    rigid = {obj.name: rigid_bone(obj, solver.rig) for obj in sources}
    deforming = [obj for obj in sources if not rigid[obj.name]]
    frames = {obj.name: [] for obj in deforming}
    normal_frames = {obj.name: [] for obj in deforming}
    rigid_frames = {name: [] for name, bone in rigid.items() if bone}
    rigid_bounds = {}
    solver._delivery_pose_basis = []
    solver._delivery_fps = fps
    frame_count = fps*6+1
    for bone in solver.rig.pose.bones:
        bone.rotation_mode = 'QUATERNION'
    targets = []
    for frame in range(frame_count):
        diagnostic = solver.pose_time(frame/fps)
        targets.append(diagnostic)
        solver._delivery_pose_basis.append({bone.name: bone.matrix_basis.copy() for bone in solver.rig.pose.bones})
        for obj in deforming:
            frames[obj.name].append(points(obj))
            normal_frames[obj.name].append(normals(obj))
        for name, bone in rigid.items():
            if bone:
                rigid_frames[name].append((solver.rig.matrix_world@solver.rig.pose.bones[bone].matrix).copy())
                if frame==0:
                    xyz = points(bpy.data.objects[name])
                    low, high = xyz.min(axis=0), xyz.max(axis=0)
                    rigid_bounds[name] = [Vector((x, y, z)) for x in (low[0], high[0])
                                          for y in (low[1], high[1]) for z in (low[2], high[2])]
    all_bounds = [np.concatenate(frame_points) for name, frame_points in frames.items()
                  if not name.startswith('PULSE region ')]
    for name, transforms in rigid_frames.items():
        reference = transforms[0].inverted()
        all_bounds.append(np.array([list((transform@reference)@corner)
                                   for transform in transforms for corner in rigid_bounds[name]]))
    world = np.concatenate(all_bounds)
    bounds = {'min': world.min(axis=0).tolist(), 'max': world.max(axis=0).tolist()}
    solver.pose_time(0)
    deps = bpy.context.evaluated_depsgraph_get()
    baked = []; normal_targets = {}; errors = {}; ranks = {}
    for source in sources:
        mesh = bpy.data.meshes.new_from_object(source.evaluated_get(deps), preserve_all_data_layers=True, depsgraph=deps)
        mesh.transform(source.matrix_world)
        obj = bpy.data.objects.new('Web '+source.name, mesh)
        bpy.context.collection.objects.link(obj); baked.append(obj)
        if rigid[source.name]:
            reference = rigid_frames[source.name][0].inverted()
            obj.rotation_mode = 'QUATERNION'
            for frame, transform in enumerate(rigid_frames[source.name]):
                obj.matrix_world = transform@reference
                for prop in ('location', 'rotation_quaternion', 'scale'):
                    obj.keyframe_insert(prop, frame=frame)
            obj.animation_data.action.name = 'Exercise'; linear(obj.animation_data.action)
            ranks[source.name] = 0; errors[source.name] = 0.
            continue
        xyz = np.array(frames[source.name], dtype=np.float32)
        ns = np.array(normal_frames[source.name], dtype=np.float32)
        packed = np.concatenate((xyz, ns*NORMAL_SCALE), axis=1)
        delta, weights, error = compress_frames(packed, .00015)
        delta, weights = unsigned_components(delta, weights)
        errors[source.name] = error; ranks[source.name] = len(delta)
        if not len(delta):
            continue
        vertex_count = xyz.shape[1]
        obj.shape_key_add(name='Basis')
        for i, positions in enumerate(delta[:, :vertex_count]):
            key = obj.shape_key_add(name='Native component '+str(i))
            key.slider_min = 0; key.slider_max = 1
            key.data.foreach_set('co', (xyz[0]+positions).ravel())
            for frame in range(frame_count):
                key.value = float(weights[frame, i])
                key.keyframe_insert('value', frame=frame)
        action = obj.data.shape_keys.animation_data.action
        action.name = 'Exercise'; linear(action)
        normal_targets[obj.name] = (xyz[0], delta[:, vertex_count:]/NORMAL_SCALE)
    scene = bpy.context.scene
    scene.render.fps = fps; scene.frame_start = 0; scene.frame_end = frame_count-1; scene.frame_set(0)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in baked:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = baked[0]
    path = output/(exercise+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB', use_selection=True,
        export_animations=True, export_animation_mode='ACTIVE_ACTIONS', export_nla_strips_merged_animation_name='Exercise',
        export_force_sampling=True, export_frame_range=True, export_optimize_animation_size=False,
        export_morph=True, export_morph_normal=False, export_morph_tangent=False,
        export_try_sparse_sk=True, export_yup=True, export_skins=False)
    patch_glb(path); add_exact_morph_normals(path, normal_targets)
    for obj in baked:
        bpy.data.objects.remove(obj, do_unlink=True)
    return {'glb_bytes': path.stat().st_size, 'glb_sha256': sha(path), 'native_bones': 81, 'fps': fps,
            'native_influences_used': 8, 'runtime': 'baked_mesh_morph_animation',
            'compression_max_error_m': errors, 'morph_components': ranks,
            'timeTargets': targets, 'world_bounds': bounds}


def render_preview(solver, exercise, output, bounds):
    for obj in list(bpy.context.scene.objects):
        if obj.type in ('LIGHT', 'CAMERA'):
            bpy.data.objects.remove(obj, do_unlink=True)
    centre = (Vector(bounds['min'])+Vector(bounds['max']))*.5
    extent = Vector(bounds['max'])-Vector(bounds['min'])
    floor = json.loads((ROOT/'assets/muscles/catalog.json').read_text())['exercises'][exercise]['camera']['floor']
    direction = Vector((1, -1, .75)) if floor else Vector((0, -1, .12))
    bpy.ops.object.camera_add(location=centre+direction*5)
    cam = bpy.context.object
    cam.rotation_euler = (centre-cam.location).to_track_quat('-Z', 'Y').to_euler()
    cam.data.type = 'ORTHO'; cam.data.ortho_scale = max(extent.z, extent.y if floor else extent.x, 1)*1.18
    scene = bpy.context.scene; scene.camera = cam
    for loc, power in [((-3, -4, 4), 450), ((3, -2, 3), 350), ((1, 2, 4), 450)]:
        bpy.ops.object.light_add(type='AREA', location=loc)
        lamp = bpy.context.object; lamp.data.energy = power; lamp.data.size = 4
        lamp.rotation_euler = (centre-lamp.location).to_track_quat('-Z', 'Y').to_euler()
    scene.render.engine = 'CYCLES'; scene.cycles.samples = 24; scene.cycles.use_denoising = True
    scene.render.resolution_x = 600; scene.render.resolution_y = 700; scene.render.resolution_percentage = 100
    scene.render.film_transparent = True; scene.render.image_settings.file_format = 'PNG'
    scene.view_settings.view_transform = 'AgX'
    if scene.world is None:
        scene.world = bpy.data.worlds.new('Native review world')
    scene.world.color = (.12, .12, .12)
    for obj in bpy.context.scene.objects:
        if obj.name.startswith('PULSE region '):
            obj.hide_render = True
    scene.render.filepath = str(output/(exercise+'-preview.png'))
    bpy.ops.render.render(write_still=True)
    for obj in bpy.context.scene.objects:
        if obj.name.startswith('PULSE region '):
            obj.hide_render = False


def approved(output, report):
    folder = ROOT/'.build/original-rig/native-review-02'
    data = json.loads((folder/'build-report.json').read_text())
    from squat_sample import depth_at
    for exercise in ('shoulder_press', 'curl'):
        entry = data['exercises'][exercise].copy()
        for suffix in ('.glb', '-native-source.blend'):
            shutil.copy2(folder/(exercise+suffix), output/(exercise+suffix))
        shutil.copy2(folder/(exercise+'-top.png'), output/(exercise+'-preview.png'))
        samples = entry['targets']; steps = entry['pose_steps']; time_targets = []
        for frame in range(181):
            d = depth_at(frame/30)*steps; lo = int(d); hi = min(steps, lo+1); fraction = d-lo
            time_targets.append({side: {key: [a+(b-a)*fraction for a, b in zip(samples[lo][side][key], samples[hi][side][key])]
                for key in ('shoulder', 'elbow', 'wrist', 'grip_center')} for side in ('L', 'R')})
        bpy.ops.wm.open_mainfile(filepath=str(output/(exercise+'-native-source.blend')), use_scripts=False)
        world = []
        for frame in range(0, 181, 3):
            bpy.context.scene.frame_set(frame); world.append(points(bpy.data.objects['Man']))
        xyz = np.concatenate(world)
        entry.update(timeTargets=time_targets, world_bounds={'min': xyz.min(axis=0).tolist(), 'max': xyz.max(axis=0).tolist()},
                     preserved_approved_sample=True, native_bones=81, source_skin_fingerprint=report['source_skin_fingerprint'])
        entry['artifact_hashes'] = {'glb': sha(output/(exercise+'.glb')), 'source': sha(output/(exercise+'-native-source.blend'))}
        report['exercises'][exercise] = entry


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output-dir', required=True, type=Path)
    parser.add_argument('--exercises', nargs='*')
    parser.add_argument('--no-render', action='store_true')
    parser.add_argument('--fps', type=int, choices=(30,60,90,180), default=30)
    parser.add_argument('--replace', action='store_true')
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    output = args.output_dir.resolve(); output.mkdir(parents=True, exist_ok=True)
    source = ROOT/'.build/original-rig/native-import-04/original-rig-staging.blend'
    bpy.ops.wm.open_mainfile(filepath=str(source), use_scripts=False)
    expected = fingerprint(bpy.data.objects['Man'])
    report_path = output/'build-report.json'
    report = json.loads(report_path.read_text()) if report_path.exists() else {
        'source': str(source), 'source_skin_fingerprint': expected, 'bones': 81, 'exercises': {}, 'ready_for_production': False}
    if report['source_skin_fingerprint']!=expected:
        raise RuntimeError('Build resume uses a different source Skin')
    if not all(e in report['exercises'] for e in ('shoulder_press', 'curl')):
        approved(output, report); write_report(report_path, report)
    from native_motion import NativeMotion
    catalog = json.loads((ROOT/'assets/muscles/catalog.json').read_text())['exercises']
    for exercise in args.exercises or IDS:
        if exercise in ('shoulder_press','curl'):
            continue
        if exercise in report['exercises'] and not args.replace:
            continue
        bpy.ops.wm.open_mainfile(filepath=str(source), use_scripts=False); bpy.context.scene.frame_set(0)
        solver = NativeMotion(bpy.data.objects['Armature'], exercise)
        for obj in bpy.context.scene.objects:
            obj.animation_data_clear()
        prepare(output); solver.equipment()
        solver.rig['native_reference_world_json'] = json.dumps({n: [list(row) for row in m] for n, m in solver.reference.items()})
        create_regions(solver, exercise, catalog)
        entry = bake(solver, exercise, output, args.fps)
        solver.pose_time(0)
        author_source(solver, exercise)
        path = output/(exercise+'-native-source.blend')
        bpy.ops.wm.save_as_mainfile(filepath=str(path))
        if fingerprint(bpy.data.objects['Man'])!=expected:
            raise RuntimeError('Original Skin changed: '+exercise)
        entry['source_skin_fingerprint'] = expected; entry['source_weights_unchanged'] = True
        entry['artifact_hashes'] = {'glb': sha(output/(exercise+'.glb')), 'source': sha(path)}
        if not args.no_render:
            bpy.context.scene.frame_set(int(3.2*args.fps)); render_preview(solver, exercise, output, entry['world_bounds'])
        report['exercises'][exercise] = entry
        write_report(report_path, report)
        print('NATIVE_LIBRARY_READY', exercise, entry['glb_bytes'], flush=True)
    print('NATIVE_LIBRARY_BUILD_COUNT', len(report['exercises']), flush=True)


if __name__ == '__main__':
    main()
