# Fitness polish verification — 2026-09-27

Implementation branch: `feature/fitness-polish`, original baseline `4c28139`. Approved visual direction remains `docs/design-board-a.png` and `docs/design-board-b.png`. This report covers the upgraded running application, not the original mockboards.

## Delivered

- One consistent licensed MakeHuman/MPFB athlete across eight actual skinned GLBs, gallery thumbnails, home illustration and avatar. Source and limitations: [character-upgrade.md](character-upgrade.md).
- Compact Today, Plan, Library, Workout, Nutrition and Insights layouts; inline plan editing, remaining-action replacement with completed work preserved, camera controls/reset and target-muscle schematic.
- Date-selected meals/water and independent energy/protein/carbs/fat/water targets; immutable consumed snapshots and backward migration. Tomorrow adoption leaves today intact.
- Desktop nutrition uses a 350px summary/goals/hydration column beside meal rows. Floor exercises open from the side; the camera aims at floor height and derives distance from viewport aspect to keep the full body visible.

## Automated verification

Final source checks:

- `flutter test --reporter compact`: **45 tests passed**.
- `dart analyze`: **No issues found**.
- `flutter build web --release`: **Succeeded**.
- `git diff --check`: clean.
- All eight built GLBs and ten built PNGs byte-match their current source assets. GLBs total 31,873,544 bytes; each is independently loaded.
- Asset validation and independent inspection confirm one 53-joint skin, finite accessors, normalized weights, embedded textures and a closed 4-second Exercise clip per model. Detailed checks are in `assets/models/validation.json`.

Domain regressions include nonconsecutive completed set indices during replacement, dated targets on the home page after midnight, nutrition migration/atomic load failure, future planning without actual intake, and preserved historical meal snapshots.

## Actual browser verification

CUA operated the real release build through the in-app browser. Destructive test data was avoided: all functional test records were created on isolated `127.0.0.1:8880`; existing `127.0.0.1:8879` storage was preserved. The user preview at 8879 was refreshed to the final build and left on Today.

Verified flows:

- Edit 12 repetitions to 13, save; complete one set on the test origin, replace remaining work with curl, refresh: original completed squat remains one set, new curl has two, total remains fourteen, actual time is preserved.
- Previous-day meal recording changes that date to 410 kcal while today remains zero. Editing today's energy target updates the summary; adopted tomorrow plans remain saved after refresh.
- The 7-day history reflects only the real test record and preserves gaps. Recommendation adoption shows the saved state.
- Actual model loading, animated pose changes, pause/play, drag rotation, front/side re-selection, reset and slow playback controls. Fixed transparent-skin sorting seen in an intermediate export; final face renders correctly.
- Bridge side view has full body visible and centered after a viewport-dependent camera-distance correction. Ground pose and skin deformation were inspected separately from the static thumbnails.
- Mobile pages examined at 320px and 390px during integration, final user-panel screenshots at 361×882, final floor view at 390×844, desktop at 1280×720 and 1280×900. No clipping/overflow found in the inspected final views; 320/390/1100 widget layout tests also pass.
- Fresh final main-preview and desktop-test console checks contain no errors or warnings. An older temporary test tab retained pre-upgrade avatar-404 warnings; the obsolete URL is no longer referenced, and all final PNGs are verified present.

Independent code/asset review closed the daily-target mismatch, default-side auto-progression and camera re-selection findings. No remaining P1/P2 issue was reported. Final camera math/platform parameter changes were also reviewed.

## Screenshots

These are actual running-app captures, not generated mockups:

- [Mobile Today](polish-mobile-home.png)
- [Mobile Plan](polish-mobile-plan.png)
- [Mobile Library](polish-mobile-library.png)
- [Mobile Workout](polish-mobile-workout.png)
- [Ground 3D view](polish-mobile-ground-3d.png)
- [Mobile Nutrition](polish-mobile-nutrition.png)
- [Mobile Insights](polish-mobile-insights.png)
- [Desktop Today](polish-desktop-home.png)
- [Desktop Nutrition](polish-desktop-nutrition.png)

## Limits

The character is a stylized real-proportion game asset. The animations use procedural skeletal targets; no claim of photorealism, motion capture, automatic pose assessment or biomechanical certification is made. Native Android/iOS scaffolds remain present, but SDKs are unavailable on this machine, so native packages and physical-phone GPU/frame-rate behavior remain unverified. Recommendations are transparent local rules; no cloud account/synchronization or wearable data integration is included.

The local preview at 8879 remains running. Temporary test tabs and the 8880 test server were closed; authoring source/dependencies remain in the ignored `.build/character` directory for reproduction. No paid asset or service was purchased.
