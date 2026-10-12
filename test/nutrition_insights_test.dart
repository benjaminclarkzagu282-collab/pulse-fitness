import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulse_fitness/core/app_state.dart';
import 'package:pulse_fitness/core/catalog.dart';
import 'package:pulse_fitness/screens/nutrition.dart';
import 'package:pulse_fitness/screens/insights.dart';
import 'package:pulse_fitness/ui/theme.dart';
import 'package:pulse_fitness/ui/components.dart';

void main() {
  Future<AppState> store() async {
    SharedPreferences.setMockInitialValues({});
    return AppState(
      await SharedPreferences.getInstance(),
      now: () => DateTime(2026, 9, 26),
    );
  }

  Future<void> render(
    WidgetTester tester,
    AppState state,
    bool insights,
    Size size,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        theme: pulseTheme(),
        home: Scaffold(
          body: AnimatedBuilder(
            animation: state,
            builder: (_, _) => SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: insights
                    ? InsightsScreen(state: state)
                    : NutritionScreen(state: state),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final size in [
    const Size(320, 720),
    const Size(390, 844),
    const Size(1100, 900),
  ]) {
    testWidgets('screen layouts ${size.width}', (tester) async {
      final state = await store();
      await render(tester, state, false, size);
      expect(tester.takeException(), isNull);
      await render(tester, state, true, size);
      expect(tester.takeException(), isNull);
      expect(find.text('这段时间还没有记录'), findsOneWidget);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }
  testWidgets('record undo and preserved consumed snapshot', (tester) async {
    final state = await store();
    await render(tester, state, false, const Size(1100, 900));
    await tester.tap(find.text('记录餐食').first);
    await tester.pumpAndSettle();
    expect(state.log.meals.length, 1);
    expect(state.nutrition.kcal, 410);
    await state.setMeal(0, 'rice_breakfast', 1.5);
    await tester.pumpAndSettle();
    expect(state.nutrition.kcal, 410);
    expect(find.textContaining('更换计划不会改写摄入'), findsOneWidget);
    await tester.tap(find.text('撤销记录').first);
    await tester.pumpAndSettle();
    expect(state.log.meals, isEmpty);
    await tester.tap(find.text('记录餐食').first);
    await tester.pumpAndSettle();
    expect(state.nutrition.kcal, 555);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  testWidgets('explicit recommendation adoption and repeat edits', (
    tester,
  ) async {
    final state = await store();
    await render(tester, state, true, const Size(1100, 1600));
    expect(state.tomorrowAdopted, false);
    final today = state.plan.toJson().toString();
    await tester.ensureVisible(find.text('采用下次安排'));
    await tester.tap(find.text('采用下次安排'));
    await tester.pumpAndSettle();
    expect(state.tomorrowAdopted, true);
    expect(state.plan.toJson().toString(), today);
    expect(find.text('已保存 · 调整后可再次采用'), findsOneWidget);
    await tester.ensureVisible(find.text('调整'));
    await tester.tap(find.text('调整'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('移除此动作').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('保留训练调整'));
    await tester.tap(find.text('保留训练调整'));
    await tester.pumpAndSettle();
    expect(find.text('已调整 · 待采用'), findsOneWidget);
    final before = state.plans[state.tomorrow]!.items.length;
    await tester.ensureVisible(find.text('采用下次安排'));
    await tester.tap(find.text('采用下次安排'));
    await tester.pumpAndSettle();
    expect(state.plans[state.tomorrow]!.items.length, before - 1);
    expect(tester.takeException(), isNull);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  testWidgets('preferences filter meal plans and keep logged meal intact', (
    tester,
  ) async {
    final state = await store();
    await state.toggleMeal(0);
    await render(tester, state, false, const Size(1100, 1200));
    await tester.tap(find.byTooltip('饮食偏好与目标'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('素食优先'));
    await tester.tap(find.text('大豆'));
    await tester.tap(find.text('乳制品'));
    await tester.tap(find.text('保存偏好与目标'));
    await tester.pumpAndSettle();
    expect(state.diet, '素食优先');
    expect(state.allergens, containsAll(['大豆', '乳制品']));
    expect(state.meals[0].mealId, 'rice_breakfast');
    expect(state.meals[1].mealId, 'lentils');
    expect(state.meals[3].mealId, 'chickpea');
    expect(state.log.meals[0]!.title, '燕麦鸡蛋早餐');
    expect(state.nutrition.kcal, 410);
    await tester.ensureVisible(find.text('+ 250 ml'));
    await tester.tap(find.text('+ 250 ml'));
    await tester.pumpAndSettle();
    expect(state.log.waterMl, 250);
    await tester.tap(find.byTooltip('− 250 ml'));
    await tester.pumpAndSettle();
    expect(state.log.waterMl, 0);
    expect(tester.takeException(), isNull);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  testWidgets(
    'tomorrow meal edits are local until adoption and saved view stays stable',
    (tester) async {
      final state = await store();
      await state.toggleMeal(0);
      await render(tester, state, true, const Size(1100, 1600));
      final todayMeals = state.meals.map((m) => m.toJson()).toString();
      await tester.tap(
        find.text(
          '早餐 · ${mealById(state.recommendation.meals.first.mealId).title}',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('杂粮水果碗'));
      await tester.tap(find.text('2 ×'));
      await tester.tap(find.text('确认搭配与份量'));
      await tester.pumpAndSettle();
      expect(state.tomorrowAdopted, false);
      expect(state.meals.map((m) => m.toJson()).toString(), todayMeals);
      expect(state.nutrition.kcal, 410);
      await tester.ensureVisible(find.text('采用下次安排'));
      await tester.tap(find.text('采用下次安排'));
      await tester.pumpAndSettle();
      expect(state.mealPlans[state.tomorrow]![0].mealId, 'rice_breakfast');
      expect(state.mealPlans[state.tomorrow]![0].factor, 2);
      await state.addWater(250);
      await tester.pumpAndSettle();
      expect(find.text('早餐 · 杂粮水果碗'), findsOneWidget);
      expect(state.nutrition.kcal, 410);
      expect(tester.takeException(), isNull);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
  testWidgets('history periods preserve missing dates as null gaps', (
    tester,
  ) async {
    final state = await store();
    await state.addWater(250);
    await render(tester, state, true, const Size(1100, 1600));
    var chart = tester.widget<MiniChart>(find.byType(MiniChart));
    expect(chart.values.length, 1);
    await tester.tap(find.text('7 天'));
    await tester.pumpAndSettle();
    chart = tester.widget<MiniChart>(find.byType(MiniChart));
    expect(chart.values.length, 7);
    expect(chart.values.where((value) => value == null).length, 6);
    expect(chart.values.last, state.score.total.toDouble());
    await tester.tap(find.text('30 天'));
    await tester.pumpAndSettle();
    chart = tester.widget<MiniChart>(find.byType(MiniChart));
    expect(chart.values.length, 30);
    expect(chart.values.where((value) => value == null).length, 29);
    expect(find.textContaining('250 ml 水'), findsOneWidget);
    expect(tester.takeException(), isNull);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  testWidgets('date arrows scope records and future edits to selected date', (
    tester,
  ) async {
    final state = await store();
    await render(tester, state, false, const Size(390, 844));
    expect(
      tester.getTopLeft(find.text('今天摄入')).dy,
      lessThan(tester.getTopLeft(find.text('今天餐食')).dy),
    );
    await tester.tap(find.byTooltip('前一天'));
    await tester.pumpAndSettle();
    expect(find.text('所选日期 · 09.25'), findsOneWidget);
    await tester.tap(find.text('记录餐食').first);
    await tester.pumpAndSettle();
    expect(state.logs['2026-09-25']!.meals.length, 1);
    expect(state.log.meals, isEmpty);
    await tester.tap(find.byTooltip('后一天'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('后一天'));
    await tester.pumpAndSettle();
    expect(find.text('明天 · 09.27'), findsOneWidget);
    expect(find.text('未来仅安排计划，当天再记录实际摄入与饮水。'), findsOneWidget);
    expect(find.text('记录餐食'), findsNothing);
    await tester.tap(find.text('更换 / 份量 ›').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('杂粮水果碗'));
    await tester.tap(find.text('2 ×'));
    await tester.tap(find.text('确认搭配与份量'));
    await tester.pumpAndSettle();
    expect(state.mealPlans[state.tomorrow]!.first.mealId, 'rice_breakfast');
    expect(state.mealPlans[state.tomorrow]!.first.factor, 2);
    expect(state.logs.containsKey(state.tomorrow), false);
    expect(state.nutrition.kcal, 0);
    expect(tester.takeException(), isNull);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  testWidgets('date navigation has a thirty day future bound', (tester) async {
    final state = await store();
    await render(tester, state, false, const Size(390, 844));
    for (var i = 0; i < 30; i++) {
      await tester.tap(find.byTooltip('后一天'));
      await tester.pump();
    }
    final forward = tester.widget<IconButton>(
      find.byWidgetPredicate((w) => w is IconButton && w.tooltip == '后一天'),
    );
    expect(forward.onPressed, isNull);
    expect(find.text('所选日期 · 10.26'), findsOneWidget);
    expect(state.history.where((l) => l.hasActivity), isEmpty);
    expect(tester.takeException(), isNull);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  testWidgets('goal sheet edits stay local until saved for selected date', (
    tester,
  ) async {
    final state = await store();
    await render(tester, state, false, const Size(390, 844));
    await tester.tap(find.byTooltip('前一天'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的目标'));
    await tester.pumpAndSettle();
    expect(find.text('我的目标 · 2026-09-25'), findsOneWidget);
    var slider = tester.widget<Slider>(find.byType(Slider).at(1));
    slider.onChanged!(150);
    await tester.pumpAndSettle();
    expect(state.targetsForDate('2026-09-25').protein, 120);
    await tester.ensureVisible(find.text('保存所选日期目标'));
    await tester.tap(find.text('保存所选日期目标'));
    await tester.pumpAndSettle();
    expect(state.targetsForDate('2026-09-25').protein, 150);
    expect(state.proteinTarget, 120);
    expect(tester.takeException(), isNull);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
