# PULSE character asset upgrade

> Historical report for the 2026-09-27 MakeHuman version. Current bundled assets were replaced on 2026-09-28; see [realistic-character-upgrade.md](realistic-character-upgrade.md). Current source/license information is in `docs/assets/character-sources.json`.

Delivered 2026-09-27. The former disconnected primitive mannequin is replaced by one consistent, **stylized adult with real human proportions**, generated from the existing MakeHuman continuous base mesh and its authored deformation weights. This is an asset-based skinned character, not a photorealistic scan or motion-capture performance.

## Delivered files

- Eight models: `assets/models/athlete_{squat,pushup,lunge,bridge,plank,row,jumping_jack,curl}.glb`.
- Matching tightly cropped transparent `assets/images/athlete_<id>.png` thumbnails; `athlete_hero.png` is the squat and `athlete_avatar.png` is a nonempty 384 × 384 face portrait.
- Reusable packed Blender source: `.build/character/athlete-source.blend` (about 4 MB; intentionally ignored with downloaded authoring dependencies).
- Visual review sheet: [athlete-preview.png](../assets/athlete-preview.png).
- Machine-readable checks and output SHA-256 digests: [validation.json](../../assets/models/validation.json).
- Exact provenance, input archive hashes, authors and modifications: [character-sources.json](../assets/character-sources.json). Full asset license: [CC0](../assets/character-CC0-license.md).

Stable exercise IDs remain unchanged. The `athlete_` filename prefix deliberately invalidates old browser asset URLs. Old unprefixed models/images are removed from the working tree; their prior versions remain in Git history. No Dart files or pubspec were edited by the character task.

## Mesh, skeleton, materials and motion

The source uses MPFB's official MakeHuman base, adult masculine macro targets (age .5, muscle .85), the 53-joint `game_engine` skeleton and authored skin weights. Visible neck, limbs, face and fingers are actual continuous human surfaces. Helper geometry and skin fully occluded by clothing are removed for export, as in a clothed game character; these are not separately constructed cylindrical limbs. Body and hair receive one subdivision level, preserving weighted deformation and curved silhouettes.

The costume uses Margaret Toigo's existing CC0 crew-neck T-shirt, extended and widened at its lower hem, and Cortu Johnstone's CC0 cargo trousers cropped above the knee and recolored as charcoal training shorts. MakeHuman's short02 textured hair is darkened; shoes05 preserves its existing sneaker and sock texture. The face uses the existing young Asian male skin and brown iris atlas. Row/curl have original dumbbells bound to hand bones. Detailed fingers and their bones are retained.

Each GLB has one 4-second `Exercise` clip at 24 fps. Procedural joint targets and two-bone IK drive the actual skeleton. Squat keeps feet in place and directs knees outward toward the feet; reverse lunge steps one leg back and returns, so the lead side does not alternate in this clip. Push-up and plank use fixed hand/foot targets; bridge uses supine shoulders/head, arms along the body, bent knees and fixed feet. Plank has a small breathing movement. Motion is a visual exercise demonstration, not biomechanically validated coaching or mocap.

Blender source is Z-up and faces -Y; glTF's Y-up export faces +Z. This preserves model-viewer front `0deg` and side `90deg`. Only selected character meshes and the armature are exported; render lights, camera and floor are excluded. Images use transparent backgrounds and an eight-pixel outer margin after tight alpha-bound cropping.

Browser inspection caught a difference from Blender: imported skin/shoes initially exported with BLEND and could sort behind hair. Export finalization explicitly sets skin, eyes, clothes and shoes to OPAQUE; hair, eyebrows and lashes use MASK with alpha cutoff .4. Both sides of cloth/hair are rendered. Main task confirmed the corrected face in the actual model-viewer and checked bridge/plank in the browser.

## Size and validation

Every file has 53 joints, one skin and one `Exercise` animation. Character-only exports have 53,768 exported vertices and 102,486 triangles; row/curl include 432 additional prop vertices and 264 additional triangles. This preserves the requested silhouette and fingers rather than aggressively decimating the mesh.

Models are approximately 3.97–4.00 MB each (3.79–3.81 MiB); all eight total about 31.9 MB and are independently loadable. Embedded skin/shoe/hair atlases are at most 1024 pixels; eyes/brows/lashes are 256 pixels. Opaque skin, shoes and eyes use JPEG; cutout textures use PNG. No external texture URL or model dependency is required.

Fresh verification completed for all eight final binaries:

- glTF 2.0 header/length, one skin, expected animation name and embedded buffers.
- Every accessor finite and within readable buffer data; weights normalized within .002.
- Strictly increasing sampled times; 4-second duration; matching first/last transforms within .0001 (quaternion sign equivalence allowed); each clip has changing channels.
- Every exported mesh primitive contains JOINTS_0 and WEIGHTS_0.
- No render cameras/lights in GLBs; final alpha modes restricted to OPAQUE/MASK.
- Every embedded image at most 1024 pixels; all ten final PNGs are nonempty RGBA.
- Actual Blender previews inspected for all eight exercises; initial standing/squat and revised source reviewed by main task. Browser material and bridge pose checks were performed by main task. Python source compiles.

Structural checks do not establish real-device GPU performance or prove zero cloth intersection across every interpolated frame and view. No physical-device frame-rate benchmark was performed. Minor deformation/finger simplification and procedural timing remain visible. The final result is intentionally described as a stylized, skinned instructional character.

## Reproduction

Requirements: Blender 5.2.1, Python 3 with Pillow, Git and curl. Input archives and MPFB source are isolated in the already-ignored `.build/character` directory; no permanent add-on installation or user preference save is needed.

```sh
python3 tools/fetch_character_sources.py
/Applications/Blender.app/Contents/MacOS/Blender --factory-startup --background --python tools/build_athlete.py
/Applications/Blender.app/Contents/MacOS/Blender --factory-startup --background --python tools/animate_athlete.py
python3 tools/finalize_character_assets.py
```

`fetch_character_sources.py` pins MPFB revision `3edf9df0551765be43563d047888cf7877eb89b4` and verifies all three official archive SHA-256 hashes before extraction. `build_athlete.py` creates the packed reusable source. `animate_athlete.py -- --preview` renders standing/squat candidates; `-- --review` renders an eight-pose contact set without exporting. The finalizer compresses and repacks embedded images, crops output PNGs and writes the validation report. MPFB source code remains GPL-3.0; the separate core/garment assets and resulting meshes are CC0. No paid asset or image-generation service was used.
