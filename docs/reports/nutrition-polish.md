# Nutrition and insights polish — Task 3

Implemented against `.superpowers/sdd/2026-09-27-fitness-polish/task-3-brief.md` and visually inspected `docs/design-board-b.png` before editing. Only Task 3's assigned source, test and report files were edited. Browser visual verification is left to the root agent's integrated CUA pass.

## Nutrition behavior and API

- Added immutable `NutritionTargets` values for energy, protein, carbohydrate, fat and water. AppState stores a separate target snapshot per date; defaults are 1800 kcal, 120 g protein, 195 g carbohydrate, 60 g fat and 2000 ml water, all editable reference values rather than inferred prescriptions.
- Existing getters and mutation signatures still default to today. Added `targetsForDate`, `logForDate`, `mealsForDate`, `nutritionForDate`, `plannedNutritionForDate`, `canRecordDate`; existing `addWater`, `toggleMeal`, `setMeal`, `swapMeal` and `savePreferences` accept optional named `date`.
- Date arrows select from the previous 365 days through the next 30 days. Past meal logging, undo, water and planning act on that date. Future dates permit meal/portion and goal planning but disable actual meal/water recording in both UI and state methods. Merely browsing or planning a future date creates no future consumed log.
- Goal edits update the selected date and that date's existing `DailyLog.waterTarget`. Editing today also updates defaults for newly created dates. Editing a past/future date never changes today's defaults or another date's snapshot.
- Diet and allergens retain their global semantics: today/future pending meal options are filtered while actual consumed records remain immutable. The preferences sheet explains this scope; the goals sheet names its selected date and explains default behavior.
- MealRecord title/nutrients remain actual snapshots. Changing planned meal/portion or target cannot rewrite intake; a changed row explains undo/re-record. Four-slot record completeness remains the nutrition score; macro/energy amounts never enter scoring or reward lower intake.

## Persistence and recovery

- Export schema is version 3 under the existing storage key. Macro defaults and the date target map are included.
- Legacy records without the new target map capture the saved energy/macro defaults once for their existing log/meal-plan dates. Historical `DailyLog.waterTarget` takes precedence over today's/global water default for that date's migrated target.
- All newly added fields parse before committing the loaded snapshot. Invalid target data follows the existing verified unreadable-payload backup/retry path; no partial state replacement.
- Recommendation adoption snapshots tomorrow's goals alongside tomorrow's training/meals and cannot touch today's actual records. Existing fatigue, tiny-training-plan, custom target preservation and backup safeguards were not changed.

## Compact layout decisions

- Nutrition starts with date bar and intake/energy progress, then protein/carbohydrate/fat target progress, goals/preferences controls, four compact existing-photo meal rows, a single water row and next suggestion. Longer selection and goal editing stay in scrollable local sheets.
- Insights uses the reference title, Today/7/30 controls, compact today score ring/bars and weights, true history chart with null gaps, then training and food cards. The period controls scope actual history; the score ring explicitly remains today's completion.
- Next cards share one row at 300 px available content width, so ordinary 390 px mobile layouts show both cards while the narrow 320 px test harness can stack. Full training targets, reasons and older records remain reachable in sheets.
- Local training and meal edits remain draft-only until the explicit “采用下次安排” action. Adopted tomorrow plans stay stable on unrelated state updates and can be edited/re-adopted.
- Legitimate test selector changes: water undo now uses its tooltip; the adopt button is shorter; history tests explicitly select 7 days after the Today default.

## Verification

- `/Users/jiyibo/.local/share/flutter/bin/flutter test test/app_state_test.dart test/nutrition_insights_test.dart --reporter expanded`: **37 tests passed**, including all pre-existing focused tests and 9 added checks.
- Added domain checks cover selected-date logging/change/undo isolation, future planning without consumed records, midnight activation of a future plan, independent target persistence, legacy energy/macro/water migration, unchanged scoring at different portions and target levels, and atomic failed target loads.
- Added widget checks cover summary-before-meals order, working date arrows and selected-date isolation, future planning-only UI, the 30-day future bound, and goal edits staying local until saved. Existing tests exercise 320/390/1100 px layout, preserved intake snapshots, preferences, explicit adoption, repeat edits, and true 7/30-day chart gaps.
- Dart static analysis of the four assigned source files and two assigned test files: **No issues found**.
- `git diff --check` on assigned source/test files: clean.

## Desktop responsive follow-up

The root agent's integrated CUA check approved the mobile 390 px view and domain behavior, but identified unnecessary stretching and below-fold content on desktop 1280 px. Nutrition now uses a desktop-only layout when available content width reaches 900 px: header/date stay common above a fixed 350 px summary/goals/hydration column and an expanded meal rows/next suggestion column. Below 900 px, the exact previous mobile widget order, spacing and functionality remain. No API, domain, insights or shared component changes were made in this follow-up.

Verification after this change:

- `flutter test test/nutrition_insights_test.dart --reporter expanded`: **11 tests passed**, covering 320/390/1100 px layouts and all nutrition/insights interactions.
- `dart analyze lib/screens/nutrition.dart`: **No issues found**.
- `git diff --check -- lib/screens/nutrition.dart`: clean.
