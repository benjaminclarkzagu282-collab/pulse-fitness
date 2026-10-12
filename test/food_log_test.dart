import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulse_fitness/core/app_state.dart';
import 'package:pulse_fitness/core/models.dart';
import 'package:pulse_fitness/screens/nutrition.dart';
import 'package:pulse_fitness/ui/theme.dart';

void main() {
  late AppState state;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    state = AppState(
      await SharedPreferences.getInstance(),
      now: () => DateTime(2026, 10, 3),
    );
  });
  CustomFood food({
    String name = '原味酸奶',
    Nutrients per100g = const Nutrients(80, 4, 10, 2),
    String source = '包装标签',
  }) => CustomFood(
    id: 'yogurt-custom',
    name: name,
    source: source,
    per100g: per100g,
    allergens: ['乳制品'],
    vegetarian: true,
  );

  test('grams intake is date-specific and immutable after catalog edits and reload', () async {
    await state.saveCustomFood(food());
    expect(
      await state.logFood('yogurt-custom', 150, 0, date: '2026-10-02'),
      isTrue,
    );
    final before = state.logs['2026-10-02']!.foodEntries.single.toJson();
    expect(state.nutritionForDate('2026-10-02').toJson(), [120, 6, 15, 3]);
    await state.saveCustomFood(
      food(
        name: '新版酸奶',
        source: '新包装',
        per100g: const Nutrients(100, 6, 12, 3),
      ),
    );
    expect(state.logs['2026-10-02']!.foodEntries.single.toJson(), before);
    expect(state.nutrition.kcal, 0);
    await state.logFood('yogurt-custom', 100, 1);
    final restored = AppState(state.preferences, now: state.now);
    await restored.load();
    expect(restored.storageError, isNull);
    expect(restored.customFoods['yogurt-custom']!.name, '新版酸奶');
    expect(restored.logs['2026-10-02']!.foodEntries.single.toJson(), before);
    expect(restored.nutrition.kcal, 100);
  });

  test('entries add to meal snapshot, union slots cap completion, removal is individual', () async {
    await state.saveCustomFood(food());
    await state.toggleMeal(0);
    final meal = state.log.meals[0]!.toJson();
    for (var slot = 0; slot < 4; slot++) {
      await state.logFood('yogurt-custom', 100, slot);
    }
    await state.logFood('yogurt-custom', 50, 0);
    expect(state.log.mealCount, 4);
    expect(state.score.nutrition, 100);
    expect(state.nutrition.kcal, 410 + 360);
    final id = state.log.foodEntries.last.id;
    expect(await state.removeFoodEntry(id), isTrue);
    expect(state.nutrition.kcal, 410 + 320);
    expect(state.log.meals[0]!.toJson(), meal);
    await state.toggleMeal(0);
    expect(state.nutrition.kcal, 320);
    expect(state.log.mealCount, 4);
    expect(state.log.hasActivity, isTrue);
  });

  test('invalid source numeric values dates and disallowed foods never mutate intake', () async {
    expect(await state.saveCustomFood(food(source: ' ')), isFalse);
    expect(
      await state.saveCustomFood(
        food(per100g: const Nutrients(double.nan, 4, 10, 2)),
      ),
      isFalse,
    );
    await state.saveCustomFood(food());
    for (final date in ['2026-10-04', '2026-02-30', 'bad']) {
      expect(await state.logFood('yogurt-custom', 100, 0, date: date), isFalse);
    }
    for (final grams in [0.0, -5.0, double.infinity, 10001.0]) {
      expect(await state.logFood('yogurt-custom', grams, 0), isFalse);
    }
    expect(await state.logFood('unknown', 100, 0), isFalse);
    expect(await state.logFood('yogurt-custom', 100, 4), isFalse);
    expect(state.logs, isEmpty);
    await state.savePreferences(
      diet: '素食优先',
      allergens: {'乳制品'},
      calories: 1800,
      water: 2000,
    );
    expect(state.availableFoods, isEmpty);
    expect(await state.logFood('yogurt-custom', 100, 0), isFalse);
    expect(state.logs, isEmpty);
  });

  test(
    'legacy meal payload loads without food keys and preserves previous meal',
    () async {
      await state.toggleMeal(0);
      final old = jsonDecode(state.exportJson()) as Map<String, dynamic>;
      old['version'] = 3;
      old.remove('customFoods');
      old['logs'][state.today].remove('foodEntries');
      await state.preferences.setString(AppState.storageKey, jsonEncode(old));
      final restored = AppState(state.preferences, now: state.now);
      await restored.load();
      expect(restored.nutrition.kcal, 410);
      expect(restored.log.foodEntries, isEmpty);
      expect(restored.customFoods, isEmpty);
    },
  );

  test('suggestion responds to target and actual intake while retaining restrictions and targets', () async {
    final targets = state.targetsForDate(state.tomorrow).toJson();
    final before = state.recommendation.meals.map((m) => m.mealId).toList();
    await state.saveCustomFood(
      CustomFood(
        id: 'protein',
        name: '个人记录食物',
        source: '包装标签',
        per100g: const Nutrients(400, 100, 0, 0),
        vegetarian: true,
      ),
    );
    await state.logFood('protein', 150, 1);
    final after = state.recommendation;
    expect(after.meals.map((m) => m.mealId), isNot(equals(before)));
    expect(after.nutritionReason, contains('1 天实际摄入'));
    expect(after.nutritionReason, contains('热量'));
    expect(after.nutritionReason, contains('碳水'));
    expect(state.targetsForDate(state.tomorrow).toJson(), targets);
    await state.savePreferences(
      diet: '素食优先',
      allergens: {'大豆', '乳制品'},
      calories: 1800,
      water: 2000,
    );
    final filtered = state.recommendation.meals;
    for (var slot = 0; slot < 4; slot++) {
      expect(
        state.availableMeals(slot).any((m) => m.id == filtered[slot].mealId),
        isTrue,
      );
    }
  });

  test(
    'reading an unadopted recommendation keeps tomorrow targets live',
    () async {
      final initial = state.recommendation;
      expect(initial.nutritionReason, contains('热量 1800 kcal'));
      expect(state.nutritionTargets.containsKey(state.tomorrow), isFalse);
      await state.savePreferences(
        diet: state.diet,
        allergens: {},
        calories: 2400,
        water: 2500,
        protein: 150,
        carbs: 280,
        fat: 80,
      );
      final updated = state.recommendation;
      expect(state.tomorrowAdopted, isFalse);
      expect(updated.nutritionReason, contains('热量 2400 kcal'));
      expect(updated.nutritionReason, contains('蛋白质 150 g'));
      expect(updated.nutritionReason, contains('碳水 280 g'));
      expect(updated.nutritionReason, contains('脂肪 80 g'));
      expect(state.nutritionTargets.containsKey(state.tomorrow), isFalse);
    },
  );

  test(
    'explicit or adopted tomorrow targets survive today default edits',
    () async {
      await state.savePreferences(
        diet: state.diet,
        allergens: {},
        calories: 2100,
        water: 2500,
        protein: 130,
        carbs: 230,
        fat: 70,
        date: state.tomorrow,
      );
      await state.savePreferences(
        diet: state.diet,
        allergens: {},
        calories: 2400,
        water: 3000,
        protein: 150,
        carbs: 280,
        fat: 80,
      );
      expect(state.recommendation.nutritionReason, contains('热量 2100 kcal'));
      expect(state.recommendation.nutritionReason, contains('蛋白质 130 g'));
      expect(state.nutritionTargets[state.tomorrow]!.carbs, 230);
      await state.adoptRecommendation(state.recommendation);
      final adopted = state.nutritionTargets[state.tomorrow]!.toJson();
      await state.savePreferences(
        diet: state.diet,
        allergens: {},
        calories: 1800,
        water: 2000,
        protein: 100,
        carbs: 190,
        fat: 60,
      );
      expect(state.nutritionTargets[state.tomorrow]!.toJson(), adopted);
      expect(state.recommendation.nutritionReason, contains('热量 2100 kcal'));
    },
  );

  for (final width in [320.0, 390.0]) {
    testWidgets('food create edit log and remove at $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: pulseTheme(),
          home: Scaffold(
            body: AnimatedBuilder(
              animation: state,
              builder: (_, _) => SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: NutritionScreen(state: state),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('食物记录与食物库'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新建食物'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('food-name')), '原味酸奶');
      await tester.enterText(find.byKey(const ValueKey('food-source')), '包装标签');
      for (final key in ['kcal', 'protein', 'carbs', 'fat']) {
        await tester.enterText(
          find.byKey(ValueKey('food-$key')),
          key == 'kcal' ? '80' : '4',
        );
      }
      await tester.ensureVisible(find.text('保存食物'));
      await tester.tap(find.text('保存食物'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('记录克数'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('food-grams')), '150');
      await tester.pump();
      await tester.ensureVisible(find.text('加入所选日期'));
      await tester.tap(find.text('加入所选日期'));
      await tester.pumpAndSettle();
      expect(state.nutrition.kcal, 120);
      await tester.tap(find.byTooltip('编辑原味酸奶'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('food-name')), '新名称');
      await tester.ensureVisible(find.text('保存食物'));
      await tester.tap(find.text('保存食物'));
      await tester.pumpAndSettle();
      expect(state.log.foodEntries.single.food.name, '原味酸奶');
      await tester.ensureVisible(find.byTooltip('移除此条摄入'));
      await tester.tap(find.byTooltip('移除此条摄入'));
      await tester.pumpAndSettle();
      expect(state.log.foodEntries, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}
