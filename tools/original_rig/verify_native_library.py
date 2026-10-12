"""Independent native Skin / delivered mesh verification, run inside Blender.

The runtime intentionally has no skin: every original influence is evaluated
in the editable 81-bone source, then baked to mesh morphs. Inspecting JOINTS_0
on that delivery would therefore measure the wrong contract. Passing proves
the checks below, never motion capture, anatomy, or coach certification.
"""
import argparse
import hashlib
import json
import math
import struct
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
THRESHOLDS = {'roundtrip_error_m': .0005, 'loop_gap_m': .0006,
              'floor_penetration_m': .0025, 'support_gap_m': .006,
              'support_drift_m': .002, 'chain_absolute_error_m': .0005,
              'chain_relative_error': .002, 'handle_penetration_m': .001,
              'plate_penetration_m': .001}
APPROVED = ('shoulder_press', 'curl')


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def json_safe(value):
    if isinstance(value, float) and not math.isfinite(value):
        return None
    if isinstance(value, dict):
        return {k: json_safe(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [json_safe(v) for v in value]
    return value


def read_glb(path):
    raw = path.read_bytes()
    if len(raw) < 20 or struct.unpack_from('<III', raw) != (0x46546c67, 2, len(raw)):
        raise ValueError('Invalid GLB header')
    doc = None
    binary = b''
    offset = 12
    while offset < len(raw):
        size, kind = struct.unpack_from('<II', raw, offset)
        chunk = raw[offset+8:offset+8+size]
        if len(chunk) != size:
            raise ValueError('Truncated GLB chunk')
        if kind == 0x4e4f534a:
            doc = json.loads(chunk)
        elif kind == 0x004e4942:
            binary = chunk
        offset += size+8
    if doc is None:
        raise ValueError('Missing GLB JSON')
    return doc, binary


def time_values(doc, binary, index):
    accessor = doc['accessors'][index]
    if accessor['componentType'] != 5126 or accessor['type'] != 'SCALAR' or 'sparse' in accessor:
        raise ValueError('Animation time accessor must be ordinary float scalars')
    view = doc['bufferViews'][accessor['bufferView']]
    if view.get('buffer', 0) != 0:
        raise ValueError('External animation time buffer')
    offset = view.get('byteOffset', 0)+accessor.get('byteOffset', 0)
    stride = view.get('byteStride', 4)
    return [struct.unpack_from('<f', binary, offset+i*stride)[0] for i in range(accessor['count'])]


def glb_contract(doc, binary, regions):
    errors = []
    clips = doc.get('animations', [])
    duration = None
    if len(clips) != 1 or clips[0].get('name') != 'Exercise':
        errors.append({'code': 'exercise_animation_required'})
    else:
        clip = clips[0]
        if not clip.get('channels') or not clip.get('samplers'):
            errors.append({'code': 'empty_animation'})
        if any(s.get('interpolation', 'LINEAR') != 'LINEAR' for s in clip.get('samplers', [])):
            errors.append({'code': 'nonlinear_runtime_animation'})
        durations = []
        for index in sorted({s['input'] for s in clip.get('samplers', [])}):
            try:
                values = time_values(doc, binary, index)
                valid = (len(values) >= 2 and all(math.isfinite(t) for t in values)
                         and all(a < b for a, b in zip(values, values[1:])))
                if not valid:
                    errors.append({'code': 'invalid_animation_times', 'accessor': index})
                    continue
                durations.append(values[-1]-values[0])
                if abs(values[0]) > .00001 or abs(values[-1]-6.) > .00001:
                    errors.append({'code': 'animation_duration', 'start': values[0], 'end': values[-1]})
            except (KeyError, IndexError, ValueError, struct.error) as exc:
                errors.append({'code': 'invalid_animation_times', 'detail': str(exc)})
        if durations:
            duration = max(durations)
    used = {p.get('material') for mesh in doc.get('meshes', []) for p in mesh.get('primitives', [])}
    names = {m.get('name') for i, m in enumerate(doc.get('materials', [])) if i in used}
    missing = sorted({'PULSE Muscle '+r for r in regions}-names)
    if missing:
        errors.append({'code': 'missing_region_materials', 'names': missing})
    return {'passed': not errors, 'errors': errors, 'duration_seconds': duration,
            'runtime_skin_count': len(doc.get('skins', [])),
            'used_region_materials': sorted(n for n in names if n and n.startswith('PULSE Muscle '))}


def skin_contract(observed, baseline):
    errors = []
    if len(observed['bone_names']) != 81 or observed['bone_names'] != baseline['bone_names']:
        errors.append({'code': 'native_bones_changed'})
    if observed['bind_fingerprint'] != baseline['bind_fingerprint']:
        errors.append({'code': 'native_bind_changed'})
    if (observed['weight_fingerprint'] != baseline['weight_fingerprint']
            or observed['group_names'] != baseline['group_names']
            or observed['vertices'] != baseline['vertices']):
        errors.append({'code': 'source_weights_changed'})
    if observed['max_influences'] != baseline['max_influences']:
        errors.append({'code': 'original_influences_changed'})
    if observed['armature_modifiers'] != 1 or observed['invalid_weight_vertices']:
        errors.append({'code': 'invalid_source_skin'})
    return {**observed, 'weights_unchanged': not any(e['code'] == 'source_weights_changed' for e in errors),
            'passed': not errors, 'errors': errors}


def library_contract(entries, ids):
    missing = sorted(set(ids)-set(entries))
    unexpected = sorted(set(entries)-set(ids))
    failed = sorted(e for e, record in entries.items() if record.get('passed') is not True)
    return {'passed': not missing and not unexpected and not failed,
            'expected_exercises': len(ids), 'verified_exercises': len(entries),
            'missing_exercises': missing, 'unexpected_exercises': unexpected, 'failed_exercises': failed}


def equipment_contract(exercise, dumbbell_sides, has_support):
    expected = []
    if exercise in ('row', 'curl', 'floor_press', 'shoulder_press', 'lateral_raise', 'reverse_fly', 'romanian_deadlift'):
        expected = ['L', 'R']
    elif exercise == 'single_arm_row':
        expected = ['R']
    errors = []
    if sorted(dumbbell_sides) != expected:
        errors.append({'code': 'wrong_native_dumbbells', 'expected_sides': expected, 'actual_sides': dumbbell_sides})
    if exercise in ('incline_pushup', 'single_arm_row') and not has_support:
        errors.append({'code': 'missing_support_equipment'})
    return {'passed': not errors, 'errors': errors}


def grip_contract(observed):
    errors = []
    if (abs(observed['handle_diameter_m']-.028) > .0005
            or abs(observed['handle_length_m']-.165) > .0005
            or abs(observed['plate_radius_m']-.06375) > .0005):
        errors.append({'code': 'wrong_dumbbell_dimensions'})
    if observed['grip_center_error_m'] > .0005:
        errors.append({'code': 'dumbbell_attachment_shift'})
    if not observed['handle_samples'] or observed['max_handle_penetration_m'] > THRESHOLDS['handle_penetration_m']:
        errors.append({'code': 'hand_handle_penetration'})
    if observed['max_plate_penetration_m'] > THRESHOLDS['plate_penetration_m']:
        errors.append({'code': 'hand_plate_penetration'})
    return {'passed': not errors, 'errors': errors}


def overlay_weight_contract(body_rows, overlay_rows):
    mismatch = []
    for i, (a, b) in enumerate(zip(body_rows, overlay_rows)):
        if set(a) != set(b) or any(abs(a[n]-b[n]) > .000001 for n in a if n in b):
            mismatch.append(i)
    if len(body_rows) != len(overlay_rows):
        mismatch.append(min(len(body_rows), len(overlay_rows)))
    return {'passed': not mismatch, 'mismatched_vertices': len(mismatch), 'first': mismatch[:10]}


def ordered_surface_mapping(candidates):
    """Recover the overlay helper's sorted source subset without using weights.

    The 0.8 mm normal offset can make a neighboring garment seam vertex closer
    than the true source. Minimize distance subject to the original vertex order
    so that this ambiguity cannot silently select a different weight row.
    """
    states = {-1: (0., None)}
    history = []
    for choices in candidates:
        current = {}
        for index, distance in choices:
            possible = [(cost, previous) for previous, (cost, _) in states.items() if previous < index]
            if possible:
                cost, previous = min(possible)
                current[index] = (cost+distance*distance, previous)
        if not current:
            raise ValueError('Overlay vertices do not match an ordered original surface subset')
        history.append(current)
        states = current
    cursor = min(states, key=lambda index: states[index][0])
    mapping = []
    for row in reversed(history):
        mapping.append(cursor)
        cursor = row[cursor][1]
    return list(reversed(mapping))


def audit_overlay_weights(sources, overlays, rig):
    from mathutils.kdtree import KDTree
    source_data = {}
    for name, body in sources.items():
        if body is None:
            continue
        tree = KDTree(len(body.data.vertices))
        rows = []
        for v in body.data.vertices:
            tree.insert(body.matrix_world @ v.co, v.index)
            rows.append({body.vertex_groups[g.group].name: float(g.weight) for g in v.groups})
        tree.balance()
        source_data[name] = tree, rows
    result = {}
    for overlay in overlays:
        name = overlay.get('source_surface', 'Man')
        if name not in source_data:
            result[overlay.name] = {'passed': False, 'source_surface': name, 'error': 'Unknown original source surface'}
            continue
        tree, rows = source_data[name]
        candidates = [[(i, d) for _, i, d in tree.find_range(overlay.matrix_world @ v.co, .001)]
                      for v in overlay.data.vertices]
        try:
            mapping = ordered_surface_mapping(candidates)
        except ValueError as exc:
            result[overlay.name] = {'passed': False, 'source_surface': name, 'error': str(exc)}
            continue
        observed = [{overlay.vertex_groups[g.group].name: float(g.weight) for g in v.groups}
                    for v in overlay.data.vertices]
        checked = overlay_weight_contract([rows[i] for i in mapping], observed)
        distance = max(min(d for i, d in choices if i == selected) for choices, selected in zip(candidates, mapping))
        bound = any(m.type == 'ARMATURE' and m.object == rig for m in overlay.modifiers)
        checked.update({'max_rest_surface_offset_m': distance, 'bound_to_original_rig': bound, 'source_surface': name})
        checked['passed'] &= distance <= .001 and bound
        result[overlay.name] = checked
    return result


def skin_observation(rig, body):
    rows = [[(g.group, float(g.weight)) for g in v.groups] for v in body.data.vertices]
    bind = [(b.name, b.parent.name if b.parent else None, [list(row) for row in b.matrix_local])
            for b in rig.data.bones]
    invalid = sum(not row or any(not math.isfinite(w) or w < 0 for _, w in row)
                  or abs(sum(w for _, w in row)-1) > .002 for row in rows)
    return {'bone_names': sorted(b.name for b in rig.data.bones),
            'bind_fingerprint': hashlib.sha256(json.dumps(bind, separators=(',', ':')).encode()).hexdigest(),
            'weight_fingerprint': hashlib.sha256(json.dumps(rows, separators=(',', ':')).encode()).hexdigest(),
            'group_names': [g.name for g in body.vertex_groups], 'vertices': len(rows),
            'max_influences': max((len(row) for row in rows), default=0),
            'armature_modifiers': sum(m.type == 'ARMATURE' and m.object == rig for m in body.modifiers),
            'invalid_weight_vertices': invalid}


def evaluated_points(obj, surface_only=False):
    import bpy
    import numpy as np
    evaluated = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh = evaluated.to_mesh()
    xyz = np.empty(len(mesh.vertices)*3, dtype=np.float32)
    mesh.vertices.foreach_get('co', xyz)
    xyz = xyz.reshape((-1, 3))
    if surface_only:
        indices = np.empty(len(mesh.loops), dtype=np.int32)
        mesh.loops.foreach_get('vertex_index', indices)
        xyz = xyz[np.unique(indices)]
    transform = np.asarray(evaluated.matrix_world, dtype=np.float32)
    xyz = xyz @ transform[:3, :3].T+transform[:3, 3]
    evaluated.to_mesh_clear()
    return xyz


def set_time(seconds):
    import bpy
    scene = bpy.context.scene
    frame = seconds*scene.render.fps/scene.render.fps_base
    scene.frame_set(int(frame), subframe=frame-int(frame))


def capture_times(fps):
    """Every delivery key and interval midpoint, including the loop seam."""
    frame_count = round(fps*6)
    return [i/(fps*2) for i in range(frame_count*2+1)]


def support_patches(body, neutral, origins):
    import numpy as np
    groups = {g.index: g.name for g in body.vertex_groups}
    masks = {}
    for side in ('L', 'R'):
        for part in ('Foot', 'Hand'):
            prefix = 'Man_'+side+part
            masks[part.lower()+'_'+side] = np.asarray([
                sum(g.weight for g in v.groups if groups[g.group].startswith(prefix)) > .5
                for v in body.data.vertices])
        # Heel rise rolls the foot around its toe pads. The distal toe Skin
        # is the stationary contact witness; the initial low heel is not.
        prefix = 'Man_'+side+'Foot'
        masks['forefoot_'+side] = np.asarray([
            sum(g.weight for g in v.groups if groups[g.group].startswith(prefix)
                and groups[g.group].endswith('2')) > .98
            for v in body.data.vertices])
        for part, label in [('Calf', 'knee'), ('Forearm1', 'forearm')]:
            masks[label+'_'+side] = np.linalg.norm(neutral-origins['Man_'+side+part], axis=1) < .10
    trunk = np.asarray([sum(g.weight for g in v.groups if groups[g.group].startswith(
        ('Man_Spine3', 'Man_Spine4', 'Man_Ribcage'))) > .5 for v in body.data.vertices])
    masks['back'] = trunk & (neutral[:, 1] > origins['Man_Spine3'][1])
    return masks


def contact_policy(exercise):
    fixed = ['foot_L', 'foot_R']
    if exercise == 'calf_raise':
        fixed = ['forefoot_L', 'forefoot_R']
    if exercise == 'lunge':
        fixed = ['foot_L']
    if exercise in ('jumping_jack', 'step_jack'):
        fixed = []
    if exercise == 'kneeling_pushup':
        fixed = ['knee_L', 'knee_R', 'hand_L', 'hand_R']
    elif exercise in ('pushup', 'incline_pushup'):
        fixed += ['hand_L', 'hand_R']
    elif exercise == 'plank':
        fixed += ['forearm_L', 'forearm_R']
    elif exercise == 'single_arm_row':
        fixed += ['hand_L']
    elif exercise in ('bridge', 'floor_press'):
        fixed += ['back']
    elif exercise == 'dead_bug':
        fixed = ['back']
    elif exercise == 'bird_dog':
        fixed = []
    elif exercise == 'side_plank':
        fixed = ['forearm_R', 'foot_R']
    return fixed


def hand_surface_audit(rig, body, reference):
    """Sample actual Skin triangles in the fitted handle frame, per present side."""
    import bpy
    import numpy as np
    from mathutils import Matrix
    from native_upper import GRIP_CENTER, HANDLE_RADIUS, HALF_HANDLE
    body.data.calc_loop_triangles()
    triangles = np.asarray([t.vertices[:] for t in body.data.loop_triangles])
    xyz = evaluated_points(body)
    records = {}
    for side in ('L', 'R'):
        if bpy.data.objects.get('Native dumbbell '+side) is None:
            continue
        name = 'Man_'+side+'Hand'
        wrist = reference[name].translation
        d = (reference[name+'Middle1'].translation-wrist).normalized()
        a = reference[name+'Index1'].translation-reference[name+'Pinky1'].translation
        a = (a-d*a.dot(d)).normalized()
        palm = Matrix((a, d, a.cross(d)*(-1 if side == 'L' else 1))).transposed()
        hand = rig.matrix_world @ rig.pose.bones[name].matrix
        delta = hand.to_quaternion() @ reference[name].to_quaternion().inverted()
        frame = delta.to_matrix() @ palm
        local = (xyz-np.asarray(hand.translation)) @ np.asarray(frame.inverted()).T
        group_ids = {g.index for g in body.vertex_groups if g.name.startswith(name)}
        mask = np.asarray([sum(g.weight for g in v.groups if g.group in group_ids) > .5
                           for v in body.data.vertices])
        tris = local[triangles[mask[triangles].any(axis=1)]]
        surface = np.concatenate([local[mask], tris.mean(axis=1), (tris[:, 0]+tris[:, 1])*.5,
                                  (tris[:, 1]+tris[:, 2])*.5, (tris[:, 2]+tris[:, 0])*.5])
        radial = np.linalg.norm(surface[:, 1:3]-np.asarray(GRIP_CENTER)[1:3], axis=1)
        handle = radial[np.abs(surface[:, 0]-GRIP_CENTER.x) < HALF_HANDLE]
        plates = [np.maximum(0, np.minimum(.0225-np.abs(surface[:, 0]-x), .06375-radial))
                  for x in (-.10375, .10375)]
        equipment = bpy.data.objects['Native dumbbell '+side]
        equipment_local = (evaluated_points(equipment)-np.asarray(hand.translation)) @ np.asarray(frame.inverted()).T
        steel = {i for i, m in enumerate(equipment.data.materials) if m.name.startswith('Native grip steel')}
        handle_ids = sorted({v for p in equipment.data.polygons if p.material_index in steel for v in p.vertices})
        handle_xyz = equipment_local[handle_ids]
        centre = (equipment_local.min(axis=0)+equipment_local.max(axis=0))*.5
        records[side] = {'surface_samples': len(surface), 'handle_samples': len(handle),
                         'max_handle_penetration_m': float(max(0., HANDLE_RADIUS-handle.min())) if len(handle) else None,
                         'max_plate_penetration_m': float(max(p.max() for p in plates)),
                         'handle_diameter_m': float(np.linalg.norm(handle_xyz[:, 1:3]-centre[1:3], axis=1).max()*2),
                         'handle_length_m': float(np.ptp(handle_xyz[:, 0])),
                         'plate_radius_m': float(np.linalg.norm(equipment_local[:, 1:3]-centre[1:3], axis=1).max()),
                         'grip_center_error_m': float(np.linalg.norm(centre-np.asarray(GRIP_CENTER)))}
    return records


def animation_key_range(rig):
    action = rig.animation_data.action if rig.animation_data else None
    values = []
    if action:
        for layer in action.layers:
            for strip in layer.strips:
                for slot in action.slots:
                    bag = strip.channelbag(slot)
                    if bag:
                        values += [float(k.co.x) for fc in bag.fcurves for k in fc.keyframe_points]
    return [min(values), max(values)] if values else None


def audit_source(exercise, path, baseline, neutral, origins, capture_times):
    import bpy
    import numpy as np
    from mathutils import Matrix
    bpy.ops.wm.open_mainfile(filepath=str(path), use_scripts=False)
    rig = bpy.data.objects['Armature']
    body = bpy.data.objects['Man']
    skin = skin_contract(skin_observation(rig, body), baseline)
    errors = list(skin['errors'])
    clothes = bpy.data.objects.get('Boxers')
    clothes_skin = skin_contract(skin_observation(rig, clothes), baseline['clothes']) if clothes else None
    if clothes_skin is None or not clothes_skin['passed']:
        errors.append({'code': 'original_clothing_skin_changed', 'detail': clothes_skin})
    scene = bpy.context.scene
    key_range = animation_key_range(rig)
    seconds = None if key_range is None else (key_range[1]-key_range[0])*scene.render.fps_base/scene.render.fps
    if seconds is None or abs(seconds-6.) > .00001 or key_range[0] != 0:
        errors.append({'code': 'source_animation_duration', 'key_range': key_range, 'seconds': seconds})
    reference = {name: Matrix(m) for name, m in json.loads(rig['native_reference_world_json']).items()}
    reference_error = max(float(np.abs(np.asarray(reference[n])-matrix).max())
                          for n, matrix in baseline['reference_world'].items())
    if set(reference) != set(baseline['reference_world']) or reference_error > .00001:
        errors.append({'code': 'native_reference_changed', 'max_matrix_error': reference_error})
    pairs = [(b.parent.name, b.name) for b in rig.data.bones if b.parent]
    lengths = {pair: float(np.linalg.norm(origins[pair[1]]-origins[pair[0]])) for pair in pairs}
    patches = support_patches(body, neutral, origins)
    fixed = contact_policy(exercise)
    contacts = {name: [] for name in fixed}
    anchors = {}
    drift = 0.
    minimum = math.inf
    chain_absolute = chain_relative = loop = 0.
    chain_worst = None
    first_body = first_bones = None
    surface = {}
    equipment = [o.name for o in scene.objects if o.type == 'MESH' and o.name.startswith(
        ('Native dumbbell', 'Native support', 'PULSE support'))]
    top = bpy.data.objects.get('Native support top') or bpy.data.objects.get('PULSE support top')
    top_points = evaluated_points(top) if top else None
    support_height = None if top is None else float(top_points[:, 2].max())
    equipment_check = equipment_contract(exercise, [n[-1] for n in equipment if n.startswith('Native dumbbell')], top is not None)
    errors.extend(equipment_check['errors'])
    support_misses = 0
    support_penetration = 0.
    frame_count = scene.frame_end+1
    fps = scene.render.fps/scene.render.fps_base
    for frame in range(frame_count):
        scene.frame_set(frame)
        positions = {n: np.asarray((rig.matrix_world @ p.matrix).translation)
                     for n, p in rig.pose.bones.items()}
        matrices = np.asarray([np.asarray(rig.matrix_world @ p.matrix) for p in rig.pose.bones])
        if not np.isfinite(matrices).all():
            errors.append({'code': 'nonfinite_native_pose', 'frame': frame})
            break
        for pair, expected in lengths.items():
            absolute = abs(float(np.linalg.norm(positions[pair[1]]-positions[pair[0]]))-expected)
            relative = absolute/expected if expected > 1e-6 else 0.
            if absolute > chain_absolute:
                chain_absolute, chain_worst = absolute, {'pair': pair, 'frame': frame, 'reference_length_m': expected}
            chain_relative = max(chain_relative, relative)
            if absolute > THRESHOLDS['chain_absolute_error_m']+expected*THRESHOLDS['chain_relative_error']:
                if not any(e['code'] == 'native_chain_length_changed' for e in errors):
                    errors.append({'code': 'native_chain_length_changed', 'pair': pair, 'frame': frame, 'error_m': absolute})
        xyz = evaluated_points(body)
        if not np.isfinite(xyz).all():
            errors.append({'code': 'nonfinite_native_skin', 'frame': frame})
            break
        minimum = min(minimum, float(xyz[:, 2].min()))
        if top is not None:
            inside = ((xyz[:, :2] > top_points[:, :2].min(axis=0)+.004)
                      & (xyz[:, :2] < top_points[:, :2].max(axis=0)-.004)).all(axis=1)
            inside &= (xyz[:, 2] > top_points[:, 2].min()) & (xyz[:, 2] < support_height)
            if inside.any():
                support_penetration = max(support_penetration, float(support_height-xyz[inside, 2].min()))
        if first_body is None:
            first_body, first_bones = xyz.copy(), positions
        if frame == frame_count-1:
            loop = max(float(np.linalg.norm(xyz-first_body, axis=1).max()),
                       max(float(np.linalg.norm(positions[n]-first_bones[n])) for n in positions))
        for name in fixed:
            patch = xyz[patches[name]]
            if not len(patch):
                errors.append({'code': 'empty_support_patch', 'patch': name})
                continue
            height = support_height if top is not None and name.startswith('hand') else 0.
            if height:
                inside = ((patch[:, :2] >= top_points[:, :2].min(axis=0)-.002)
                          & (patch[:, :2] <= top_points[:, :2].max(axis=0)+.002)).all(axis=1)
                if not inside.any():
                    support_misses += 1
                    continue
                patch = patch[inside]
            contacts[name].append(float(patch[:, 2].min())-height)
            # Contact witnesses follow only the initial near-surface vertices;
            # knee flexion and forefoot pivoting do not imply a planted foot slide.
            if frame == 0:
                ids = np.where(patches[name])[0]
                low = xyz[ids, 2].min()
                ids = ids[xyz[ids, 2] < low+.003]
                anchors[name] = (ids, xyz[ids].copy())
            ids, initial = anchors[name]
            if name not in ('back', 'knee_L', 'knee_R'):
                drift = max(drift, float(np.linalg.norm(xyz[ids, :2]-initial[:, :2], axis=1).max()))
        if exercise == 'step_jack' and min(float(xyz[patches['foot_'+s], 2].min()) for s in ('L', 'R')) > .006:
            errors.append({'code': 'step_jack_both_feet_airborne', 'frame': frame})
        if exercise == 'bird_dog':
            heights = {part+'_'+s: float(xyz[patches[part+'_'+s], 2].min())
                       for part in ('hand', 'knee') for s in ('L', 'R')}
            if min(max(heights['hand_L'], heights['knee_R']), max(heights['hand_R'], heights['knee_L'])) > .006:
                errors.append({'code': 'bird_dog_supports_lifted', 'frame': frame})
        if frame % max(1, round(fps/5)) == 0 or frame == frame_count-1:
            checked = hand_surface_audit(rig, body, reference)
            if checked:
                surface[str(frame/fps)] = checked
    if minimum < -THRESHOLDS['floor_penetration_m']:
        errors.append({'code': 'skin_below_floor', 'minimum_m': minimum})
    if loop > THRESHOLDS['loop_gap_m']:
        errors.append({'code': 'source_loop_gap', 'gap_m': loop})
    for name, values in contacts.items():
        if not values or max(values) > THRESHOLDS['support_gap_m']:
            errors.append({'code': 'support_lifted', 'patch': name, 'maximum_gap_m': max(values) if values else None})
    if support_misses:
        errors.append({'code': 'hand_misses_support', 'frames': support_misses})
    if support_penetration > THRESHOLDS['floor_penetration_m']:
        errors.append({'code': 'skin_penetrates_support', 'maximum_m': support_penetration})
    if drift > THRESHOLDS['support_drift_m']:
        errors.append({'code': 'support_surface_slide', 'maximum_m': drift})
    for t, pose in surface.items():
        for side, record in pose.items():
            errors.extend({**error, 'time': t, 'side': side, **record} for error in grip_contract(record)['errors'])
    regions = json.loads((ROOT/'assets/muscles/catalog.json').read_text())['exercises'][exercise]['regions']
    required = list(dict.fromkeys(['Man', 'Boxers']+['PULSE region '+r['id'] for r in regions]+equipment+
                                 [o.name for o in scene.objects if o.type == 'MESH']))
    missing = [n for n in required if bpy.data.objects.get(n) is None]
    if missing:
        errors.append({'code': 'missing_source_meshes', 'names': missing})
    overlay_weights = audit_overlay_weights({'Man': body, 'Boxers': clothes}, [bpy.data.objects[n] for n in required
        if n.startswith('PULSE region ') and n not in missing], rig)
    for name, checked in overlay_weights.items():
        if not checked['passed']:
            errors.append({'code': 'overlay_skin_differs_from_body', 'name': name, **checked})
    expected = {n: [] for n in required if n not in missing}
    for t in capture_times:
        set_time(t)
        for name in expected:
            expected[name].append(evaluated_points(bpy.data.objects[name], surface_only=name != 'Man'))
    source = {'passed': not errors, 'errors': errors, 'skin': skin, 'clothing_skin': clothes_skin, 'duration_seconds': seconds,
              'native_reference_max_matrix_error': reference_error,
              'samples': frame_count, 'fps': fps, 'minimum_skin_height_m': minimum, 'loop_gap_m': loop,
              'chain_max_absolute_error_m': chain_absolute, 'chain_max_relative_error': chain_relative,
              'worst_chain': chain_worst, 'support_surface_drift_m': drift,
              'contact_height_ranges_m': {n: [min(v), max(v)] if v else None for n, v in contacts.items()},
              'support_top_height_m': support_height, 'surfaces': surface, 'equipment': equipment,
              'support_penetration_m': support_penetration, 'overlay_weights': overlay_weights}
    return source, expected


def audit_roundtrip(path, expected, times):
    import bpy
    import numpy as np
    from mathutils.kdtree import KDTree
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 30
    bpy.ops.import_scene.gltf(filepath=str(path))
    set_time(0)
    errors = []
    measured = {}
    for name, truth in expected.items():
        obj = bpy.data.objects.get('Web '+name)
        if obj is None:
            errors.append({'code': 'missing_delivered_mesh', 'name': name})
            continue
        initial = evaluated_points(obj, surface_only=name != 'Man')
        tree = KDTree(len(truth[0]))
        for i, co in enumerate(truth[0]):
            tree.insert(co, i)
        tree.balance()
        mapping = np.asarray([tree.find(co)[1] for co in initial])
        imported_tree = KDTree(len(initial))
        for i, co in enumerate(initial):
            imported_tree.insert(co, i)
        imported_tree.balance()
        reverse_mapping = np.asarray([imported_tree.find(co)[1] for co in truth[0]])
        # glTF may duplicate UV/material seam vertices; a nearest-source mapping
        # is acceptable only when every imported vertex passes every sampled pose.
        maximum = 0.
        loop = 0.
        first = None
        for t, native in zip(times, truth):
            set_time(t)
            xyz = evaluated_points(obj, surface_only=name != 'Man')
            if not np.isfinite(xyz).all() or len(xyz) != len(mapping):
                errors.append({'code': 'invalid_delivered_geometry', 'name': name, 'time': t})
                maximum = math.inf
                break
            difference = max(float(np.linalg.norm(xyz-native[mapping], axis=1).max()),
                             float(np.linalg.norm(xyz[reverse_mapping]-native, axis=1).max()))
            maximum = max(maximum, difference)
            if first is None:
                first = xyz.copy()
            if t == 6:
                loop = float(np.linalg.norm(xyz-first, axis=1).max())
        measured[name] = {'max_error_m': maximum, 'loop_gap_m': loop,
                          'source_vertices': len(truth[0]), 'delivered_vertices': len(initial)}
        if maximum > THRESHOLDS['roundtrip_error_m']:
            errors.append({'code': 'roundtrip_error', 'name': name, 'maximum_m': maximum})
        if loop > THRESHOLDS['loop_gap_m']:
            errors.append({'code': 'delivered_loop_gap', 'name': name, 'maximum_m': loop})
        set_time(0)
    return {'passed': not errors, 'errors': errors, 'sample_times_seconds': times, 'meshes': measured,
            'roundtrip_max_error_m': {n: v['max_error_m'] for n, v in measured.items()}}


def main():
    import bpy
    import numpy as np
    sys.path.insert(0, str(ROOT/'tools'))
    sys.path.insert(0, str(HERE))
    from motion_library import IDS
    parser = argparse.ArgumentParser()
    parser.add_argument('--input-dir', required=True, type=Path)
    parser.add_argument('--approved-dir', type=Path, default=ROOT/'.build/original-rig/native-review-02')
    parser.add_argument('--baseline-source', type=Path, default=ROOT/'.build/original-rig/native-import-04/original-rig-staging.blend')
    parser.add_argument('--exercise', choices=IDS)
    parser.add_argument('--wait-for-build', action='store_true', help='Wait for each completed build-report entry before checking its files')
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    folder = args.input_dir.resolve()
    build = json.loads((folder/'build-report.json').read_text())
    bpy.ops.wm.open_mainfile(filepath=str(args.baseline_source), use_scripts=False)
    rig, body = bpy.data.objects['Armature'], bpy.data.objects['Man']
    baseline = skin_observation(rig, body)
    baseline['clothes'] = skin_observation(rig, bpy.data.objects['Boxers'])
    baseline['reference_world'] = {n: np.asarray(rig.matrix_world @ p.matrix) for n, p in rig.pose.bones.items()}
    neutral = evaluated_points(body)
    origins = {n: np.asarray((rig.matrix_world @ p.matrix).translation) for n, p in rig.pose.bones.items()}
    report = {'schema': 'native-library-verification-v1', 'coach_review_completed': False,
              'verifier_sha256': sha256(Path(__file__)),
              'baseline_source': str(args.baseline_source.resolve()), 'baseline_source_sha256': sha256(args.baseline_source),
              'source_skin_fingerprint': baseline['weight_fingerprint'], 'thresholds': THRESHOLDS,
              'build_report_sha256': sha256(folder/'build-report.json'),
              'exercises': {}, 'passed': False}
    for exercise in ([args.exercise] if args.exercise else IDS):
        if args.wait_for_build:
            deadline = time.monotonic()+3600
            announced = False
            while True:
                try:
                    build = json.loads((folder/'build-report.json').read_text())
                    ready = exercise in build.get('exercises', {})
                except json.JSONDecodeError:
                    ready = False
                if ready:
                    break
                if not announced:
                    print('NATIVE_VERIFY_WAIT', exercise, flush=True)
                    announced = True
                if time.monotonic() > deadline:
                    raise RuntimeError('Timed out waiting for completed build: '+exercise)
                time.sleep(2)
        location = folder
        if exercise in APPROVED and not (folder/(exercise+'.glb')).exists():
            location = args.approved_dir.resolve()
        glb, source = location/(exercise+'.glb'), location/(exercise+'-native-source.blend')
        entry = {'passed': False, 'glb_path': str(glb), 'source_path': str(source), 'errors': []}
        try:
            entry['glb_sha256'], entry['source_sha256'] = sha256(glb), sha256(source)
            # Check every delivered key and every interval midpoint. Dense
            # deliveries must be audited over their full six-second timeline.
            delivery_fps = build.get('exercises', {}).get(exercise, {}).get('fps', 30)
            times = capture_times(delivery_fps)
            regions = json.loads((ROOT/'assets/muscles/catalog.json').read_text())['exercises'][exercise]['regions']
            doc, binary = read_glb(glb)
            entry['glb'] = glb_contract(doc, binary, [r['id'] for r in regions])
            entry['source'], expected = audit_source(exercise, source, baseline, neutral, origins, times)
            entry['roundtrip'] = audit_roundtrip(glb, expected, times)
            metadata = build.get('exercises', {}).get(exercise, {})
            if metadata.get('glb_sha256') and metadata['glb_sha256'] != entry['glb_sha256']:
                entry['errors'].append({'code': 'build_glb_hash_mismatch'})
            if exercise in APPROVED:
                approved = args.approved_dir/(exercise+'.glb')
                entry['approved_glb_unchanged'] = entry['glb_sha256'] == sha256(approved)
                if not entry['approved_glb_unchanged']:
                    entry['errors'].append({'code': 'approved_glb_changed'})
            entry['passed'] = not entry['errors'] and all(entry[k]['passed'] for k in ('glb', 'source', 'roundtrip'))
        except Exception as exc:
            entry['errors'].append({'code': 'verification_exception', 'detail': str(exc), 'type': type(exc).__name__})
        report['exercises'][exercise] = entry
        destination = folder/('verification-'+args.exercise+'.json' if args.exercise else 'verification.json')
        report.update(library_contract(report['exercises'], IDS))
        destination.write_text(json.dumps(json_safe(report), indent=2, ensure_ascii=False, allow_nan=False))
        print('NATIVE_VERIFY', json.dumps({'exercise': exercise, 'passed': entry['passed'],
              'errors': entry['errors'], 'source_errors': entry.get('source', {}).get('errors'),
              'roundtrip_errors': entry.get('roundtrip', {}).get('errors')}), flush=True)
    # Bind the completed aggregate to the final metadata, and refuse any source
    # or GLB that changed while earlier items were being checked.
    build = json.loads((folder/'build-report.json').read_text())
    report['build_report_sha256'] = sha256(folder/'build-report.json')
    for exercise, entry in report['exercises'].items():
        for field, path_key in [('glb_sha256', 'glb_path'), ('source_sha256', 'source_path')]:
            path = Path(entry[path_key])
            if not path.exists() or entry.get(field) != sha256(path):
                entry['errors'].append({'code': 'artifact_changed_during_verification', 'artifact': path_key})
                entry['passed'] = False
        metadata = build.get('exercises', {}).get(exercise, {})
        if metadata.get('glb_sha256') and metadata['glb_sha256'] != entry.get('glb_sha256'):
            entry['errors'].append({'code': 'final_build_glb_hash_mismatch'})
            entry['passed'] = False
    if report['baseline_source_sha256'] != sha256(args.baseline_source):
        for entry in report['exercises'].values():
            entry['errors'].append({'code': 'baseline_changed_during_verification'})
            entry['passed'] = False
    report.update(library_contract(report['exercises'], IDS))
    destination.write_text(json.dumps(json_safe(report), indent=2, ensure_ascii=False, allow_nan=False))
    selected_passed = all(v['passed'] for v in report['exercises'].values())
    if not selected_passed or (not args.exercise and not report['passed']):
        raise RuntimeError('Native library verification failed; see '+str(destination))


if __name__ == '__main__':
    main()
