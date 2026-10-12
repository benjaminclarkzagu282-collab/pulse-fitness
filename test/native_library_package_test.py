"""Real-file checks for the native delivery gate and reversible app replacement."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools/original_rig/package_native_library.py"
CATALOG = json.loads((ROOT / "assets/muscles/catalog.json").read_text())


class NativeLibraryPackagingTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.folder = self.root / ".build/original-rig/native-library-01"
        self.approved = self.root / ".build/original-rig/native-review-02"
        self.folder.mkdir(parents=True)
        self.approved.mkdir(parents=True)
        for relative in ("assets/models", "assets/images", "assets/muscles", "web"):
            (self.root / relative).mkdir(parents=True)
        (self.root / "web/exercise-review.html").write_text("Native review page")
        (self.root / "assets/muscles/catalog.json").write_text(json.dumps(CATALOG))
        (self.root / "assets/muscles/controller.js").write_text("Shared controls")
        self.build = {"source_skin_fingerprint": "original-fingerprint", "exercises": {}}
        self.verified = {"passed": True, "exercises": {}}
        for exercise in CATALOG["exercises"]:
            model = f"Native GLB {exercise}".encode()
            source = f"Native original Skin {exercise}".encode()
            (self.folder / f"{exercise}.glb").write_bytes(model)
            (self.folder / f"{exercise}-native-source.blend").write_bytes(source)
            (self.folder / f"{exercise}-preview.png").write_bytes(f"Preview {exercise}".encode())
            (self.root / f"assets/models/athlete_{exercise}.glb").write_bytes(f"Old model {exercise}".encode())
            (self.root / f"assets/images/athlete_{exercise}.png").write_bytes(f"Old preview {exercise}".encode())
            if exercise in ("curl", "shoulder_press"):
                (self.approved / f"{exercise}.glb").write_bytes(model)
            model_hash = hashlib.sha256(model).hexdigest()
            self.build["exercises"][exercise] = {
                "bone_count": 81,
                "glb_sha256": model_hash,
                "artifact_hashes": {"glb": model_hash, "source": hashlib.sha256(source).hexdigest()},
                "world_bounds": {"min": [-.5, -1, 0], "max": [.5, 1, 2.4]},
                "timeTargets": [{"time": n / 30, "L": {"grip_center": [1, 2, 3]}} for n in range(181)],
            }
            self.verified["exercises"][exercise] = {"passed": True, "glb_sha256": model_hash}
        self.write_reports()

    def write_reports(self):
        (self.folder / "build-report.json").write_text(json.dumps(self.build))
        (self.folder / "verification.json").write_text(json.dumps(self.verified))

    def run_package(self, *arguments):
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--root", str(self.root), "--input-dir", str(self.folder), *arguments],
            capture_output=True,
            text=True,
            check=False,
        )

    def assert_untouched(self):
        for exercise in CATALOG["exercises"]:
            self.assertEqual((self.root / f"assets/models/athlete_{exercise}.glb").read_bytes(), f"Old model {exercise}".encode())
        self.assertEqual(json.loads((self.root / "assets/muscles/catalog.json").read_text()), CATALOG)
        self.assertFalse((self.root / ".build/original-rig/native-app-backups").exists())

    def test_complete_verified_library_replaces_models_and_preserves_previous_delivery(self):
        result = self.run_package()
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads((self.root / "docs/reports/native-library-integration.json").read_text())
        backup = Path(report["backup_dir"])
        self.assertEqual(len(report["exercises"]), 24)
        for exercise in CATALOG["exercises"]:
            self.assertEqual((self.root / f"assets/models/athlete_{exercise}.glb").read_bytes(), f"Native GLB {exercise}".encode())
            self.assertEqual((backup / f"assets/models/athlete_{exercise}.glb").read_bytes(), f"Old model {exercise}".encode())
            self.assertEqual((self.root / f"build/web/assets/assets/models/athlete_{exercise}.glb").read_bytes(), f"Native GLB {exercise}".encode())
        packaged = json.loads((self.root / "assets/muscles/catalog.json").read_text())
        camera = packaged["exercises"]["shoulder_press"]
        self.assertEqual(camera["cameraTarget"], "0m 1.2m 0m")
        self.assertEqual(camera["camera"]["motionHeight"], 2.4)
        self.assertGreater(camera["camera"]["minDistance"], 4.8)
        self.assertEqual(camera["regions"], CATALOG["exercises"]["shoulder_press"]["regions"])
        self.assertEqual(camera["phases"], CATALOG["exercises"]["shoulder_press"]["phases"])
        self.assertEqual((self.root / "build/web/exercise-review.html").read_text(), "Native review page")

    def test_missing_exercise_is_rejected_before_any_replacement(self):
        del self.build["exercises"]["squat"]
        self.write_reports()
        result = self.run_package()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("complete 24", result.stderr)
        self.assert_untouched()

    def test_small_native_offsets_use_plain_metre_coordinates(self):
        self.build['exercises']['squat']['world_bounds'] = {'min': [-.5, -1, 0], 'max': [.500028, 1, 2.4]}
        self.write_reports()
        result = self.run_package()
        self.assertEqual(result.returncode, 0, result.stderr)
        packaged = json.loads((self.root/'assets/muscles/catalog.json').read_text())
        self.assertEqual(packaged['exercises']['squat']['cameraTarget'], '0.000014m 1.2m 0m')

    def test_failed_item_is_rejected_even_when_aggregate_flag_is_true(self):
        self.verified["exercises"]["plank"]["passed"] = False
        self.write_reports()
        result = self.run_package()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("plank", result.stderr)
        self.assert_untouched()

    def test_changed_model_is_rejected_after_verification(self):
        (self.folder / "squat.glb").write_bytes(b"Unverified changed model")
        result = self.run_package()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("hash", result.stderr.lower())
        self.assert_untouched()

    def test_approved_sample_bytes_cannot_be_changed(self):
        (self.approved / "curl.glb").write_bytes(b"Actually approved curl")
        result = self.run_package()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("approved", result.stderr.lower())
        self.assert_untouched()

    def test_check_only_validates_without_replacing_assets(self):
        result = self.run_package("--check-only")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_untouched()

    def test_missing_editable_source_is_rejected(self):
        (self.folder / "squat-native-source.blend").unlink()
        result = self.run_package()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("source", result.stderr.lower())
        self.assert_untouched()

    def test_nonfinite_bounds_cannot_replace_camera(self):
        self.build["exercises"]["curl"]["world_bounds"]["max"][2] = float("inf")
        self.write_reports()
        result = self.run_package()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("bounds", result.stderr.lower())
        self.assert_untouched()


if __name__ == "__main__":
    unittest.main()
