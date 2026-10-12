import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:pulse_fitness/screens/insights.dart';
import 'package:pulse_fitness/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulse_fitness/core/app_state.dart';
import 'package:pulse_fitness/core/models.dart';
import 'package:pulse_fitness/screens/workout.dart';

void main() {
  late AppState state;
  late DateTime clock;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    clock = DateTime(2026, 9, 26, 10);
    state = AppState(await SharedPreferences.getInstance(), now: () => clock);
    await state.load();
  });

  Future<void> recordRecovery({
    int sleep = 3,
    int soreness = 0,
    bool pain = false,
  }) async {
    state.log;
    final payload = jsonDecode(state.exportJson()) as Map<String, dynamic>;
    payload['logs'][state.today]['recovery'] = {
      'sleepQuality': sleep,
      'soreness': soreness,
      'pain': pain,
    };
    await state.preferences.setString(AppState.storageKey, jsonEncode(payload));
    await state.load();
  }

  Future<void> successfulDay({
    int reps = 12,
    double weight = 10,
    bool actual = true,
  }) async {
    await state.savePlan(state.plan.copyWith(items: [const PlanItem('squat')]));
    for (var index = 0; index < 3; index++) {
      await state.completeSet(
        'squat',
        index,
        1,
        actualReps: actual ? reps : null,
        weightKg: actual ? weight : null,
      );
    }
    await recordRecovery();
  }

  test('a completed set snapshots its fatigue and elapsed time', () async {
    await state.completeSet('squat', 0, 2, seconds: 34);
    final saved = jsonDecode(state.exportJson())['logs'][state.today];
    expect(saved['setRecords'], isNotNull);
    expect(saved['setRecords']['squat']['0']['fatigue'], 2);
    expect(saved['setRecords']['squat']['0']['elapsedSeconds'], 34);
    expect(saved['setRecords']['squat']['0']['actualReps'], isNull);
  });
  test(
    'actual reps and weight survive plan edits, duplicate taps and reload',
    () async {
      await state.completeSet(
        'squat',
        0,
        2,
        actualReps: 10,
        weightKg: 12.5,
        seconds: 34,
      );
      await state.completeSet(
        'squat',
        0,
        1,
        actualReps: 20,
        weightKg: 99,
        seconds: 50,
      );
      await state.savePlan(
        state.plan.copyWith(items: [const PlanItem('squat', reps: 6)]),
      );
      final restored = AppState(state.preferences, now: () => clock);
      await restored.load();
      final saved = restored.log.setRecords['squat']![0]!;
      expect(saved.actualReps, 10);
      expect(saved.weightKg, 12.5);
      expect(saved.target, 12);
      expect(saved.fatigue, 2);
      expect(restored.log.trainingSeconds, 34);
      expect(restored.log.setCount, 1);
    },
  );

  test('invalid actuals are rejected before marking a set complete', () async {
    for (final invalid in [
      {#actualReps: 0},
      {#actualReps: -1},
      {#actualReps: 1001},
      {#actualSeconds: 1},
      {#weightKg: double.nan},
      {#weightKg: double.infinity},
      {#weightKg: -1.0},
      {#weightKg: 1001.0},
      {#seconds: -1},
      {#seconds: 7201},
    ]) {
      await Function.apply(state.completeSet, ['squat', 0, 2], invalid);
    }
    await state.completeSet('squat', 0, 4);
    for (final invalidSeconds in [0, -1, 7201]) {
      await state.completeSet('plank', 0, 2, actualSeconds: invalidSeconds);
    }
    expect(state.log.setCount, 0);
    expect(state.log.fatigue, isEmpty);
    expect(state.log.setRecords, isEmpty);
  });

  test('explicit timed actuals never manufacture repetition counts', () async {
    await state.completeSet('plank', 0, 1, seconds: 60, actualSeconds: 42);
    final saved = state.log.setRecords['plank']![0]!;
    expect(saved.actualSeconds, 42);
    expect(saved.actualReps, isNull);
    expect(saved.achievedTarget, isTrue);
  });

  test(
    'legacy JSON keeps completion and does not fabricate actual records',
    () async {
      await state.completeSet('squat', 0, 1);
      final legacy = jsonDecode(state.exportJson()) as Map<String, dynamic>;
      for (final entry in (legacy['logs'] as Map).values) {
        (entry as Map).remove('setRecords');
      }
      await state.preferences.setString(
        AppState.storageKey,
        jsonEncode(legacy),
      );
      final restored = AppState(state.preferences, now: () => clock);
      await restored.load();
      expect(restored.log.setCount, 1);
      expect(restored.log.setRecords, isEmpty);
    },
  );
  test(
    'recovery is restored by date and pain produces an explained rest day',
    () async {
      await recordRecovery(pain: true);
      final suggestion = state.recommendation;
      expect(suggestion.plan.items, isEmpty);
      expect(suggestion.reasons.join(' '), contains('疼痛'));
      expect(suggestion.reasons.join(' '), isNot(contains('沿用你的动作')));
      final yesterday = state.today;
      clock = DateTime(2026, 9, 27);
      final payload = jsonDecode(state.exportJson())['logs'][yesterday];
      expect(payload['recovery']['pain'], isTrue);
    },
  );

  test(
    'poor sleep without training history conservatively reduces volume',
    () async {
      final total = state.plan.totalSets;
      await recordRecovery(sleep: 1, soreness: 2);
      expect(state.recommendation.plan.totalSets, lessThan(total));
      expect(state.recommendation.reasons.join(' '), contains('睡眠'));
    },
  );

  test(
    'two successful same-action actual sessions permit a small progression',
    () async {
      await successfulDay();
      clock = DateTime(2026, 9, 27);
      await successfulDay();
      final suggestion = state.recommendation;
      expect(suggestion.plan.items.single.exerciseId, 'squat');
      expect(suggestion.plan.items.single.reps, 13);
      expect(suggestion.plan.items.single.sets, 3);
      expect(suggestion.reasons.join(' '), contains('两次'));
      expect(suggestion.reasons.join(' '), isNot(contains('优先切换到上肢')));
    },
  );

  test(
    'one actual session and legacy success cannot trigger progression',
    () async {
      await successfulDay(actual: false);
      clock = DateTime(2026, 9, 27);
      await successfulDay();
      expect(state.recommendation.plan.items.single.reps, 12);
      expect(state.recommendation.reasons.join(' '), isNot(contains('小幅进阶')));
    },
  );

  test(
    'reduced load and poor recovery cannot masquerade as progression',
    () async {
      await successfulDay(weight: 20);
      clock = DateTime(2026, 9, 27);
      await successfulDay(weight: 10);
      expect(state.recommendation.plan.items.single.reps, 12);
      await recordRecovery(sleep: 1);
      expect(state.recommendation.plan.totalSets, lessThan(3));
      expect(state.recommendation.reasons.join(' '), isNot(contains('小幅进阶')));
    },
  );

  test('replacement preserves a nonconsecutive actual set under its retained index', () async {
    await state.completeSet(
      'squat',
      2,
      2,
      actualReps: 9,
      weightKg: 5,
      seconds: 30,
    );
    await replaceWorkoutAction(state, 0, 'pushup');
    expect(state.log.setRecords['squat']![0]!.actualReps, 9);
    expect(state.log.setRecords['squat']![0]!.setIndex, 0);
    expect(state.log.setRecords['squat']!.containsKey(2), isFalse);
  });

  test(
    'recovery editing is dated, validated and cannot record a future date',
    () async {
      final dynamic editable = state;
      const good = RecoveryFeedback(sleepQuality: 3, soreness: 0, pain: false);
      const pain = RecoveryFeedback(sleepQuality: 1, soreness: 2, pain: true);
      await editable.saveRecovery(good, date: '2026-09-25');
      await editable.saveRecovery(pain);
      await editable.saveRecovery(good, date: state.tomorrow);
      await editable.saveRecovery(
        const RecoveryFeedback(sleepQuality: 4, soreness: -1, pain: false),
      );
      expect(state.logs['2026-09-25']!.recovery!.pain, isFalse);
      expect(state.log.recovery!.pain, isTrue);
      expect(state.logs.containsKey(state.tomorrow), isFalse);
      final restored = AppState(state.preferences, now: () => clock);
      await restored.load();
      expect(restored.log.recovery!.sleepQuality, 1);
      await editable.saveRecovery(good);
      expect(state.log.recovery!.pain, isFalse);
    },
  );

  testWidgets(
    'recovery sheet saves explicit feedback and exposes per-set history',
    (tester) async {
      await tester.runAsync(
        () => state.completeSet('squat', 0, 2, actualReps: 10, weightKg: 12.5),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: pulseTheme(),
          home: Scaffold(
            body: SingleChildScrollView(child: InsightsScreen(state: state)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('记录恢复'), findsOneWidget);
      await tester.ensureVisible(find.text('记录恢复'));
      await tester.tap(find.text('记录恢复'));
      await tester.pumpAndSettle();
      expect(find.text('睡眠质量'), findsOneWidget);
      expect(find.text('酸痛程度'), findsOneWidget);
      await tester.tap(find.text('有疼痛或不适'));
      await tester.tap(find.text('保存恢复反馈'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pumpAndSettle();
      expect(state.log.recovery!.pain, isTrue);
      await tester.ensureVisible(find.text('查看全部实际记录'));
      await tester.tap(find.text('查看全部实际记录'));
      await tester.pumpAndSettle();
      expect(find.textContaining('10 次'), findsOneWidget);
      expect(find.textContaining('12.5 kg'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'actual-set sheet validates input and returns actual reps and load',
    (tester) async {
      SetRecord? recorded;
      await tester.pumpWidget(
        MaterialApp(
          theme: pulseTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  recorded = await promptActualSet(
                    context,
                    const PlanItem('squat'),
                    setIndex: 0,
                    elapsedSeconds: 34,
                    fatigue: 2,
                  );
                },
                child: const Text('记录本组'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('记录本组'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('actual-count')), '0');
      await tester.tap(find.text('保存本组记录'));
      await tester.pumpAndSettle();
      expect(find.text('请输入 1–1000 的实际次数'), findsOneWidget);
      expect(recorded, isNull);
      await tester.enterText(find.byKey(const ValueKey('actual-count')), '10');
      await tester.enterText(
        find.byKey(const ValueKey('actual-weight')),
        '12.5',
      );
      await tester.tap(find.text('保存本组记录'));
      await tester.pumpAndSettle();
      expect(recorded!.actualReps, 10);
      expect(recorded!.weightKg, 12.5);
      expect(recorded!.elapsedSeconds, 34);
    },
  );

  test(
    'invalid persisted actuals cannot partly replace an existing log',
    () async {
      await state.completeSet('squat', 0, 2, actualReps: 10, weightKg: 5);
      final before = state.exportJson();
      final payload = jsonDecode(before) as Map<String, dynamic>;
      payload['logs'][state.today]['setRecords']['squat']['0']['actualReps'] =
          0;
      await state.preferences.setString(
        AppState.storageKey,
        jsonEncode(payload),
      );
      await state.load();
      expect(state.storageFailure, StorageFailure.load);
      expect(state.exportJson(), before);
      expect(state.log.setRecords['squat']![0]!.actualReps, 10);
    },
  );

  testWidgets('backgrounding latches workout pause until explicit resume', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: pulseTheme(),
        home: WorkoutScreen(state: state),
      ),
    );
    final dynamic session = tester.state(find.byType(WorkoutScreen));
    expect(session.watch.isRunning, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(session.paused, isTrue);
    expect(session.watch.isRunning, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(session.paused, isTrue);
    expect(session.watch.isRunning, isFalse);
    session.togglePause();
    expect(session.paused, isFalse);
    expect(session.watch.isRunning, isTrue);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'timed set sheet returns actual seconds independently of its target',
    (tester) async {
      SetRecord? recorded;
      await tester.pumpWidget(
        MaterialApp(
          theme: pulseTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  recorded = await promptActualSet(
                    context,
                    const PlanItem('plank', reps: 30),
                    setIndex: 1,
                    elapsedSeconds: 42,
                    fatigue: 1,
                  );
                },
                child: const Text('记录本组'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('记录本组'));
      await tester.pumpAndSettle();
      expect(find.text('实际完成秒数'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('actual-count')), '35');
      await tester.tap(find.text('保存本组记录'));
      await tester.pumpAndSettle();
      expect(recorded!.actualSeconds, 35);
      expect(recorded!.elapsedSeconds, 42);
      expect(recorded!.actualReps, isNull);
      expect(recorded!.target, 30);
    },
  );
  test(
    'timed completion-only keeps elapsed time without actuals or progression',
    () async {
      for (var day = 0; day < 2; day++) {
        clock = DateTime(2026, 9, 26 + day);
        await state.savePlan(
          state.plan.copyWith(
            items: [const PlanItem('plank', sets: 1, reps: 30)],
          ),
        );
        await state.completeSet('plank', 0, 1, seconds: 42);
        await recordRecovery();
        final record = state.log.setRecords['plank']![0]!;
        expect(record.elapsedSeconds, 42);
        expect(record.actualSeconds, isNull);
        expect(record.actualReps, isNull);
        expect(record.weightKg, isNull);
        expect(record.achievedTarget, isFalse);
      }
      expect(state.recommendation.reasons.join(' '), isNot(contains('小幅进阶')));
    },
  );

  test(
    'timed achievement and stopwatch elapsed time roundtrip independently',
    () async {
      await state.completeSet('plank', 0, 2, seconds: 70, actualSeconds: 45);
      final restored = AppState(state.preferences, now: () => clock);
      await restored.load();
      final record = restored.log.setRecords['plank']![0]!;
      expect(record.actualSeconds, 45);
      expect(record.elapsedSeconds, 70);
      expect(restored.log.trainingSeconds, 70);
      expect(record.weightKg, isNull);
    },
  );

  testWidgets(
    'completion-only prompt ignores numeric fields and preserves stopwatch',
    (tester) async {
      SetRecord? recorded;
      await tester.pumpWidget(
        MaterialApp(
          theme: pulseTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  recorded = await promptActualSet(
                    context,
                    const PlanItem('plank', reps: 30),
                    setIndex: 0,
                    elapsedSeconds: 70,
                    fatigue: 2,
                    weightKg: 12.5,
                  );
                },
                child: const Text('记录本组'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('记录本组'));
      await tester.pumpAndSettle();
      expect(find.text('只标记完成，不记录实际数值'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('actual-count')), '0');
      await tester.tap(find.text('只标记完成，不记录实际数值'));
      await tester.pumpAndSettle();
      expect(recorded!.actualSeconds, isNull);
      expect(recorded!.actualReps, isNull);
      expect(recorded!.weightKg, isNull);
      expect(recorded!.elapsedSeconds, 70);
      expect(recorded!.fatigue, 2);
      expect(recorded!.achievedTarget, isFalse);
    },
  );

  testWidgets(
    'blank unknown weight stays omitted when actual target is confirmed',
    (tester) async {
      SetRecord? recorded;
      await tester.pumpWidget(
        MaterialApp(
          theme: pulseTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  recorded = await promptActualSet(
                    context,
                    const PlanItem('squat'),
                    setIndex: 0,
                    elapsedSeconds: 34,
                    fatigue: 2,
                  );
                },
                child: const Text('记录本组'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('记录本组'));
      await tester.pumpAndSettle();
      final weightField = tester.widget<TextFormField>(
        find.byKey(const ValueKey('actual-weight')),
      );
      expect(weightField.controller!.text, isEmpty);
      await tester.tap(find.text('保存本组记录'));
      await tester.pumpAndSettle();
      expect(recorded!.actualReps, 12);
      expect(recorded!.weightKg, isNull);
    },
  );
}
