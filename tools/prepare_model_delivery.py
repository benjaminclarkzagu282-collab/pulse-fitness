"""Lossless delivery variants; originals and editable rigs are never modified."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUNDLED = {"squat", "pushup"}

def digest(data):
    return hashlib.sha256(data).hexdigest()

def prepare(verify=False):
    target = ROOT / "web/remote/models"
    target.mkdir(parents=True, exist_ok=True)
    manifest_path = ROOT / "assets/muscles/model_manifest.json"
    previous = json.loads(manifest_path.read_text()) if verify else None
    records = {}
    for path in sorted((ROOT / "assets/models").glob("athlete_*.glb")):
        name = path.stem.removeprefix("athlete_")
        raw = path.read_bytes()
        packed_path = target / (path.name + ".gz")
        if verify:
            packed = packed_path.read_bytes()
        else:
            packed = gzip.compress(raw, compresslevel=6, mtime=0)
            packed_path.write_bytes(packed)
        if gzip.decompress(packed) != raw:
            raise ValueError(f"Lossless verification failed: {name}")
        record = {"bytes": len(raw), "compressedBytes": len(packed),
                  "sha256": digest(raw), "compressedSha256": digest(packed),
                  "bundled": name in BUNDLED}
        if previous is not None and previous["models"].get(name) != record:
            raise ValueError(f"Manifest differs from current original: {name}")
        records[name] = record
        print(f"{name}: {len(raw)/1048576:.2f} -> {len(packed)/1048576:.2f} MiB; hash verified", flush=True)
    if len(records) != 24:
        raise ValueError(f"Expected 24 actions, got {len(records)}")
    manifest = {"version": 1, "compression": "gzip-lossless", "models": records}
    if not verify:
        manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    summary = {"passed": True, "actions": len(records),
               "original_bytes": sum(r["bytes"] for r in records.values()),
               "compressed_bytes": sum(r["compressedBytes"] for r in records.values()),
               "bundled_model_bytes": sum(r["bytes"] for r in records.values() if r["bundled"]),
               "all_original_hashes_preserved": True}
    output = ROOT / "docs/reports/model-delivery-lossless.json"
    output.write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary), flush=True)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--verify", action="store_true")
    prepare(parser.parse_args().verify)
