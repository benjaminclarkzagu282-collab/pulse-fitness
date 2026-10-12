"""361-sample checks on imported lower/core GLBs, including negative controls."""
import argparse, json, math, struct, sys
from pathlib import Path
import bpy
ROOT=Path(__file__).resolve().parents[1];WORK=ROOT/'.build/motion-library'
sys.path.insert(0,str(ROOT/'tools'))
from check_motion_library import PAIRS
IDS=['sumo_squat','split_squat','lateral_lunge','calf_raise','dead_bug','bird_dog','side_plank','step_jack']

def check(e,args):
    path=Path(args.glb) if args.glb else WORK/'base'/f'{e}.glb'
    assert path.is_file(),f'Missing delivered clip {path}'
    raw=path.read_bytes();n=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+n])
    assert len(doc['animations'])==1 and doc['animations'][0]['name']=='Exercise'
    assert all(s.get('interpolation','LINEAR')=='LINEAR' for s in doc['animations'][0]['samplers'])
    assert all(doc['accessors'][s['input']]['count']==181 for s in doc['animations'][0]['samplers']), 'Every channel must have 181 authored samples'
    bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.scene.render.fps=30
    bpy.ops.import_scene.gltf(filepath=str(path));scene=bpy.context.scene
    rig=next(o for o in scene.objects if o.type=='ARMATURE');body=bpy.data.objects['Man']
    end=max(k.co.x for a in bpy.data.actions for l in a.layers for st in l.strips for sl in a.slots for fc in st.channelbag(sl).fcurves for k in fc.keyframe_points)
    assert abs(end-180)<.01,f'Wrong duration {end}'
    patches={}
    for s,sg in [('l',1),('r',-1)]:
        patches['foot_'+s]=[v.index for v in body.data.vertices if v.co.x*sg>.1 and v.co.z<.035]
        patches['heel_'+s]=[v.index for v in body.data.vertices if v.co.x*sg>.1 and v.co.z<.035 and v.co.y>.065]
        patches['ball_'+s]=[v.index for v in body.data.vertices if v.co.x*sg>.1 and v.co.z<.025 and v.co.y<-.055]
        for part,rad in [('hand',None),('lowerarm',.06),('calf',.06)]:
            name=part+'_'+s;group=body.vertex_groups[name].index;head=rig.data.bones[name].head_local
            patches[name]=[v.index for v in body.data.vertices if (any(g.group==group and g.weight>.7 for g in v.groups) if rad is None else (v.co-head).length<rad)]
    patches['back']=[v.index for v in body.data.vertices if v.co.y>.075 and .76<v.co.z<1.25]
    supports={'sumo_squat':['foot_l','foot_r'],'split_squat':['foot_l','foot_r'],'lateral_lunge':['foot_l','foot_r'],
              'calf_raise':['ball_l','ball_r'],'dead_bug':['pelvis'],'bird_dog':['hand_r','calf_l'],
              'side_plank':['lowerarm_r','foot_r'],'step_jack':[]}[e]
    contact={'dead_bug':['back'],'side_plank':['lowerarm_r','foot_r']}.get(e,supports)
    names=['pelvis','upperarm_l','upperarm_r','hand_l','hand_r','thigh_l','thigh_r','calf_l','calf_r','foot_l','foot_r','ball_l','ball_r']
    motion={n:[] for n in names};contact_heights={p:[] for p in patches}
    initial=None;start={};worst=(0,'',0);stretch=0.;minimum=1e3;drift=0.;loop=0.;slide=0.;last=None;low=[1e3]*3;high=[-1e3]*3
    for i in range(361):
        t=i/60;frame=(0 if args.inject_frozen else t*30)
        scene.frame_set(int(frame),subframe=frame-int(frame))
        if args.inject_root_slide:rig.location.x=.02*math.sin(math.pi*t/6)**2
        if args.inject_joint_gap:
            m=rig.pose.bones['hand_l'].matrix.copy();m.translation.x+=.02*math.sin(math.pi*t/6)**2;rig.pose.bones['hand_l'].matrix=m
        bpy.context.view_layer.update()
        for a,b in PAIRS+[(f'foot_{s}',f'ball_{s}') for s in ('l','r')]:
            gap=(rig.pose.bones[a].tail-rig.pose.bones[b].head).length
            if gap>worst[0]:worst=(gap,a+' -> '+b,t)
        for p in rig.pose.bones:
            assert all(math.isfinite(v) for v in (*p.head,*p.tail)),f'Non-finite joint {p.name}'
            stretch=max(stretch,abs(p.length/rig.data.bones[p.name].length-1))
        points=[rig.matrix_world@p.head for p in rig.pose.bones]
        if initial is None:initial=points
        if i==360:loop=max((a-b).length for a,b in zip(points,initial))
        for name in motion:motion[name].append(rig.matrix_world@rig.pose.bones[name].head)
        for name in supports:
            pt=rig.matrix_world@rig.pose.bones[name].head
            if name not in start:start[name]=pt
            drift=max(drift,(pt-start[name]).length)
        evaluated=body.evaluated_get(bpy.context.evaluated_depsgraph_get());verts=[evaluated.matrix_world@v.co for v in evaluated.data.vertices]
        minimum=min(minimum,min(v.z for v in verts))
        for ax in range(3):low[ax]=min(low[ax],min(v[ax] for v in verts));high[ax]=max(high[ax],max(v[ax] for v in verts))
        for p,ids in patches.items():contact_heights[p].append(min(verts[j].z for j in ids))
        if e=='step_jack' and last:
            for s in ('l','r'):
                if contact_heights['foot_'+s][-1]<.003 and contact_heights['foot_'+s][-2]<.003:
                    a,b=motion['foot_'+s][-1],motion['foot_'+s][-2];slide=max(slide,math.hypot(a.x-b.x,a.y-b.y))
        last=True
    ranges={n:[max(v[ax] for v in vs)-min(v[ax] for v in vs) for ax in range(3)] for n,vs in motion.items()}
    errors=[]
    if worst[0]>.0005:errors.append(f'joint gap {worst}')
    if stretch>.002:errors.append(f'stretch {stretch}')
    if loop>.0006:errors.append(f'loop {loop}')
    if drift>.0006:errors.append(f'support drift {drift}')
    if minimum<-.001:errors.append(f'skin below ground {minimum}')
    for p in contact:
        if p in contact_heights and max(contact_heights[p])>.006:errors.append(f'{p} support lifted {max(contact_heights[p])}')
    if slide>.0005:errors.append(f'grounded translation {slide}')
    def require(n,ax,v):
        if ranges[n][ax]<v:errors.append(f'missing {n} motion {ranges[n]} expected axis {ax} >= {v}')
    if e in ('sumo_squat','split_squat'):require('pelvis',2,.15)
    if e=='sumo_squat':
        if min(v.x for v in motion['foot_l'])<.25:errors.append('sumo stance too narrow')
    if e=='split_squat':
        if motion['foot_r'][0].y-motion['foot_l'][0].y<.45:errors.append('split stance too short')
    if e=='lateral_lunge':
        require('pelvis',0,.35)
        if not (motion['pelvis'][90].x>.15 and motion['pelvis'][270].x<-.15):errors.append('missing alternating hip shift')
    if e=='calf_raise':
        require('foot_l',2,.035)
        if max(contact_heights['heel_l'])-min(contact_heights['heel_l'])<.05:errors.append('no heel lift')
    if e=='dead_bug':
        for s in ('l','r'):require('hand_'+s,1,.20);require('foot_'+s,1,.20)
        for index,arm,leg in [(90,'l','r'),(270,'r','l')]:
            if motion['hand_'+arm][index].y>motion['hand_'+arm][0].y-.20:errors.append('arm not overhead')
            if motion['foot_'+leg][index].y<motion['foot_'+leg][0].y+.20:errors.append('opposite leg not extended')
    if e=='bird_dog':require('hand_l',1,.25);require('foot_r',1,.25)
    if e in ('sumo_squat','lateral_lunge'):
        peaks=[(195,'l'),(195,'r')] if e=='sumo_squat' else [(90,'l'),(270,'r')]
        for i,s in peaks:
            shin=motion['calf_'+s][i]-motion['foot_'+s][i];toe=motion['ball_'+s][i]-motion['foot_'+s][i]
            shin.z=toe.z=0
            if math.degrees(shin.angle(toe))>15:errors.append(f'{s} knee and toe directions differ at authored peak')
    if e in ('dead_bug','bird_dog'):
        for n in ('pelvis','upperarm_l','upperarm_r'):
            if max(ranges[n])>.001:errors.append('core reference trunk moves')
    if e=='side_plank':
        for s in ('l','r'):
            a=motion['thigh_'+s][0]-motion['calf_'+s][0];b=motion['foot_'+s][0]-motion['calf_'+s][0]
            if math.degrees(a.angle(b))<165:errors.append('side plank knee visibly bent')
        if max(max(v) for v in ranges.values())>.001:errors.append('side plank not static')
        if abs(motion['upperarm_l'][0].z-motion['upperarm_r'][0].z)<.27:errors.append('torso not lateral')
    if e=='step_jack':
        for s in ('l','r'):require('foot_'+s,0,.20);require('foot_'+s,2,.025)
        if any(min(contact_heights['foot_l'][i],contact_heights['foot_r'][i])>.006 for i in range(361)):errors.append('both feet airborne')
    result=dict(exercise=e,samples=361,worst_joint_gap_m=worst,max_relative_bone_length_error=stretch,loop_gap_m=loop,support_drift_m=drift,minimum_skin_height_m=minimum,grounded_foot_step_m=slide,contact_height_ranges={p:[min(contact_heights[p]),max(contact_heights[p])] for p in contact if p in patches},landmark_range_m=ranges,envelope_min_m=low,envelope_max_m=high,errors=errors)
    print('LOWER_CHECK',json.dumps(result),flush=True);return result

def main():
    p=argparse.ArgumentParser();p.add_argument('--exercise',choices=IDS);p.add_argument('--glb');p.add_argument('--inject-root-slide',action='store_true');p.add_argument('--inject-joint-gap',action='store_true');p.add_argument('--inject-frozen',action='store_true');a=p.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    results=[check(e,a) for e in ([a.exercise] if a.exercise else IDS)]
    tag='negative' if a.inject_root_slide or a.inject_joint_gap or a.inject_frozen else 'verification'
    (WORK/f'lower-{tag}.json').write_text(json.dumps(results,indent=2))
    assert not any(r['errors'] for r in results),json.dumps({r['exercise']:r['errors'] for r in results if r['errors']})
if __name__=='__main__':main()
