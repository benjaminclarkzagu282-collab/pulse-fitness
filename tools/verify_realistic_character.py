"""Check the actual Blender asset before exporting it into the fitness app.

Run with Blender --background --python-exit-code 1 --python this_file -- file.blend.
This catches absent binding, unweighted vertices, broken textures and excessive geometry.
"""
import sys
import math
from pathlib import Path

import bpy

path = Path(sys.argv[sys.argv.index('--') + 1])
bpy.ops.wm.open_mainfile(filepath=str(path), use_scripts=False)
if bpy.context.mode != 'OBJECT':
    bpy.ops.object.mode_set(mode='OBJECT')
rigs = [o for o in bpy.context.scene.objects if o.type == 'ARMATURE']
assert len(rigs) == 1, f'Expected one deformation skeleton; found {len(rigs)}'
rig = rigs[0]
meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH' and not o.hide_render]
triangles = 0
for ob in meshes:
    assert any(m.type == 'ARMATURE' and m.object == rig for m in ob.modifiers), ob.name
    assert ob.data.uv_layers, f'UVs missing: {ob.name}'
    ob.data.calc_loop_triangles()
    triangles += len(ob.data.loop_triangles)
    for vertex in ob.data.vertices:
        weights = [g.weight for g in vertex.groups if g.weight > 0]
        assert weights and len(weights) <= 4, (ob.name, vertex.index, weights)
        assert abs(sum(weights) - 1) < .001, (ob.name, vertex.index, sum(weights))
    assert ob.data.materials and all(ob.data.materials), f'Material missing: {ob.name}'
assert triangles < 65000, f'Mobile character too dense: {triangles} triangles'
textures = [i for i in bpy.data.images if i.source == 'FILE' and i.users]
assert textures, 'No skin textures loaded'
for image in textures:
    assert image.packed_file or Path(bpy.path.abspath(image.filepath)).is_file(), image.name
    assert 0 < max(image.size) <= 2048, (image.name, tuple(image.size))
sys.path.insert(0, str(Path(__file__).resolve().parent))
from animate_athlete import IDS, pose
for exercise in IDS:
    first = None
    for phase in (0, .25, .5, .75, 1):
        pose(rig, exercise, phase)
        depsgraph = bpy.context.evaluated_depsgraph_get()
        points = [ob.matrix_world @ v.co for ob in meshes
                  for v in ob.evaluated_get(depsgraph).data.vertices]
        assert all(math.isfinite(c) for p in points for c in p), exercise
        minimum = min(p.z for p in points)
        assert minimum >= -.003, f'{exercise}/{phase}: geometry below floor ({minimum:.4f} m)'
        if exercise in ('pushup','plank'):
            body = bpy.data.objects['Man']
            evaluated = body.evaluated_get(depsgraph)
            for side in ('l','r'):
                indices = {g.index for g in body.vertex_groups if g.name in ('foot_'+side,'ball_'+side)}
                toes = [evaluated.data.vertices[v.index].co.z for v in body.data.vertices
                        if sum(g.weight for g in v.groups if g.group in indices) > .8]
                assert min(toes) < .008, f'{exercise}/{side}: toes floating above floor'
        if phase == 0:
            first = points
        elif phase == 1:
            assert max((a-b).length for a,b in zip(first,points)) < .0001, exercise
print(f'PASS: {len(rig.data.bones)} bones; {len(meshes)} bound meshes; '
      f'{triangles} triangles; {len(textures)} textures; all vertices normalized; '
      'eight closed pose loops; sampled geometry stays above floor.')
