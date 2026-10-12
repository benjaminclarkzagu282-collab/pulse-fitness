# Squat review sample implementation plan

> Execution: implement inline in the existing feature/fitness-polish checkout. The user approved a single squat sample, with reference, multi-view playback, and a review record.

**Goal:** Produce one inspectable bodyweight squat using the existing realistic character.

**Architecture:** A dedicated squat authoring module operates on the existing bound skeleton. A separate GLB and editable Blender file are delivered in a standalone review page. Existing app clips stay untouched while this sample is reviewed.

**Tech Stack:** Blender 5.2, Python, glTF, the app's bundled model-viewer, HTML/JS.

**Spec:** User-approved five-step proposal in this conversation. First deliverable is a squat sample, synchronized front/side playback and an honest technical/review record.

## Constraints

- Reuse local character and free tools. Do not alter original assets.
- Variant: bodyweight squat, arms reaching forward for counterbalance.
- Reference: ACE Bodyweight Squat, https://www.acefitness.org/resources/everyone/exercise-library/135/bodyweight-squat/ and Mayo Clinic squat video, https://www.mayoclinic.org/healthy-lifestyle/fitness/multimedia/squat/vid-20084663.
- Reference concepts: stable feet, knee/toe direction, coordinated hip/knee flexion, stable trunk, controlled descent/ascent. Numeric poses fit this model; they are not universal human prescriptions.
- No claim of trainer approval or biomechanical certification. Do not redistribute reference media.

## Work

- [x] Inspect current squat at standing/middle/bottom; record limb disconnects and foot motion before edits.
- [x] Add a real skeleton regression check for joint continuity, segment lengths, planted foot transforms and continuous playback. Run against old motion to demonstrate the relevant failure.
- [x] Create tools/squat_sample.py: calibrated stance, length-preserving leg solution, independent neck and arm controls, controlled descent/pause/ascent, dense animation keys.
- [x] Export web/review/squat-v2.glb and an editable Blender file. Render side/front review poses and inspect them before delivery.
- [x] Create web/squat-review.html with synchronized views, scrubber, speed, pause, phase buttons, reference links and review status.
- [x] Validate actual exported GLB after reimport, not only authoring functions. Check every frame and intermediate samples.
- [x] Serve through existing port 8879; inspect actual browser playback and controls on desktop/mobile; report limitations and deliver.

## Regression contract

For every sampled pose, adjacent arm/leg bones meet within 0.5 mm, limb lengths stay within 0.2% of rest, foot transforms stay fixed within 0.5 mm, coordinates are finite, and first/last poses agree. The check must catch moving the feet or an unreachable wrist/ankle target. Inspect actual skin separately because a correct skeleton alone does not establish movement quality.

## Delivery

One isolated sample with a review page and source file; no bulk regeneration of the eight production exercises. Technical evidence is labeled separately from pending professional movement review.
