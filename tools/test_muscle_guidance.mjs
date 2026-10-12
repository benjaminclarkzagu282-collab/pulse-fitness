import test from 'node:test';
import assert from 'node:assert/strict';
import { muscleDisplay } from '../web/review/muscle-guidance.mjs';

test('normal mode hides every overlay even at bottom pause', () => {
  assert.ok(Object.values(muscleDisplay(3.25, false, 'all').opacity).every(v => v === 0));
});
test('bottom hold does not extinguish participating regions', () => {
  const result = muscleDisplay(3.25, true, 'all');
  assert.equal(result.phase, '底部停顿');
  assert.ok(Object.values(result.opacity).every(v => v > .3));
});
test('selection changes emphasis without changing the motion phase', () => {
  const result = muscleDisplay(4.5, true, 'glutes');
  assert.equal(result.phase, '起身');
  assert.ok(result.opacity.glutes > result.opacity.quads);
  assert.ok(result.opacity.glutes > result.opacity.core);
});
test('scrubbing backwards reconstructs guidance from time, without old phase state', () => {
  muscleDisplay(4.5, true, 'quads');
  assert.equal(muscleDisplay(1.75, true, 'quads').phase, '控制下蹲');
  assert.equal(muscleDisplay(0, true, 'all').phase, '准备');
  assert.deepEqual(muscleDisplay(0, true, 'all').opacity, muscleDisplay(6, true, 'all').opacity);
});
