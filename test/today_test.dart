import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulse_fitness/app.dart';
import 'package:pulse_fitness/core/app_state.dart';
import 'package:pulse_fitness/core/models.dart';

void main() {
  Future<AppState> store() async {
    SharedPreferences.setMockInitialValues({});
    return AppState(
      await SharedPreferences.getInstance(),
      now: () => DateTime(2026, 9, 27),
    );
  }

  Future<void> render(
    WidgetTester tester,
    AppState state, {
    double width = 390,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(PulseApp(state: state));
    await tester.pumpAndSettle();
  }

  testWidgets('unrecorded meals stay distinct from recorded energy', (
    tester,
  ) async {
    final state = await store();
    await render(tester, state);
    expect(find.text('尚未记录餐食'), findsOneWidget);
    expect(find.text('0 / 1800 kcal'), findsNothing);
    await state.toggleMeal(0);
    await tester.pumpAndSettle();
    expect(find.text('尚未记录餐食'), findsNothing);
    expect(find.text('已摄入 410 kcal'), findsOneWidget);
    expect(find.text('蛋白质 24g  ·  碳水 48g  ·  脂肪 14g'), findsOneWidget);
  });

  testWidgets(
    'calendar distinguishes completed, partial, rest and planned days without creating records',
    (tester) async {
      final state = await store();
      final template = state.template;
      state.plans['2026-09-21'] = template.copyWith();
      state.logs['2026-09-21'] = DailyLog(
        '2026-09-21',
        completedSets: {
          for (final item in template.items)
            item.exerciseId: Set.of(List.generate(item.sets, (i) => i)),
        },
      );
      state.plans['2026-09-23'] = template.copyWith();
      state.logs['2026-09-23'] = DailyLog(
        '2026-09-23',
        completedSets: {
          'squat': {0},
        },
      );
      await render(tester, state);
      expect(find.byTooltip('9月21日 · 已完成'), findsOneWidget);
      expect(find.byTooltip('9月22日 · 休息日'), findsOneWidget);
      expect(find.byTooltip('9月23日 · 部分完成'), findsOneWidget);
      expect(find.byTooltip('9月26日 · 未记录'), findsOneWidget);
      final beforeLogs = state.logs.length;
      final beforePlans = state.plans.length;
      await tester.tap(find.byTooltip('9月22日 · 休息日'));
      await tester.pumpAndSettle();
      expect(find.text('这一天没有记录'), findsOneWidget);
      expect(state.logs.length, beforeLogs);
      expect(state.plans.length, beforePlans);
    },
  );

  testWidgets(
    'quick water entry records only the current day and supports undo',
    (tester) async {
      final state = await store();
      await render(tester, state);
      final button = find.byKey(const Key('quick-water'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(state.log.waterMl, 250);
      await tester.tap(find.text('撤销'));
      await tester.pumpAndSettle();
      expect(state.log.waterMl, 0);
    },
  );

  testWidgets(
    'recommendation shows fatigue reason and saved plan never claims a new rationale',
    (tester) async {
      final state = await store();
      await state.completeSet('squat', 0, 3);
      await render(tester, state);
      expect(find.textContaining('最近反馈偏吃力'), findsOneWidget);
      await state.adoptRecommendation(
        NextRecommendation(
          date: state.tomorrow,
          plan: state.recommendation.plan.copyWith(title: '我自己的明日计划'),
          meals: state.recommendation.meals,
          reasons: const ['irrelevant'],
          nutritionReason: '',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('我自己的明日计划'), findsOneWidget);
      expect(find.textContaining('最近反馈偏吃力'), findsNothing);
      expect(find.text('已保存你的安排，可在记录页继续调整。'), findsOneWidget);
    },
  );

  testWidgets(
    'calendar preserves actual sets after the recorded exercise is removed',
    (tester) async {
      final state = await store();
      await state.completeSet('squat', 0, 2);
      await state.savePlan(
        state.plan.copyWith(
          items: state.plan.items
              .where((i) => i.exerciseId != 'squat')
              .toList(),
        ),
      );
      await render(tester, state);
      await tester.tap(find.byTooltip('9月27日 · 已训练'));
      await tester.pumpAndSettle();
      expect(find.text('训练已记录 1 组'), findsOneWidget);
      expect(state.log.setCount, 1);
    },
  );

  testWidgets(
    'water undo after midnight subtracts only the capped increment from its original date',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      var clock = DateTime(2026, 9, 27, 23, 59);
      final state = AppState(
        await SharedPreferences.getInstance(),
        now: () => clock,
      );
      await state.addWater(5900);
      await render(tester, state);
      final button = find.byKey(const Key('quick-water'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(state.logs['2026-09-27']!.waterMl, 6000);
      expect(find.text('已记录 100 ml 饮水'), findsOneWidget);
      clock = DateTime(2026, 9, 28);
      await tester.tap(find.text('撤销'));
      await tester.pumpAndSettle();
      expect(state.logs['2026-09-27']!.waterMl, 5900);
      expect(state.log.waterMl, 0);
    },
  );

  testWidgets(
    'future day across month boundary remains read only with an empty plan',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final state = AppState(
        await SharedPreferences.getInstance(),
        now: () => DateTime(2026, 9, 30),
      );
      await state.savePlan(state.plan.copyWith(items: []));
      await render(tester, state, width: 320);
      expect(find.text('添加动作'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final logDates = state.logs.keys.toList();
      final planDates = state.plans.keys.toList();
      await tester.tap(find.byTooltip('10月3日 · 休息日'));
      await tester.pumpAndSettle();
      expect(find.text('留一些时间休息恢复'), findsOneWidget);
      expect(state.logs.keys.toList(), logDates);
      expect(state.plans.keys.toList(), planDates);
    },
  );

  for (final width in [320.0, 390.0, 1100.0]) {
    testWidgets('training stays first and home fits at $width', (tester) async {
      final state = await store();
      await render(tester, state, width: width);
      expect(tester.takeException(), isNull);
      expect(
        tester.getTopLeft(find.text('开始训练')).dy,
        lessThan(tester.getTopLeft(find.text('今日进度')).dy),
      );
      expect(find.text('完成今日训练'), findsNothing);
      expect(find.text('还没开始，按自己的节奏来'), findsOneWidget);
    });
  }
}
