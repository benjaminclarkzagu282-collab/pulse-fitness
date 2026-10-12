# iOS six improvements implementation plan

> For agentic workers: execute task by task with subagent-driven-development and review checkpoints. The user has authorized implementation in this session.

**Goal:** Improve the existing 24-action fitness app in all six requested areas, without claiming coach certification or iPhone validation that has not happened.

**Architecture:** Keep the existing original-rig assets and Flutter screens. Add a verified on-demand asset store with a small bundled base, actual set records and recovery feedback, editable food records, portable backups, and an accessible privacy page. Technical evidence and external acceptance status are recorded separately.

**Tech stack:** Flutter/Dart, existing model-viewer, local JSON storage, HTTP, SHA-256, filesystem/browser caches, Python asset preparation.

## Global constraints

- Preserve every original athlete GLB and original MAX/FBX/editable source byte-for-byte; any delivery compression must decompress to the original SHA-256.
- Keep all 24 actions available, with the existing muscles and cameras. Muscle colors are qualitative participation, not measured force.
- Do not mark any action professionally reviewed without actual identified reviewer evidence.
- Do not claim native iPhone performance/installation passes without a real device run. Complete local tests and provide the device acceptance script.
- Old training/nutrition JSON must still load. Imports must validate before mutating storage, preserve current data on failure, and keep a pre-import backup.
- Export and clear data are explicit user actions. Do not erase the user's existing records during verification.
- Keep existing completed meal snapshots, repeated-set idempotence, and date isolation.
- Never fabricate nutrition precision. User food values use a named source and a grams-based estimate; suggestions explain their inputs.
- No public deployment, subscription purchase, messages to others, or professional review is implied by this local implementation request.

## Task 1: Actual training and recovery

Files: `lib/core/models.dart`, `lib/core/app_state.dart`, `lib/screens/workout.dart`, `lib/screens/insights.dart`, `test/training_records_test.dart`.

Interfaces: `SetRecord(setIndex, fatigue, elapsedSeconds, target, timed, actualReps?, actualSeconds?, weightKg?)`; `RecoveryFeedback(sleepQuality, soreness, pain)`; optional actual values in `completeSet`; `saveRecovery` persists date-specific feedback. Existing `completedSets` stays compatible.

- [x] Write tests for actual reps/weight roundtrip, repeated-set protection, old JSON, recovery-driven reduction, progression requiring repeated successful same-action records.
- [x] Run `flutter test test/training_records_test.dart`, observe missing behavior.
- [x] Add set detail inputs to the completion flow; display history detail. Preserve rest/session accounting.
- [x] Recommend adjustment only from relevant actual records; recovery/pain overrides progression. Explain changes and retain editable adoption.
- [x] Run existing app-state/workout tests and the new tests; review the diff.

## Task 2: Portable backup and privacy

Files: `lib/core/backup.dart`, `lib/screens/settings.dart`, `lib/core/app_state.dart`, `lib/app.dart`, `web/privacy.html`, `test/backup_test.dart`.

Interfaces: `BackupEnvelope` wraps versioned `exportJson`; preview validates shape, IDs, dates, numeric ranges, and references before `restoreBackup`; `clearUserData` resets local records with explicit confirmation. The screen exposes export, paste/import preview, restore, clear, and privacy.

- [x] Write negative tests for truncated/future-version backups and unknown IDs; valid roundtrip retains actual records and custom foods.
- [x] Validate the complete snapshot before replacement and verify pre-import backup before writing. Roll back storage on replacement failure.
- [x] Add JSON download/share where available and universally usable copy/paste. Explain backup sensitivity in product language.
- [x] Add privacy text describing actual local records and optional model requests; do not invent cloud services.
- [x] Run backup/storage tests and mobile-width widget tests; review the diff.

## Task 3: Daily food records

Files: `lib/core/food_log.dart`, `lib/core/models.dart`, `lib/core/app_state.dart`, `lib/screens/food_log.dart`, `lib/screens/nutrition.dart`, `test/food_log_test.dart`.

Interfaces: named custom food per 100g with source/allergens, date-specific `FoodEntry` containing an immutable nutrition snapshot and grams; append entries into an existing meal slot without destroying the previous snapshot.

- [x] Write tests for grams calculation, edits preserving previous intake, allergens, date limits, and persistence.
- [x] Add food creation/edit, meal-slot logging with grams, and removal of individual entries. Planned meals remain separate.
- [x] Improve next-meal selection with calorie and macro targets, preferences and recent intake, rather than maximizing protein alone. Never modify targets automatically.
- [x] Run nutrition tests and 320/390px widget layout checks; review the diff.

## Task 4: Lossless on-demand models

Files: `tools/prepare_model_delivery.py`, `assets/muscles/model_manifest.json`, `lib/core/model_assets.dart`, platform cache adapters, `lib/ui/exercise_view.dart`, native/web exercise surfaces, `pubspec.yaml`, `test/model_assets_test.dart`.

Interfaces: manifest entries include compressed/original size and SHA-256; model resolver emits progress and returns an asset, browser blob, or cached local file source. Configuration uses `PULSE_ASSET_BASE_URL`; web defaults to its own root, native refuses to invent a host.

- [x] Test corrupted download rejection, cache reuse, cancel/switch race, missing host and progress without fake percentages.
- [x] Prepare gzip variants and assert decompressed SHA-256 equals all 24 originals; keep core squat/pushup bundled and separate remaining model delivery.
- [x] Integrate bounded downloads, verified cache, retry, clear cache and a static demonstration fallback. Show download size and missing host guidance.
- [x] Build web output including prepared remote files for the local review; verify existing review URLs and all 24 models remain usable.
- [x] Record measured packaging reduction and compression fidelity; review code.

## Task 5: Action review and teaching

Files: `assets/muscles/review_status.json`, action teaching screen/widgets, `web/action-acceptance.html`, `docs/reports/action-acceptance.md`, tests.

- [x] Inventory all 24 source references, stage labels, tips, known mistakes and available simplified alternatives.
- [x] Add paused stage selection and front/side/back camera controls for consistent inspection.
- [x] Expose source and pending professional review status without misleading approval labels; provide actual review record fields in an offline reviewer checklist.
- [x] Validate full action coverage, phase seeking and camera behavior; preserve original animation bytes.

## Task 6: iPhone resilience and acceptance

Files: lifecycle handling in workout/viewer, `tools/check_ios_readiness.py`, `docs/ios-device-acceptance.md`, regression/widget tests.

- [x] Pause active training and 3D animation on background; require explicit resume, preserving rest remaining and recorded sets.
- [x] Test at 320/390px and lifecycle pause/resume using Flutter tests; verify failed 3D loading retains actionable fallback.
- [x] Inspect Xcode/device availability and native plugin constraints. Build native if the toolchain exists; otherwise retain an explicit unverified device gate.
- [x] Run full Flutter tests, Dart analysis, model/controller checks and release web build. Smoke-test the resulting UI in the browser.
- [x] Produce a six-area delivery report with commands, measurements, changed files, and remaining coach/device/deployment gates.

## Verification commands

```sh
/Users/jiyibo/.local/share/flutter/bin/flutter test
/Users/jiyibo/.local/share/flutter/bin/dart analyze lib test
node --test test/muscle_controller_test.cjs
python3 tools/prepare_model_delivery.py --verify
/Users/jiyibo/.local/share/flutter/bin/flutter build web --release
python3 tools/check_ios_readiness.py
```

## Progress

- [x] Actual records and recovery — 62 focused tests passed; independent review approved completion-only / actual-time separation.
- [x] Backup and privacy
- [x] Food logging and recommendation — 9 new tests and existing regressions passed; independent review approved immutable snapshots and draft targets.
- [x] Verified model download/cache
- [x] Action teaching and review workflow
- [x] Lifecycle resilience and local verification — 148 full tests, 12 Node tests, clean analysis, lossless checks, release web build and browser flows passed; native device remains unverified.
- [ ] Identified coach review (external gate)
- [ ] iPhone device acceptance (external gate)

Final integration: 148 Flutter tests passed, Dart analysis clean; backup corrupt-storage recovery and video lifecycle race were independently re-reviewed. Release web smoke test and final report are complete: docs/reports/2026-10-03-six-improvements.md. Full Xcode/CocoaPods are unavailable, so native build/device gates remain unverified.
