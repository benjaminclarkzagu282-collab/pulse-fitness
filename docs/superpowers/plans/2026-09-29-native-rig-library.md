# Original Rig Library Migration Implementation Plan

> **For agentic workers:** Use the independent task boundaries below, then review the combined delivery. Track progress in `docs/reports/native-library-progress.md`.

**Goal:** Migrate all 24 existing demonstrations to the user's original CAT Skin, preserving the approved native shoulder press and curl, and deliver them in the Flutter app and review page.

**Architecture:** Preserve the source FBX and 81-bone, eight-influence Skin. Retarget the existing reference-authored motion trajectories onto native joint origins and native segment lengths, using native hand grip attachment. Bake the full evaluated Skin to compatible mesh animation for the existing model-viewer; verify the delivered mesh against the editable rig before packaging.

**Tech Stack:** Blender 5.2, Python/NumPy, glTF morph animation, Flutter/model-viewer.

**Spec:** User accepted the native shoulder/curl review and requested migration of the remaining 22 motions on 2026-09-29; baseline evidence is `docs/reports/native-rig-intake-2026-09-29.md`.

## Global Constraints

- Original MAX, FBX and source weights stay unchanged; keep 81 native bones and every original influence in editable sources.
- Keep the approved two demonstration GLBs unchanged.
- Exercise IDs, six-second duration and muscle participation metadata stay compatible with the existing 24-item catalog.
- Demonstrations remain reference-authored animation, not motion capture or coach certification.
- Use actual native joint origins; Blender display tails do not describe CAT length directions.
- No commits, unrelated cleanup or external publication. Existing unfinished workspace changes remain intact.

## Task 1: Native motion solver

**Create:** `tools/original_rig/native_motion.py` and its focused structural/pose checks.

**Interface:** `NativeMotion(rig, exercise)` extends the original solver interface with `pose_time(seconds) -> dict`, `pose(exercise, depth)`, `equipment()` and `reference`. Diagnostics include L/R shoulder, elbow, wrist and grip_center world positions. Read existing `.build/motion-library/{exercise}.blend` or base GLB poses as trajectory references; native body transformations and lengths determine the output.

- [x] Load all 22 existing source actions, map original native chains and retain reference pose matrices.
- [x] Transfer trunk orientation, solve original limb lengths to contact trajectories, distribute forearm rotation, transport head accessories and source roll.
- [x] Use the fitted native fingers for dumbbell motions; support hands and feet use their actual posed skin envelope.
- [x] Check all 181 frames for finite matrices, constant segment lengths, loop seams and contacts; render representative standing and floor poses.

## Task 2: Compatible animation delivery

**Create:** `tools/original_rig/build_native_library.py`; reuse preparation and overlay helpers from `build_native_review.py`.

**Consumes:** NativeMotion interface. **Produces:** per-motion GLB, editable native source, preview PNG, `build-report.json` entries with fingerprint, camera bounds/targets, sample times and baking errors.

- [x] Bake time-based poses without forcing alternating movements into the old single-depth cycle.
- [x] Evaluate all original influences before mesh conversion. Keep interpolation/compression error measurable with a 0.5 mm target.
- [x] Include all muscle regions with exact runtime material names and the same deformation as body.
- [x] Keep build outputs separate until verification succeeds; retain approved shoulder/curl assets.

## Task 3: Verification gate

**Create:** `tools/original_rig/verify_native_library.py`.

**Consumes:** verified approved samples and new build directory. **Produces:** per-motion checks and aggregate `verification.json`; packaging refuses failed items.

- [x] Compare source weight fingerprints and 81 native bones for every editable action.
- [x] Check ground and support contacts, limb chain lengths, finite animation and start/end loop.
- [x] Sample hand surfaces against dumbbell handles and plates.
- [x] Reimport actual GLBs, compare meshes and muscle layers against native sources, and check duration and region names.

## Task 4: App and review integration

**Create/modify:** packaging script, `assets/models`, `assets/images`, muscle catalog camera fields, `web/exercise-review.html`, and docs/status.

**Consumes:** complete 24-motion verified manifest. **Produces:** synchronized Flutter assets and local web build.

- [x] Package only a complete, passed 24-item set; back up prior delivery for reversible replacement.
- [x] Fit cameras to native standing/floor bounds and route all 24 exercise IDs to their new demonstrations.
- [x] Preserve playback, slow speed, muscle selection and workout integration.
- [x] Run focused Python/Flutter/controller checks, rebuild Flutter web, and verify standing, floor, alternating and equipment examples in the browser.
- [x] Save a screenshot, close any temporary transfer services, and report actual completion plus remaining technical limitations.
