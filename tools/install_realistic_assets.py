"""Validate every staged asset, preserve the previous set, then install locally."""
import json
import shutil
from pathlib import Path

from PIL import Image
from finalize_character_assets import IDS, validate

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / '.build/realistic-character'
STAGED = WORK / 'output'
report = {exercise: validate(STAGED / f'models/athlete_{exercise}.glb', texture_limit=2048)
          for exercise in IDS}
names = [*IDS, 'hero', 'home', 'avatar']
for name in names:
    path = STAGED / f'images/athlete_{name}.png'
    image = Image.open(path)
    assert image.mode == 'RGBA' and image.getbbox(), f'Empty render: {path}'
    if name != 'avatar':
        box = image.getbbox()
        assert box[0] > 0 and box[1] > 0 and box[2] < image.width and box[3] < image.height, \
            f'Clipped silhouette: {path}'
assert (WORK / 'athlete-animated.blend').is_file(), 'Editable animated source missing'

# No bundled file is touched until the full staged set has passed validation.
for folder in ('models', 'images'):
    backup = WORK / 'previous-assets' / folder
    backup.mkdir(parents=True, exist_ok=True)
    for source in (ROOT / 'assets' / folder).glob('athlete_*'):
        if not (backup / source.name).exists():
            shutil.copy2(source, backup / source.name)
    for source in (STAGED / folder).glob('athlete_*'):
        shutil.copy2(source, ROOT / 'assets' / folder / source.name)
(ROOT / 'assets/models/validation.json').write_text(json.dumps(report, indent=2) + '\n')
delivery = ROOT.parent / 'characters/02_健身人物成品'
delivery.mkdir(exist_ok=True)
shutil.copy2(WORK / 'athlete-animated.blend', delivery / '健身人物_材质骨骼与八种动作.blend')
print(json.dumps({'models': len(report), 'images': len(names),
                  'model_bytes': sum(r['bytes'] for r in report.values()),
                  'editable_source': str(delivery / '健身人物_材质骨骼与八种动作.blend')},
                 ensure_ascii=False, indent=2))
