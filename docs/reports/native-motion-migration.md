# Native motion migration — 2026-09-29

The remaining 22 reference-authored six-second loops are implemented in
`tools/original_rig/native_motion.py`. The approved native shoulder press and
curl implementation and delivered assets are unchanged.

`NativeMotion(rig, exercise)` extends `NativeUpper` and provides
`pose_time(seconds)`, `pose(exercise, depth)`, `equipment()`, and the inherited
reference, placement and native grip methods. Production callers must use
`pose_time`: dead bug, lateral lunge and step jack retain separate left/right
phases, and jumping jack retains its flight and landing phases.

The solver reads each action from `.build/motion-library/{exercise}.blend`,
samples its 181 frames at 30 FPS, and removes the legacy reference armature from
the scene. The sampled joint directions and body orientation determine intent;
the actual native joint origins and segment lengths determine the output.
Native physical X axes and original roll are retained instead of using Blender
CAT display tails. Forearm rotation is distributed over all three native segments.
No native bind matrix, source body vertex, bone name or source body weight is
edited. The three existing pelvic soft-tissue controls fold with native leg
flexion so the shorts retain their fitted crotch shape; the helper chain keeps
its original physical length.

Grounding is based on actual native skin envelopes. Hands open in the native
palm plane; finger spread and phalanx lengths are retained. Pushup, plank and
incline pushup rotate the intact native leg line around their toe-supported
ankles. Plank pitch is fitted to its native forearm envelope. Bridge, floor
press, dead bug, kneeling pushup, bird dog and side plank fit back, knee or
forearm contact patches. Calf raise plants the native toe chains while fitting
hindfoot skin about the metatarsal pivot; this replaces the legacy rig's single
ball bone.

Dumbbells are created only for row, floor press, lateral raise, single arm row,
reverse fly and Romanian deadlift. Single arm row carries only the right weight.
Their original fitted native grip and reference-to-bind attachment remain in
use. Objects are named `Native dumbbell L/R`. Incline pushup uses a 0.50 m
support, and single arm row a 0.5625 m support, named `Native support top` and
`Native support leg ...`.

`equipment()` also attaches the original rigid eyes, brows, eyelashes and mouth
accessories to `Man_Head` with their own reference-to-bind transformation.
Builders must prepare appearance before calling this method so generated brow
meshes receive the same head attachment.

## Verification

Focused helper: `tools/original_rig/check_native_motion.py`.

The complete sweep is run with Blender 5.2.1 against
`.build/original-rig/native-import-04/original-rig-staging.blend`. It checks all
181 frames of every new action for finite pose matrices, actual native joint
segment lengths, an intact 81-bone bind structure, unchanged source weights,
loop closure, evaluated body ground clearance, hand/support skin contact, and
fitted handle penetration. Evidence is written to
`.build/original-rig/native-motion-check-all.json` and its adjacent log.

Representative standing, floor, support and equipment views are generated in
`.build/original-rig/native-motion-renders/`. Their creation follows the same
appearance-before-attachment ordering as the production builder.

Final smoke sweep passed all 22 actions, including the pelvic helper chain,
at 0, 1.5 and 6 seconds. Its report is
`.build/original-rig/native-motion-check-quick-final.json`. The full 181-frame
sweep completed. Final calf toe-chain and both jack orientation refinements
were subsequently checked over all 181 frames in `native-motion-check-calf-final.json`
and `native-motion-check-jacks-final.json`. The independent delivery gate also
checks every authored frame in all 24 editable sources.

The final solver hash is recorded in the delivery summary. Jack motions use a
continuous frontal palm plane through the overhead arc. Maximum shortest-path
rotation change at 30 FPS is 11.177 degrees for jumping jack and 13.544 degrees
for step jack. Original bones, bind matrices and Skin weights remain unchanged.

## Limits

These motions transfer existing reference-authored animation; they are not
motion capture or coach certification. Surface contact fitting uses authored
native skin patches and retains an intentional 1 mm ground clearance. The
legacy action uses a smaller display scale. Horizontal trajectories use a 1.25
scale, standing poses anchor to the native reference and use the native/source
leg-length ratio vertically, and floor poses are fitted to their native skin
contacts. IK and native joint lengths resolve the limb proportions.
The focused helper proves the editable native solver. Delivery GLB interpolation,
full mesh/normal error, runtime region naming, cameras and app integration are
separate checks in the library builder and delivery verifier.
