# Original 3D exercise asset report

Implemented only the isolated asset task: `tools/generate_models.py`, eight `assets/models/*.glb`, eight 600px `assets/images/exercise_*.png`, and asset documentation / review evidence. No application, pubspec or test files were edited by this asset task.

## Generation and provenance

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --python tools/generate_models.py
```

Tool version: Blender 5.2.1 LTS. All geometry, colors and motions are original procedural definitions in the script. The person has a shaped graphite shirt, shorts, lime details, matte skin, cropped hair, hands and white/gray running shoes. Row and curl include original dumbbells. No network asset download or third-party art was used.

## Verification

The generator parses each resulting GLB and validates every binary accessor and transform for finite values and buffer bounds. It checks one animation named `Exercise`, nonempty meshes/channels, 4-second duration, increasing sample times, motion changes, closed loop endpoints, and fixed feet/palm anchors for floor-supported movements. The jumping-jack feet intentionally move. Detailed per-file results are in `assets/models/validation.json`.

Rendered all eight thumbnails and reviewed `assets/models/contact-sheet.png` as an image. The review resolved shortened torso geometry, bridge orientation, straight-body pushup posture, forearm plank support and rear-lunge heel placement. Final silhouettes distinguish the eight exercises, keep the mannequin within frame, and show shirt, limbs and shoes under common lighting.

The contact sheet was assembled from the eight 600px PNG files with the bundled Python runtime and Pillow, in catalog order, at 300px per tile with labels. It is review evidence rather than an app asset.

## Remaining concerns

The mannequin uses rigid articulated segments and simplified contact surfaces, not skinning or motion capture. These are stylized generic movement demonstrations without a medical or clinical accuracy claim. Plank has deliberately small breathing motion; lunge loops a single stance. Application-side GLB loading and viewer playback remain part of the parent integration task. Android/iOS builds were not run or claimed by this task.

## Transparent homepage hero

Added `assets/images/hero.png` as a fresh 3D render of the same original athlete in a standing three-quarter pose. Regenerate just this image without exporting or replacing any existing exercise asset:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --python tools/generate_models.py -- --hero-only
```

The helper removes the studio ground mesh before rendering and enables transparent film plus RGBA output. Final PNG inspection: 700×850, RGBA, alpha range 0–255, 492,998 completely transparent pixels, foreground bounds `(207, 72, 461, 818)` (approximately 88% of image height). The full figure remains inside the frame. Visual inspection confirmed the standing posture and absence of a studio background rectangle. A small neck-seam adjustment applies only to this static hero portrait.

Read each of the eight GLBs and eight `exercise_*.png` files and compared its bytes to `git show HEAD:<path>` after rendering: all 16 existing exercise assets are unchanged. No image editing or bitmap background removal was used.

For app camera controls: Blender front is −Y; the Y-up glTF conversion makes the mannequin face +Z. `camera-orbit="0deg …"` views the front, `180deg` views the back, and `90deg` views from +X. GLB export precedes studio setup, so the exercise models contain no studio ground, camera, or lights.
