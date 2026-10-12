import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulse_fitness/core/app_state.dart';
import 'package:pulse_fitness/core/models.dart';
import 'package:pulse_fitness/core/catalog.dart';

void main() {
  late AppState state;
  late DateTime clock;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    clock = DateTime(2026, 9, 26, 10);
    state = AppState(await SharedPreferences.getInstance(), now: () => clock);
    await state.load();
  });
  test('new user has zero completion and no fabricated history', () {
    expect(state.score.total, 0);
    expect(state.history.where((d) => d.hasActivity), isEmpty);
  });
  test('repeated set completion is idempotent and bounded', () async {
    final item = state.plan.items.first;
    await state.completeSet(item.exerciseId, 0, 2);
    await state.completeSet(item.exerciseId, 0, 2);
    expect(state.log.completedSets[item.exerciseId]!.length, 1);
    await state.completeSet(item.exerciseId, 999, 2);
    expect(state.log.completedSets[item.exerciseId]!.length, 1);
  });
  test('records persist and midnight starts a separate daily log', () async {
    await state.addWater(250);
    await state.toggleMeal(0);
    final restored = AppState(
      await SharedPreferences.getInstance(),
      now: () => clock,
    );
    await restored.load();
    expect(restored.log.waterMl, 250);
    expect(restored.log.meals.length, 1);
    clock = DateTime(2026, 9, 27, 1);
    expect(restored.log.waterMl, 0);
    expect(restored.history.where((d) => d.hasActivity).length, 1);
  });
  test(
    'empty training goal cannot produce NaN or free training points',
    () async {
      await state.savePlan(state.plan.copyWith(items: []));
      expect(state.score.training, 0);
      expect(state.score.total, 0);
    },
  );
  test(
    'high fatigue produces a reduced next plan and explains the reason',
    () async {
      await state.completeSet(state.plan.items.first.exerciseId, 0, 3);
      final suggestion = state.recommendation;
      expect(suggestion.reasons.join(' '), contains('吃力'));
      expect(suggestion.plan.items.every((item) => item.sets <= 2), isTrue);
    },
  );
  test('adopting a recommendation changes tomorrow but not today', () async {
    final todayIds = state.plan.items.map((e) => e.exerciseId).toList();
    final suggestion = state.recommendation;
    await state.adoptRecommendation(suggestion);
    expect(state.plan.items.map((e) => e.exerciseId), todayIds);
    clock = DateTime(2026, 9, 27, 9);
    expect(
      state.plan.items.map((e) => e.exerciseId),
      suggestion.plan.items.map((e) => e.exerciseId),
    );
  });
  test(
    'changing planned meals preserves the nutrition actually logged',
    () async {
      await state.toggleMeal(0);
      final loggedCalories = state.nutrition.kcal;
      await state.swapMeal(0);
      expect(state.nutrition.kcal, loggedCalories);
    },
  );
  test('first recommendation retains every custom set, rep and rest', () async {
    await state.savePlan(
      state.plan.copyWith(
        items: [
          const PlanItem('curl', sets: 1, reps: 7, rest: 37),
          const PlanItem('plank', sets: 4, reps: 48, rest: 83),
        ],
      ),
    );
    expect(state.recommendation.plan.toJson(), state.plan.toJson());
  });
  test(
    'an intentionally empty plan stays empty with or without history',
    () async {
      await state.savePlan(state.plan.copyWith(items: []));
      expect(state.recommendation.plan.items, isEmpty);
      await state.savePlan(
        state.plan.copyWith(items: [const PlanItem('squat')]),
      );
      await state.completeSet('squat', 0, 3);
      await state.savePlan(state.plan.copyWith(items: []));
      expect(state.recommendation.plan.items, isEmpty);
    },
  );
  test(
    'normal recommendation uses actual custom volume and compatible targets',
    () async {
      await state.savePlan(
        state.plan.copyWith(
          items: [const PlanItem('curl', sets: 2, reps: 9, rest: 37)],
        ),
      );
      await state.completeSet('curl', 0, 1);
      final next = state.recommendation.plan;
      expect(next.totalSets, 2);
      expect(next.items.single.reps, 9);
      expect(next.items.single.rest, 37);
    },
  );
  test('fatigue cannot increase a one-set baseline', () async {
    await state.savePlan(
      state.plan.copyWith(
        items: [const PlanItem('squat', sets: 1, reps: 8, rest: 45)],
      ),
    );
    await state.completeSet('squat', 0, 3);
    expect(state.recommendation.plan.totalSets, lessThanOrEqualTo(1));
    expect(state.recommendation.reasons.join(' '), isNot(contains('减少组数')));
  });
  test(
    'historical water completion retains the daily target after edits',
    () async {
      await state.addWater(1000);
      final yesterday = state.log;
      expect(state.scoreFor(yesterday).habits, 50);
      clock = DateTime(2026, 9, 27, 10);
      await state.addWater(1000);
      await state.savePreferences(
        diet: state.diet,
        allergens: {},
        calories: 1800,
        water: 1000,
      );
      expect(state.score.habits, 100);
      expect(state.scoreFor(yesterday).habits, 50);
      final restored = AppState(
        await SharedPreferences.getInstance(),
        now: () => clock,
      );
      await restored.load();
      expect(restored.scoreFor(restored.logs[yesterday.date]!).habits, 50);
    },
  );
  test(
    'legacy records snapshot the saved global target on migration',
    () async {
      await state.addWater(750);
      final legacy = jsonDecode(state.exportJson()) as Map<String, dynamic>;
      legacy['waterTarget'] = 1500;
      for (final value in (legacy['logs'] as Map).values) {
        (value as Map).remove('waterTarget');
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppState.storageKey, jsonEncode(legacy));
      final restored = AppState(prefs, now: () => clock);
      await restored.load();
      final oldLog = restored.log;
      clock = DateTime(2026, 9, 27);
      await restored.savePreferences(
        diet: restored.diet,
        allergens: {},
        calories: 1800,
        water: 3000,
      );
      expect(restored.scoreFor(oldLog).habits, 50);
    },
  );
  test(
    'unreadable payload is backed up and retry never overwrites it',
    () async {
      const raw = '{broken original';
      final prefs = RecordingPreferences({AppState.storageKey: raw});
      final broken = AppState(prefs, now: () => clock);
      await broken.load();
      expect(broken.storageError, contains('读取失败'));
      expect(broken.storageFailure, StorageFailure.load);
      expect(prefs.values['pulse_fitness_v1_unreadable_backup'], raw);
      await broken.retrySave();
      expect(prefs.values[AppState.storageKey], raw);
      expect(prefs.writes.where((k) => k == AppState.storageKey), isEmpty);
      expect(broken.storageError, isNot(contains('导出')));
    },
  );
  test(
    'load retry restores repaired data rather than saving defaults',
    () async {
      final prefs = RecordingPreferences({AppState.storageKey: '{broken'});
      final broken = AppState(prefs, now: () => clock);
      await broken.load();
      await state.addWater(750);
      final valid = state.exportJson();
      prefs.values[AppState.storageKey] = valid;
      await broken.retrySave();
      expect(broken.log.waterMl, 750);
      expect(broken.storageError, isNull);
      expect(prefs.values[AppState.storageKey], valid);
    },
  );
  test(
    'normal write after unreadable load requires a verified raw backup',
    () async {
      const raw = '{original cannot parse';
      final prefs = RecordingPreferences({AppState.storageKey: raw})
        ..rejectBackup = true;
      final broken = AppState(prefs, now: () => clock);
      await broken.load();
      await broken.addWater(250);
      expect(prefs.values[AppState.storageKey], raw);
      expect(prefs.writes.where((k) => k == AppState.storageKey), isEmpty);
      prefs.rejectBackup = false;
      await broken.addWater(250);
      expect(prefs.values['pulse_fitness_v1_unreadable_backup'], raw);
      expect(
        (jsonDecode(prefs.values[AppState.storageKey]!)['logs'] as Map)
            .values
            .single['water'],
        500,
      );
    },
  );
  test(
    'late parse failure cannot partly replace the in-memory state',
    () async {
      await state.savePlan(state.plan.copyWith(title: '我的计划'));
      await state.addWater(250);
      final before = state.exportJson();
      final bad = jsonDecode(before) as Map<String, dynamic>;
      bad['template']['title'] = '不得载入';
      bad['favorites'] = [123];
      await state.preferences.setString(AppState.storageKey, jsonEncode(bad));
      await state.load();
      expect(state.exportJson(), before);
      expect(state.storageError, contains('读取失败'));
    },
  );
  test(
    'write failure retry saves edits without entering load recovery',
    () async {
      final prefs = RecordingPreferences({})..rejectMain = true;
      final unsaved = AppState(prefs, now: () => clock);
      await unsaved.load();
      await unsaved.addWater(250);
      expect(unsaved.storageError, contains('保存失败'));
      expect(unsaved.storageFailure, StorageFailure.save);
      prefs.rejectMain = false;
      await unsaved.retrySave();
      expect(unsaved.storageError, isNull);
      expect(
        jsonDecode(
          prefs.values[AppState.storageKey]!,
        )['logs'][unsaved.today]['water'],
        250,
      );
      expect(
        prefs.values.containsKey('pulse_fitness_v1_unreadable_backup'),
        isFalse,
      );
    },
  );
  test('training alone preserves meal suggestions, restrictions, portions and targets', () async {
    await state.savePreferences(
      diet: '素食优先',
      allergens: {'大豆', '海鲜'},
      calories: 2300,
      water: 2000,
    );
    for (var slot = 0; slot < 4; slot++) {
      await state.setMeal(
        slot,
        state.meals[slot].mealId,
        [1.5, 1.25, .75, 1.5][slot],
      );
    }
    final withoutTraining = state.recommendation;
    final factors = state.meals.map((m) => m.factor).toList();
    await state.completeSet(state.plan.items.first.exerciseId, 0, 3);
    final withTraining = state.recommendation;
    expect(
      withTraining.meals.map((m) => m.mealId),
      equals(withoutTraining.meals.map((m) => m.mealId)),
    );
    expect(withTraining.meals.map((m) => m.factor), factors);
    expect(state.calorieTarget, 2300);
    for (var slot = 0; slot < 4; slot++) {
      final selected = mealById(withTraining.meals[slot].mealId);
      expect(selected.vegetarian, isTrue);
      expect(selected.allergens.any(state.allergens.contains), isFalse);
    }
    expect(withTraining.nutritionReason, contains('没有实际摄入记录'));
    expect(withTraining.nutritionReason, contains('热量'));
    expect(withTraining.nutritionReason, contains('碳水'));
    expect(withTraining.nutritionReason, contains('蛋白质'));
  });
  test(
    'matching exercise keeps its custom targets when other slots switch',
    () async {
      await state.savePlan(
        state.plan.copyWith(
          items: [
            const PlanItem('plank', sets: 4, reps: 48, rest: 83),
            const PlanItem('squat', sets: 1, reps: 7, rest: 37),
          ],
        ),
      );
      await state.completeSet('squat', 0, 1);
      final next = state.recommendation.plan;
      final retained = next.items.singleWhere((i) => i.exerciseId == 'plank');
      expect(retained.toJson(), state.plan.items.first.toJson());
      expect(next.totalSets, state.plan.totalSets);
    },
  );
  test(
    'selected date meal logging, changing and undo never touches today',
    () async {
      const selected = '2026-09-25';
      await state.toggleMeal(0);
      await state.setMeal(0, 'rice_breakfast', 1.5, date: selected);
      await state.toggleMeal(0, date: selected);
      await state.addWater(750, date: selected);
      expect(state.logs[selected]!.meals[0]!.nutrients.kcal, 555);
      expect(state.logs[selected]!.waterMl, 750);
      expect(state.nutrition.kcal, 410);
      expect(state.log.waterMl, 0);
      await state.swapMeal(0, date: selected);
      expect(state.nutritionForDate(selected).kcal, 555);
      await state.toggleMeal(0, date: selected);
      expect(state.nutritionForDate(selected).kcal, 0);
      expect(state.nutrition.kcal, 410);
    },
  );
  test('future meal planning never fabricates future consumption', () async {
    final future = state.tomorrow;
    await state.setMeal(0, 'rice_breakfast', 2, date: future);
    await state.toggleMeal(0, date: future);
    await state.addWater(250, date: future);
    expect(state.mealPlans[future]!.first.factor, 2);
    expect(state.logs.containsKey(future), false);
    expect(state.nutritionForDate(future).kcal, 0);
    clock = DateTime(2026, 9, 27);
    await state.toggleMeal(0);
    expect(state.nutrition.kcal, 740);
  });
  test(
    'macro and energy target snapshots persist separately by date',
    () async {
      const past = '2026-09-25';
      state.mealsForDate(past);
      state.mealsForDate(state.tomorrow);
      await state.savePreferences(
        diet: state.diet,
        allergens: {},
        calories: 2400,
        water: 3000,
        protein: 150,
        carbs: 280,
        fat: 80,
      );
      expect(state.targetsForDate(past).calories, 1800);
      expect(state.targetsForDate(state.tomorrow).protein, 120);
      await state.savePreferences(
        diet: state.diet,
        allergens: {},
        calories: 2100,
        water: 1500,
        protein: 130,
        carbs: 230,
        fat: 70,
        date: past,
      );
      expect(state.calorieTarget, 2400);
      expect(state.proteinTarget, 150);
      expect(state.targetsForDate(past).protein, 130);
      final restored = AppState(state.preferences, now: () => clock);
      await restored.load();
      expect(
        restored.targetsForDate(past).toJson(),
        state.targetsForDate(past).toJson(),
      );
      expect(restored.targetsForDate(state.today).carbs, 280);
      expect(restored.targetsForDate(state.tomorrow).fat, 60);
    },
  );
  test(
    'legacy nutrition migration snapshots saved defaults and historical water',
    () async {
      await state.addWater(750);
      final legacy = jsonDecode(state.exportJson()) as Map<String, dynamic>;
      legacy.remove('nutritionTargets');
      legacy.remove('proteinTarget');
      legacy.remove('carbsTarget');
      legacy.remove('fatTarget');
      legacy['calorieTarget'] = 2200;
      legacy['waterTarget'] = 3000;
      legacy['logs'][state.today]['waterTarget'] = 1500;
      await state.preferences.setString(
        AppState.storageKey,
        jsonEncode(legacy),
      );
      final restored = AppState(state.preferences, now: () => clock);
      await restored.load();
      final oldDate = restored.today;
      expect(restored.targetsForDate(oldDate).calories, 2200);
      expect(restored.targetsForDate(oldDate).protein, 120);
      expect(restored.targetsForDate(oldDate).water, 1500);
      clock = DateTime(2026, 9, 27);
      await restored.savePreferences(
        diet: restored.diet,
        allergens: {},
        calories: 1800,
        water: 2000,
        protein: 100,
        carbs: 200,
        fat: 50,
      );
      expect(restored.targetsForDate(oldDate).calories, 2200);
      expect(restored.scoreFor(restored.logs[oldDate]!).habits, 50);
    },
  );
  test(
    'goal edits preserve consumed snapshots and do not reward under-eating',
    () async {
      await state.toggleMeal(0);
      final actual = state.log.meals[0]!.toJson();
      final score = state.score.nutrition;
      await state.savePreferences(
        diet: state.diet,
        allergens: {},
        calories: 1000,
        water: 2000,
        protein: 1,
        carbs: 1,
        fat: 1,
      );
      expect(state.log.meals[0]!.toJson(), actual);
      expect(state.score.nutrition, score);
      await state.setMeal(1, state.meals[1].mealId, .5);
      await state.toggleMeal(1);
      final halfPortionScore = state.score.nutrition;
      await state.toggleMeal(1);
      await state.setMeal(1, state.meals[1].mealId, 2);
      await state.toggleMeal(1);
      expect(state.score.nutrition, halfPortionScore);
    },
  );
  test(
    'invalid target payload load is atomic and retained for recovery',
    () async {
      await state.addWater(250);
      final before = state.exportJson();
      final bad = jsonDecode(before) as Map<String, dynamic>;
      bad['nutritionTargets'][state.today]['protein'] = 'invalid';
      await state.preferences.setString(AppState.storageKey, jsonEncode(bad));
      await state.load();
      expect(state.exportJson(), before);
      expect(state.storageFailure, StorageFailure.load);
      expect(
        state.preferences.getString(AppState.unreadableBackupKey),
        jsonEncode(bad),
      );
    },
  );
}

class RecordingPreferences implements SharedPreferences {
  final Map<String, String> values;
  final List<String> writes = [];
  bool rejectBackup = false, rejectMain = false;
  RecordingPreferences(this.values);
  @override
  String? getString(String key) => values[key];
  @override
  Future<bool> setString(String key, String value) async {
    writes.add(key);
    if ((rejectMain && key == AppState.storageKey) ||
        (rejectBackup && key == 'pulse_fitness_v1_unreadable_backup')) {
      return false;
    }
    values[key] = value;
    return true;
  }

  @override
  Future<void> reload() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
