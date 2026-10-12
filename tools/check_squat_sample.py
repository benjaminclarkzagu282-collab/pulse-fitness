"""Geometric regression, not a fitness certification. Run inside Blender.

With --legacy, checks the old authoring function to reproduce disconnected joints.
Otherwise imports the delivered GLB and inspects the actual animation.
"""
import json
import math
import sys
from pathlib import Path
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
legacy = '--legacy' in sys.argv
if legacy:
    bpy.ops.wm.open_mainfile(filepath=str(ROOT / '.build/realistic-character/athlete-source.blend'), use_scripts=False)
    from animate_athlete import pose
else:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    path = sys.argv[sys.argv.index('--glb') + 1] if '--glb' in sys.argv else str(ROOT / 'web/review/squat-v2.glb')
    bpy.ops.import_scene.gltf(filepath=path)
rig = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
scene = bpy.context.scene
end = 96 if legacy else max(k.co.x for a in bpy.data.actions for slot in a.slots for layer in a.layers for strip in layer.strips for fc in strip.channelbag(slot).fcurves for k in fc.keyframe_points)
pairs = [(a+'_'+s, b+'_'+s) for s in ('l','r') for a,b in (('thigh','calf'),('calf','foot'),('upperarm','lowerarm'),('lowerarm','hand'))]
worst = (0, '', 0)
foot_start = {}
foot_rotation_start = {}
max_foot_drift = 0
max_foot_rotation = 0
first = None
loop_gap = 0
max_length_error = 0
minimum_skin_height = float('inf')
max_contact_height = 0
samples = max(360, math.ceil(end*2))
meshes = [ob for ob in bpy.context.scene.objects if ob.type=='MESH']
body = next(ob for ob in meshes if ob.name=='Man')
# Named patches include both heel and forefoot on each sole. They are measured
# from the imported rest mesh, independent of the animation generator.
patches = {(side,part): [v.index for v in body.data.vertices
                       if v.co.x*sign>0 and v.co.z<.008 and
                       (v.co.y>0 if part=='heel' else v.co.y<-.05)]
           for side,sign in [('l',1),('r',-1)] for part in ['heel','forefoot']}
assert all(patches.values()), 'Missing plantar contact patches'
root_location = rig.location.copy()
for i in range(samples+1):
    phase = i / samples
    if legacy:
        pose(rig, 'squat', phase)
    else:
        frame = phase * end
        scene.frame_set(int(frame), subframe=frame-int(frame))
    if '--inject-root-slide' in sys.argv:
        # Negative fixture: a globally sliding character must fail even when
        # every foot bone is stationary in its armature's local space.
        rig.location = root_location + Vector((.02*math.sin(math.pi*phase)**2,0,0))
        bpy.context.view_layer.update()
    for a,b in pairs:
        gap = (rig.pose.bones[a].tail - rig.pose.bones[b].head).length
        if gap > worst[0]: worst = (gap, a+' -> '+b, phase)
    for p in rig.pose.bones:
        assert all(math.isfinite(c) for c in p.head), p.name
        if p.name.startswith(('thigh_','calf_','upperarm_','lowerarm_')):
            max_length_error=max(max_length_error,abs(p.length/rig.data.bones[p.name].length-1))
    for side in ('l','r'):
        foot = rig.pose.bones['foot_'+side]
        points = (rig.matrix_world@foot.head, rig.matrix_world@foot.tail)
        rotation = (rig.matrix_world@foot.matrix).to_quaternion()
        if side not in foot_start: foot_start[side] = points
        if side not in foot_rotation_start: foot_rotation_start[side] = rotation
        angle = rotation.rotation_difference(foot_rotation_start[side]).angle
        max_foot_rotation = max(max_foot_rotation, min(angle,2*math.pi-angle))
        max_foot_drift = max(max_foot_drift, *( (a-b).length for a,b in zip(points, foot_start[side]) ))
    points = [rig.matrix_world@p.head for p in rig.pose.bones]
    if first is None: first = points
    if i == samples: loop_gap = max((a-b).length for a,b in zip(first, points))
    evaluated = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
    verts = evaluated.data.vertices
    minimum_skin_height=min(minimum_skin_height,min((evaluated.matrix_world@v.co).z for v in verts))
    max_contact_height=max(max_contact_height,*(min((evaluated.matrix_world@verts[j].co).z for j in patch) for patch in patches.values()))
result = {'legacy': legacy, 'samples':samples+1, 'worst_joint_gap_m':worst,
          'foot_drift_m':max_foot_drift, 'loop_gap_m':loop_gap,
          'max_foot_rotation_rad':max_foot_rotation,
          'max_relative_limb_length_error':max_length_error,
          'minimum_skin_height_m':minimum_skin_height, 'max_sole_contact_height_m':max_contact_height}
print('SQUAT_CHECK', json.dumps(result))
assert worst[0] < .0005, f'Disconnected limb: {worst}'
assert max_foot_drift < .0005, f'Foot slide: {max_foot_drift}'
assert max_foot_rotation < math.radians(.05), f'Foot rotation drift: {max_foot_rotation}'
assert loop_gap < .0005, f'Loop jump: {loop_gap}'
assert max_length_error < .002, f'Limb stretching: {max_length_error}'
assert minimum_skin_height > -.003, f'Skin below floor: {minimum_skin_height}'
assert max_contact_height < .004, f'Heel or forefoot off floor: {max_contact_height}'
if not legacy:
    out=ROOT/'.build/squat-sample/verification.json'
    out.write_text(json.dumps(result,ensure_ascii=False,indent=2))
