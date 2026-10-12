# Homepage six-point refinement

Delivered 2026-09-27. Scope: the six homepage improvements approved in chat. Existing training, nutrition, scoring rules and SharedPreferences storage remain compatible.

## Result

1. Today's training is the first major card, with a prominent start/continue button. The large initial zero-score panel is replaced by a compact progress section further down the page.
2. Training metadata and set progress are kept in the training card. The duplicate training summary and training checklist entry are removed. The score section has an explicit no-activity state.
3. `athlete_home.png` is rendered from the existing licensed MakeHuman character with a green jersey, warmer key light, soft fill/rim light and a portrait camera fitted to the evaluated character silhouette. The entire head and shoes remain visible, separately from the button. Existing 3D exercise clips are unchanged by this homepage refinement.
4. Meals show an explicit unrecorded state; after logging, the card shows recorded kcal and protein/carbs/fat alongside the selected date's calorie target. Water has a +250 ml action and an undo that uses the actual capped increment and original date.
5. The week strip includes real date numbers and visible training/rest/recorded status labels. Day details read maps without creating historical/future plans or logs. Actual recorded sets stay visible after the user removes a previously trained exercise. Tomorrow's card exposes the recommendation's actual training reasons and meal selection basis; no-history and saved-plan states are distinguished. Saved plans do not inherit a newly generated explanation that may not apply.
6. A stronger training gradient is paired with quieter nutrition and water surfaces, readable secondary copy, reduced border repetition and a responsive desktop arrangement. The former decorative avatar is removed from the homepage header.

## Validation

- Full Flutter suite: **55 tests passed**; Dart analyzer: **no issues**.
- Release web build succeeded. The built hero image byte-matches the source, with nonzero alpha margins on all four edges.
- Added regressions for unrecorded/recorded meals, calendar states, no phantom past/future logs, removed-exercise records, water undo across midnight and near its 6000 ml limit, saved recommendation explanations, empty plans and month boundaries.
- Layout tests cover widths 320, 390 and 1100. Browser inspection covered 320, 390, the user's normal narrow viewport, and 1280 desktop, including real entry into the 3D workout page.
- In an isolated localhost:8881 test origin, meal logging changed home totals to 410 kcal with macros; water added 250 ml and undo restored zero. The temporary meal record was undone; the QA tab and server were closed. No test intake or training was added to the user's localhost:8879 origin.
- Main preview at localhost:8879 is updated and remains open. Browser warning/error log was empty on final inspection. Temporary viewport overrides were reset.
- Independent code review caught the original portrait framing and historical-set display defects; both were corrected and checked again.

Screenshots: `home-six-mobile.png`, `home-six-desktop.png`.

The new portrait uses the same CC0 character/garment sources documented in `docs/assets/character-CC0-license.md` and `docs/assets/character-sources.json`. Reproduce with `Blender --background --python tools/render_home_athlete.py`. It is a rendered illustration for the training card; exercise motion remains the existing procedural skinned animation. Native device performance was not tested in this pass.
