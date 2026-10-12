import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_fitness/core/progress_summary.dart';
import 'package:pulse_fitness/core/models.dart';
import 'package:pulse_fitness/core/body_metrics.dart';

void main() {
  test(
    'empty and water-only histories never earn training or food milestones',
    () {
      for (final logs in [
        <DailyLog>[],
        [DailyLog('2026-10-03', waterMl: 2000)],
      ]) {
        final summary = ProgressSummary.fromLogs(logs, today: '2026-10-03');
        expect(summary.trainingDays, 0);
        expect(summary.completedSets, 0);
        expect(summary.foodDays, 0);
        expect(summary.earnedMilestones, isEmpty);
      }
    },
  );
  test('counts actual sets dates food and time excluding future and duplicate dates', () {
    final logged = DailyLog(
      '2026-10-01',
      completedSets: {
        'squat': {0, 1},
      },
      trainingSeconds: 125,
      meals: {0: MealRecord('早饭', Nutrients(100, 5, 10, 2))},
    );
    final summary = ProgressSummary.fromLogs([
      logged,
      logged,
      DailyLog(
        '2026-10-04',
        completedSets: {
          'squat': {0},
        },
      ),
    ], today: '2026-10-03');
    expect(summary.trainingDays, 1);
    expect(summary.completedSets, 2);
    expect(summary.followAlongSeconds, 125);
    expect(summary.foodDays, 1);
    expect(summary.earnedMilestones.map((m) => m.id), ['first-set']);
  });
  test(
    'milestones recompute deterministically from persisted actual records',
    () {
      final logs = List.generate(
        7,
        (i) => DailyLog(
          '2026-09-${20 + i}',
          completedSets: {
            'squat': {0, 1, 2, 3, 4, 5, 6, 7},
          },
          meals: {0: MealRecord('餐食', Nutrients(100, 5, 10, 2))},
        ),
      );
      final first = ProgressSummary.fromLogs(logs, today: '2026-10-03');
      final reloaded = ProgressSummary.fromLogs(
        logs.map((e) => DailyLog.fromJson(e.toJson())),
        today: '2026-10-03',
      );
      expect(first.earnedMilestones.map((m) => m.id), [
        'first-set',
        'three-days',
        'fifty-sets',
        'seven-food-days',
      ]);
      expect(
        reloaded.earnedMilestones.map((m) => m.id),
        first.earnedMilestones.map((m) => m.id),
      );
    },
  );
  test('body series preserve actual dates and latest metric independently', () {
    final records = [
      const BodyRecord('2026-09-25', weightKg: 135),
      const BodyRecord('2026-10-01', weightKg: 132),
      const BodyRecord('2026-10-03', waistCm: 110),
    ];
    final series = BodySeries(
      records,
      today: '2026-10-03',
      days: 7,
      metric: BodyMetric.weight,
    );
    expect(series.points.map((p) => p.date), ['2026-10-01']);
    expect(series.points.single.value, 132);
    expect(series.latest!.date, '2026-10-01');
    expect(series.minY, lessThan(132));
    expect(series.maxY, greaterThan(132));
    final waist = BodySeries(
      records,
      today: '2026-10-03',
      days: 30,
      metric: BodyMetric.waist,
    );
    expect(waist.latest!.date, '2026-10-03');
  });
  test(
    'actual custom food entries count food days without suggested meals',
    () {
      final food = CustomFood(
        id: 'f',
        name: '食物',
        source: '标签',
        per100g: const Nutrients(100, 5, 10, 2),
      );
      final logs = [
        DailyLog(
          '2026-10-03',
          foodEntries: [
            FoodEntry(
              id: 'e',
              date: '2026-10-03',
              slot: 0,
              grams: 100,
              food: food,
              nutrients: food.per100g,
            ),
          ],
        ),
      ];
      final summary = ProgressSummary.fromLogs(logs, today: '2026-10-03');
      expect(summary.foodDays, 1);
      expect(summary.trainingDays, 0);
      expect(summary.earnedMilestones, isEmpty);
    },
  );
}
