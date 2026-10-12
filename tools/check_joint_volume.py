"""Independent geometric regression checks for the delivered, re-imported GLB.

Run in Blender; no authoring modules or deformation helpers are imported.
Thresholds are engineering screens fixed against the acknowledged defective
2026-09-29 review clips, not anatomical or medical specifications.
"""
import argparse
import hashlib
import json
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / '.build/joint-volume/validation'
LIMITS = {
    'elbow_area_ratio_min': .65,
    'elbow_area_ratio_max': 1.40,
    'elbow_adjacent_normalized_radius_step_max': .15,
    'shoulder_cap_min_stretch_p10_min': .30,
    'shoulder_cap_area_ratio_min': .55,
    'shoulder_cap_area_ratio_max': 1.60,
    'shoulder_cap_max_stretch_p90_max': 2.0,
    'skin_loop_gap_m_max': .0006,
    'rest_geometry_difference_m_max': .000001,
    'far_skin_difference_m_max': .001,
    'bone_head_difference_m_max': .001,
    'intersection_line_m_min': .001,
    'exposed_crossings_max': 0,
}
EXERCISES = ('curl', 'shoulder_press')
REFERENCE_SHA256 = {
    'curl': 'ba90c81f50647a05986c89330e002a89ae98a4a595039cf09f7d5414106c3c6c',
    'shoulder_press': '16d388f058080ff62651f93d16c6378a40e4a8dae117e572bcce44fe8e08f9fd',
}


def load(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 30
    bpy.ops.import_scene.gltf(filepath=str(path))
    candidates = [o for o in bpy.context.scene.objects if o.type == 'MESH' and 'upperarm_l' in o.vertex_groups and 'thigh_l' in o.vertex_groups and max(v.co.z for v in o.data.vertices)-min(v.co.z for v in o.data.vertices) > 1.2]
    assert len(candidates) == 1, 'Cannot uniquely identify full body skin'
    body = candidates[0]
    rig = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
    body.data.calc_loop_triangles()
    rest = np.array([v.co[:] for v in body.data.vertices], dtype=float)
    tris = np.array([t.vertices[:] for t in body.data.loop_triangles], dtype=int)
    return body, rig, rest, tris


def evaluated(body, frame):
    whole = int(frame)
    bpy.context.scene.frame_set(whole, subframe=frame-whole)
    bpy.context.view_layer.update()
    ev = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
    return np.array([tuple(ev.matrix_world @ v.co) for v in ev.data.vertices])


def section(rest, tris, center, normal):
    """Closed rest-surface intersection; retain edge barycentrics as witnesses."""
    distances = (rest-center) @ normal
    nodes, segments = {}, []
    dtri = distances[tris]
    for tri in tris[(dtri.min(axis=1) < 0) & (dtri.max(axis=1) > 0)]:
        cut = []
        for a, b in ((tri[0], tri[1]), (tri[1], tri[2]), (tri[2], tri[0])):
            if distances[a] * distances[b] < 0:
                t = float(distances[a] / (distances[a]-distances[b]))
                point = rest[a]*(1-t) + rest[b]*t
                key = tuple(np.round(point, 6))
                nodes[key] = (int(a), int(b), t)
                cut.append(key)
        if len(cut) == 2:
            segments.append(cut)
    adjacent = {}
    for a, b in segments:
        adjacent.setdefault(a, []).append(b)
        adjacent.setdefault(b, []).append(a)
    loops = []
    while adjacent:
        first = next(iter(adjacent))
        current, previous, loop = first, None, []
        while current in adjacent:
            loop.append(current)
            choices = [n for n in adjacent[current] if n != previous]
            del adjacent[current]
            if not choices:
                break
            previous, current = current, choices[0]
            if current == first:
                break
        if len(loop) > 5 and current == first:
            loops.append(loop)
    if not loops:
        raise ValueError('No closed material section')
    loop = min(loops, key=lambda x: np.linalg.norm(np.array(x).mean(axis=0)-center))
    if np.linalg.norm(np.array(loop).mean(axis=0)-center) > .1:
        raise ValueError('Section selected another body part')
    return np.array([nodes[k] for k in loop])


def ring_points(vertices, ring):
    t = ring[:, 2, None]
    return vertices[ring[:, 0].astype(int)]*(1-t) + vertices[ring[:, 1].astype(int)]*t


def polygon_area(points):
    centered = points-points.mean(axis=0)
    # Magnitude of polygon vector area: orientation-independent, allows bend.
    return float(np.linalg.norm(np.cross(centered, np.roll(centered, -1, axis=0)).sum(axis=0))/2)


def prepare_regions(rest, tris, rig):
    centers = rest[tris].mean(axis=1)
    regions = {}
    for side in ('l', 'r'):
        for joint, name, radius in [('elbow', 'lowerarm', .12), ('shoulder', 'upperarm', .16)]:
            bone = rig.data.bones[name+'_'+side]
            center = np.array(bone.head_local[:])
            axis = np.array((bone.tail_local-bone.head_local).normalized()[:])
            selected = np.where(np.linalg.norm(centers-center, axis=1) < radius)[0]
            region = {'triangles': selected, 'center': center}
            if joint == 'elbow':
                region['rings'] = [section(rest, tris, center+axis*x, axis) for x in np.linspace(-.06, .06, 13)]
                region['rest_areas'] = np.array([polygon_area(ring_points(rest, ring)) for ring in region['rings']])
                # Posterior elbow cap, outside the anterior flexion crease.
                region['exposed'] = set(np.where((np.linalg.norm(centers-center, axis=1) < .09) & (centers[:, 1]-center[1] > .015))[0])
            else:
                sign = 1 if side == 'l' else -1
                outward = np.array([-axis[2]*sign, 0, abs(axis[0])])
                outward /= np.linalg.norm(outward)
                cap = np.where((np.linalg.norm(centers-center, axis=1) < .105) & ((centers-center)@outward > .025) & (abs((centers-center)@axis) < .075))[0]
                region['cap'] = cap
                region['exposed'] = set(cap)
                p = rest[tris[cap]]
                e0, e1 = p[:, 1]-p[:, 0], p[:, 2]-p[:, 0]
                normal = np.cross(e0, e1)
                region['rest_cap_areas'] = np.linalg.norm(normal, axis=1)/2
                normal /= np.linalg.norm(normal, axis=1)[:, None]
                u = e0/np.linalg.norm(e0, axis=1)[:, None]
                v = np.cross(normal, u)
                uv = np.stack([np.stack([(e0*u).sum(1), (e0*v).sum(1)], 1), np.stack([(e1*u).sum(1), (e1*v).sum(1)], 1)], 2)
                region['rest_inverse'] = np.linalg.inv(uv)
            regions[joint+'_'+side] = region
    return regions


def geometry_metrics(vertices, tris, region, joint):
    if joint == 'elbow':
        ratios = np.array([polygon_area(ring_points(vertices, ring)) for ring in region['rings']])/region['rest_areas']
        return {'section_area_ratios': ratios.tolist(), 'area_min': float(ratios.min()), 'area_max': float(ratios.max()),
                'radius_step_max': float(abs(np.diff(np.sqrt(ratios))).max())}
    p = vertices[tris[region['cap']]]
    edges = np.stack([p[:, 1]-p[:, 0], p[:, 2]-p[:, 0]], axis=2)
    stretches = np.linalg.svd(edges@region['rest_inverse'], compute_uv=False)
    areas = np.linalg.norm(np.cross(p[:, 1]-p[:, 0], p[:, 2]-p[:, 0]), axis=1)/2
    return {'cap_area_ratio': float(areas.sum()/region['rest_cap_areas'].sum()),
            'minimum_stretch_p10': float(np.quantile(stretches[:, 1], .1)),
            'maximum_stretch_p90': float(np.quantile(stretches[:, 0], .9))}


def segment_triangle(segment, triangle):
    """Strict interior intersection, excluding grazing and coplanar contacts."""
    direction = segment[1]-segment[0]
    e1, e2 = triangle[1]-triangle[0], triangle[2]-triangle[0]
    h = np.cross(direction, e2)
    determinant = e1@h
    if abs(determinant) < 1e-12:
        return None
    inv = 1/determinant
    s = segment[0]-triangle[0]
    u = inv*(s@h)
    if not 1e-6 < u < 1-1e-6:
        return None
    q = np.cross(s, e1)
    v = inv*(direction@q)
    if v < 1e-6 or u+v > 1-1e-6:
        return None
    t = inv*(e2@q)
    if not 1e-6 < t < 1-1e-6:
        return None
    return segment[0]+t*direction


def intersections(vertices, tris, region, canonical, neighbors):
    ids = region['triangles']
    selected = tris[ids]
    tree = BVHTree.FromPolygons(vertices.tolist(), selected.tolist(), all_triangles=True)
    crossings = []
    for i, j in tree.overlap(tree):
        if i >= j or any(int(b) in neighbors[int(a)] for a in canonical[selected[i]] for b in canonical[selected[j]]):
            continue
        p, q = vertices[selected[i]], vertices[selected[j]]
        hits = []
        for a, b in ((0, 1), (1, 2), (2, 0)):
            x, y = segment_triangle(p[[a, b]], q), segment_triangle(q[[a, b]], p)
            if x is not None:
                hits.append(x)
            if y is not None:
                hits.append(y)
        if len(hits) > 1:
            length = max(float(np.linalg.norm(a-b)) for a in hits for b in hits)
            if length > LIMITS['intersection_line_m_min']:
                crossings.append({'triangles': [int(ids[i]), int(ids[j])], 'line_length_m': length,
                                  'exposed': int(ids[i]) in region['exposed'] or int(ids[j]) in region['exposed']})
    return {'pairs': crossings, 'count': len(crossings), 'exposed_count': sum(x['exposed'] for x in crossings),
            'longest_line_m': max((x['line_length_m'] for x in crossings), default=0.)}


def reference(exercise, frames):
    path = ROOT / 'web/review/quality' / (exercise+'.glb')
    assert hashlib.sha256(path.read_bytes()).hexdigest() == REFERENCE_SHA256[exercise], 'Frozen defect baseline changed'
    body, rig, rest, tris = load(path)
    bone_names = sorted(b.name for b in rig.data.bones)
    # Far-region witnesses verify the torso and legs have not moved accidentally.
    far_ids = np.where((abs(rest[:, 0]) < .12) & (rest[:, 2] < 1.0))[0]
    positions, bones = {}, {}
    for frame in frames:
        positions[frame] = evaluated(body, frame)[far_ids]
        bones[frame] = np.array([tuple(rig.matrix_world@rig.pose.bones[n].head) for n in bone_names])
    return {'path': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'rest': rest,
            'triangles': tris, 'far_ids': far_ids, 'far_positions': positions, 'bone_names': bone_names, 'bones': bones}


def render_closeups(body, rig, exercise, directory, ref, frames=(0, 53, 97)):
    directory.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    for obj in scene.objects:
        if obj.type == 'MESH':
            obj.hide_render = obj != body
    material = bpy.data.materials.new('Validation neutral gray')
    material.diffuse_color = (.48, .48, .48, 1)
    body.data.materials.clear()
    body.data.materials.append(material)
    for polygon in body.data.polygons:
        polygon.material_index = 0
    scene.render.engine = 'BLENDER_WORKBENCH'
    shading = scene.display.shading
    shading.light = 'STUDIO'
    shading.studiolight_rotate_z = .3
    shading.color_type = 'MATERIAL'
    shading.show_shadows = True
    shading.show_cavity = True
    shading.cavity_type = 'BOTH'
    shading.curvature_ridge_factor = 1.25
    shading.curvature_valley_factor = 1.0
    shading.background_type = 'WORLD'
    scene.world = scene.world or bpy.data.worlds.new('Validation world')
    scene.world.color = (.16, .16, .16)
    scene.render.resolution_x = 900
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    camera_data = bpy.data.cameras.new('Validation camera')
    camera = bpy.data.objects.new('Validation camera', camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    camera_data.type = 'ORTHO'
    joint = 'lowerarm_l' if exercise == 'curl' else 'upperarm_l'
    camera_data.ortho_scale = .39 if exercise == 'curl' else .48
    # Camera is based only on frozen review-clip bone positions, not candidate geometry.
    reference_path = ROOT / 'web/review/quality' / (exercise+'.glb')
    metadata = {'reference': str(reference_path), 'engine': 'BLENDER_WORKBENCH', 'body_only': True, 'views': []}
    for frame in frames:
        evaluated(body, frame)
        target = Vector(ref['bones'][frame][ref['bone_names'].index(joint)])
        for view, direction in [('front', Vector((1.15, -3, .6))), ('rear', Vector((1.15, 3, .6)))]:
            camera.location = target + direction.normalized()*2
            camera.rotation_euler = (target-camera.location).to_track_quat('-Z', 'Y').to_euler()
            scene.render.filepath = str(directory/f'{exercise}-{frame:03}-{view}.png')
            bpy.ops.render.render(write_still=True)
            metadata['views'].append({'frame': frame, 'view': view, 'camera_location': list(camera.location), 'target': list(target),
                                      'rotation_euler': list(camera.rotation_euler), 'ortho_scale': camera_data.ortho_scale})
    (directory/'render-settings.json').write_text(json.dumps(metadata, indent=2))


def check(args):
    frames = [x/2 for x in range(361)]
    comparison_frames = [0, 53, 97, 180]
    ref = reference(args.exercise, comparison_frames)
    body, rig, rest, tris = load(args.glb)
    regions = prepare_regions(rest, tris, rig)
    _, canonical = np.unique(np.round(rest, 6), axis=0, return_inverse=True)
    neighbors = {int(i): {int(i)} for i in canonical}
    for tri in canonical[tris]:
        for vertex in tri:
            neighbors[int(vertex)].update(int(x) for x in tri)
    result = {'exercise': args.exercise, 'input': str(args.glb), 'input_sha256': hashlib.sha256(args.glb.read_bytes()).hexdigest(),
              'reference_glb': ref['path'], 'reference_sha256': ref['sha256'], 'limits': LIMITS,
              'sample_frames': 361, 'intersection_frames': list(range(0, 181, 15))+[53, 97],
              'method': 'Material-section vector areas and rest-to-posed triangle tangent singular values; measured on re-imported GLB skin.',
              'limitations': ['Engineering regression limits, not medical/anatomical standards.', 'Strict non-coplanar triangle crossings above 1 mm; coplanar overlap and fine contacts are not classified.', 'Interior flexion-crease crossing counts are reported separately; no claim of globally intersection-free skin.'],
              'errors': [], 'region_summaries': {}, 'intersection_samples': [], 'samples': []}
    errors = set()
    if not set(ref['bone_names']).issubset(set(b.name for b in rig.data.bones)):
        errors.add('original skeleton bone missing')
    # glTF morph export can reorder/split coincident vertices; compare geometry,
    # then map every candidate witness to the frozen old rest surface position.
    from mathutils.kdtree import KDTree
    tree = KDTree(len(ref['rest']))
    for index, point in enumerate(ref['rest']):
        tree.insert(Vector(point), index)
    tree.balance()
    mapping, distances = [], []
    for point in rest:
        _, index, distance = tree.find(Vector(point))
        mapping.append(index)
        distances.append(distance)
    mapping = np.array(mapping)
    reverse_tree = KDTree(len(rest))
    for index, point in enumerate(rest):
        reverse_tree.insert(Vector(point), index)
    reverse_tree.balance()
    reverse_distance = max(reverse_tree.find(Vector(p))[2] for p in ref['rest'])
    result['rest_geometry_difference_m'] = float(max(max(distances), reverse_distance))
    result['body_triangle_count'] = len(tris)
    if len(tris) != len(ref['triangles']):
        errors.add('body triangle count changed')
    same_mesh = result['rest_geometry_difference_m'] <= LIMITS['rest_geometry_difference_m_max']
    if not same_mesh:
        errors.add('body rest shape changed')
    far_ids = np.where((abs(rest[:, 0]) < .12) & (rest[:, 2] < 1.0))[0]
    far_lookup = {int(index): j for j, index in enumerate(ref['far_ids'])}
    far_reference_indices = np.array([far_lookup[int(mapping[i])] for i in far_ids])
    result['metric_controls'] = {}
    for name, region in regions.items():
        joint = name.split('_')[0]
        neutral = geometry_metrics(rest, tris, region, joint)
        collapsed = geometry_metrics(rest*.25, tris, region, joint)
        inflated = geometry_metrics(rest*1.5, tris, region, joint)
        if joint == 'elbow':
            ok = abs(neutral['area_min']-1) < 1e-8 and collapsed['area_min'] < LIMITS['elbow_area_ratio_min'] and inflated['area_max'] > LIMITS['elbow_area_ratio_max']
        else:
            ok = abs(neutral['minimum_stretch_p10']-1) < 1e-8 and collapsed['minimum_stretch_p10'] < LIMITS['shoulder_cap_min_stretch_p10_min'] and inflated['cap_area_ratio'] > LIMITS['shoulder_cap_area_ratio_max']
        result['metric_controls'][name] = {'neutral_unit_scale_and_collapse_and_bulge_controls_pass': bool(ok)}
        if not ok:
            errors.add(name+': invalid metric calibration')
    first = None
    far_difference = bone_difference = 0.
    for frame in frames:
        vertices = evaluated(body, frame)
        if not np.isfinite(vertices).all():
            errors.add('non-finite deformed vertices')
            break
        if first is None:
            first = vertices.copy()
        if frame == 180:
            result['skin_loop_gap_m'] = float(np.linalg.norm(vertices-first, axis=1).max())
            if result['skin_loop_gap_m'] > LIMITS['skin_loop_gap_m_max']:
                errors.add('skin loop gap')
        if frame in comparison_frames and same_mesh:
            far_difference = max(far_difference, float(np.linalg.norm(vertices[far_ids]-ref['far_positions'][frame][far_reference_indices], axis=1).max()))
            heads = np.array([tuple(rig.matrix_world@rig.pose.bones[n].head) for n in ref['bone_names']])
            bone_difference = max(bone_difference, float(np.linalg.norm(heads-ref['bones'][frame], axis=1).max()))
        sample = {'frame': frame, 'regions': {}}
        for name, region in regions.items():
            joint = name.split('_')[0]
            metrics = geometry_metrics(vertices, tris, region, joint)
            sample['regions'][name] = metrics
            if joint == 'elbow':
                checks = [('elbow_area_ratio_min', metrics['area_min'], 'min'), ('elbow_area_ratio_max', metrics['area_max'], 'max'),
                          ('elbow_adjacent_normalized_radius_step_max', metrics['radius_step_max'], 'max')]
            else:
                checks = [('shoulder_cap_min_stretch_p10_min', metrics['minimum_stretch_p10'], 'min'),
                          ('shoulder_cap_area_ratio_min', metrics['cap_area_ratio'], 'min'), ('shoulder_cap_area_ratio_max', metrics['cap_area_ratio'], 'max'),
                          ('shoulder_cap_max_stretch_p90_max', metrics['maximum_stretch_p90'], 'max')]
            for key, value, direction in checks:
                summary = result['region_summaries'].setdefault(name, {})
                if key not in summary or (value < summary[key]['value'] if direction == 'min' else value > summary[key]['value']):
                    summary[key] = {'value': value, 'frame': frame, 'limit': LIMITS[key]}
                if value < LIMITS[key] if direction == 'min' else value > LIMITS[key]:
                    errors.add(name+': '+key)
        result['samples'].append(sample)
        if frame in result['intersection_frames']:
            target_joint = 'elbow' if args.exercise == 'curl' else 'shoulder'
            item = {'frame': frame, 'regions': {}}
            for side in ('l', 'r'):
                name = target_joint+'_'+side
                crossing = intersections(vertices, tris, regions[name], canonical, neighbors)
                item['regions'][name] = crossing
                if crossing['exposed_count'] > LIMITS['exposed_crossings_max']:
                    errors.add(name+': exposed skin self-intersection')
            result['intersection_samples'].append(item)
    result['far_skin_difference_m'] = far_difference
    result['bone_head_difference_m'] = bone_difference
    if far_difference > LIMITS['far_skin_difference_m_max']:
        errors.add('torso/legs drifted relative to frozen pose')
    if bone_difference > LIMITS['bone_head_difference_m_max']:
        errors.add('original bone heads drifted relative to frozen pose')
    result['errors'] = sorted(errors)
    result['passed'] = not errors
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2))
    print('JOINT_VOLUME_CHECK', json.dumps({k: v for k, v in result.items() if k not in ('samples', 'intersection_samples')}), flush=True)
    if args.render_dir:
        render_closeups(body, rig, args.exercise, args.render_dir, ref)
    if errors and not args.allow_failure:
        raise AssertionError(result['errors'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exercise', choices=EXERCISES, required=True)
    parser.add_argument('--glb', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--render-dir', type=Path)
    parser.add_argument('--allow-failure', action='store_true', help='Still record failures; useful when capturing the known-bad baseline.')
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    check(args)


if __name__ == '__main__':
    main()
