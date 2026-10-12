"""Damage real exported assets in memory to verify binding failures are caught."""
import copy
import struct
import unittest
from verify_library_muscles import ROOT, read, validate_overlay_binding


class OverlayBindingTests(unittest.TestCase):
    def setUp(self):
        self.doc,self.blob=read(ROOT/'assets/models/athlete_squat.glb')
        self.node=next(n for n in self.doc['nodes'] if n.get('name')=='PULSE region quads')

    def test_delivered_skin_matches_source(self):
        validate_overlay_binding(self.doc,self.blob,'quads')

    def test_detached_overlay_is_rejected(self):
        del self.node['skin']
        with self.assertRaises(AssertionError):
            validate_overlay_binding(self.doc,self.blob,'quads')

    def mutated_joint(self,new_joint):
        attrs=self.doc['meshes'][self.node['mesh']]['primitives'][0]['attributes']
        acc=self.doc['accessors'][attrs['JOINTS_0']]
        view=self.doc['bufferViews'][acc['bufferView']]
        offset=view.get('byteOffset',0)+acc.get('byteOffset',0)
        data=bytearray(self.blob)
        struct.pack_into('<'+{5121:'B',5123:'H'}[acc['componentType']],data,offset,new_joint)
        return data

    def test_out_of_range_joint_is_rejected(self):
        data=self.mutated_joint(len(self.doc['skins'][0]['joints']))
        with self.assertRaises(AssertionError):
            validate_overlay_binding(self.doc,data,'quads')

    def test_wrong_but_existing_joint_is_rejected(self):
        data=self.mutated_joint(0)
        with self.assertRaises(AssertionError):
            validate_overlay_binding(self.doc,data,'quads')


if __name__=='__main__':unittest.main()
