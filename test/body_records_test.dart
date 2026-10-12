import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulse_fitness/core/app_state.dart';
import 'package:pulse_fitness/core/body_metrics.dart';
import 'package:pulse_fitness/core/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    state = AppState(
      await SharedPreferences.getInstance(),
      now: () => DateTime(2026, 10, 3),
    );
  });
  test('snapshot version includes independent body measurements', () {
    final snapshot = jsonDecode(state.exportJson());
    expect(snapshot['version'], 6);
    expect(snapshot['bodyRecords'], isEmpty);
  });
  test('invalid body records reject atomically including invalid date and nonfinite', () async {
    final before = state.exportJson();
    for (final record in [
      const BodyRecord('2026-02-30', weightKg: 70),
      const BodyRecord('2026-10-04', weightKg: 70),
      const BodyRecord('2026-10-03'),
      const BodyRecord('2026-10-03', weightKg: double.nan),
      const BodyRecord('2026-10-03', weightKg: double.infinity),
      const BodyRecord('2026-10-03', weightKg: 19),
      const BodyRecord('2026-10-03', weightKg: 351),
      const BodyRecord('2026-10-03', waistCm: 29),
      const BodyRecord('2026-10-03', waistCm: 251),
      BodyRecord('2026-10-03', weightKg: 70, note: 'x' * 201),
    ]) {
      await expectLater(state.saveBodyRecord(record), throwsArgumentError);
      expect(state.exportJson(), before);
    }
    await expectLater(
      state.removeBodyRecord('2026-10-04'),
      throwsArgumentError,
    );
    await expectLater(state.removeBodyRecord('bad'), throwsArgumentError);
    expect(state.exportJson(), before);
  });
  test(
    'same day update persists a single partial body snapshot then removes it',
    () async {
      await state.saveBodyRecord(
        const BodyRecord(
          '2026-10-03',
          weightKg: 125.5,
          waistCm: 110,
          note: '晨起',
        ),
      );
      await state.saveBodyRecord(
        const BodyRecord('2026-10-03', waistCm: 108.5),
      );
      final restored = AppState(state.preferences, now: state.now);
      await restored.load();
      expect(restored.bodyRecords.length, 1);
      expect(restored.bodyRecords[state.today]!.weightKg, isNull);
      expect(restored.bodyRecords[state.today]!.waistCm, 108.5);
      expect(restored.logs, isEmpty);
      await restored.removeBodyRecord(state.today);
      expect(restored.bodyRecords, isEmpty);
    },
  );
  test('legacy local snapshots without body field still load', () async {
    await state.addWater(250);
    for (var version = 1; version <= 5; version++) {
      final j = jsonDecode(state.exportJson()) as Map<String, dynamic>;
      j['version'] = version;
      j.remove('bodyRecords');
      await state.preferences.setString(AppState.storageKey, jsonEncode(j));
      final restored = AppState(state.preferences, now: state.now);
      await restored.load();
      expect(restored.storageError, isNull);
      expect(restored.log.waterMl, 250);
      expect(restored.bodyRecords, isEmpty);
    }
  });
  test(
    'malformed late body payload preserves the full loaded snapshot',
    () async {
      await state.saveBodyRecord(const BodyRecord('2026-10-02', weightKg: 120));
      await state.addWater(250);
      final before = state.exportJson();
      final j = jsonDecode(before);
      j['template']['title'] = '不得载入';
      j['bodyRecords']['2026-10-02']['weightKg'] = 'invalid';
      await state.preferences.setString(AppState.storageKey, jsonEncode(j));
      await state.load();
      expect(state.exportJson(), before);
      expect(state.storageFailure, StorageFailure.load);
      expect(
        state.preferences.getString(AppState.unreadableBackupKey),
        jsonEncode(j),
      );
    },
  );
  test('v6 local snapshot missing body collection cannot overwrite any current fields', () async {
    await state.saveBodyRecord(const BodyRecord('2026-10-02', weightKg: 120));
    await state.addWater(250);
    final before = state.exportJson();
    final j = jsonDecode(before);
    j.remove('bodyRecords');
    j['template']['title'] = '不得载入';
    j['waterTarget'] = 1500;
    final corrupt = jsonEncode(j);
    await state.preferences.setString(AppState.storageKey, corrupt);
    await state.load();
    expect(state.exportJson(), before);
    expect(state.storageFailure, StorageFailure.load);
    expect(state.preferences.getString(AppState.storageKey), corrupt);
    expect(state.preferences.getString(AppState.unreadableBackupKey), corrupt);
  });

  test(
    'explicit null body field is corrupt and never clears current body records',
    () async {
      await state.saveBodyRecord(const BodyRecord('2026-10-02', weightKg: 120));
      final before = state.exportJson();
      final j = jsonDecode(before);
      j['bodyRecords'] = null;
      await state.preferences.setString(AppState.storageKey, jsonEncode(j));
      await state.load();
      expect(state.exportJson(), before);
      expect(state.storageFailure, StorageFailure.load);
    },
  );

  test(
    'v6 backup validates body structure and union dates without mutating',
    () async {
      await state.saveBodyRecord(const BodyRecord('2026-10-01', weightKg: 120));
      await state.addWater(250);
      final raw = state.exportJson();
      final preview = state.previewBackup(raw);
      expect(preview.bodyCount, 1);
      expect(preview.dates, ['2026-10-01', '2026-10-03']);
      expect(() => preview.dates.add('x'), throwsUnsupportedError);
      for (final change in <void Function(dynamic)>[
        (j) => j.remove('bodyRecords'),
        (j) => j['bodyRecords']['2026-10-01']['date'] = '2026-10-02',
        (j) => j['bodyRecords']['2026-10-01']['weightKg'] = 500,
        (j) => j['bodyRecords']['2026-10-01']['unknown'] = 1,
        (j) => j['bodyRecords']['2026-10-01'].remove('note'),
      ]) {
        final j = jsonDecode(raw);
        change(j);
        expect(() => state.previewBackup(jsonEncode(j)), throwsFormatException);
        expect(state.exportJson(), raw);
      }
    },
  );
  test(
    'body records survive backup restore, clear and previous snapshot recovery',
    () async {
      await state.saveBodyRecord(const BodyRecord('2026-10-02', weightKg: 130));
      final before = state.exportJson();
      final backup = await state.exportBackup();
      await state.clearUserData();
      expect(state.bodyRecords, isEmpty);
      await state.restorePreviousBackup();
      expect(state.exportJson(), before);
      await state.removeBodyRecord('2026-10-02');
      await state.restoreBackup(state.previewBackup(backup));
      expect(state.exportJson(), before);
    },
  );
  test(
    'program save changes only its requested date and rejects completed today',
    () async {
      await state.toggleMeal(0);
      await state.addWater(250);
      final before = jsonDecode(state.exportJson()) as Map<String, dynamic>;
      final program = TrainingPlan(
        title: '试用计划',
        items: [const PlanItem('curl', sets: 2)],
      );
      await state.saveProgramPlan(program, date: state.tomorrow);
      final after = jsonDecode(state.exportJson()) as Map<String, dynamic>;
      after['plans'].remove(state.tomorrow);
      expect(after, before);
      await state.saveProgramPlan(program, date: state.today);
      expect(state.plans[state.today]!.title, '试用计划');
      state.logs[state.today]!.completedSets['squat'] = {
        0,
      }; // Any completed set, even outside the current plan.
      final protected = state.exportJson();
      await expectLater(
        state.saveProgramPlan(program, date: state.today),
        throwsStateError,
      );
      expect(state.exportJson(), protected);
    },
  );
  test('program validation rejects invalid dates IDs duplicates and ranges atomically', () async {
    final before = state.exportJson();
    final good = TrainingPlan(items: [const PlanItem('squat')]);
    for (final date in ['2026-10-02', '2026-02-30']) {
      await expectLater(
        state.saveProgramPlan(good, date: date),
        throwsArgumentError,
      );
    }
    for (final plan in [
      TrainingPlan(items: [const PlanItem('unknown')]),
      TrainingPlan(items: [const PlanItem('squat'), const PlanItem('squat')]),
      TrainingPlan(items: [const PlanItem('squat', sets: 9)]),
      TrainingPlan(items: [const PlanItem('squat', reps: 0)]),
      TrainingPlan(items: [const PlanItem('squat', rest: 301)]),
      TrainingPlan(minutes: 9, items: []),
      TrainingPlan(days: [1, 1], items: []),
    ]) {
      await expectLater(
        state.saveProgramPlan(plan, date: state.today),
        throwsArgumentError,
      );
    }
    expect(state.exportJson(), before);
  });
}
