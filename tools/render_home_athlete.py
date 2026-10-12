"""Render a full silhouette for the home card from the licensed 3D source."""
import sys
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
WIDTH, HEIGHT = 450, 820
sys.path.insert(0, str(ROOT / 'tools'))
from animate_athlete import pose

bpy.ops.wm.open_mainfile(filepath=str(ROOT / '.build/character/athlete-source.blend'))
rig = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
pose(rig, 'squat', .29)
jersey = bpy.data.materials.get('Graphite technical jersey')
jersey.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value = (.07, .23, .15, 1)
jersey.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value = .64
scene = bpy.context.scene
for ob in list(scene.objects):
    if ob.type in ['LIGHT', 'CAMERA']:
        bpy.data.objects.remove(ob, do_unlink=True)

target = Vector((0, -.05, .68))
for location, energy, size, color in [
    ((-3, -4, 4), 500, 4, (1, .87, .72)),
    ((3, -2, 2), 160, 3, (.86, .94, 1)),
    ((1, 3, 3.5), 650, 2.5, (.83, 1, .66)),
]:
    bpy.ops.object.light_add(type='AREA', location=location)
    light = bpy.context.object
    light.data.energy, light.data.size, light.data.color = energy, size, color
    light.rotation_euler = (target - light.location).to_track_quat('-Z', 'Y').to_euler()
bpy.ops.object.camera_add(location=(3.4, -6, 2))
camera = bpy.context.object
camera.rotation_euler = (target - camera.location).to_track_quat('-Z', 'Y').to_euler()
camera.data.type = 'ORTHO'
camera.data.ortho_scale = 1.6
scene.camera = camera
# Fit the evaluated silhouette in the portrait without clipping or dead space.
bpy.context.view_layer.update()
inverse = camera.matrix_world.inverted()
points = [inverse @ ob.matrix_world @ vertex.co
          for ob in scene.objects if ob.type == 'MESH' and not ob.hide_render
          for vertex in ob.evaluated_get(bpy.context.evaluated_depsgraph_get()).data.vertices]
left, right = min(p.x for p in points), max(p.x for p in points)
bottom, top = min(p.y for p in points), max(p.y for p in points)
rotation = camera.matrix_world.to_quaternion()
camera.location += rotation @ Vector(((left + right) / 2, (bottom + top) / 2, 0))
camera.data.ortho_scale = max(top - bottom, (right - left) * HEIGHT / WIDTH) * 1.10
scene.render.engine = 'CYCLES'
scene.cycles.samples = 48
scene.cycles.use_denoising = True
scene.render.resolution_x, scene.render.resolution_y = WIDTH, HEIGHT
scene.render.resolution_percentage = 100
scene.world.color = (.12, .12, .12)
scene.view_settings.view_transform = 'AgX'
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'
scene.render.film_transparent = True
scene.render.filepath = str(ROOT / 'assets/images/athlete_home.png')
bpy.ops.render.render(write_still=True)
