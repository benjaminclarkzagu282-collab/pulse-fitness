"""Validate structure only: passing never certifies source weights or anatomy."""
from collections import Counter
import math
import re


def canonical(name):
    # Blender makes otherwise duplicate MAX node names unique this way.
    return re.sub(r'\.\d{3}$', '', name)


def validate(observation, expected_bones):
    names=observation['bone_names']
    missing=Counter(expected_bones)-Counter(canonical(n) for n in names)
    errors=[]
    if missing:
        errors.append({'code':'missing_original_bones','names':list(missing.elements())})
    if observation['armature_modifier_count'] != 1:
        errors.append({'code':'body_needs_one_armature_modifier'})
    rows=observation['weights'];count=observation['vertex_count']
    if count<=0 or len(rows)!=count:
        errors.append({'code':'missing_body_vertex_data'})
    unbound=[];invalid=[];name_set=set(names)
    for i,row in enumerate(rows):
        if not row or not any(math.isfinite(w) and w>0 for _,w in row):
            unbound.append(i)
        if (any(n not in name_set or not math.isfinite(w) or w<0 for n,w in row)
                or not math.isfinite(sum(w for _,w in row))
                or abs(sum(w for _,w in row)-1)>0.002):
            invalid.append(i)
    if unbound:errors.append({'code':'unbound_vertices','count':len(unbound),'first':unbound[:10]})
    if invalid:errors.append({'code':'invalid_weights','count':len(invalid),'first':invalid[:10]})
    return {'structure_passed':not errors,'errors':errors,
            'body_vertices':count,'bone_count':len(names),
            'max_influences':max((len(row) for row in rows),default=0),
            'ready_for_app':False,'original_weight_fidelity_verified':False,
            'pending':['source_weight_comparison','pose_review','web_roundtrip_review']}
