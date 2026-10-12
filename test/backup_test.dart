import 'dart:convert';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulse_fitness/core/app_state.dart';
import 'package:pulse_fitness/core/models.dart';

void main() {
  late AppState s;
  late MemoryPreferences p;
  setUp(() async {
    p = MemoryPreferences();
    s = AppState(p, now: () => DateTime(2026, 10, 3));
    await s.load();
  });
  Map<String, dynamic> snapshot() => jsonDecode(s.exportJson());
  test('checksum preview is read only', () async {
    await s.addWater(250);
    final before = s.exportJson();
    final raw = await s.exportBackup();
    expect(s.previewBackup(raw).payloadJson, before);
    expect(s.exportJson(), before);
    final j = jsonDecode(raw);
    j['payload']['waterTarget'] = 1500;
    expect(() => s.previewBackup(jsonEncode(j)), throwsFormatException);
  });
  test('roundtrip actual records and edited immutable food snapshot', () async {
    await s.completeSet(
      'squat',
      0,
      2,
      actualReps: 11,
      weightKg: 20,
      seconds: 35,
    );
    await s.saveRecovery(
      const RecoveryFeedback(sleepQuality: 2, soreness: 1, pain: false),
    );
    CustomFood food(double kcal) => CustomFood(
      id: 'mine',
      name: '酸奶',
      source: '标签',
      per100g: Nutrients(kcal, 5, 8, 2),
      allergens: ['乳制品'],
    );
    await s.saveCustomFood(food(80));
    await s.logFood('mine', 150, 0);
    await s.saveCustomFood(food(90));
    final raw = await s.exportBackup();
    final original = s.exportJson();
    await s.addWater(500);
    final prior = s.exportJson();
    await s.restoreBackup(s.previewBackup(raw));
    expect(s.exportJson(), original);
    expect(s.log.foodEntries.single.nutrients.kcal, 120);
    expect(s.customFoods['mine']!.per100g.kcal, 90);
    expect(s.hasPreviousBackup, isTrue);
    await s.restorePreviousBackup();
    expect(s.exportJson(), prior);
  });
  test('every required v6 field and future version rejected', () {
    expect(() => s.previewBackup('{'), throwsFormatException);
    for (final k in snapshot().keys) {
      if (k == 'version') continue;
      final j = snapshot()..remove(k);
      expect(
        () => s.previewBackup(jsonEncode(j)),
        throwsFormatException,
        reason: k,
      );
    }
    expect(
      () => s.previewBackup(jsonEncode(snapshot()..['version'] = 7)),
      throwsFormatException,
    );
  });
  test('invalid IDs dates duplicates numeric ranges and missing log fields rejected', () async {
    await s.completeSet('squat', 0, 2, actualReps: 10);
    final mutations = <void Function(Map<String, dynamic>)>[
      (j) => j['template']['items'][0]['id'] = 'unknown',
      (j) => j['favorites'] = ['squat', 'squat'],
      (j) => j['favorites'] = ['unknown'],
      (j) => j['template']['items'].add(j['template']['items'][0]),
      (j) => j['template']['days'] = [1, 1],
      (j) => j['template']['items'][0]['sets'] = 9,
      (j) => j['logs']['2026-02-30'] = j['logs'][s.today],
      (j) => j['logs'][s.today]['date'] = '2026-10-02',
      (j) => j['logs'][s.today]['water'] = -1,
      (j) => j['logs'][s.today]['fatigue'] = [4],
      (j) => j['logs'][s.today]['sets']['missing'] = [0],
      (j) => j['logs'][s.today]['sets']['squat'] = [0, 0],
      (j) => j['logs'][s.today]['setRecords']['squat']['0']['setIndex'] = 1,
      (j) => j['logs'][s.today]['setRecords']['squat']['0']['weightKg'] = 1001,
      (j) => j['logs'][s.today].remove('recovery'),
      (j) => j['logs'][s.today].remove('foodEntries'),
      (j) => j['mealPlans'][s.today] = [
        {'id': 'missing', 'factor': 1},
      ],
      (j) => j['nutritionTargets'][s.today]['protein'] = 0,
      (j) => j['calorieTarget'] = '1800',
      (j) => j['customFoods']['ghost'] = {},
    ];
    final before = s.exportJson();
    for (final change in mutations) {
      final j = snapshot();
      change(j);
      expect(() => s.previewBackup(jsonEncode(j)), throwsFormatException);
      expect(s.exportJson(), before);
    }
  });
  test('dangling customfood references rejected', () async {
    await s.saveCustomFood(
      CustomFood(
        id: 'f',
        name: '蛋',
        source: '包装',
        per100g: const Nutrients(100, 10, 1, 5),
      ),
    );
    await s.logFood('f', 100, 0);
    final bad = snapshot()..['customFoods'] = {};
    expect(() => s.previewBackup(jsonEncode(bad)), throwsFormatException);
  });
  test('complete legacy v1–5 retain meal snapshots', () async {
    await s.toggleMeal(0);
    for (var v = 1; v <= 5; v++) {
      final j = snapshot()..['version'] = v;
      if (v < 6) j.remove('bodyRecords');
      if (v < 5) {
        j.remove('customFoods');
        for (final l in j['logs'].values) {
          l.remove('foodEntries');
        }
      }
      if (v < 4) {
        for (final l in j['logs'].values) {
          l.remove('setRecords');
          l.remove('recovery');
        }
      }
      if (v < 3) {
        for (final k in [
          'proteinTarget',
          'carbsTarget',
          'fatTarget',
          'nutritionTargets',
        ]) {
          j.remove(k);
        }
      }
      if (v < 2) {
        for (final l in j['logs'].values) {
          l.remove('waterTarget');
        }
      }
      await s.restoreBackup(s.previewBackup(jsonEncode(j)));
      expect(s.log.meals[0]!.nutrients.kcal, 410);
    }
  });
  test('backup write failure preserves main and live state', () async {
    await s.addWater(250);
    final before = s.exportJson();
    final j = snapshot()..['waterTarget'] = 1500;
    p.rejectBackup = true;
    await expectLater(
      s.restoreBackup(s.previewBackup(jsonEncode(j))),
      throwsStateError,
    );
    expect(s.exportJson(), before);
    expect(p.values[AppState.storageKey], before);
  });
  test('false after write rolls back main and live state', () async {
    await s.addWater(250);
    final before = s.exportJson();
    final j = snapshot()..['waterTarget'] = 1500;
    p.failNextMainAfterWrite = true;
    await expectLater(
      s.restoreBackup(s.previewBackup(jsonEncode(j))),
      throwsStateError,
    );
    expect(s.exportJson(), before);
    expect(p.values[AppState.storageKey], before);
  });
  test(
    'failed clear preserves data and successful clear can restore',
    () async {
      await s.addWater(250);
      final before = s.exportJson();
      p.failNextMainAfterWrite = true;
      await expectLater(s.clearUserData(), throwsStateError);
      expect(s.exportJson(), before);
      expect(p.values[AppState.storageKey], before);
      await s.clearUserData();
      expect(s.logs, isEmpty);
      expect(s.customFoods, isEmpty);
      await s.restorePreviousBackup();
      expect(s.exportJson(), before);
    },
  );
  test(
    'delete local backup removes recovery copies without touching records',
    () async {
      await s.addWater(250);
      await s.clearUserData();
      final before = s.exportJson();
      p.values[AppState.unreadableBackupKey] = 'unreadable';
      await s.deleteLocalBackups();
      expect(s.hasPreviousBackup, isFalse);
      expect(p.values.containsKey(AppState.unreadableBackupKey), isFalse);
      expect(s.exportJson(), before);
    },
  );
  test(
    'concurrent edit during replacement aborts and preserves newer queued save',
    () async {
      await s.addWater(250);
      final imported = snapshot()..['waterTarget'] = 1500;
      final gate = Completer<void>();
      p.backupGate = gate.future;
      final restore = s.restoreBackup(s.previewBackup(jsonEncode(imported)));
      final failed = expectLater(restore, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      final edit = s.addWater(250);
      gate.complete();
      await failed;
      await edit;
      expect(s.log.waterMl, 500);
      expect(s.waterTarget, 2000);
      expect(
        jsonDecode(p.values[AppState.storageKey]!)['logs'][s.today]['water'],
        500,
      );
    },
  );
  test('duplicate JSON keys and nonfinite numeric payload rejected', () {
    final raw = s.exportJson();
    expect(
      () => s.previewBackup(
        raw.replaceFirst('"version":6', '"version":6,"version":6'),
      ),
      throwsFormatException,
    );
    expect(
      () => s.previewBackup(
        raw.replaceFirst('"calorieTarget":1800', '"calorieTarget":1e999'),
      ),
      throwsFormatException,
    );
  });
  test('unknown fields cannot be silently dropped on import', () {
    final bad = snapshot()..['futurePersonalData'] = {'weight': 75};
    expect(() => s.previewBackup(jsonEncode(bad)), throwsFormatException);
  });
  test('envelope date and version type must be valid', () async {
    final exported = jsonDecode(await s.exportBackup());
    exported['createdAt'] = '2026-02-30T00:00:00Z';
    expect(() => s.previewBackup(jsonEncode(exported)), throwsFormatException);
    exported['createdAt'] = '2026-10-03T00:00:00Z';
    exported['envelopeVersion'] = 1.0;
    expect(() => s.previewBackup(jsonEncode(exported)), throwsFormatException);
  });
  test('removed actions remain valid historical actual records', () async {
    await s.completeSet('squat', 0, 1, actualReps: 12, weightKg: 20);
    await s.savePlan(s.plan.copyWith(items: []));
    final before = s.exportJson();
    await s.restoreBackup(s.previewBackup(await s.exportBackup()));
    expect(s.exportJson(), before);
    expect(s.log.setRecords['squat']![0]!.actualReps, 12);
  });
  test('restore previous waits for already queued replacement', () async {
    await s.addWater(250);
    await s.clearUserData();
    await s.addWater(500);
    final clear = s.clearUserData();
    final restore = s.restorePreviousBackup();
    await clear;
    await restore;
    expect(s.log.waterMl, 500);
  });
  test(
    'valid import repairs corrupt storage and retains actual unreadable raw',
    () async {
      await s.addWater(750);
      final valid = await s.exportBackup();
      p.values[AppState.storageKey] = '{first corrupt payload';
      final broken = AppState(p, now: s.now);
      await broken.load();
      expect(broken.storageFailure, StorageFailure.load);
      const actualRaw = '{current corrupt payload';
      p.values[AppState.storageKey] = actualRaw;
      await broken.restoreBackup(broken.previewBackup(valid));
      expect(broken.log.waterMl, 750);
      expect(broken.storageError, isNull);
      expect(p.values[AppState.unreadableBackupKey], actualRaw);
      expect(broken.hasPreviousBackup, isFalse);
    },
  );
  test(
    'unreadable archive failure aborts explicit import without mutation',
    () async {
      await s.addWater(500);
      final valid = await s.exportBackup();
      const raw = '{corrupt main';
      p.values[AppState.storageKey] = raw;
      p.rejectUnreadableArchive = true;
      final broken = AppState(p, now: s.now);
      await broken.load();
      final before = broken.exportJson();
      await expectLater(
        broken.restoreBackup(broken.previewBackup(valid)),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('归档'),
          ),
        ),
      );
      expect(p.values[AppState.storageKey], raw);
      expect(p.values[AppState.unreadableBackupKey], isNull);
      expect(broken.exportJson(), before);
      expect(broken.hasPreviousBackup, isFalse);
    },
  );
  test(
    'replacement failure rolls back corrupt main and retains archive',
    () async {
      await s.addWater(500);
      final valid = await s.exportBackup();
      const raw = '{original corrupt main';
      p.values[AppState.storageKey] = raw;
      final broken = AppState(p, now: s.now);
      await broken.load();
      final before = broken.exportJson();
      p.failNextMainAfterWrite = true;
      await expectLater(
        broken.restoreBackup(broken.previewBackup(valid)),
        throwsStateError,
      );
      expect(
        p.failNextMainAfterWrite,
        isFalse,
        reason: 'Replacement was attempted only after archive verification',
      );
      expect(p.values[AppState.storageKey], raw);
      expect(p.values[AppState.unreadableBackupKey], raw);
      expect(broken.exportJson(), before);
      expect(broken.storageFailure, StorageFailure.load);
    },
  );
  test('valid previous backup repairs corrupt main without replacing it with defaults', () async {
    await s.addWater(500);
    final previous = await s.exportBackup();
    p.values[AppState.previousBackupKey] = previous;
    const raw = '{unreadable';
    p.values[AppState.storageKey] = raw;
    final broken = AppState(p, now: s.now);
    await broken.load();
    await broken.restorePreviousBackup();
    expect(broken.log.waterMl, 500);
    expect(p.values[AppState.previousBackupKey], previous);
    expect(p.values[AppState.unreadableBackupKey], raw);
  });
  test('deliberate clear archives corrupt raw and preserves an existing usable backup', () async {
    await s.addWater(500);
    final previous = await s.exportBackup();
    p.values[AppState.previousBackupKey] = previous;
    const raw = '{unreadable';
    p.values[AppState.storageKey] = raw;
    final broken = AppState(p, now: s.now);
    await broken.load();
    await broken.clearUserData();
    expect(broken.logs, isEmpty);
    expect(broken.storageError, isNull);
    expect(p.values[AppState.previousBackupKey], previous);
    expect(p.values[AppState.unreadableBackupKey], raw);
    await broken.restorePreviousBackup();
    expect(broken.log.waterMl, 500);
  });
  test('export flushes queued saves', () async {
    final save = s.addWater(250);
    final raw = await s.exportBackup();
    await save;
    expect(s.previewBackup(raw).payloadJson, s.exportJson());
    expect(p.values[AppState.storageKey], s.exportJson());
  });
}

class MemoryPreferences implements SharedPreferences {
  Future<void>? backupGate;
  final values = <String, String>{};
  bool rejectBackup = false,
      failNextMainAfterWrite = false,
      rejectUnreadableArchive = false;
  @override
  String? getString(String key) => values[key];
  @override
  Future<bool> setString(String key, String value) async {
    if (key == AppState.previousBackupKey && backupGate != null) {
      await backupGate;
    }
    if (rejectBackup && key == AppState.previousBackupKey) return false;
    if (rejectUnreadableArchive && key == AppState.unreadableBackupKey) {
      return false;
    }
    values[key] = value;
    if (key == AppState.storageKey && failNextMainAfterWrite) {
      failNextMainAfterWrite = false;
      return false;
    }
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    values.remove(key);
    return true;
  }

  @override
  Future<void> reload() async {}
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
