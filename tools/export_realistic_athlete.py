"""Export and render the bound realistic character into a staged output directory."""
import sys
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / '.build/realistic-character'
OUT = WORK / 'output'
sys.path.insert(0, str(ROOT / 'tools'))
from animate_athlete import IDS, animate, equipment, finalize_glb, pose


def render(path, exercise, portrait=False, home=False):
    scene = bpy.context.scene
    for ob in list(scene.objects):
        if ob.type in ('LIGHT', 'CAMERA'):
            bpy.data.objects.remove(ob, do_unlink=True)
    target = Vector((0, -.025, 1.34 if portrait else .7))
    for location, energy, size, color in [
        ((-3,-4,4), 400, 2.5, (1,.89,.79)),
        ((3,-2,2), 110, 3, (.83,.91,1)),
        ((1,3,3), 500, 2, (.90,1,.89)),
    ]:
        bpy.ops.object.light_add(type='AREA', location=location)
        ob = bpy.context.object
        ob.data.energy, ob.data.size, ob.data.color = energy, size, color
        ob.rotation_euler = (target-ob.location).to_track_quat('-Z','Y').to_euler()
    location = (1.3,-6,1.52) if portrait else (3.4,-6,1.9)
    bpy.ops.object.camera_add(location=location)
    camera = bpy.context.object
    camera.rotation_euler = (target-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.data.type = 'ORTHO'
    scene.camera = camera
    width, height = (450,820) if home else ((512,512) if portrait else (640,720))
    bpy.context.view_layer.update()
    if portrait:
        camera.data.ortho_scale = .36
    else:
        inverse = camera.matrix_world.inverted()
        points = [inverse@ob.matrix_world@v.co
                  for ob in scene.objects if ob.type == 'MESH' and not ob.hide_render
                  for v in ob.evaluated_get(bpy.context.evaluated_depsgraph_get()).data.vertices]
        left,right = min(p.x for p in points),max(p.x for p in points)
        bottom,top = min(p.y for p in points),max(p.y for p in points)
        camera.location += camera.matrix_world.to_quaternion() @ Vector(((left+right)/2,(bottom+top)/2,0))
        camera.data.ortho_scale = max(top-bottom,(right-left)*height/width)*1.12
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 48
    scene.cycles.use_denoising = True
    scene.render.resolution_x,scene.render.resolution_y = width,height
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = 'AgX'
    scene.view_settings.look = 'AgX - Medium High Contrast'
    scene.view_settings.exposure = -.3
    scene.world.color = (.12,.12,.12)
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def main():
    (OUT/'models').mkdir(parents=True,exist_ok=True)
    (OUT/'images').mkdir(exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=str(WORK/'athlete-source.blend'),use_scripts=False)
    rig = next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
    for exercise in IDS:
        equipment(rig,exercise)
        animate(rig,exercise)
        bpy.ops.object.select_all(action='DESELECT')
        rig.select_set(True)
        for ob in bpy.context.scene.objects:
            if ob.type=='MESH':ob.select_set(True)
        bpy.context.view_layer.objects.active = rig
        path = OUT/f'models/athlete_{exercise}.glb'
        bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,
                                  export_animations=True,export_animation_mode='ACTIVE_ACTIONS',
                                  export_nla_strips_merged_animation_name='Exercise',
                                  export_force_sampling=True,export_frame_range=True,
                                  export_yup=True,export_morph=False)
        finalize_glb(path)
        rig.animation_data.action.name = exercise
        rig.animation_data.action.use_fake_user = True
        bpy.context.scene.frame_set(0 if exercise in ('pushup','plank') else 48)
        render(OUT/f'images/athlete_{exercise}.png',exercise)
        if exercise=='squat':
            render(OUT/'images/athlete_hero.png',exercise)
    rig.animation_data_clear()
    equipment(rig,'standing')
    pose(rig,'standing',0)
    render(OUT/'images/athlete_avatar.png','standing',portrait=True)
    pose(rig,'squat',.22)
    render(OUT/'images/athlete_home.png','squat',home=True)
    rig.animation_data_create()
    rig.animation_data.action = bpy.data.actions['squat']
    bpy.context.scene.frame_set(20)
    add_editable_props(rig)
    bpy.ops.wm.save_as_mainfile(filepath=str(WORK/'athlete-animated.blend'))


def add_editable_props(rig):
    """Keep optional equipment in the editable source without showing it in squat."""
    equipment(rig,'curl')
    collection = bpy.data.collections.new('Dumbbells - enable for row or curl')
    bpy.context.scene.collection.children.link(collection)
    for ob in list(bpy.context.scene.objects):
        if ob.name.startswith('PULSE dumbbell'):
            for old in list(ob.users_collection):
                old.objects.unlink(ob)
            collection.objects.link(ob)
    collection.hide_viewport = True
    collection.hide_render = True


if __name__=='__main__':main()
