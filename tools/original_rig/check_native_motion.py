"""Focused native retargeting checks; run with Blender --python-exit-code 1.

Checks retained Skin/binds, finite matrices, native physical segment lengths,
loop seam and evaluated contact envelopes. Does not package production assets.
"""
import argparse,hashlib,json,sys,math
from pathlib import Path
import bpy,numpy as np
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(Path(__file__).parent));sys.path.insert(0,str(ROOT/'tools'))
from native_motion import NativeMotion,IDS
from build_native_review import fingerprint,points,grip_audit


def main():
    ap=argparse.ArgumentParser();ap.add_argument('--output',type=Path,default=ROOT/'.build/original-rig/native-motion-check.json')
    ap.add_argument('--quick',action='store_true');ap.add_argument('--exercise',nargs='*',choices=IDS);ap.add_argument('--render',action='store_true')
    args=ap.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    report={'fps':30,'duration':6,'samples_per_action':3 if args.quick else 181,'exercises':{}}
    for exercise in (args.exercise or IDS):
        bpy.ops.wm.open_mainfile(filepath=str(ROOT/'.build/original-rig/native-import-04/original-rig-staging.blend'),use_scripts=False)
        bpy.context.scene.frame_set(0);rig=bpy.data.objects['Armature'];body=bpy.data.objects['Man']
        for o in bpy.context.scene.objects:o.animation_data_clear()
        skin=fingerprint(body);bind={b.name:np.array(b.matrix_local) for b in rig.data.bones}
        solver=NativeMotion(rig,exercise)
        if args.render:
            from build_native_review import prepare
            folder=args.output.parent/'native-motion-renders';folder.mkdir(exist_ok=True)
            prepare(folder)
        solver.equipment()
        frames=[0,45,180] if args.quick else list(range(181))
        before=None;previous_rotations=None;max_angular_step=0.;seam=0.;length=0.;min_z=100.;max_projection=0.;max_contact=0.;max_grip=0.;deep_grip=0;max_support=0.;diagnostics=[]
        for f in frames:
            diagnostic=solver.pose_time(f/30);matrices={p.name:np.array(rig.matrix_world@p.matrix) for p in rig.pose.bones}
            assert all(np.isfinite(m).all() for m in matrices.values()),exercise+' non-finite pose'
            rotations={p.name:(rig.matrix_world@p.matrix).to_quaternion() for p in rig.pose.bones}
            if previous_rotations is not None and not args.quick:
                max_angular_step=max(max_angular_step,max(math.degrees(2*math.acos(min(1.,abs(q.dot(previous_rotations[n]))))) for n,q in rotations.items()))
            previous_rotations=rotations
            for bone in rig.pose.bones:
                if bone.parent:
                    expected=(solver.origin(bone.name)-solver.origin(bone.parent.name)).length
                    actual=float(np.linalg.norm(matrices[bone.name][:3,3]-matrices[bone.parent.name][:3,3]))
                    length=max(length,abs(actual-expected))
            helper_a='Man_PelvisBone002';helper_b=helper_a+'Bone001'
            helper_native=(solver.origin(helper_b)-solver.origin(helper_a)).length
            helper_actual=float(np.linalg.norm(matrices[helper_b][:3,3]-matrices[helper_a][:3,3]))
            length=max(length,abs(helper_actual-helper_native))
            if f==0:before=matrices
            if f==180:seam=max(float(np.abs(m-before[n]).max()) for n,m in matrices.items())
            for side in ('L','R'):
                for a,b,key in [('Upperarm','Forearm1','upper_length'),('Forearm1','Hand','forearm_length'),('Thigh','Calf','thigh_length'),('Calf','Foot','calf_length')]:
                    native=(solver.origin('Man_'+side+b)-solver.origin('Man_'+side+a)).length
                    actual=np.linalg.norm(matrices['Man_'+side+b][:3,3]-matrices['Man_'+side+a][:3,3])
                    length=max(length,abs(diagnostic[side][key]-native),abs(float(actual)-native))
            xyz=points(body);min_z=min(min_z,float(xyz[:,2].min()))
            if diagnostic['L'].get('gripped') or diagnostic['R'].get('gripped'):
                grip=grip_audit(solver)
                for side in ('L','R'):
                    if diagnostic[side].get('gripped'):
                        max_grip=max(max_grip,grip[side]['max_handle_surface_penetration_m'])
                        deep_grip+=grip[side]['vertices_deeper_than_2mm']
            max_support=max(max_support,abs(diagnostic.get('native_support_skin_error_m',0)))
            if f in (0,45,90,135,180):
                diagnostics.append({'frame':f,'diagnostic':diagnostic,'body_min_z':float(xyz[:,2].min())})
            max_projection=max(max_projection,diagnostic.get('max_reach_projection_m',0))
            for c in diagnostic.get('contacts',[]):max_contact=max(max_contact,abs(c.get('skin_contact_error_m',0)))
        checks={'bones':len(rig.data.bones),'weights_unchanged':skin==fingerprint(body),'binds_unchanged':all(np.array_equal(bind[b.name],np.array(b.matrix_local)) for b in rig.data.bones),
                'max_length_error_m':length,'loop_matrix_max_error':seam,'representative_body_min_z_m':min_z,'max_reach_projection_m':max_projection,
                'max_open_hand_contact_error_m':max_contact,'max_support_skin_error_m':max_support,'max_handle_surface_penetration_m':max_grip,'vertices_deeper_than_2mm':deep_grip,'max_angular_step_deg':max_angular_step,'source':solver.trajectory['source'],'samples':diagnostics}
        assert checks['bones']==81 and checks['weights_unchanged'] and checks['binds_unchanged'],exercise+' native structural invariant failed'
        assert length<2e-5 and seam<1e-4,exercise+' native length / loop invariant failed'
        assert min_z>-.002 and max_contact<.002 and max_support<.002 and deep_grip==0,exercise+' native contact invariant failed'
        if exercise in ('jumping_jack','step_jack') and not args.quick:
            assert max_angular_step<15,exercise+' abrupt native wrist/forearm rotation'
        report['exercises'][exercise]=checks
        print('NATIVE_CHECK',exercise,json.dumps({k:v for k,v in checks.items() if k not in ('samples','source')}),flush=True)
        if args.render:
            solver.pose_time(1.5 if exercise in ('dead_bug','step_jack','lateral_lunge') else 3)
            render_pose(folder/exercise,solver)
    report['all_structural_checks_passed']=True
    args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(report,ensure_ascii=False,indent=2))


def render_pose(path,solver):
    from mathutils import Vector
    sc=bpy.context.scene
    for o in list(sc.objects):
        if o.type in ('CAMERA','LIGHT'):bpy.data.objects.remove(o,do_unlink=True)
    xyz=points(bpy.data.objects['Man']);low=xyz.min(axis=0);high=xyz.max(axis=0);center=Vector((low+high)*.5)
    for loc,power,size in [((-3,-4,4),450,4),((3,-2,3),350,3),((1,2,4),450,3)]:
        bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object;o.data.energy=power;o.data.size=size
        o.rotation_euler=(center-o.location).to_track_quat('-Z','Y').to_euler()
    for view,offset in [('front',Vector((0,-5,1))),('side',Vector((5,-1,1)))]:
        bpy.ops.object.camera_add(location=center+offset);cam=bpy.context.object
        cam.rotation_euler=(center-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=max(high-low)*1.2;sc.camera=cam
        sc.render.engine='CYCLES';sc.cycles.samples=16;sc.cycles.use_denoising=True
        sc.render.resolution_x=600;sc.render.resolution_y=600;sc.render.resolution_percentage=100;sc.render.film_transparent=True
        if sc.world is None:sc.world=bpy.data.worlds.new('Native review world')
        sc.world.color=(.12,.12,.12);sc.view_settings.view_transform='AgX';sc.render.filepath=str(path)+'-'+view+'.png'
        bpy.ops.render.render(write_still=True)
        bpy.data.objects.remove(cam,do_unlink=True)


if __name__=='__main__':main()
