# PULSE Visual Refresh and Growth Features Implementation Plan

> For agentic workers: use subagent-driven-development with task review checkpoints. The user authorized implementation and original imagery in this session.

**Goal:** Make PULSE feel like a polished fitness client while adding usable training programs, body measurement trends and earned milestones.

**Architecture:** Keep the five existing tabs and the accepted 24-action pipeline. Add a separate growth screen and program preview screen; body measurements are a top-level versioned local collection, while milestones are derived from real logs. Refresh shared tokens and the home hierarchy using an original generated editorial cover.

**Tech stack:** Flutter/Dart, existing SharedPreferences JSON/backup validator, CustomPainter, bundled PNG. No new cloud service or chart dependency.

## Global constraints

- Preserve existing dirty work, accepted model/source bytes and all current user records; do not commit/reset or clear the actual browser storage.
- Do not invent body samples, workout activity, earned badges, coach certification, calories burned, heart rate or cloud sync.
- Keep `nav-0` through `nav-4` and `open-settings`; new routes must remain accessible at 320/390px.
- Use generated photo decoratively, not as an exercise or anatomical demonstration.
- Old versions 1–5 remain loadable/importable. Version 6 requires a validated body-record collection; all import validation precedes replacement.
- Applying a program to an already-started day is blocked, with tomorrow available. Preserve existing logs, food, targets and weekday choices; an existing tomorrow plan needs explicit overwrite confirmation.
- Native iPhone/toolchain gates remain explicitly unverified. This request does not authorize public deployment.

## Task 1: Body records and growth screen

Files: new `lib/core/body_metrics.dart`, `lib/core/progress_summary.dart`, `lib/screens/progress.dart`; modify `lib/core/app_state.dart`, `lib/core/backup.dart`, `lib/screens/settings.dart`, `web/privacy.html`; tests `test/body_metrics_test.dart`, `test/progress_screen_test.dart`, existing backup regressions.

Interfaces:

```dart
BodyRecord(String date, {double? weightKg, double? waistCm, String note = ''});
final Map<String, BodyRecord> bodyRecords = {};
Future<void> saveBodyRecord(BodyRecord record);
Future<void> removeBodyRecord(String date);
Future<void> saveProgramPlan(TrainingPlan plan, {required String date});
class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key, required AppState state});
}
```

Body values: at least one of weight/waist, finite weight 20–350kg and waist 30–250cm, note at most 200 characters, valid date not in the future. Same-date edits replace only that measurement; body recording alone never creates training completion points. `saveProgramPlan` accepts today/future valid dates, refuses today if any set has been completed, and changes only the selected dated plan.

- [x] Write/run tests for zero fake activity, valid/date-specific records, invalid/future/NaN data, roundtrip, version 1–5 migration, strict backup rejection, clear/restore preservation, and today-program guard.
- [x] Implement version 6 body persistence in tolerant local load and strict backup validation; include measurements in preview count/date range and privacy.
- [x] Build growth screen with add/edit form, latest available weight/waist values, 7/30-day trend, missing values preserved, one sample as one point, actual-date history and transparent earned milestones.
- [x] Test empty state, earned milestone semantics, chart scaling above 100kg, mixed partial records and 320/390px forms; independently review changes.

## Task 2: Training program discovery and preview

Files: new `lib/core/training_programs.dart`, `lib/screens/programs.dart`; modify only `lib/screens/plan.dart`; tests `test/training_programs_test.dart`, `test/programs_screen_test.dart`.

Interfaces:

```dart
class ProgramsScreen extends StatelessWidget {
  const ProgramsScreen({super.key, required AppState state});
}
```

Four catalog-based reference presets: short full-body bodyweight, lower body/control, dumbbell upper body, core. Each card shows exact movements, required equipment, planned sets and estimated time. Preview never mutates state; user selects today/tomorrow then confirms. Preserve current weekday selection. Call `state.saveProgramPlan(value, date: selectedDate)`, disabling today once training has started and confirming before replacement of an existing dated plan.

- [x] Write/run tests for valid unique catalog IDs, timed/rep defaults, no mutation during preview, active-day guard and previous records unaffected.
- [x] Implement program cards/details and explicit adoption, linking the existing plan editor to the program route.
- [x] Test mobile layout and actual preview/confirmation interactions; independently review.

## Task 3: Visual system, shell and home

Files: `lib/ui/theme.dart`, `lib/ui/components.dart`, `lib/app.dart`, `lib/screens/today.dart`, targeted layout refinements in `lib/screens/insights.dart`, `lib/screens/library.dart`, `lib/screens/nutrition.dart`; new `test/visual_growth_navigation_test.dart`.

- [x] Write/run navigation tests expecting working program/growth shortcuts and preservation of existing settings/five tabs at small widths.
- [x] Apply neutral graphite surfaces, restrained lime, clearer type/section hierarchy, softer borders and consistent 18–24px cards; render existing eyebrow labels.
- [x] Integrate `assets/images/editorial-training-v1.png` into responsive training hero while preserving actual completion/resume CTA. Add real 7-day overview and four functional shortcuts.
- [x] Add global progress entry and records-page growth entry. Stack recommendation cards below 600px; keep existing controls/labels and state behavior.
- [x] Test responsive routes, zero-state data and navigation. Inspect 390px and desktop screenshots of final release build.

## Task 4: Original asset and final verification

- [x] Generate original gym cover using built-in imagegen, inspect and copy to project; exact prompt/source in `docs/design/2026-10-03-generated-cover.md`.
- [x] Run full Flutter tests, Dart analysis, controller regressions and release web build after integration.
- [x] Review final scoped diffs against `.build/visual-refresh/baseline`; correct concrete findings and re-run affected checks.
- [x] Capture browser evidence without writing/clearing main-origin user data; publish local preview and delivery report with remaining native/coach gates.

References for design organization: [Apple Fitness+](https://www.apple.com/apple-fitness-plus/), [Nike Training Club](https://www.nike.com/ntc-app), [Hevy](https://www.hevyapp.com/). These guide content organization; their brand assets are not copied.
