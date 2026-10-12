"""Independently project all measured native bounds into common viewports."""
import json
import math
from pathlib import Path
from package_native_library import native_camera, viewer_point, sha256

ROOT = Path(__file__).resolve().parents[2]
path = ROOT/'.build/original-rig/native-library-02/build-report.json'
build = json.loads(path.read_text())
catalog = json.loads((ROOT/'assets/muscles/catalog.json').read_text())
report = {'build_report_sha256': sha256(path), 'passed': True, 'exercises': {}}
for exercise, entry in build['exercises'].items():
    target, camera = native_camera(entry, catalog['exercises'][exercise]['camera']['floor'])
    assert catalog['exercises'][exercise]['cameraTarget'] == target
    assert catalog['exercises'][exercise]['camera'] == camera
    low, high = entry['world_bounds']['min'], entry['world_bounds']['max']
    points = [viewer_point([x, y, z]) for x in (low[0], high[0])
              for y in (low[1], high[1]) for z in (low[2], high[2])]
    centre = [(min(p[i] for p in points)+max(p[i] for p in points))/2 for i in range(3)]
    maximum = 0.
    for aspect in (.35, .6, 1., 1.8):
        distance = max(camera['minDistance'], max(camera['motionWidth']*1.16/(2*math.tan(math.pi/12)*aspect),
                       camera['motionHeight']*1.16/(2*math.tan(math.pi/12)))+camera['depthMargin']+.3)
        for elevation in (75, 90):
            phi = math.radians(elevation)
            for azimuth in range(0, 360, 45):
                theta = math.radians(azimuth)
                forward = [math.sin(theta)*math.sin(phi), math.cos(phi), math.cos(theta)*math.sin(phi)]
                right = [math.cos(theta), 0, -math.sin(theta)]
                up = [-math.sin(theta)*math.cos(phi), math.sin(phi), -math.cos(theta)*math.cos(phi)]
                for point in points:
                    delta = [v-c for v, c in zip(point, centre)]
                    depth = distance-sum(a*b for a, b in zip(delta, forward))
                    x = abs(sum(a*b for a, b in zip(delta, right)))/(depth*math.tan(math.pi/12)*aspect)
                    y = abs(sum(a*b for a, b in zip(delta, up)))/(depth*math.tan(math.pi/12))
                    maximum = max(maximum, x, y)
    assert maximum < .96, (exercise, maximum)
    report['exercises'][exercise] = {'max_viewport_fraction': maximum, 'cameraTarget': target, 'camera': camera}
(ROOT/'docs/reports/native-library-camera-check.json').write_text(json.dumps(report, indent=2)+'\n')
print('24 native camera envelopes passed; maximum viewport fraction',
      max(e['max_viewport_fraction'] for e in report['exercises'].values()))
