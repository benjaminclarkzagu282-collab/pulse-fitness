"""Negative controls for the independent native delivery gate (no Blender needed)."""
import copy
import importlib.util
import math
import struct
import unittest
from pathlib import Path


class NativeDeliveryGate(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        path = Path(__file__).with_name('verify_native_library.py')
        cls.gate = None
        if path.exists():
            spec = importlib.util.spec_from_file_location('native_delivery_gate', path)
            cls.gate = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(cls.gate)

    def contract(self):
        self.assertIsNotNone(self.gate, 'The delivery verification gate is missing')
        binary = struct.pack('<3f', 0., 3., 6.)
        doc = {
            'bufferViews': [{'buffer': 0, 'byteOffset': 0, 'byteLength': 12}],
            'accessors': [{'bufferView': 0, 'componentType': 5126, 'count': 3,
                           'type': 'SCALAR', 'min': [0.], 'max': [6.]}],
            'materials': [{'name': 'Original Body'}, {'name': 'PULSE Muscle deltoids'}],
            'meshes': [{'name': 'Web Man', 'primitives': [{'material': 0}]},
                       {'name': 'Web PULSE region deltoids', 'primitives': [{'material': 1}]}],
            'animations': [{'name': 'Exercise',
                            'samplers': [{'input': 0, 'interpolation': 'LINEAR'}],
                            'channels': [{'sampler': 0, 'target': {'path': 'weights', 'node': 0}}]}],
        }
        return doc, binary

    def test_baked_runtime_does_not_require_skin_attributes(self):
        doc, binary = self.contract()
        result = self.gate.glb_contract(doc, binary, ['deltoids'])
        self.assertTrue(result['passed'], result)
        self.assertEqual(result['duration_seconds'], 6.)
        self.assertEqual(result['runtime_skin_count'], 0)

    def test_real_sampler_values_override_claimed_duration(self):
        doc, _ = self.contract()
        result = self.gate.glb_contract(doc, struct.pack('<3f', 0., 2., 5.), ['deltoids'])
        self.assertFalse(result['passed'])
        self.assertIn('animation_duration', [e['code'] for e in result['errors']])

    def test_unassigned_material_does_not_count_as_muscle_coverage(self):
        doc, binary = self.contract()
        doc['meshes'][1]['primitives'][0]['material'] = 0
        result = self.gate.glb_contract(doc, binary, ['deltoids'])
        self.assertFalse(result['passed'])
        self.assertIn('missing_region_materials', [e['code'] for e in result['errors']])

    def test_nonfinite_and_unsorted_time_data_are_rejected(self):
        doc, _ = self.contract()
        for values in [(0., math.nan, 6.), (0., 6., 3.)]:
            with self.subTest(values=values):
                result = self.gate.glb_contract(doc, struct.pack('<3f', *values), ['deltoids'])
                self.assertFalse(result['passed'])
                self.assertIn('invalid_animation_times', [e['code'] for e in result['errors']])

    def test_changed_weights_cannot_pass_with_81_bones(self):
        self.assertIsNotNone(self.gate, 'The delivery verification gate is missing')
        baseline = {'bone_names': ['bone'+str(i) for i in range(81)],
                    'bind_fingerprint': 'bind-a', 'weight_fingerprint': 'weights-a',
                    'group_names': ['bone0'], 'vertices': 2, 'max_influences': 8,
                    'armature_modifiers': 1, 'invalid_weight_vertices': 0}
        changed = copy.deepcopy(baseline)
        changed['weight_fingerprint'] = 'weights-b'
        result = self.gate.skin_contract(changed, baseline)
        self.assertFalse(result['passed'])
        self.assertIn('source_weights_changed', [e['code'] for e in result['errors']])

    def test_complete_manifest_rejects_missing_and_failed_entries(self):
        self.assertIsNotNone(self.gate, 'The delivery verification gate is missing')
        ids = ['a', 'b', 'c']
        entries = {name: {'passed': True} for name in ids}
        self.assertTrue(self.gate.library_contract(entries, ids)['passed'])
        del entries['b']
        self.assertFalse(self.gate.library_contract(entries, ids)['passed'])
        entries['b'] = {'passed': False}
        self.assertFalse(self.gate.library_contract(entries, ids)['passed'])

    def test_dense_delivery_checks_every_key_and_midpoint_through_six_seconds(self):
        for fps in (30, 90):
            times = self.gate.capture_times(fps)
            self.assertEqual(len(times), fps*12+1)
            self.assertEqual(times[0], 0.)
            self.assertEqual(times[-1], 6.)
            self.assertIn(.5/fps, times)
            self.assertIn(3.+.5/fps, times)

    def test_calf_raise_tracks_stationary_toe_pads_instead_of_rising_heels(self):
        self.assertEqual(self.gate.contact_policy('calf_raise'), ['forefoot_L', 'forefoot_R'])
        self.assertEqual(self.gate.contact_policy('squat'), ['foot_L', 'foot_R'])

    def test_missing_held_equipment_is_rejected(self):
        self.assertIsNotNone(self.gate, 'The delivery verification gate is missing')
        self.assertTrue(callable(getattr(self.gate, 'equipment_contract', None)), 'Equipment gate is missing')
        self.assertTrue(self.gate.equipment_contract('single_arm_row', ['R'], True)['passed'])
        self.assertFalse(self.gate.equipment_contract('row', ['L'], False)['passed'])
        self.assertFalse(self.gate.equipment_contract('incline_pushup', [], False)['passed'])

    def test_wrong_handle_size_or_attachment_is_rejected(self):
        self.assertIsNotNone(self.gate, 'The delivery verification gate is missing')
        self.assertTrue(callable(getattr(self.gate, 'grip_contract', None)), 'Grip geometry gate is missing')
        valid = {'handle_diameter_m': .028, 'handle_length_m': .165,
                 'plate_radius_m': .06375, 'grip_center_error_m': .0001,
                 'handle_samples': 8, 'max_handle_penetration_m': .0001,
                 'max_plate_penetration_m': 0.}
        self.assertTrue(self.gate.grip_contract(valid)['passed'])
        for field, value in [('handle_diameter_m', .055), ('grip_center_error_m', .02),
                             ('max_plate_penetration_m', .01)]:
            with self.subTest(field=field):
                changed = dict(valid, **{field: value})
                self.assertFalse(self.gate.grip_contract(changed)['passed'])

    def test_overlay_cannot_drop_body_influences(self):
        self.assertIsNotNone(self.gate, 'The delivery verification gate is missing')
        self.assertTrue(callable(getattr(self.gate, 'overlay_weight_contract', None)), 'Overlay gate is missing')
        body = [{'a': .2, 'b': .3, 'c': .1, 'd': .1, 'e': .3}]
        self.assertTrue(self.gate.overlay_weight_contract(body, body)['passed'])
        shortened = [{'a': .2, 'b': .3, 'c': .1, 'd': .4}]
        self.assertFalse(self.gate.overlay_weight_contract(body, shortened)['passed'])

    def test_surface_mapping_respects_original_vertex_order_at_a_seam(self):
        self.assertIsNotNone(self.gate, 'The delivery verification gate is missing')
        self.assertTrue(callable(getattr(self.gate, 'ordered_surface_mapping', None)), 'Surface mapping is missing')
        candidates = [[(0, .0008)], [(3, .00078), (1, .0008)], [(2, .0008)], [(3, .0008)]]
        self.assertEqual(self.gate.ordered_surface_mapping(candidates), [0, 1, 2, 3])


if __name__ == '__main__':
    unittest.main()
