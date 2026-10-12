/* Shared by the Flutter surfaces and the standalone exercise review. */
(function (root) {
  'use strict';

  const PRIMARY = [1, .12, .018];
  const STABILIZER = [.012, .5, .3];
  const PREFIX = 'PULSE Muscle ';
  const controllers = new WeakMap();

  function create(viewer, options) {
    controllers.get(viewer)?.dispose();
    const state = {
      catalog: null, exerciseId: '', muscles: true, selectedRegion: 'all',
      playing: true, speed: 1, reducedMotion: false, ...options,
    };
    let materials = [];
    let frame = 0;
    let disposed = false;
    let lastPaint = -Infinity;
    let phaseKey = '';
    let phase = null;
    const definition = () => state.catalog?.exercises?.[state.exerciseId];
    const duration = () => Number(state.catalog?.duration) || 6;

    function normalizeSelection() {
      if (!definition()?.regions?.some(r => r.id === state.selectedRegion)) {
        state.selectedRegion = 'all';
      }
    }

    function bindMaterials() {
      materials = (viewer.model?.materials || [])
        .filter(m => m.name?.startsWith(PREFIX))
        .map(material => {
          material.setAlphaMode('BLEND');
          return {material, id: material.name.slice(PREFIX.length), last: null};
        });
    }

    function focusRegion() {
      const region = definition()?.regions?.find(r => r.id === state.selectedRegion);
      const view = region?.view || definition()?.defaultView || 'front';
      const theta = view === 'back' ? 180 : view === 'side' ? 90 : 0;
      const orbit = viewer.getCameraOrbit?.();
      const radius = orbit?.radius > 0 ? `${orbit.radius}m` : '110%';
      const phi = orbit?.phi > 0 ? `${orbit.phi}rad` : '75deg';
      viewer.cameraOrbit = `${theta}deg ${phi} ${radius}`;
    }

    function playback() {
      viewer.timeScale = state.speed;
      if (state.playing && !state.reducedMotion) viewer.play?.();
      else viewer.pause?.();
    }

    function paint() {
      if (disposed) return;
      const exercise = definition();
      const length = duration();
      // Adding length to an already-positive decimal can round a phase boundary
      // backwards (for example 1.8 becomes 1.7999999999999998).
      const remainder = (Number(viewer.currentTime) || 0) % length;
      const time = remainder < 0 ? remainder + length : remainder;
      const phases = exercise?.phases || [];
      let index = phases.findIndex(p => time >= p.start && time < p.end);
      if (index < 0 && phases.length) index = phases.length - 1;
      const next = phases[index];
      phase = next ? {exerciseId: state.exerciseId, index, ...next, duration: length} : null;
      const key = `${state.exerciseId}:${index}`;
      if (key !== phaseKey) {
        phaseKey = key;
        if (phase) state.onPhase?.({...phase});
      }
      // This shared visual rhythm is a phase cue, never force or EMG.
      // One smooth envelope spans the repetition; holds remain illuminated.
      const smooth = x => { const v = Math.max(0, Math.min(1, x)); return v * v * (3 - 2 * v); };
      const hold = phases.length === 1 || state.exerciseId === 'plank';
      const alpha = state.reducedMotion || hold ? .8
        : .58 + .22 * smooth((time - .5) / .55) * smooth((length - .5 - time) / .55);
      for (const entry of materials) {
        const region = exercise?.regions?.find(r => r.id === entry.id);
        const color = region?.role === 'stabilizer' ? STABILIZER : PRIMARY;
        const focused = state.selectedRegion === 'all' || state.selectedRegion === entry.id;
        const opacity = state.muscles && region ? alpha * (focused ? 1 : .16) : 0;
        const rgba = [...color, opacity];
        if (!entry.last || rgba.some((v, i) => Math.abs(v - entry.last[i]) > .002)) {
          entry.material.pbrMetallicRoughness.setBaseColorFactor(rgba);
          entry.material.setEmissiveFactor?.(color.map(v => v * .12));
          entry.last = rgba;
        }
      }
    }

    function tick(now) {
      if (disposed) return;
      // Continue sampling while paused so external timeline seeking works too.
      if (now - lastPaint >= 32 && !root.document?.hidden) {
        lastPaint = now;
        paint();
      }
      frame = root.requestAnimationFrame(tick);
    }

    function loaded() {
      bindMaterials();
      playback();
      if (Number.isFinite(state.seekTime)) viewer.currentTime = Math.max(0, Math.min(duration() - .001, state.seekTime));
      phaseKey = '';
      paint();
    }

    function update(patch) {
      if (disposed) return;
      const changedExercise = patch.exerciseId !== undefined && patch.exerciseId !== state.exerciseId;
      const changedSelection = patch.selectedRegion !== undefined && patch.selectedRegion !== state.selectedRegion;
      const changedPlayback = ['playing', 'speed', 'reducedMotion'].some(k => patch[k] !== undefined && patch[k] !== state[k]);
      Object.assign(state, patch);
      if (changedExercise) {
        state.selectedRegion = patch.selectedRegion ?? 'all';
        phaseKey = '';
        bindMaterials();
      }
      normalizeSelection();
      // Camera writes are explicit; ordinary phase/state updates preserve drags.
      if (patch.orbit !== undefined) viewer.cameraOrbit = patch.orbit;
      else if (changedSelection && !changedExercise) focusRegion();
      if (patch.target !== undefined) viewer.cameraTarget = patch.target;
      if (changedPlayback) playback();
      if (Number.isFinite(patch.seekTime)) viewer.currentTime = Math.max(0, Math.min(duration() - .001, patch.seekTime));
      paint();
    }

    function dispose() {
      if (disposed) return;
      disposed = true;
      root.cancelAnimationFrame(frame);
      viewer.removeEventListener('load', loaded);
      if (controllers.get(viewer) === api) controllers.delete(viewer);
    }

    const api = {
      update,
      dispose,
      getState: () => ({
        exerciseId: state.exerciseId,
        muscles: state.muscles,
        selectedRegion: state.selectedRegion,
        playing: state.playing && !state.reducedMotion,
        speed: state.speed,
        phase: phase ? {...phase} : null,
      }),
    };
    controllers.set(viewer, api);
    normalizeSelection();
    if (state.orbit !== undefined) viewer.cameraOrbit = state.orbit;
    if (state.target !== undefined) viewer.cameraTarget = state.target;
    viewer.addEventListener('load', loaded);
    if (viewer.model) loaded();
    frame = root.requestAnimationFrame(tick);
    return api;
  }

  root.PulseMuscles = Object.freeze({create});
})(typeof window !== 'undefined' ? window : globalThis);
