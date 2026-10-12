"""Combine unchanged, independently checked actions with freshly checked fixes.

No failed result is reusable. All inputs must come from the exact same verifier,
baseline and thresholds; actual files, build hashes and sampling coverage are
checked again before a complete aggregate can replace verification.json.
"""
import argparse
import copy
import json
from pathlib import Path

from package_native_library import EXPECTED_IDS, artifact_hash
from verify_native_library import sha256, capture_times, library_contract, THRESHOLDS


def merge(folder, reports):
    build_path = folder/'build-report.json'
    build = json.loads(build_path.read_text())
    verifier_hash = sha256(Path(__file__).with_name('verify_native_library.py'))
    result = None
    selected = {}
    lineage = []
    for path in reports:
        report = json.loads(path.read_text())
        if report['verifier_sha256'] != verifier_hash or report['thresholds'] != THRESHOLDS:
            raise ValueError('Verification implementation or thresholds differ: '+str(path))
        baseline = Path(report['baseline_source'])
        if report['baseline_source_sha256'] != sha256(baseline):
            raise ValueError('Baseline source changed: '+str(path))
        if result is None:
            result = copy.deepcopy(report)
        elif any(report[k] != result[k] for k in ('baseline_source', 'baseline_source_sha256', 'source_skin_fingerprint')):
            raise ValueError('Reports use different native source evidence')
        accepted = []
        for exercise, entry in report['exercises'].items():
            if not entry['passed']:
                continue
            if exercise not in EXPECTED_IDS or entry.get('errors') or not all(
                entry.get(k, {}).get('passed') is True for k in ('source', 'glb', 'roundtrip')):
                raise ValueError('Invalid passed result: '+exercise)
            metadata = build['exercises'][exercise]
            fps = metadata.get('fps', 30)
            if entry['roundtrip']['sample_times_seconds'] != capture_times(fps) or entry['source']['samples'] != fps*6+1:
                raise ValueError('Sampling does not cover the current delivery: '+exercise)
            for kind in ('glb', 'source'):
                suffix = '.glb' if kind == 'glb' else '-native-source.blend'
                actual = folder/(exercise+suffix)
                if Path(entry[kind+'_path']).resolve() != actual.resolve():
                    raise ValueError('Report names a different artifact: '+exercise)
                digest = sha256(actual)
                if entry[kind+'_sha256'] != digest or artifact_hash(metadata, kind, actual.name) != digest:
                    raise ValueError('Artifact changed after independent verification: '+exercise)
            if exercise in selected and selected[exercise] != entry:
                raise ValueError('Conflicting verification results: '+exercise)
            selected[exercise] = copy.deepcopy(entry)
            accepted.append(exercise)
        lineage.append({'report': str(path.resolve()), 'sha256': sha256(path), 'accepted_exercises': accepted})
    if result is None:
        raise ValueError('No verification reports supplied')
    aggregate = library_contract(selected, EXPECTED_IDS)
    if not aggregate['passed']:
        raise ValueError('Incomplete passed set: '+json.dumps(aggregate))
    result.update(aggregate)
    result['exercises'] = selected
    result['build_report_sha256'] = sha256(build_path)
    result['verification_lineage'] = lineage
    destination = folder/'verification.json'
    temporary = destination.with_name(destination.name+'.pending')
    temporary.write_text(json.dumps(result, indent=2, ensure_ascii=False, allow_nan=False)+'\n')
    temporary.replace(destination)
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input-dir', required=True, type=Path)
    parser.add_argument('--reports', nargs='+', required=True, type=Path)
    args = parser.parse_args()
    try:
        merged = merge(args.input_dir.resolve(), args.reports)
    except (ValueError, KeyError, OSError) as exc:
        parser.exit(1, 'Verification merge refused: '+str(exc)+'\n')
    print('All 24 actions independently passed; current hashes and full sampling coverage confirmed.')
