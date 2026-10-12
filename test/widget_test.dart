import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulse_fitness/app.dart';
import 'package:pulse_fitness/core/app_state.dart';
import 'package:pulse_fitness/core/models.dart';

void main() {
  testWidgets('home uses the selected day nutrition target snapshot', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    var clock = DateTime(2026, 9, 26);
    final state = AppState(
      await SharedPreferences.getInstance(),
      now: () => clock,
    );
    state.nutritionTargets[state.tomorrow] = const NutritionTargets(
      calories: 2400,
      protein: 140,
      carbs: 280,
      fat: 80,
      water: 1500,
    );
    clock = DateTime(2026, 9, 27);
    await state.addWater(1500);
    await tester.pumpWidget(PulseApp(state: state));
    await tester.pumpAndSettle();
    expect(find.text('目标 2400 kcal · 记录后查看摄入情况'), findsOneWidget);
    expect(find.text('1500 / 1500 ml'), findsOneWidget);
  });
  for (final sheetOpen in [false, true]) {
    testWidgets(
      'midnight preserves adopted plan with settings open: $sheetOpen',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        var clock = DateTime(2026, 9, 26, 23, 59);
        final state = AppState(
          await SharedPreferences.getInstance(),
          now: () => clock,
        );
        final next = state.recommendation;
        await state.adoptRecommendation(
          NextRecommendation(
            date: next.date,
            plan: next.plan.copyWith(title: '已确认的明日安排', minutes: 15),
            meals: next.meals,
            reasons: next.reasons,
            nutritionReason: next.nutritionReason,
          ),
        );
        tester.view.physicalSize = const Size(1100, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(PulseApp(state: state));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('nav-1')));
        await tester.pumpAndSettle();
        if (sheetOpen) {
          await tester.tap(find.byTooltip('计划设置'));
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField), '昨天未提交的编辑');
        }
        clock = DateTime(2026, 9, 27, 0, 1);
        await tester.pump(const Duration(seconds: 31));
        await tester.pumpAndSettle();
        if (sheetOpen) {
          await tester.tap(find.text('应用设置'));
          await tester.pumpAndSettle();
          await tester.pump(const Duration(seconds: 5));
          await tester.pumpAndSettle();
        }
        final save = find.byKey(const Key('save-plan'));
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(state.plan.title, '已确认的明日安排');
        expect(state.plan.minutes, 15);
      },
    );
  }
  testWidgets(
    'all main navigation destinations are reachable without losing data',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final state = AppState(await SharedPreferences.getInstance());
      await state.load();
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(PulseApp(state: state));
      await tester.pumpAndSettle();
      expect(find.text('今天，也要动起来'), findsOneWidget);
      await tester.tap(find.byKey(const Key('nav-1')));
      await tester.pumpAndSettle();
      expect(find.text('我的训练计划'), findsOneWidget);
      await tester.tap(find.byKey(const Key('nav-3')));
      await tester.pumpAndSettle();
      expect(find.text('健康饮食'), findsOneWidget);
      await tester.tap(find.byKey(const Key('nav-4')));
      await tester.pumpAndSettle();
      expect(find.text('复盘与下次安排'), findsOneWidget);
    },
  );
}
