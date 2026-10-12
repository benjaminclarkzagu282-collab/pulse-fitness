"""Small real Blender export regression for differing vertex/frame counts."""
import json
import sys
from pathlib import Path
import bpy
import numpy as np
from mathutils.kdtree import KDTree

sys.path.insert(0, str(Path(__file__).parent))
from build_native_library import bake, author_source, points
from verify_native_library import read_glb, time_values


def check(fps):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.object.armature_add()
    rig = bpy.context.object
    bpy.ops.mesh.primitive_cube_add(size=.2, location=(0, 0, 1))
    body = bpy.context.object
    body.name = 'Man'
    body.data.materials.append(bpy.data.materials.new('Probe body'))
    reference = np.array([v.co[:] for v in body.data.vertices], dtype=np.float32)

    class Solver:
        def __init__(self):
            self.rig = rig

        def pose_time(self, seconds):
            xyz = reference.copy()
            xyz[:, 0] += .1*np.sin(seconds*2*np.pi/6)
            xyz[0, 2] += .02*(np.cos(seconds*2*np.pi/6)-1)
            body.data.vertices.foreach_set('co', xyz.ravel())
            body.data.update()
            bpy.context.view_layer.update()
            return {}

    solver = Solver()
    folder = Path(__file__).resolve().parents[2]/'.build/original-rig/mesh-delivery-probe'
    folder.mkdir(parents=True, exist_ok=True)
    name = 'probe-'+str(fps)
    report = bake(solver, name, folder, fps)
    author_source(solver, name)
    assert bpy.context.scene.frame_end == fps*6
    assert bpy.context.scene.render.fps == fps
    assert len(report['timeTargets']) == fps*6+1
    times = [i/(2*fps) for i in range(12*fps+1)]
    truth = []
    for t in times:
        solver.pose_time(t)
        truth.append(points(body))
    doc, binary = read_glb(folder/(name+'.glb'))
    for sampler in doc['animations'][0]['samplers']:
        values = time_values(doc, binary, sampler['input'])
        assert values[0] == 0 and values[-1] == 6, (fps, values[-1])
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 30
    bpy.ops.import_scene.gltf(filepath=str(folder/(name+'.glb')))
    imported = bpy.data.objects['Web Man']
    tree = KDTree(len(truth[0]))
    for i, co in enumerate(truth[0]):
        tree.insert(co, i)
    tree.balance()
    mapping = [tree.find(co)[1] for co in points(imported)]
    error = 0
    for t, native in zip(times, truth):
        f = t*30
        bpy.context.scene.frame_set(int(f), subframe=f-int(f))
        error = max(error, float(np.linalg.norm(points(imported)-native[mapping], axis=1).max()))
    assert error < .00015, (fps, error)
    print('MESH_DELIVERY_REGRESSION', json.dumps({'fps': fps, 'samples': len(times), 'max_error_m': error}), flush=True)


for rate in (30, 90):
    check(rate)
