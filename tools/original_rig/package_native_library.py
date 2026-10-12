"""Gate and reversibly package all 24 verified original-Skin demonstrations.

This process copies existing approved GLB bytes; it never re-exports models.
Run --check-only to inspect the complete delivery without changing app assets.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import shutil
import sys
from datetime import datetime, timezone


ROOT = Path(__file__).resolve().parents[2]
APPROVED_IDS = ("shoulder_press", "curl")
EXPECTED_IDS = frozenset((
    "squat", "pushup", "lunge", "bridge", "plank", "row", "jumping_jack", "curl",
    "kneeling_pushup", "incline_pushup", "floor_press", "shoulder_press",
    "lateral_raise", "single_arm_row", "reverse_fly", "romanian_deadlift",
    "sumo_squat", "split_squat", "lateral_lunge", "calf_raise", "dead_bug",
    "bird_dog", "side_plank", "step_jack",
))


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def viewer_point(world):
    # The builder reports Blender world metres (Z-up); GLB is glTF Y-up.
    x, y, z = world
    return [x, z, -y]


def native_camera(entry, floor):
    bounds = entry.get("world_bounds")
    if not isinstance(bounds, dict):
        raise ValueError("Native camera requires world_bounds")
    minimum, maximum = bounds.get("min"), bounds.get("max")
    if not (isinstance(minimum, list) and isinstance(maximum, list)
            and len(minimum) == len(maximum) == 3
            and all(isinstance(v, (int, float)) and math.isfinite(v) for v in minimum + maximum)
            and all(low < high for low, high in zip(minimum, maximum))):
        raise ValueError("Native world_bounds must have finite non-empty axes")
    corners = [viewer_point([x, y, z]) for x in (minimum[0], maximum[0])
               for y in (minimum[1], maximum[1]) for z in (minimum[2], maximum[2])]
    low = [min(point[i] for point in corners) for i in range(3)]
    high = [max(point[i] for point in corners) for i in range(3)]
    center = [(a + b) / 2 for a, b in zip(low, high)]
    sizes = [b - a for a, b in zip(low, high)]
    width = math.hypot(sizes[0], sizes[2])
    height = sizes[1]
    phi = math.radians(75)
    depth_margin = height / 2 * math.cos(phi) + width / 2 * math.sin(phi)
    projected_height = height * math.sin(phi) + width * math.cos(phi)
    distance = max(2.8, projected_height * 1.16 / (2 * math.tan(math.pi / 12)) + depth_margin + .3)
    camera = {"floor": floor, "minDistance": round(distance, 6),
              "motionWidth": round(width, 6), "motionHeight": round(height, 6),
              "depthMargin": round(depth_margin, 6)}
    target = " ".join(f"{0 if round(value, 6) == 0 else round(value, 6):.6f}".rstrip('0').rstrip('.')+'m'
                      for value in center)
    return target, camera


def artifact_hash(entry, kind, filename):
    hashes = entry.get("artifact_hashes", {})
    if kind == "glb":
        return entry.get("glb_sha256") or hashes.get("glb") or hashes.get(filename)
    return entry.get("source_sha256") or hashes.get("source") or hashes.get(filename)


def validate_delivery(root, folder, approved):
    catalog = read_json(root / "assets/muscles/catalog.json")
    build = read_json(folder / "build-report.json")
    verified = read_json(folder / "verification.json")
    for description, entries in (("catalog", catalog.get("exercises")),
                                 ("build", build.get("exercises")),
                                 ("verification", verified.get("exercises"))):
        if not isinstance(entries, dict) or set(entries) != EXPECTED_IDS:
            raise ValueError(f"The {description} must contain a complete 24-exercise set")
    if verified.get("passed") is not True:
        raise ValueError("The native library has not passed aggregate verification")
    if catalog.get("duration") != 6:
        raise ValueError("The native library requires the shared six-second catalog")
    if not build.get("source_skin_fingerprint"):
        raise ValueError("Missing original Skin fingerprint in build report")
    report_hash = verified.get("build_report_sha256")
    if report_hash and report_hash != sha256(folder / "build-report.json"):
        raise ValueError("Build report hash changed after verification")
    artifacts = {}
    # Validate every input before creating a backup or changing any destination.
    for exercise in catalog["exercises"]:
        entry = build["exercises"][exercise]
        check = verified["exercises"][exercise]
        if check.get("passed") is not True:
            raise ValueError(f"Native exercise did not pass verification: {exercise}")
        if entry.get("bone_count", entry.get("native_bones")) != 81:
            raise ValueError(f"Native exercise must retain 81 source bones: {exercise}")
        files = {"glb": folder / f"{exercise}.glb",
                 "source": folder / f"{exercise}-native-source.blend"}
        hashes = {}
        for kind, path in files.items():
            if not path.is_file() or path.stat().st_size == 0:
                raise ValueError(f"Missing native {kind} artifact: {path}")
            hashes[kind] = sha256(path)
            expected = artifact_hash(entry, kind, path.name)
            if not expected or expected != hashes[kind]:
                raise ValueError(f"Native {kind} hash does not match build: {exercise}")
        verified_hash = artifact_hash(check, "glb", files["glb"].name)
        if not verified_hash or verified_hash != hashes["glb"]:
            raise ValueError(f"Native GLB hash does not match verification: {exercise}")
        source_verified_hash = artifact_hash(check, "source", files["source"].name)
        if source_verified_hash and source_verified_hash != hashes["source"]:
            raise ValueError(f"Native source hash does not match verification: {exercise}")
        if exercise in APPROVED_IDS:
            sample = approved / f"{exercise}.glb"
            if not sample.is_file() or sha256(sample) != hashes["glb"]:
                raise ValueError(f"The approved native sample bytes changed: {exercise}")
        target, camera = native_camera(entry, catalog["exercises"][exercise]["camera"]["floor"])
        preview = folder / f"{exercise}-preview.png"
        artifacts[exercise] = {"files": files, "hashes": hashes, "preview": preview,
                               "cameraTarget": target, "camera": camera}
    return catalog, build, verified, artifacts


def copy_atomic(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name(destination.name + ".native-pending")
    try:
        shutil.copy2(source, temporary)
        temporary.replace(destination)
    finally:
        temporary.unlink(missing_ok=True)


def package(root, folder, approved, check_only=False):
    catalog, build, verified, artifacts = validate_delivery(root, folder, approved)
    if check_only:
        return {"passed": True, "check_only": True, "exercise_count": len(artifacts)}
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
    backup = root / ".build/original-rig/native-app-backups" / stamp
    destinations = [root / "assets/muscles/catalog.json"]
    for exercise, artifact in artifacts.items():
        destinations.append(root / f"assets/models/athlete_{exercise}.glb")
        if artifact["preview"].is_file():
            destinations.append(root / f"assets/images/athlete_{exercise}.png")
    old_paths = []
    for path in destinations:
        if path.is_file():
            saved = backup / path.relative_to(root)
            saved.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, saved)
            old_paths.append(path.relative_to(root).as_posix())
    backup.mkdir(parents=True, exist_ok=True)
    (backup / "backup-manifest.json").write_text(json.dumps({"created_utc": stamp, "paths": old_paths}, indent=2) + "\n")
    try:
        for exercise, artifact in artifacts.items():
            copy_atomic(artifact["files"]["glb"], root / f"assets/models/athlete_{exercise}.glb")
            if artifact["preview"].is_file():
                copy_atomic(artifact["preview"], root / f"assets/images/athlete_{exercise}.png")
            catalog["exercises"][exercise].update({"cameraTarget": artifact["cameraTarget"], "camera": artifact["camera"]})
        catalog_path = root / "assets/muscles/catalog.json"
        temporary_catalog = catalog_path.with_name("catalog.json.native-pending")
        temporary_catalog.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        temporary_catalog.replace(catalog_path)
    except Exception:
        for relative in old_paths:
            copy_atomic(backup / relative, root / relative)
        for path in destinations:
            if path.relative_to(root).as_posix() not in old_paths:
                path.unlink(missing_ok=True)
        raise
    # Keep the already-served Flutter build synchronized until the full rebuild.
    for path in destinations + [root / "assets/muscles/controller.js"]:
        copy_atomic(path, root / "build/web/assets" / path.relative_to(root))
    copy_atomic(root / "web/exercise-review.html", root / "build/web/exercise-review.html")
    report = {
        "passed": True, "created_utc": stamp, "input_dir": str(folder), "backup_dir": str(backup),
        "build_report_sha256": sha256(folder / "build-report.json"),
        "verification_sha256": sha256(folder / "verification.json"),
        "source_skin_fingerprint": build["source_skin_fingerprint"],
        "original_native_bones": 81,
        "runtime": "baked_mesh_animation_from_all_original_influences",
        "approved_samples_unchanged": list(APPROVED_IDS),
        "exercises": {exercise: {"model": f"assets/models/athlete_{exercise}.glb",
                                  "glb_sha256": artifact["hashes"]["glb"],
                                  "source_sha256": artifact["hashes"]["source"],
                                  "preview_updated": artifact["preview"].is_file(),
                                  "cameraTarget": artifact["cameraTarget"], "camera": artifact["camera"]}
                      for exercise, artifact in artifacts.items()},
    }
    report_path = root / "docs/reports/native-library-integration.json"
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-dir", required=True, type=Path)
    parser.add_argument("--root", type=Path, default=ROOT, help=argparse.SUPPRESS)
    parser.add_argument("--approved-dir", type=Path)
    parser.add_argument("--check-only", action="store_true")
    args = parser.parse_args()
    root = args.root.resolve()
    approved = (args.approved_dir or root / ".build/original-rig/native-review-02").resolve()
    try:
        report = package(root, args.input_dir.resolve(), approved, args.check_only)
    except (ValueError, KeyError, OSError, TypeError) as error:
        print(f"Native library packaging refused: {error}", file=sys.stderr)
        return 1
    if args.check_only:
        print("All 24 native demonstrations passed the packaging gate. App assets are unchanged.")
    else:
        print(f"Packaged 24 verified native demonstrations. Previous delivery: {report['backup_dir']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
