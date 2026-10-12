# Fitness visual fidelity and character upgrade

User approved the proposed upgrade on 2026-09-27. Source of visual truth: docs/design-board-a.png and docs/design-board-b.png. Current branch baseline 4c28139.

## Constraints and acceptance

Keep Flutter and all verified local data behavior. Improve the actual running app, not just generate a new mock. Current primitive mannequin is explicitly rejected by the user. Character must be an anatomically continuous skinned mesh with realistic proportions, face/hair, sportswear and shoes. Reuse the same character for thumbnails, hero and real animated GLBs. Use assets with documented licenses; do not purchase or submit paid generation without an approved budget. First verify a squat render and bending deformation before publishing all eight moves. Avoid claiming photo-realistic or exact mock fidelity unless actual output warrants it.

Restore the six-screen designs' compact mobile information hierarchy. Desktop adapts it rather than defining it. Preserve real empty states and historical snapshots; no fabricated score or history. Add missing visible interactions (date navigation, nutrition goals, action replacement, camera reset and clear target-muscle visualization). Native builds remain unverified until SDKs are available.

### Task 1: Existing human assets, real skinning and animation

Own assets/models, assets/images/hero.png, assets/images/avatar.png, assets/images/exercise-*.png, tools character/animation scripts, docs/reports/character-upgrade.md and docs/assets/ source manifests. Preserve existing images filenames where UI uses them, inspect catalog paths. Do not modify Dart or pubspec.

Use a documented free existing human source, preferably MakeHuman/MPFB official assets (core CC0; each third-party garment license separately checked). Local Blender is /Applications/Blender.app/Contents/MacOS/Blender (5.2.1). Official source https://static.makehumancommunity.org/mpfb.html and https://static.makehumancommunity.org/assets/assetpacks.html . Download into a project ignored working area (large authoring/dependency files must not accidentally enter git). Do not use paid marketplace assets without approval. Do not rebuild a primitive segmented mannequin as a fallback.

Produce an athletic male with short dark hair, graphite T-shirt, shorts and light sneakers close to the reference. Skin mesh deforms continuously through a skeletal rig. Export GLB Exercise loop, keep stable IDs squat,pushup,lunge,bridge,plank,row,jumping_jack,curl and exercise camera directions used by current renderer (front 0°, side90°). Work in neutral anatomical orientation then verify export camera directions. Build a reusable Blender source and reproducible script; rigs can be driven procedurally but do not approximate body with disconnected primitives. Foot grounding and reasonable shoulder/elbow/knee form matter. Preserve fingers, reduce clothes penetration and keep scene objects out of GLB. Optimize models/textures for phone without visibly destroying the character. Do not declare complete until actual rendered previews have been inspected.

First deliver candidate standing and squat previews plus provenance report for root visual review while continuing useful asset work. Then generate eight GLBs and consistent cropped transparent exercise thumbnails, squat hero and avatar. Document mesh/rig/animations, polygons/textures/sizes/licenses. Validate loop endpoints and GLB structure. No subagents. Commit only owned artifacts after review readiness, write detailed report and return short status.

### Task 2: Six-screen visual fidelity

Own lib/ui, lib/screens/today.dart, plan.dart, library.dart, workout.dart, lib/app.dart and related UI tests. Root handles this task while Task1 works only on assets. Reuse existing data interfaces and colors but match boards tightly at 390x844: home compact score summary first, week strip, compact training image card, three daily to-dos and next card; plan inline editable rows; action gallery with clean cutout character and subtle studio lighting; guided workout large 3D viewport above compact tabs/counters/tips/fatigue/completion control. Avoid gratuitous English eyebrows or oversized blank cards. Nutrition/insights revisions follow Task3.

Use real character art once Task1 available. Make front/side/reset/playback controls complete; implement action replacement within current workout plan and target-muscle illustration with explicit schematic label, not fabricated medical assessment. Preserve timers/date guards and disposal. Follow actual screenshots for visual acceptance, test key stateful interactions rather than shallow implementation-mirroring tests.

### Task 3: Nutrition/date goals and compact insights

Own lib/core/models.dart, app_state.dart, lib/screens/nutrition.dart, insights.dart and domain/nutrition tests. After Task1, can delegate with explicit API contract. Add date-selected meal view and logging by selected date with immutable nutrient snapshots and per-date targets; safely preserve old saved schema. Date arrow controls actually work. Add user-set protein/carbs/fat goals alongside energy and water, with explanatory estimate text and no score incentive for under-eating. Preserve today default interfaces. Render summary first, compact meal rows with existing photos, watermark/datebar/preferences, hydration and next suggestion. Insights follows reference: Today/7/30 controls, compact score panel, history trend, training/meal next cards and one explicit adopt button. No fake data. Never change today's records on adopting tomorrow.

### Task 4: Integrated verification and review

Run dart analyze, focused then complete flutter test, flutter build web --release. Fresh CUA browser on preview: mobile 390x844 and 320xheight, desktop; actual 3D rotation/play/pause, character silhouette, material, skinning; plan edit/replace/save/reload; selected-date meals goals with history snapshot; adopted next draft. Save actual screenshots. Independent review with diff package and concrete spec; fix material findings and re-review. Preserve working preview and report limits honestly.
