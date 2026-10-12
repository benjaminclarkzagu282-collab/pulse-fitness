"""Catch silent fallback to static meshes, guessed rigs, or incomplete Skin data."""
import unittest
from contract import validate

class ImportContract(unittest.TestCase):
    def valid(self):
        return {'bone_names':['Man_LCollarbone','Man_LForearm1'],
                'vertex_count':2, 'armature_modifier_count':1,
                'weights':[[['Man_LCollarbone',1.0]],
                           [['Man_LCollarbone',0.25],['Man_LForearm1',0.75]]]}

    def test_static_fbx_is_rejected(self):
        r=self.valid();r['bone_names']=[];r['weights']=[[],[]];r['armature_modifier_count']=0
        self.assertFalse(validate(r,['Man_LCollarbone','Man_LForearm1'])['structure_passed'])

    def test_auto_rig_with_wrong_names_is_rejected(self):
        r=self.valid();r['bone_names']=['upperarm_l','lowerarm_l']
        self.assertFalse(validate(r,['Man_LCollarbone','Man_LForearm1'])['structure_passed'])

    def test_unbound_vertices_are_rejected(self):
        r=self.valid();r['weights'][1]=[]
        self.assertFalse(validate(r,['Man_LCollarbone','Man_LForearm1'])['structure_passed'])

    def test_bad_weights_are_rejected(self):
        for value in [float('nan'),-0.3,0.2]:
            with self.subTest(value=value):
                r=self.valid();r['weights'][0][0][1]=value
                self.assertFalse(validate(r,['Man_LCollarbone','Man_LForearm1'])['structure_passed'])

    def test_group_without_corresponding_bone_is_rejected(self):
        r=self.valid();r['weights'][0][0][0]='missing_bone'
        self.assertFalse(validate(r,['Man_LCollarbone','Man_LForearm1'])['structure_passed'])

    def test_blender_suffix_preserves_duplicate_source_nodes(self):
        r=self.valid();r['bone_names']=['Man_LCollarbone','Man_LCollarbone.001','Man_LForearm1']
        self.assertTrue(validate(r,['Man_LCollarbone','Man_LCollarbone','Man_LForearm1'])['structure_passed'])
        r['bone_names'].remove('Man_LCollarbone.001')
        self.assertFalse(validate(r,['Man_LCollarbone','Man_LCollarbone','Man_LForearm1'])['structure_passed'])

    def test_valid_structure_never_claims_deformation_acceptance(self):
        result=validate(self.valid(),['Man_LCollarbone','Man_LForearm1'])
        self.assertTrue(result['structure_passed'])
        self.assertFalse(result['ready_for_app'])
        self.assertFalse(result['original_weight_fidelity_verified'])

if __name__=='__main__':unittest.main()
