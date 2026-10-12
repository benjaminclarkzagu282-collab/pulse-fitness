import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_fitness/core/catalog.dart';
import 'package:pulse_fitness/core/training_programs.dart';

void main() {
  test(
    'four reference programs have unique known actions and exact equipment',
    () {
      expect(trainingPrograms, hasLength(4));
      expect(trainingPrograms.map((p) => p.id).toSet(), hasLength(4));
      for (final program in trainingPrograms) {
        final plan = program.createPlan(days: [2, 5]);
        expect(plan.items, isNotEmpty);
        expect(
          plan.items.map((i) => i.exerciseId).toSet().length,
          plan.items.length,
        );
        final equipment = plan.items
            .expand((i) => exerciseById(i.exerciseId).requiredEquipment)
            .toSet();
        expect(plan.equipment.split('＋').toSet(), equipment);
        expect(plan.minutes, inInclusiveRange(10, 30));
        for (final item in plan.items) {
          expect(item.sets, inInclusiveRange(1, 2));
          expect(item.rest, inInclusiveRange(30, 60));
        }
      }
    },
  );
  test('timed targets are explicit seconds and reps remain manageable', () {
    final timed = <String, int>{};
    for (final program in trainingPrograms) {
      for (final item in program.createPlan(days: []).items) {
        if (exerciseById(item.exerciseId).timed) {
          timed[item.exerciseId] = item.reps;
        } else {
          expect(item.reps, inInclusiveRange(6, 10));
        }
      }
    }
    expect(timed, {'step_jack': 30, 'plank': 20});
  });
  test('each preview and adoption isolates mutable weekday lists', () {
    final days = [2, 5];
    final first = trainingPrograms.first.createPlan(days: days);
    final second = trainingPrograms.first.createPlan(days: days);
    days.add(7);
    first.days.add(3);
    expect(second.days, [2, 5]);
    expect(trainingPrograms.first.createPlan(days: [2, 5]).days, [2, 5]);
    expect(identical(first, second), isFalse);
    expect(() => first.items.clear(), throwsUnsupportedError);
  });
}
