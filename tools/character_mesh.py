"""Locate actual skin after Blender imports glTF morph animation wrappers."""
import bpy

def body_mesh():
    matches=[o for o in bpy.context.scene.objects if o.type=='MESH' and o.vertex_groups.get('upperarm_l') and o.vertex_groups.get('thigh_l') and not o.name.startswith('PULSE region')]
    # Region copies retain all group names; body also has nonzero leg weights.
    matches=[o for o in matches if all(any(any(g.group==o.vertex_groups[name].index and g.weight>.5 for g in v.groups) for v in o.data.vertices) for name in ('thigh_l','upperarm_l'))]
    assert len(matches)==1,[(o.name,len(o.data.vertices)) for o in matches]
    return matches[0]
