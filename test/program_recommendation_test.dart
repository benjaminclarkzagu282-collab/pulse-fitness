import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulse_fitness/core/app_state.dart';
import 'package:pulse_fitness/core/training_programs.dart';
import 'package:pulse_fitness/screens/insights.dart';
import 'package:pulse_fitness/ui/theme.dart';

void main() {
  Future<AppState> init() async {
    SharedPreferences.setMockInitialValues({});
    return AppState(
      await SharedPreferences.getInstance(),
      now: () => DateTime(2026, 10, 3),
    );
  }

  test(
    'a dated program does not claim its unsaved meals are adopted',
    () async {
      final state = await init();
      await state.saveProgramPlan(
        trainingPrograms.first.createPlan(days: [1, 3, 6]),
        date: state.tomorrow,
      );
      expect(state.mealPlans.containsKey(state.tomorrow), isFalse);
      expect(state.tomorrowAdopted, isFalse);
    },
  );

  for (final width in [320.0, 1100.0]) {
    testWidgets(
      'program is retained while pending meals can be saved at $width',
      (tester) async {
        final state = await init();
        await state.addWater(250);
        await state.completeSet('squat', 0, 2);
        await state.saveProgramPlan(
          trainingPrograms[2].createPlan(days: [2, 5]),
          date: state.tomorrow,
        );
        final program = jsonEncode(state.plans[state.tomorrow]!.toJson());
        final todayLog = jsonEncode(state.logs[state.today]!.toJson());
        final template = jsonEncode(state.template.toJson());
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
                  padding: const EdgeInsets.all(16),
                  child: InsightsScreen(state: state),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('训练已保存 · 餐食待确认'), findsOneWidget);
        expect(find.text(trainingPrograms[2].title), findsOneWidget);
        expect(state.mealPlans.containsKey(state.tomorrow), isFalse);
        final action = find.text('保存餐食并保留训练');
        await tester.ensureVisible(action);
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(state.tomorrowAdopted, isTrue);
        expect(state.mealPlans[state.tomorrow], hasLength(4));
        expect(jsonEncode(state.plans[state.tomorrow]!.toJson()), program);
        expect(jsonEncode(state.logs[state.today]!.toJson()), todayLog);
        expect(jsonEncode(state.template.toJson()), template);
        expect(find.text('已保存 · 调整后可再次采用'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
