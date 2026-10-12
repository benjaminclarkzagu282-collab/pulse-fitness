import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulse_fitness/core/app_state.dart';
import 'package:pulse_fitness/core/catalog.dart';
import 'package:pulse_fitness/core/models.dart';
import 'package:pulse_fitness/core/model_assets.dart';
import 'package:pulse_fitness/screens/library.dart';
import 'package:pulse_fitness/screens/workout.dart';

const addedIds = <String>[
  'kneeling_pushup',
  'incline_pushup',
  'floor_press',
  'shoulder_press',
  'lateral_raise',
  'single_arm_row',
  'reverse_fly',
  'romanian_deadlift',
  'sumo_squat',
  'split_squat',
  'lateral_lunge',
  'calf_raise',
  'dead_bug',
  'bird_dog',
  'side_plank',
  'step_jack',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('all movements have verified model delivery, bundled images and fallback videos', () async {
    final ids = exercises.map((e) => e.id).toSet();
    expect(ids, containsAll(addedIds));
    expect(ids.length, 24);
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final paths = manifest.listAssets().toSet();
    final delivery = jsonDecode(
      await rootBundle.loadString('assets/muscles/model_manifest.json'),
    ) as Map<String, dynamic>;
    final models = delivery['models'] as Map<String, dynamic>;
    expect(models.keys.toSet(), ids);
    final bundled = <String>{};
    for (final id in ids) {
      final exercise = exerciseById(id);
      final entry = ModelAsset.fromJson(
        id,
        Map<String, dynamic>.from(models[id] as Map),
      );
      expect(exercise.model, 'assets/models/athlete_$id.glb');
      expect(exercise.image, 'assets/images/athlete_$id.png');
      expect(paths.contains(exercise.model), entry.bundled, reason: id);
      expect(paths, contains(exercise.image), reason: id);
      expect(paths, contains('assets/videos/$id.mp4'), reason: id);
      expect(entry.bytes, greaterThan(0), reason: id);
      expect(
        entry.compressedBytes,
        inExclusiveRange(0, entry.bytes),
        reason: id,
      );
      expect(entry.sha256Hex, matches(RegExp(r'^[a-f0-9]{64}$')), reason: id);
      expect(
        entry.compressedSha256,
        matches(RegExp(r'^[a-f0-9]{64}$')),
        reason: id,
      );
      expect(entry.remotePath, 'remote/models/athlete_$id.glb.gz');
      if (entry.bundled) bundled.add(id);
    }
    expect(bundled, {'squat', 'pushup'});
  });

  test('new choices persist with timer defaults while existing plan and logs survive loading', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final state = AppState(prefs);
    await state.completeSet('squat', 0, 2, seconds: 37);
    final previousPlan = jsonEncode(state.plan.toJson());
    final previousLog = jsonEncode(state.log.toJson());
    final restored = AppState(prefs);
    await restored.load();
    expect(jsonEncode(restored.plan.toJson()), previousPlan);
    expect(jsonEncode(restored.log.toJson()), previousLog);
    for (final id in addedIds) {
      await restored.addExercise(id);
      await restored.toggleFavorite(id);
    }
    final reloaded = AppState(prefs);
    await reloaded.load();
    for (final id in addedIds) {
      final item = reloaded.plan.items.singleWhere(
        (item) => item.exerciseId == id,
      );
      expect(item.reps, exerciseById(id).timed ? 30 : 12, reason: id);
      expect(reloaded.favorites, contains(id));
    }
    expect(reloaded.log.trainingSeconds, 37);
    expect(reloaded.completedSetsFor('squat'), 1);
    expect(reloaded.storageError, isNull);
  });

  test(
    'workout can replace an old action with a new movement and record it',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final state = AppState(prefs);
      await replaceWorkoutAction(state, 0, 'shoulder_press');
      await state.completeSet('shoulder_press', 0, 1, seconds: 42);
      final restored = AppState(prefs);
      await restored.load();
      expect(exerciseById(restored.plan.items.first.exerciseId).name, '哑铃肩推');
      expect(restored.completedSetsFor('shoulder_press'), 1);
      expect(restored.log.trainingSeconds, 42);
    },
  );

  test(
    'recommendation rotates into new available choices without adopting them',
    () async {
      SharedPreferences.setMockInitialValues({});
      final state = AppState(await SharedPreferences.getInstance());
      await state.savePlan(
        state.plan.copyWith(
          items: const [
            PlanItem('pushup'),
            PlanItem('plank'),
            PlanItem('jumping_jack'),
            PlanItem('squat'),
          ],
        ),
      );
      for (final item in state.plan.items) {
        await state.completeSet(item.exerciseId, 0, 1, seconds: 30);
      }
      final planBefore = jsonEncode(state.plan.toJson());
      final logBefore = jsonEncode(state.log.toJson());
      final savedBefore = state.preferences.getString(AppState.storageKey);
      final suggested = state.recommendation.plan.items;
      expect(
        suggested.any((item) => addedIds.contains(item.exerciseId)),
        isTrue,
      );
      expect(suggested.length, state.plan.items.length);
      expect(
        suggested.map((item) => exerciseById(item.exerciseId).equipment),
        everyElement('徒手'),
      );
      expect(
        suggested.map((item) => item.exerciseId),
        isNot(contains('incline_pushup')),
      );
      expect(
        suggested.map((item) => item.exerciseId),
        isNot(contains('single_arm_row')),
      );
      expect(jsonEncode(state.plan.toJson()), planBefore);
      expect(jsonEncode(state.log.toJson()), logBefore);
      expect(state.preferences.getString(AppState.storageKey), savedBefore);
    },
  );

  testWidgets('library filters discover shoulders and shared equipment', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState(await SharedPreferences.getInstance());
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: LibraryScreen(state: state)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('24 个动作'), findsOneWidget);
    await tester.tap(find.text('肩部').first);
    await tester.pumpAndSettle();
    expect(find.text('哑铃肩推'), findsOneWidget);
    expect(find.text('哑铃侧平举'), findsOneWidget);
    expect(find.text('俯身反向飞鸟'), findsOneWidget);
    expect(find.text('徒手深蹲'), findsNothing);
    await tester.tap(find.text('全部').first);
    await tester.tap(find.text('哑铃').first);
    await tester.pumpAndSettle();
    expect(find.text('单臂哑铃划船'), findsOneWidget);
    expect(find.text('哑铃肩推'), findsOneWidget);
    expect(find.text('上斜俯卧撑'), findsNothing);
    await tester.tap(find.text('固定支撑台').first);
    await tester.pumpAndSettle();
    expect(find.text('单臂哑铃划船'), findsOneWidget);
    expect(find.text('上斜俯卧撑'), findsOneWidget);
    expect(find.text('哑铃肩推'), findsNothing);
  });
}
