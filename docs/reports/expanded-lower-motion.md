# Expanded lower-body and core motion review

Date: 2026-09-28. Authoring target: the existing `Man` skin and MakeHuman game-engine rig in `.build/realistic-character/athlete-source.blend`. These clips are reference-authored demonstrations, not motion capture or coach certification. The geometry thresholds below apply to this model; they are not universal exercise prescriptions.

## Delivered files and integration

- Pose implementation: `tools/motion_lower.py`, exposing `IDS`, `pose_exercise(rig, exercise, seconds)`, and a no-op `prepare_equipment`.
- Re-imported GLB checks: `tools/check_motion_lower.py`.
- Editable sources: `.build/motion-library/<id>.blend` for the eight IDs below.
- Baseline clips: `.build/motion-library/base/<id>.glb`.
- Review images: `.build/motion-library/renders/<id>-start.png` and `<id>-end.png`, plus middle or left/right images.
- Machine-readable results: `.build/motion-library/lower-verification.json`.
- Final successful command log: `.build/motion-library/lower-check-final-semantic.log`.

The shared runner imports the new module lazily and preserves the existing eight exercise implementations. This subtask did not edit the old eight GLBs, their pose functions, the shared runner, Flutter, or the catalog. Muscle surfaces and production asset publication are handled by the parent integration task.

Each clip has one `Exercise` animation, 6 seconds at 30 fps, 181 keys per exported sampler, and LINEAR interpolation. Every pose resets all bone bases. Endpoint solves preserve actual source bone lengths; unreachable endpoints raise an authoring error instead of stretching the skeleton.

## Reference-to-motion mapping

| ID | Authored demonstration and reference cues | Primary reference |
|---|---|---|
| `sumo_squat` | Controlled partial-depth wide squat. Feet remain planted, toes turn outward, knees follow the toe direction, and the trunk remains neutral. The partial depth is intentional for this rig. | [University of Calgary, Alberta Cancer Exercise home program, sumo squat](https://kinesiology.ucalgary.ca/sites/default/files/teams/24/ACE%20Home%20Based%20Maint%20Prog%20Jul%202020L.pdf) |
| `split_squat` | Fixed staggered stance, left leg forward and right heel raised. Hips lower and rise without either foot translating. Demonstrate the opposite side separately. | [ACE, static-stance lunge](https://www.acefitness.org/resources/everyone/blog/5257/4-lower-body-movements-for-beginners/) |
| `lateral_lunge` | Stationary wide-stance variation. Alternating hip shift and hip hinge load one leg while the other stays long; both heels stay planted. The catalog must describe the stationary variation. | [ACE, lateral lunge cues](https://www.acefitness.org/resources/everyone/blog/5257/4-lower-body-movements-for-beginners/) |
| `calf_raise` | Bilateral heel raise with controlled return. Hindfeet rotate about the fixed metatarsal joints; toe bones stay flat rather than translating the whole foot upward. | [Mayo Clinic, calf raise](https://www.mayoclinic.org/healthy-lifestyle/fitness/multimedia/calf-raise/vid-20084681) |
| `dead_bug` | Supine tabletop start, opposite arm and leg lower, return, then alternate sides. The trunk stays stationary and the limbs remain above the floor. | [NASM, dead bug](https://www.nasm.org/resource-center/exercise-library/dead-bug) |
| `bird_dog` | One-side demonstration: left arm reaches forward while right leg extends backward, then both return. Right palm and left knee stay under their corresponding shoulder/hip. The catalog must prompt switching sides. | [NASM, bird dog](https://www.nasm.org/resource-center/exercise-library/bird-dog) |
| `side_plank` | Static right-side forearm hold. Elbow below shoulder, trunk laterally oriented, hips elevated, knees nearly straight, feet stacked with a slight stagger. Repeat on the other side separately. | [NASM, side plank](https://www.nasm.org/resource-center/exercise-library/side-plank) |
| `step_jack` | Left foot steps out and back, then right foot. Arms rise and lower with each step; the moving foot clears the floor and the other stays grounded. | [NASM, jumping-jack step-out variation](https://www.nasm.org/resource-center/exercise-library/jumping-jacks) |

References were retrieved through web search after the local Firecrawl CLI reported it was unauthenticated. The university sumo instructions were available in the indexed PDF excerpt even though direct PDF opening failed.

## Timing contract

- Sumo squat, split squat, calf raise, and bird dog use the existing `depth_at`: 0–0.5 s setup, 0.5–3 s outbound/lowering, 3–3.5 s peak, 3.5–5.5 s return, 5.5–6 s reset.
- Lateral lunge and dead bug: 0–0.5 s setup; 0.5–1.5 s first side; 1.5–2.5 s return; 2.5–3.5 s center; 3.5–4.5 s second side; 4.5–5.5 s return; 5.5–6 s reset. For dead bug, first side means left arm/right leg.
- Step jack: 0.5–1.2 s left out, 1.2–1.8 s open hold, 1.8–2.5 s left return; 3.5–4.2 s right out, 4.2–4.8 s hold, 4.8–5.5 s right return. The remaining time is a grounded ready stance.
- Side plank holds one pose for the entire loop.

For alternating exercises, `end.png` intentionally shows the first peak at frame 45, not the neutral pose near frame 97. Separate `left.png` and `right.png` show frames 45 and 135. Other `end.png` files show frame 97; every clip also has a start image.

## Verification and visual repairs

The checker was written and run before creating the new files: `lower-missing-red.log` records the expected missing-GLB failure. Final verification imports the actual GLBs into a fresh Blender scene and samples 361 times at 60 Hz, including half-frame interpolation. It checks joint endpoints including toes and fingers, non-stretching bones, six-second closure, finite landmarks, fixed support bones, evaluated skinned contact patches, no below-floor skin, grounded foot translation, and action-specific amplitude. Semantic checks require opposite dead-bug limbs, stable core positions, wide/staggered stance, actual calf heel lift, stationary side-plank posture with nearly straight knees, and at least one grounded foot throughout step jacks. Peak knee/toe direction checks are model-specific visual regressions for sumo and lateral lunge.

The fixed thresholds remained: joint gap 0.5 mm, support drift and loop closure 0.6 mm, relative bone-length error 0.2%, skin penetration no more than 1 mm, contact envelope no more than 6 mm, and grounded foot displacement per 60 Hz sample no more than 0.5 mm.

Visual review caused geometry changes before freezing the final baselines:

- Sumo knee poles were moved outward to match the approximately 27-degree toe direction at the work pose.
- The lateral lunge stance was made less extreme and the hips moved farther back to produce a coherent hip hinge for this model. This does not encode a general prohibition on knees passing toes.
- Calf raises initially deformed toe skin through the floor. A constant metatarsal height now accommodates the real skin-weight envelope while the toe bones remain fixed.
- Bird-dog support-knee skin initially floated about 25 mm. Hip height and a small neutral trunk incline were matched to the actual knee surface while preserving the shoulder-over-hand reach.
- Side-plank knee bends were reduced by solving nearly full-length legs. The right elbow and lateral foot now support the pose; the nearest foot-to-foot skin separation is approximately 2.4 mm at the heels.

Start, work, alternate-side, and revised work poses were inspected as rendered PNGs. The checker does not estimate human tissue loading, force balance, pain, or individual exercise suitability.

Three negative controls were run against delivered GLBs and all exited with failure as intended:

| Injected defect | Clip | Detected result | Log |
|---|---|---|---|
| 20 mm root slide | calf raise | 20.0001 mm support drift | `lower-negative-root-slide.log` |
| 20 mm wrist disconnect | dead bug | 20.0000 mm elbow-to-hand gap | `lower-negative-joint-gap.log` |
| Frozen frame 0 | split squat | Missing pelvis travel | `lower-negative-frozen.log` |

## Final measurements

All 8 clips passed the final semantic checker. Measurements are in millimetres except the dimensionless bone-length error.

| Clip | Joint gap max | Support drift max | Loop gap | Skin minimum | Bone-length relative error |
|---|---:|---:|---:|---:|---:|
| `sumo_squat` | 0.00052 | 0.02129 | 0.00047 | 0.982 | 0.00000387 |
| `split_squat` | 0.00050 | 0.01205 | 0.00054 | 0.990 | 0.00000298 |
| `lateral_lunge` | 0.00053 | 0.15381 | 0.00061 | 0.876 | 0.00000263 |
| `calf_raise` | 0.00073 | 0.00468 | 0.00038 | 0.093 | 0.00000148 |
| `dead_bug` | 0.00051 | 0.00000 | 0.00060 | 4.836 | 0.00000276 |
| `bird_dog` | 0.00044 | 0.00030 | 0.00035 | 1.608 | 0.00000269 |
| `side_plank` | 0.00039 | 0.00031 | 0.00047 | 1.000 | 0.00000138 |
| `step_jack` | 0.00050 | 0.00000 | 0.00054 | 0.939 | 0.00000298 |

The largest evaluated support-patch clearance is 5.58 mm on the calf-raise forefoot; the smallest skin clearance is 0.0934 mm. Step-jack near-ground foot displacement is 0.1213 mm per sample, within the 0.5 mm regression threshold.

## Reproduction

```sh
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 --python tools/motion_library.py -- --exercise sumo_squat --render
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 --python tools/check_motion_lower.py
```

For alternating peak thumbnails use frames 45 and 135 as documented above; the generic shared render helper defaults to frame 97.

## Artifact lineage

SHA-256 checksums at handoff:

| Artifact | SHA-256 |
|---|---|
| `.build/realistic-character/athlete-source.blend` | `f94a16296fdcade19edc509df33b25993341e4021bc7f245c1b820942f4ddd83` |
| `tools/motion_lower.py` | `136df7b9da20e6f76e7c8a38f9deafd1e011ca64a1ad95c5031e126fdfd11331` |
| `tools/check_motion_lower.py` | `9cf317076fd516c70eb59006c10d9080e5aba54b374011fa5238680ad3069934` |
| `.build/motion-library/base/sumo_squat.glb` | `82ef328dcd95d4d0db59b873413244b8afb27dd2234a2d538cc6bab83470901c` |
| `.build/motion-library/base/split_squat.glb` | `d6b31ebec2abe420d544d8d630ba8475caf791739f9848dfe07868bd88964ade` |
| `.build/motion-library/base/lateral_lunge.glb` | `448932a9a3dbdc655258c4b3f659084597ec6fbe48a9f6479cd7d9197cf5e1ff` |
| `.build/motion-library/base/calf_raise.glb` | `076ed08de9b0d26192ddc4267de6b98f5615861856e6845e5924fcf381cf233a` |
| `.build/motion-library/base/dead_bug.glb` | `91ef53fed44bffe65064ac55a3a86de9522b67e0420ec7b5ec7d830ea9fbc0c0` |
| `.build/motion-library/base/bird_dog.glb` | `ff74e8a83550650c998d695312bcae0c36476e833af6a5b0ec491a5cddad5c01` |
| `.build/motion-library/base/side_plank.glb` | `922eef35c3e125100a566d9a4037e0e8abca3df2a09ebd6e6454e738c927e8b6` |
| `.build/motion-library/base/step_jack.glb` | `b88ee1b49ed2a6e45fe76f0a215079c7ab655fe7e22bcf5fe934bce1b7a04db7` |
