import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulse_fitness/core/app_state.dart';
import 'package:pulse_fitness/screens/workout.dart';

void main() {
  late AppState state;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    state = AppState(await SharedPreferences.getInstance());
  });
  test('replacement preserves finished sets and their actual time', () async {
    await state.completeSet('squat', 0, 2, seconds: 34);
    final total = state.plan.totalSets;
    final index = await replaceWorkoutAction(state, 0, 'pushup');
    expect(index, 1);
    expect(state.plan.items[0].exerciseId, 'squat');
    expect(state.plan.items[0].sets, 1);
    expect(state.plan.items[1].exerciseId, 'pushup');
    expect(state.plan.items[1].sets, 2);
    expect(state.plan.totalSets, total);
    expect(state.log.trainingSeconds, 34);
    expect(state.completedSetsFor('squat'), 1);
  });
  test('unstarted replacement preserves targets and persists', () async {
    final source = state.plan.items.first;
    await replaceWorkoutAction(state, 0, 'curl');
    final restored = AppState(await SharedPreferences.getInstance());
    await restored.load();
    expect(restored.plan.items.first.exerciseId, 'curl');
    expect(restored.plan.items.first.sets, source.sets);
    expect(restored.plan.items.first.reps, source.reps);
    expect(restored.plan.items.first.rest, source.rest);
  });
  test('duplicate replacement is a no-op', () async {
    final before = state.plan.items.map((e) => e.exerciseId).toList();
    expect(await replaceWorkoutAction(state, 0, 'plank'), 0);
    expect(state.plan.items.map((e) => e.exerciseId), before);
  });
  test(
    'replacement preserves completed sets with nonconsecutive indices',
    () async {
      await state.completeSet('squat', 2, 2, seconds: 40);
      await replaceWorkoutAction(state, 0, 'pushup');
      expect(state.completedSetsFor('squat'), 1);
      expect(state.log.setCount, 1);
      expect(state.log.trainingSeconds, 40);
      expect(state.plan.items[1].sets, 2);
    },
  );
}
