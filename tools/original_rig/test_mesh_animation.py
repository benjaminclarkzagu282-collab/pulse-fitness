"""Compression must preserve actual per-vertex movement, not only total energy."""
import unittest
import numpy as np
try:
    from mesh_animation import compress_frames
except ImportError:
    compress_frames = None
try:
    from mesh_animation import unsigned_components
except ImportError:
    unsigned_components = None


class MeshAnimationTest(unittest.TestCase):
    def setUp(self):
        self.assertTrue(callable(compress_frames), 'mesh compression is not implemented')

    def test_roundtrip_with_independent_motion_and_signed_weights(self):
        t = np.linspace(0, 2*np.pi, 31)
        basis = np.array([[0., 0., 0.], [1., 2., 3.]])
        frames = np.repeat(basis[None], len(t), axis=0)
        frames[:, 0, 0] += .4*np.sin(t)
        frames[:, 1, 2] += .2*(np.cos(t)-1)
        targets, weights, error = compress_frames(frames, 1e-6)
        decoded = frames[0] + np.einsum('fk,kvc->fvc', weights, targets)
        self.assertLess(np.linalg.norm(decoded-frames, axis=2).max(), 1e-6)
        self.assertEqual(len(targets), 2)
        self.assertLess(weights.min(), 0)
        self.assertTrue(np.allclose(weights[0], 0))

    def test_small_local_motion_must_obey_vertex_error_limit(self):
        frames = np.zeros((24, 100, 3))
        frames[:, :, 0] = np.linspace(0, 1, 24)[:, None]
        frames[:, 0, 1] = .002*np.sin(np.linspace(0, 4*np.pi, 24))
        targets, weights, error = compress_frames(frames, .00015)
        decoded = frames[0] + np.einsum('fk,kvc->fvc', weights, targets)
        self.assertLessEqual(np.linalg.norm(decoded-frames, axis=2).max(), .00015)

    def test_static_mesh_has_no_targets(self):
        targets, weights, error = compress_frames(np.ones((10, 5, 3)), .00015)
        self.assertEqual(targets.shape, (0, 5, 3))
        self.assertEqual(weights.shape, (10, 0))
        self.assertEqual(error, 0)

    def test_nonfinite_input_is_rejected(self):
        frames = np.zeros((3, 2, 3)); frames[1, 1, 2] = np.nan
        with self.assertRaises(ValueError):
            compress_frames(frames, .00015)

    def test_unsigned_player_weights_preserve_signed_motion(self):
        self.assertTrue(callable(unsigned_components), 'unsigned export is not implemented')
        targets = np.array([[[1., 2., 3.]], [[2., 0., 0.]]])
        weights = np.array([[0., 0.], [-1., .5], [.4, 1.]])
        exported, coefficients = unsigned_components(targets, weights)
        self.assertGreaterEqual(coefficients.min(), 0)
        self.assertLessEqual(coefficients.max(), 1)
        self.assertTrue(np.allclose(np.einsum('fk,kvc->fvc', weights, targets),
                                    np.einsum('fk,kvc->fvc', coefficients, exported)))

if __name__ == '__main__':
    unittest.main()
