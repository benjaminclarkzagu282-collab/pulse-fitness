import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulse_fitness/core/app_state.dart';
import 'package:pulse_fitness/core/models.dart';
import 'package:pulse_fitness/core/training_programs.dart';
import 'package:pulse_fitness/screens/programs.dart';
import 'package:pulse_fitness/screens/plan.dart';
import 'package:pulse_fitness/ui/theme.dart';

void main() {
  late AppState state;
  late DateTime clock;
  Future<void> init() async {
    SharedPreferences.setMockInitialValues({});
    clock = DateTime(2026, 10, 3, 10);
    state = AppState(await SharedPreferences.getInstance(), now: () => clock);
    await state.load();
  }

  Future<void> open(
    WidgetTester tester, {
    bool editor = false,
    double width = 390,
  }) async {
    tester.view.physicalSize = Size(width, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: pulseTheme(),
        home: editor
            ? Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: PlanScreen(state: state, openLibrary: () {}),
                ),
              )
            : ProgramsScreen(state: state),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> preview(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('preview-full-body')));
    await tester.pumpAndSettle();
  }

  Future<void> adopt(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('adopt-program')));
    await tester.tap(find.byKey(const Key('adopt-program')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'browsing and preview are read-only with exact sets and seconds',
    (tester) async {
      await init();

      final before = state.exportJson();
      await open(tester);
      await preview(tester);
      expect(find.text('2 组 × 30 秒 · 组间休息 30 秒'), findsOneWidget);
      expect(find.text('2 组 × 8 次 · 组间休息 45 秒'), findsOneWidget);
      expect(find.text('所需器械：徒手'), findsOneWidget);
      expect(state.exportJson(), before);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(state.exportJson(), before);
    },
  );
  testWidgets(
    'today adoption requires explicit dated confirmation and preserves other data',
    (tester) async {
      await init();

      await state.savePlan(state.plan.copyWith(title: '旧安排', days: [2, 5]));
      await state.addWater(250);
      await state.toggleMeal(0);
      await state.saveCustomFood(
        CustomFood(
          id: 'rice',
          name: '米饭',
          source: '测试输入',
          per100g: const Nutrients(116, 2.6, 25.9, .3),
        ),
      );
      await state.logFood('rice', 150, 1);
      await state.savePreferences(
        diet: state.diet,
        allergens: {},
        calories: 2200,
        water: 2500,
        protein: 130,
        carbs: 260,
        fat: 65,
      );
      state.logs['2026-10-02'] = DailyLog(
        '2026-10-02',
        completedSets: {
          'squat': {0},
        },
        trainingSeconds: 45,
      );
      state.plans['2026-10-02'] = state.template.copyWith(title: '昨天的计划');
      final before = jsonDecode(state.exportJson()) as Map<String, dynamic>;
      await open(tester);
      await preview(tester);
      await adopt(tester);
      expect(find.textContaining('2026-10-03'), findsWidgets);
      expect(find.textContaining('旧安排'), findsOneWidget);
      expect(state.plan.title, '旧安排');
      await tester.tap(find.byKey(const Key('confirm-program')));
      await tester.pumpAndSettle();
      expect(state.plan.title, trainingPrograms.first.title);
      expect(state.plan.days, [2, 5]);
      final after = jsonDecode(state.exportJson()) as Map<String, dynamic>;
      for (final key in before.keys.where((key) => key != 'plans')) {
        expect(after[key], before[key], reason: key);
      }
      expect(after['plans']['2026-10-02'], before['plans']['2026-10-02']);
      final restored = AppState(state.preferences, now: () => clock);
      await restored.load();
      expect(restored.plans[state.today]!.title, trainingPrograms.first.title);
    },
  );
  testWidgets(
    'any completed set disables today even if its action was removed',
    (tester) async {
      await init();

      await state.completeSet('squat', 0, 2);
      await state.savePlan(
        state.plan.copyWith(items: [const PlanItem('curl')]),
      );
      final before = state.plans[state.today]!.toJson();
      await open(tester);
      await preview(tester);
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const Key('program-today')))
            .onSelected,
        isNull,
      );
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const Key('program-tomorrow')))
            .selected,
        isTrue,
      );
      await adopt(tester);
      await tester.tap(find.byKey(const Key('confirm-program')));
      await tester.pumpAndSettle();
      expect(state.plans[state.today]!.toJson(), before);
      expect(state.plans[state.tomorrow]!.title, trainingPrograms.first.title);
      expect(state.logs[state.today]!.setCount, 1);
    },
  );
  testWidgets(
    'tomorrow replacement shows old title and cancellation preserves it',
    (tester) async {
      await init();

      await state.saveProgramPlan(
        state.template.copyWith(title: '明天原计划'),
        date: state.tomorrow,
      );
      final before = state.exportJson();
      await open(tester);
      await preview(tester);
      await tester.ensureVisible(find.byKey(const Key('program-tomorrow')));
      await tester.tap(find.byKey(const Key('program-tomorrow')));
      await tester.pumpAndSettle();
      await adopt(tester);
      expect(find.textContaining('明天原计划'), findsOneWidget);
      expect(find.textContaining('2026-10-04'), findsWidgets);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(state.exportJson(), before);
    },
  );
  testWidgets(
    'midnight while confirming cancels instead of shifting adoption',
    (tester) async {
      await init();

      final before = state.exportJson();
      await open(tester);
      await preview(tester);
      await adopt(tester);
      clock = DateTime(2026, 10, 4, 0, 1);
      await tester.tap(find.byKey(const Key('confirm-program')));
      await tester.pumpAndSettle();
      expect(state.exportJson(), before);
      expect(find.textContaining('日期已更新'), findsOneWidget);
    },
  );
  testWidgets(
    'changed dated plan during confirmation is never silently replaced',
    (tester) async {
      await init();

      await open(tester);
      await preview(tester);
      await adopt(tester);
      await state.saveProgramPlan(
        state.template.copyWith(title: '刚修改的新安排'),
        date: state.today,
      );
      await tester.tap(find.byKey(const Key('confirm-program')));
      await tester.pumpAndSettle();
      expect(state.plans[state.today]!.title, '刚修改的新安排');
      expect(find.textContaining('计划已变化'), findsOneWidget);
    },
  );
  testWidgets('training started during confirmation is rechecked', (
    tester,
  ) async {
    await init();
    await open(tester);
    await preview(tester);
    await adopt(tester);
    await state.completeSet('squat', 0, 2);
    await tester.tap(find.byKey(const Key('confirm-program')));
    await tester.pumpAndSettle();
    // Completing a set materializes today's default; it must stay that default.
    expect(state.plan.title, state.template.title);
    expect(find.textContaining('今天已有完成组记录'), findsOneWidget);
  });
  for (final width in [320.0, 390.0]) {
    testWidgets('program cards and previews fit ${width.toInt()}px', (
      tester,
    ) async {
      await init();

      await open(tester, width: width);
      expect(tester.takeException(), isNull);
      for (final program in trainingPrograms) {
        final action = find.byKey(Key('preview-${program.id}'));
        await tester.ensureVisible(action);
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(find.text('所需器械：${program.equipment}'), findsOneWidget);
        for (final item in program.items) {
          // The whole non-lazy preview is built, including rows below the fold.
          expect(
            find.textContaining('${item.sets} 组 × ${item.reps}'),
            findsWidgets,
          );
        }
        await tester.ensureVisible(find.byKey(const Key('adopt-program')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
    });
  }
  testWidgets(
    'editor asks before browsing and retains draft on return without adoption',
    (tester) async {
      await init();

      await open(tester, editor: true);
      await tester.tap(find.text('周二'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-programs')));
      await tester.pumpAndSettle();
      expect(find.text('保留草稿并浏览'), findsOneWidget);
      await tester.tap(find.text('继续编辑'));
      await tester.pumpAndSettle();
      expect(find.text('我的训练计划'), findsOneWidget);
      await tester.tap(find.byKey(const Key('open-programs')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保留草稿并浏览'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('save-plan')));
      await tester.tap(find.byKey(const Key('save-plan')));
      await tester.pumpAndSettle();
      expect(state.plan.days, [1, 2, 3, 6]);
    },
  );
  testWidgets('editor retains unsaved draft when only tomorrow is adopted', (
    tester,
  ) async {
    await init();
    await open(tester, editor: true);
    await tester.tap(find.text('周二'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-programs')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保留草稿并浏览'));
    await tester.pumpAndSettle();
    await preview(tester);
    await tester.ensureVisible(find.byKey(const Key('program-tomorrow')));
    await tester.tap(find.byKey(const Key('program-tomorrow')));
    await tester.pumpAndSettle();
    await adopt(tester);
    await tester.tap(find.byKey(const Key('confirm-program')));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('save-plan')));
    await tester.tap(find.byKey(const Key('save-plan')));
    await tester.pumpAndSettle();
    expect(state.plan.days, [1, 2, 3, 6]);
    expect(state.plans[state.tomorrow]!.title, trainingPrograms.first.title);
  });
  testWidgets(
    'editor refreshes after adopting today and loads new day after midnight',
    (tester) async {
      await init();

      await open(tester, editor: true);
      await tester.tap(find.byKey(const Key('open-programs')));
      await tester.pumpAndSettle();
      await preview(tester);
      await adopt(tester);
      await tester.tap(find.byKey(const Key('confirm-program')));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text(trainingPrograms.first.title), findsOneWidget);
      await tester.tap(find.byKey(const Key('open-programs')));
      await tester.pumpAndSettle();
      clock = DateTime(2026, 10, 4, 1);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text(state.template.title), findsOneWidget);
    },
  );
  testWidgets(
    'adopting today replaces a confirmed editor draft without stale resave',
    (tester) async {
      await init();
      await open(tester, editor: true);
      await tester.tap(find.text('周二'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-programs')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保留草稿并浏览'));
      await tester.pumpAndSettle();
      await preview(tester);
      await adopt(tester);
      await tester.tap(find.byKey(const Key('confirm-program')));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('save-plan')));
      await tester.tap(find.byKey(const Key('save-plan')));
      await tester.pumpAndSettle();
      expect(state.plan.title, trainingPrograms.first.title);
      expect(state.plan.days, [1, 3, 6]);
      expect(
        state.plan.items.map((i) => i.exerciseId),
        trainingPrograms.first.items.map((i) => i.exerciseId),
      );
    },
  );
  testWidgets(
    're-adopting the same plan still replaces the dirty editor draft',
    (tester) async {
      await init();
      await state.saveProgramPlan(
        trainingPrograms.first.createPlan(days: state.template.days),
        date: state.today,
      );
      final originalDays = List<int>.from(state.plan.days);
      await open(tester, editor: true);
      await tester.tap(find.text('周二'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-programs')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保留草稿并浏览'));
      await tester.pumpAndSettle();
      await preview(tester);
      await adopt(tester);
      await tester.tap(find.byKey(const Key('confirm-program')));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('save-plan')));
      await tester.tap(find.byKey(const Key('save-plan')));
      await tester.pumpAndSettle();
      expect(state.plan.days, originalDays);
    },
  );
  testWidgets('midnight before adopting requires a fresh preview', (
    tester,
  ) async {
    await init();
    final before = state.exportJson();
    await open(tester);
    await preview(tester);
    clock = DateTime(2026, 10, 4, 0, 1);
    await adopt(tester);
    expect(state.exportJson(), before);
    expect(find.text('方案预览'), findsNothing);
    expect(find.textContaining('日期已更新'), findsOneWidget);
  });
  testWidgets(
    'midnight during editor departure reloads instead of opening stale route',
    (tester) async {
      await init();
      await open(tester, editor: true);
      await tester.tap(find.text('周二'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-programs')));
      await tester.pumpAndSettle();
      clock = DateTime(2026, 10, 4, 0, 1);
      await tester.tap(find.text('保留草稿并浏览'));
      await tester.pumpAndSettle();
      expect(find.text('训练方案'), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('save-plan')));
      await tester.tap(find.byKey(const Key('save-plan')));
      await tester.pumpAndSettle();
      expect(state.plan.days, [1, 3, 6]);
    },
  );
  testWidgets(
    'write failure keeps preview available and retries the agreed dated plan',
    (tester) async {
      await init();
      final prefs = ProgramPreferences()..reject = true;
      state = AppState(prefs, now: () => clock);
      await open(tester);
      await preview(tester);
      await adopt(tester);
      await tester.tap(find.byKey(const Key('confirm-program')));
      await tester.pumpAndSettle();
      expect(find.text('方案预览'), findsOneWidget);
      expect(find.text('重试保存'), findsOneWidget);
      expect(state.storageError, isNotNull);
      prefs.reject = false;
      await tester.ensureVisible(find.byKey(const Key('adopt-program')));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('adopt-program')));
      await tester.pumpAndSettle();
      expect(find.text('方案预览'), findsNothing);
      expect(state.storageError, isNull);
      expect(
        jsonDecode(
          prefs.values[AppState.storageKey]!,
        )['plans']['2026-10-03']['title'],
        trainingPrograms.first.title,
      );
    },
  );
  testWidgets('retry does not claim adoption if the pending plan has changed', (
    tester,
  ) async {
    await init();
    final prefs = ProgramPreferences()..reject = true;
    state = AppState(prefs, now: () => clock);
    await open(tester);
    await preview(tester);
    await adopt(tester);
    await tester.tap(find.byKey(const Key('confirm-program')));
    await tester.pumpAndSettle();
    await state.saveProgramPlan(
      state.template.copyWith(title: '另一个已选择的计划'),
      date: state.today,
    );
    prefs.reject = false;
    await tester.ensureVisible(find.byKey(const Key('adopt-program')));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('adopt-program')));
    await tester.pumpAndSettle();
    expect(state.plans[state.today]!.title, '另一个已选择的计划');
    expect(find.text('方案预览'), findsOneWidget);
    expect(find.textContaining('计划已变化'), findsOneWidget);
    expect(find.textContaining('已将'), findsNothing);
  });
}

class ProgramPreferences implements SharedPreferences {
  final values = <String, String>{};
  bool reject = false;
  @override
  String? getString(String key) => values[key];
  @override
  Future<bool> setString(String key, String value) async {
    if (reject) return false;
    values[key] = value;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
