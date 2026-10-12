"""Render lightweight videos from the unchanged, accepted editable animation.

Run with Blender --background --python this_file -- [exercise IDs].
Only render settings in memory change; original .blend/.glb files are never saved.
"""
import json
import sys
from pathlib import Path
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / '.build/original-rig/native-library-02'
OUT = ROOT / 'assets/videos'
OUT.mkdir(parents=True, exist_ok=True)
catalog = json.loads((ROOT/'assets/muscles/catalog.json').read_text())['exercises']
report = json.loads((SOURCE/'build-report.json').read_text())
entries = report.get('exercises', report.get('results', {}))
if isinstance(entries, list):
    entries = {x['exercise']: x for x in entries}
ids = sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else list(catalog)
for exercise in ids:
    output = OUT / (exercise+'.mp4')
    if output.is_file() and output.stat().st_size > 10000:
        print('VIDEO_EXISTS', exercise, flush=True)
        continue
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE/(exercise+'-native-source.blend')), use_scripts=False)
    scene = bpy.context.scene
    original_fps = int(entries[exercise].get('fps',30))
    bounds = entries[exercise]['world_bounds']
    centre = (Vector(bounds['min'])+Vector(bounds['max']))*.5
    extent = Vector(bounds['max'])-Vector(bounds['min'])
    floor = catalog[exercise]['camera']['floor']
    direction = Vector((1,-1,.75)) if floor else Vector((.25,-1,.12))
    for obj in list(scene.objects):
        if obj.type in ('LIGHT','CAMERA'): bpy.data.objects.remove(obj, do_unlink=True)
        elif obj.name.startswith('PULSE region '): obj.hide_render = True
    bpy.ops.object.camera_add(location=centre+direction*5)
    cam = bpy.context.object
    cam.rotation_euler = (centre-cam.location).to_track_quat('-Z','Y').to_euler()
    cam.data.type='ORTHO'
    cam.data.ortho_scale=max(extent.z, extent.y if floor else extent.x,1)*1.35
    scene.camera=cam
    for pos, power in [((-3,-4,4),450),((3,-2,3),350),((1,2,4),450)]:
        bpy.ops.object.light_add(type='AREA',location=pos)
        light=bpy.context.object; light.data.energy=power; light.data.size=4
        light.rotation_euler=(centre-light.location).to_track_quat('-Z','Y').to_euler()
    scene.render.engine='CYCLES'
    scene.cycles.samples=8
    scene.cycles.use_denoising=True
    scene.render.resolution_x=256; scene.render.resolution_y=320
    scene.render.resolution_percentage=100
    scene.render.film_transparent=False
    if scene.world is None: scene.world=bpy.data.worlds.new('Fallback world')
    scene.world.color=(.08,.10,.08)
    scene.view_settings.view_transform='AgX'
    scene.frame_start=0; scene.frame_end=original_fps*6-1
    scene.frame_step=max(1,round(original_fps/10))
    scene.render.fps=10
    scene.render.image_settings.media_type='VIDEO'
    scene.render.ffmpeg.format='MPEG4'; scene.render.ffmpeg.codec='H264'
    scene.render.ffmpeg.constant_rate_factor='MEDIUM'
    scene.render.ffmpeg.audio_codec='NONE'
    scene.render.filepath=str(output)
    print('VIDEO_RENDER',exercise,original_fps,scene.frame_step,flush=True)
    bpy.ops.render.render(animation=True)
    print('VIDEO_COMPLETE',exercise,output.stat().st_size,flush=True)
