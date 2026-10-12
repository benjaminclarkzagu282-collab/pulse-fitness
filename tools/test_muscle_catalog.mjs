import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const catalog = JSON.parse(await readFile(new URL('../assets/muscles/catalog.json', import.meta.url), 'utf8'));
const sourceNotes = await readFile(new URL('../docs/reports/muscle-guidance-sources.md', import.meta.url), 'utf8') + await readFile(new URL('../docs/reports/expanded-muscle-guidance.md', import.meta.url), 'utf8');
const exerciseIds = ['squat', 'pushup', 'lunge', 'bridge', 'plank', 'row', 'jumping_jack', 'curl', 'kneeling_pushup', 'incline_pushup', 'floor_press', 'shoulder_press', 'lateral_raise', 'single_arm_row', 'reverse_fly', 'romanian_deadlift', 'sumo_squat', 'split_squat', 'lateral_lunge', 'calf_raise', 'dead_bug', 'bird_dog', 'side_plank', 'step_jack'];
const allowedRegions = new Set(['quads', 'glutes', 'core', 'chest', 'triceps', 'deltoids', 'lats', 'upper_back', 'biceps', 'hamstrings', 'calves']);
const keys = value => Object.keys(value).sort();

test('catalog exposes all 24 approved exercises with a shared six-second duration', () => {
  assert.deepEqual(keys(catalog), ['duration', 'exercises', 'version']);
  assert.equal(catalog.version, 1);
  assert.equal(catalog.duration, 6);
  assert.deepEqual(keys(catalog.exercises), exerciseIds.toSorted());
  for (const [id, exercise] of Object.entries(catalog.exercises)) {
    assert.deepEqual(keys(exercise), ['camera', 'cameraTarget', 'defaultView', ...(exercise.demoNote ? ['demoNote'] : []), 'name', 'phases', 'referenceUrls', 'regions'], id);
    assert.deepEqual(keys(exercise.camera), [...(exercise.camera.depthMargin !== undefined ? ['depthMargin'] : []), 'floor', 'minDistance', ...(exercise.camera.motionHeight !== undefined ? ['motionHeight'] : []), 'motionWidth']);
    assert.equal(typeof exercise.camera.floor, 'boolean');
    assert.ok(exercise.camera.minDistance >= 2.8 && exercise.camera.motionWidth > 0, id);
    assert.ok(exercise.name.trim(), id);
    assert.ok(['front', 'side'].includes(exercise.defaultView), id);
    assert.match(exercise.cameraTarget, /^-?(?:\d+(?:\.\d+)?|\.\d+)m -?(?:\d+(?:\.\d+)?|\.\d+)m -?(?:\d+(?:\.\d+)?|\.\d+)m$/, id);
    for (const value of exercise.cameraTarget.split(' ')) assert.ok(Number.isFinite(Number(value.slice(0, -1))), id);
    if (exercise.camera.motionHeight !== undefined) assert.ok(exercise.camera.motionHeight > 0, id);
    if (exercise.camera.depthMargin !== undefined) assert.ok(exercise.camera.depthMargin >= 0, id);
  }
});

test('each selection has one supported region, a role and a readable explanation', () => {
  for (const [id, { regions }] of Object.entries(catalog.exercises)) {
    assert.ok(regions.length >= 3 && regions.length <= 5, id);
    assert.equal(new Set(regions.map(region => region.id)).size, regions.length, `${id}: duplicate region`);
    assert.ok(regions.some(region => region.role === 'primary'), id);
    assert.ok(regions.some(region => region.role === 'stabilizer'), id);
    for (const region of regions) {
      assert.deepEqual(keys(region), ['description', 'id', 'name', 'role', ...(region.side ? ['side'] : []), 'view'], id);
      if (region.side) assert.ok(['left', 'right'].includes(region.side), id);
      assert.ok(allowedRegions.has(region.id), `${id}/${region.id}`);
      assert.ok(['primary', 'stabilizer'].includes(region.role), id);
      assert.ok(['front', 'back', 'side'].includes(region.view), id);
      assert.ok(region.name.trim() && region.description.length >= 15, id);
      assert.doesNotMatch(region.description, /\d+\s*(%|％|N\b|牛顿)|肌电值|激活率/, id);
      if (region.id === 'glutes') assert.match(region.description, /短裤.*表面/, `${id}: clothing overlay needs context`);
    }
  }
});

test('action-specific muscle selections retain their defining participants', () => {
  const requiredPrimary = {
    squat: ['quads', 'glutes'], pushup: ['chest', 'triceps'], lunge: ['quads', 'glutes'],
    bridge: ['glutes', 'hamstrings'], plank: ['core'], row: ['lats', 'upper_back'],
    jumping_jack: ['quads', 'calves', 'deltoids'], curl: ['biceps'],
  };
  for (const [id, required] of Object.entries(requiredPrimary)) {
    const regions = new Map(catalog.exercises[id].regions.map(region => [region.id, region.role]));
    required.forEach(region => assert.equal(regions.get(region), 'primary', `${id}/${region}`));
    if (id !== 'plank') assert.equal(regions.get('core'), 'stabilizer', `${id}: posture support`);
  }
});

test('phase intervals cover every clip boundary exactly once and remain usable after looping', () => {
  for (const [id, { phases }] of Object.entries(catalog.exercises)) {
    let end = 0;
    for (const phase of phases) {
      assert.deepEqual(keys(phase), ['end', 'label', 'start', 'text'], id);
      assert.equal(phase.start, end, `${id}: timeline gap or overlap`);
      assert.ok(Number.isFinite(phase.end) && phase.end > phase.start, id);
      assert.ok(phase.label.trim() && phase.text.trim(), id);
      end = phase.end;
    }
    assert.equal(end, catalog.duration, `${id}: incomplete clip`);
    // The player can scrub or loop without retaining the previous phase.
    const at = time => {
      const local = ((time % catalog.duration) + catalog.duration) % catalog.duration;
      return phases.filter(phase => phase.start <= local && local < phase.end);
    };
    const probes = [...phases.flatMap(phase => [phase.start, phase.end - 0.0001]), 6, 12, -0.0001];
    for (const time of probes) assert.equal(at(time).length, 1, `${id} at ${time}s`);
    assert.equal(at(0)[0], at(6)[0], `${id}: loop restart`);
    assert.equal(at(5.9999)[0], phases.at(-1), `${id}: end before wrap`);
  }
});

test('timings distinguish movement direction, a static plank, and single-side lunge', () => {
  const directions = {
    squat: [/下蹲/, /起身/], pushup: [/下降/, /推起/], lunge: [/后撤/, /回升/],
    bridge: [/抬髋/, /下放/], row: [/拉/, /放回/], curl: [/弯举/, /下放/],
  };
  for (const [id, [outward, returning]] of Object.entries(directions)) {
    const { phases } = catalog.exercises[id];
    assert.deepEqual(phases.map(({ start, end }) => [start, end]), [[0, .5], [.5, 3], [3, 3.5], [3.5, 5.5], [5.5, 6]], id);
    assert.match(phases[1].label, outward, id);
    assert.match(phases[3].label, returning, id);
    assert.equal(phases.at(-1).label, '回到起始', id);
  }
  assert.match(catalog.exercises.lunge.phases[0].text, /单侧后撤弓步/);
  const jack = catalog.exercises.jumping_jack.phases;
  assert.deepEqual(jack.map(({ start, end }) => [start, end]), [[0, .5], [.5, 1.4], [1.4, 3.5], [3.5, 4.4], [4.4, 6]]);
  assert.match(jack[1].label, /展开/);
  assert.match(jack[2].label, /分腿落地稳定/);
  assert.match(jack[3].label, /合拢/);
  assert.match(jack[4].label, /合脚落地稳定/);
  assert.doesNotMatch(jack[2].text, /悬空|腾空/);
  assert.match(jack[4].text, /起始站姿/);
  assert.equal(catalog.exercises.plank.phases.length, 1);
  assert.equal(catalog.exercises.plank.phases[0].label, '稳定保持');
});

test('every exercise has traceable official references documented with its interpretation', () => {
  const officialHosts = new Set(['www.acefitness.org', 'contentcdn.eacefitness.com', 'www.mayoclinic.org', 'www.nasm.org', 'www.hss.edu', 'www.montgomeryschoolsmd.org']);
  for (const [id, { referenceUrls }] of Object.entries(catalog.exercises)) {
    assert.ok(referenceUrls.length > 0, id);
    assert.equal(new Set(referenceUrls).size, referenceUrls.length, id);
    for (const value of referenceUrls) {
      const url = new URL(value);
      assert.equal(url.protocol, 'https:', id);
      assert.ok(officialHosts.has(url.hostname), `${id}: non-primary reference`);
      assert.ok(sourceNotes.includes(value), `${id}: undocumented reference`);
    }
  }
});


test('new action-specific participants and floor setup match the actual demonstrations', () => {
  const required = {
    kneeling_pushup: ['chest', 'triceps'], incline_pushup: ['chest', 'triceps'], floor_press: ['chest', 'triceps'],
    shoulder_press: ['deltoids', 'triceps'], lateral_raise: ['deltoids'], single_arm_row: ['lats', 'upper_back', 'biceps'],
    reverse_fly: ['deltoids', 'upper_back'], romanian_deadlift: ['hamstrings', 'glutes'], sumo_squat: ['quads', 'glutes'],
    split_squat: ['quads', 'glutes'], lateral_lunge: ['quads', 'glutes'], calf_raise: ['calves'],
    dead_bug: ['core'], bird_dog: ['core'], side_plank: ['core'], step_jack: ['deltoids', 'glutes'],
  };
  for (const [id, ids] of Object.entries(required)) {
    const {regions} = catalog.exercises[id];
    for (const region of ids) assert.equal(regions.find(r => r.id === region)?.role, 'primary', `${id}/${region}`);
  }
  for (const id of ['pushup', 'plank', 'bridge', 'kneeling_pushup', 'floor_press', 'dead_bug', 'bird_dog', 'side_plank']) {
    assert.equal(catalog.exercises[id].camera.floor, true, id);
  }
  assert.equal(catalog.exercises.incline_pushup.camera.floor, false);
  assert.match(catalog.exercises.incline_pushup.demoNote, /固定.*台面/);
  for (const id of ['lunge', 'split_squat', 'single_arm_row', 'bird_dog', 'side_plank']) assert.match(catalog.exercises[id].demoNote, /单侧/);
});

test('alternating and static timelines match exported clips instead of a generic repetition', () => {
  for (const id of ['lateral_lunge', 'dead_bug']) {
    assert.deepEqual(catalog.exercises[id].phases.map(p => [p.start, p.end]), [[0,.5],[.5,1.5],[1.5,2.5],[2.5,3.5],[3.5,4.5],[4.5,5.5],[5.5,6]]);
  }
  const side = catalog.exercises.side_plank.phases;
  assert.equal(side.length, 1);
  assert.equal(side[0].label, '稳定保持');
  assert.deepEqual(catalog.exercises.step_jack.phases.map(p => [p.start,p.end]), [[0,.5],[.5,1.2],[1.2,1.8],[1.8,2.5],[2.5,3.5],[3.5,4.2],[4.2,4.8],[4.8,5.5],[5.5,6]]);
  assert.match(catalog.exercises.step_jack.demoNote, /至少一脚着地/);
  assert.match(catalog.exercises.lateral_lunge.demoNote, /固定宽站姿/);
  for (const id of ['kneeling_pushup','incline_pushup','floor_press','shoulder_press','lateral_raise','single_arm_row','reverse_fly','romanian_deadlift','sumo_squat','split_squat','calf_raise','bird_dog']) {
    assert.deepEqual(catalog.exercises[id].phases.map(p => [p.start,p.end]), [[0,.5],[.5,3],[3,3.5],[3.5,5.5],[5.5,6]], id);
  }
});


test('single-arm pulling highlights the demonstrating arm and keeps torso support bilateral', () => {
  const {regions} = catalog.exercises.single_arm_row;
  for (const id of ['lats', 'upper_back', 'biceps']) {
    const region = regions.find(r => r.id === id);
    assert.equal(region.side, 'right');
    assert.match(region.description, /右侧/);
  }
  assert.equal(regions.find(r => r.id === 'core').side, undefined);
});
