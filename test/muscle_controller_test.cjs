const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {test} = require('node:test');

const script = fs.readFileSync(path.join(__dirname, '../assets/muscles/controller.js'), 'utf8');
const catalog = {
  duration: 6,
  exercises: {
    squat: {
      defaultView: 'front',
      regions: [
        {id: 'quads', role: 'primary', view: 'front'},
        {id: 'glutes', role: 'primary', view: 'back'},
        {id: 'core', role: 'stabilizer', view: 'front'},
      ],
      phases: [
        {start: 0, end: 3, label: '下蹲', text: '控制下降'},
        {start: 3, end: 3.5, label: '停顿', text: '保持稳定'},
        {start: 3.5, end: 6, label: '站起', text: '平稳站起'},
      ],
    },
    plank: {
      defaultView: 'side',
      regions: [{id: 'core', role: 'primary', view: 'side'}],
      phases: [{start: 0, end: 6, label: '支撑', text: '保持呼吸'}],
    },
  },
};

function fixture(options = {}) {
  let id = 0;
  let orbitWrites = 0;
  const frames = new Map();
  const listeners = new Map();
  const window = {
    document: {hidden: false},
    requestAnimationFrame(fn) { frames.set(++id, fn); return id; },
    cancelAnimationFrame(token) { frames.delete(token); },
  };
  vm.runInNewContext(script, {window});
  const materials = ['quads', 'glutes', 'core'].map(region => ({
    name: `PULSE Muscle ${region}`,
    rgba: null,
    mode: null,
    setAlphaMode(value) { this.mode = value; },
    setEmissiveFactor(value) { this.emissive = value; },
    pbrMetallicRoughness: {
      setBaseColorFactor(value) {
        materials.find(m => m.name === `PULSE Muscle ${region}`).rgba = Array.from(value);
      },
    },
  }));
  const viewer = {
    currentTime: 1.2,
    model: {materials},
    plays: 0,
    pauses: 0,
    _orbit: 'user drag',
    get cameraOrbit() { return this._orbit; },
    set cameraOrbit(value) { this._orbit = value; orbitWrites++; },
    getCameraOrbit() { return {radius: 3.7, phi: 1.3}; },
    play() { this.plays++; },
    pause() { this.pauses++; },
    addEventListener(name, fn) {
      if (!listeners.has(name)) listeners.set(name, new Set());
      listeners.get(name).add(fn);
    },
    removeEventListener(name, fn) { listeners.get(name)?.delete(fn); },
  };
  const phases = [];
  const controller = window.PulseMuscles.create(viewer, {
    catalog, exerciseId: 'squat', onPhase: p => phases.push(p), ...options,
  });
  let stamp = 0;
  return {
    window, viewer, controller, materials, phases, frames, listeners,
    orbitWrites: () => orbitWrites,
    tick(time) {
      viewer.currentTime = time;
      stamp += 40;
      const pending = [...frames.values()];
      frames.clear();
      for (const fn of pending) fn(stamp);
    },
  };
}

test('normal mode hides overlays without resetting time or camera', () => {
  const f = fixture();
  assert.equal(f.materials[0].mode, 'BLEND');
  assert.deepEqual(f.materials[0].rgba.slice(0, 3), [1, .12, .018]);
  assert.deepEqual(f.materials[2].rgba.slice(0, 3), [.012, .5, .3]);
  f.controller.update({muscles: false});
  assert(f.materials.every(m => m.rgba[3] === 0));
  assert.equal(f.viewer.currentTime, 1.2);
  assert.equal(f.orbitWrites(), 0);
  f.controller.update({muscles: true});
  assert(f.materials.every(m => m.rgba[3] > .57));
  assert.equal(f.viewer.plays, 1);
});

test('region focus preserves radius and clip time while other regions dim', () => {
  const f = fixture();
  f.controller.update({selectedRegion: 'glutes'});
  assert.equal(f.viewer.cameraOrbit, '180deg 1.3rad 3.7m');
  assert.equal(f.viewer.currentTime, 1.2);
  assert(f.materials[1].rgba[3] > f.materials[0].rgba[3] * 5);
  f.tick(2.3);
  f.controller.update({speed: .5, muscles: true, selectedRegion: 'glutes'});
  assert.equal(f.orbitWrites(), 1);
  assert.equal(f.viewer.currentTime, 2.3);
  assert.equal(f.viewer.timeScale, .5);
});

test('explicit camera controls take priority over region focus', () => {
  const f = fixture();
  f.controller.update({selectedRegion: 'glutes', orbit: '90deg 75deg 4m'});
  assert.equal(f.viewer.cameraOrbit, '90deg 75deg 4m');
  assert.equal(f.orbitWrites(), 1);
});

test('paused external seeking updates phase only when a boundary is crossed', () => {
  const f = fixture({playing: false});
  f.tick(1.5);
  f.tick(2.5);
  assert.equal(f.phases.length, 1);
  f.tick(3.2);
  assert.equal(f.phases.length, 2);
  assert.equal(f.phases[1].label, '停顿');
  const atHold = f.materials[0].rgba[3];
  f.tick(3.51);
  assert.equal(f.phases.length, 3);
  assert.equal(f.phases[2].label, '站起');
  assert.equal(f.materials[0].rgba[3], atHold);
  f.tick(6.2);
  assert.equal(f.controller.getState().phase.index, 0);
  assert.equal(f.viewer.plays, 0);
});

test('explicit teaching phase seek pauses at the requested time and survives load', () => {
  const f = fixture();
  f.controller.update({playing: false, seekTime: 3.25});
  assert.equal(f.viewer.currentTime, 3.25);
  assert.equal(f.controller.getState().phase.label, '停顿');
  assert.equal(f.viewer.pauses, 1);
  for (const loaded of f.listeners.get('load')) loaded();
  assert.equal(f.viewer.currentTime, 3.25);
  f.controller.update({seekTime: 99});
  assert.equal(f.viewer.currentTime, 5.999);
  f.controller.update({seekTime: -5});
  assert.equal(f.viewer.currentTime, 0);
  f.controller.update({playing: true});
  assert.equal(f.viewer.plays, 2);
});

test('exercise switch clears region selection and derives colors from its role', () => {
  const f = fixture();
  f.controller.update({selectedRegion: 'glutes'});
  const writes = f.orbitWrites();
  f.controller.update({exerciseId: 'plank'});
  assert.equal(f.controller.getState().selectedRegion, 'all');
  assert.equal(f.controller.getState().phase.exerciseId, 'plank');
  assert.equal(f.orbitWrites(), writes);
  assert.equal(f.materials[0].rgba[3], 0);
  assert.deepEqual(f.materials[2].rgba, [1, .12, .018, .8]);
  f.tick(4.8);
  assert.equal(f.materials[2].rgba[3], .8);
});

test('reduced motion pauses animation and uses a static overlay', () => {
  const f = fixture({reducedMotion: true});
  assert.equal(f.viewer.plays, 0);
  assert.equal(f.controller.getState().playing, false);
  f.tick(.1);
  assert.equal(f.materials[0].rgba[3], .8);
  f.tick(5.9);
  assert.equal(f.materials[0].rgba[3], .8);
  f.controller.update({reducedMotion: false});
  assert.equal(f.viewer.plays, 1);
});

test('recreating and disposing controller release frame loops and load listeners', () => {
  const f = fixture();
  assert.equal(f.frames.size, 1);
  assert.equal(f.listeners.get('load').size, 1);
  const second = f.window.PulseMuscles.create(f.viewer, {catalog, exerciseId: 'plank'});
  assert.equal(f.frames.size, 1);
  assert.equal(f.listeners.get('load').size, 1);
  f.controller.update({muscles: false});
  assert.equal(second.getState().muscles, true);
  second.dispose();
  second.dispose();
  assert.equal(f.frames.size, 0);
  assert.equal(f.listeners.get('load').size, 0);
});


test('all 24 catalog clips reconstruct their phases and selected regions across loops', () => {
  const actual = JSON.parse(fs.readFileSync(path.join(__dirname, '../assets/muscles/catalog.json'), 'utf8'));
  assert.equal(Object.keys(actual.exercises).length, 24);
  for (const [id, exercise] of Object.entries(actual.exercises)) {
    const f = fixture({catalog: actual, exerciseId: id});
    for (const phase of exercise.phases) {
      f.tick(phase.start);
      assert.equal(f.phases.at(-1).exerciseId, id);
      assert.equal(f.phases.at(-1).label, phase.label);
      f.tick(phase.end - .0001);
      assert.equal(f.phases.at(-1).label, phase.label);
    }
    f.tick(6);
    assert.equal(f.phases.at(-1).label, exercise.phases[0].label);
    f.controller.update({selectedRegion: 'core'});
    const visible = f.materials.find(m => m.name.endsWith('core'));
    assert(visible.rgba[3] > .5, id);
    const before = visible.rgba[3];
    f.tick(3);
    if (exercise.phases.length === 1) assert.equal(visible.rgba[3], before, `${id} static hold must not pulse`);
    f.controller.update({muscles: false});
    assert(f.materials.every(m => m.rgba[3] === 0), id);
    f.controller.dispose();
    assert.equal(f.frames.size, 0, id);
  }
});
