# Native library migration — 2026-09-30

User accepted the native shoulder press and curl and authorized all remaining 22 motions plus Flutter integration. Plan: `docs/superpowers/plans/2026-09-29-native-rig-library.md`.

| Task | State | Evidence / constraints |
| --- | --- | --- |
| Native solver | All 22 implemented; original chain, bind and weights preserved | Full structural sweep; calf toe-chain check; continuous hand orientation checks for both jack motions |
| Mesh delivery | All 24 complete and packaged | Original eight influences evaluated; approved two GLBs preserved byte-for-byte; 30/90 FPS real export regression passes |
| Verification | All 24 independently passed; file hashes and sampling coverage sealed | Every key and interval midpoint; original source fingerprint, native chains, actual contacts, grip, loop and actual GLB geometry |
| Integration | App and review assets replaced; final Flutter web build and browser checks passed | 11 Flutter tests, 17 controller/catalog tests, 34 Python tests, focused Dart analysis passed |

Use final files in `.build/original-rig/native-library-02`. Earlier diagnostic directories are not app deliveries. All 24 passed the aggregate gate before app replacement. Editable files and reports are delivered in the characters/08 folder, under the dated 24-action library.

Fixes since the first build: distinct frame and vertex counts in dense export; reuse the already prepared original texture cache when extracted source textures are absent; track calf contact at distal toe pads; replace the legacy hand-plane singularity during lateral overhead arm arcs. Verification compares every key and midpoint over the entire six seconds at each delivery's actual frame rate, without relaxing the 0.5 mm geometry limit.

The original MAX and FBX remain untouched. No commits or unrelated workspace cleanup are requested. Runtime GLBs contain evaluated mesh animation because the current model-viewer ignores the second set of Skin influences; editable native sources keep all 81 original bones and all eight influences. These demonstrations remain reference-authored and await coach review.

Final maximum geometry roundtrip error: 0.409 mm. The completed delivery record is `docs/reports/native-library-delivery.json`. Browser screenshots include `native-library-final-browser.png`, `native-library-jumping-jack-browser.png` and `native-library-app-browser.png`. The temporary mobile viewport override was reset; the local preview remains running for the user.
