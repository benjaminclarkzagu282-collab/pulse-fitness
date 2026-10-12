import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'catalog.dart';
import 'food_log.dart';
import 'backup.dart';
import 'body_metrics.dart';

enum StorageFailure { load, save }

class AppState extends ChangeNotifier {
  final SharedPreferences preferences;
  final DateTime Function() now;
  static const storageKey = 'pulse_fitness_v1';
  static const previousBackupKey = 'pulse_fitness_previous_backup_v1';
  static const unreadableBackupKey = 'pulse_fitness_v1_unreadable_backup';
  AppState(this.preferences, {DateTime Function()? now})
    : now = now ?? DateTime.now;
  TrainingPlan template = defaultPlan();
  final Map<String, TrainingPlan> plans = {};
  final Map<String, DailyLog> logs = {};
  final Map<String, BodyRecord> bodyRecords = {};
  final Map<String, List<MealPortion>> mealPlans = {};
  final Set<String> favorites = {};
  final Map<String, CustomFood> customFoods = {};
  int _foodSequence = 0;
  bool foodAllowed(CustomFood food) =>
      (diet != '素食优先' || food.vegetarian) &&
      !food.allergens.any(allergens.contains);
  List<CustomFood> get availableFoods =>
      customFoods.values.where(foodAllowed).toList();
  final Set<String> allergens = {};
  String diet = '均衡饮食';
  int calorieTarget = 1800, waterTarget = 2000;
  int proteinTarget = 120, carbsTarget = 195, fatTarget = 60;
  final Map<String, NutritionTargets> nutritionTargets = {};
  NutritionTargets get defaultNutritionTargets => NutritionTargets(
    calories: calorieTarget,
    protein: proteinTarget,
    carbs: carbsTarget,
    fat: fatTarget,
    water: waterTarget,
  );
  NutritionTargets targetsForDate(String date) => nutritionTargets.putIfAbsent(
    date,
    () => defaultNutritionTargets.copyWith(water: logs[date]?.waterTarget),
  );
  DailyLog logForDate(String date) => logs.putIfAbsent(
    date,
    () => DailyLog(date, waterTarget: targetsForDate(date).water),
  );
  List<MealPortion> mealsForDate(String date) {
    targetsForDate(date);
    return mealPlans.putIfAbsent(date, _allowedMeals);
  }

  Nutrients nutritionForDate(String date) {
    final entry = logs[date];
    if (entry == null) return Nutrients.zero;
    return entry.meals.values.fold<Nutrients>(
          Nutrients.zero,
          (n, m) => n + m.nutrients,
        ) +
        entry.foodEntries.fold<Nutrients>(
          Nutrients.zero,
          (n, e) => n + e.nutrients,
        );
  }

  Nutrients plannedNutritionForDate(String date) => mealsForDate(date).fold(
    Nutrients.zero,
    (n, m) => n + mealById(m.mealId).nutrients.scale(m.factor),
  );
  bool canRecordDate(String date) =>
      validDayKey(date) && date.compareTo(today) <= 0;
  String? storageError;
  StorageFailure? storageFailure;
  bool _loadFailed = false;
  String? _unreadableRaw;
  Future<void> _writes = Future.value();
  int _editRevision = 0;
  String get today => dayKey(now());
  String get tomorrow =>
      dayKey(DateTime(now().year, now().month, now().day + 1));
  TrainingPlan get plan => plans.putIfAbsent(today, () => template.copyWith());
  DailyLog get log => logForDate(today);
  List<MealPortion> get meals => mealsForDate(today);
  List<MealPortion> _allowedMeals() =>
      List.generate(4, (slot) => MealPortion(availableMeals(slot).first.id));
  List<MealChoice> availableMeals(int slot) => mealChoices
      .where(
        (m) =>
            m.slot == slot &&
            (diet != '素食优先' || m.vegetarian) &&
            !m.allergens.any(allergens.contains),
      )
      .toList();
  bool get tomorrowTrainingAdopted => plans.containsKey(tomorrow);
  bool get tomorrowMealsAdopted => mealPlans.containsKey(tomorrow);
  bool get tomorrowAdopted => tomorrowTrainingAdopted && tomorrowMealsAdopted;
  List<DailyLog> get history {
    final result = logs.values
        .where((l) => l.date.compareTo(today) <= 0)
        .toList();
    result.sort((a, b) => a.date.compareTo(b.date));
    return result;
  }

  List<DailyLog> recent(int days) {
    final start = dayKey(
      DateTime(now().year, now().month, now().day - days + 1),
    );
    return history.where((l) => l.date.compareTo(start) >= 0).toList();
  }

  int completedSetsFor(String id) {
    final item = plan.items.where((i) => i.exerciseId == id).firstOrNull;
    return item == null
        ? 0
        : (log.completedSets[id] ?? {}).where((v) => v < item.sets).length;
  }

  int get completedExercises =>
      plan.items.where((i) => completedSetsFor(i.exerciseId) >= i.sets).length;
  CompletionScore scoreFor(DailyLog entry) {
    final p = plans[entry.date];
    final total = p?.totalSets ?? 0;
    final done =
        p?.items.fold<int>(
          0,
          (n, item) =>
              n +
              (entry.completedSets[item.exerciseId] ?? {})
                  .where((v) => v >= 0 && v < item.sets)
                  .length,
        ) ??
        0;
    return CompletionScore(
      CompletionScore.percent(done, total),
      CompletionScore.percent(entry.mealCount, 4),
      CompletionScore.percent(entry.waterMl, entry.waterTarget),
    );
  }

  CompletionScore get score {
    plan;
    return scoreFor(log);
  }

  Nutrients get nutrition => nutritionForDate(today);
  Nutrients get plannedNutrition => plannedNutritionForDate(today);

  Future<bool> _backupUnreadablePayload() async {
    final raw = _unreadableRaw;
    if (raw == null) return false;
    try {
      if (preferences.getString(unreadableBackupKey) != raw) {
        if (!await preferences.setString(unreadableBackupKey, raw)) {
          return false;
        }
      }
      await preferences.reload();
      return preferences.getString(unreadableBackupKey) == raw;
    } catch (_) {
      return false;
    }
  }

  Future<void> load() async {
    String? raw;
    try {
      raw = preferences.getString(storageKey);
      if (raw == null) {
        _loadFailed = false;
        _unreadableRaw = null;
        storageError = null;
        storageFailure = null;
        notifyListeners();
        return;
      }
      final j = jsonDecode(raw) as Map<String, dynamic>;
      // Parse every field before committing any part of the loaded snapshot.
      final newWaterTarget = (j['waterTarget'] as int? ?? 2000).clamp(
        500,
        4000,
      );
      final newCalorieTarget = (j['calorieTarget'] as int? ?? 1800).clamp(
        1000,
        4000,
      );
      final newDiet = j['diet'] as String? ?? '均衡饮食';
      final newFavorites = List<String>.from(j['favorites'] ?? []);
      final newAllergens = List<String>.from(j['allergens'] ?? []);
      final newTemplate = TrainingPlan.fromJson(
        Map<String, dynamic>.from(j['template']),
      );
      final newPlans = (j['plans'] as Map).map(
        (k, v) => MapEntry(
          k as String,
          TrainingPlan.fromJson(Map<String, dynamic>.from(v)),
        ),
      );
      final newLogs = (j['logs'] as Map).map(
        (k, v) => MapEntry(
          k as String,
          DailyLog.fromJson(
            Map<String, dynamic>.from(v),
            defaultWaterTarget: newWaterTarget,
          ),
        ),
      );
      final newMeals = (j['mealPlans'] as Map).map(
        (k, v) => MapEntry(
          k as String,
          (v as List)
              .map((m) => MealPortion.fromJson(Map<String, dynamic>.from(m)))
              .toList(),
        ),
      );
      final newDefaults = NutritionTargets.fromJson({
        'calories': newCalorieTarget,
        'water': newWaterTarget,
        'protein': j['proteinTarget'],
        'carbs': j['carbsTarget'],
        'fat': j['fatTarget'],
      });
      final newTargets = (j['nutritionTargets'] as Map? ?? {}).map(
        (k, v) => MapEntry(
          k as String,
          NutritionTargets.fromJson(
            Map<String, dynamic>.from(v),
            defaults: newDefaults,
          ),
        ),
      );
      final newFoods = (j['customFoods'] as Map? ?? {}).map(
        (k, v) => MapEntry(
          k as String,
          CustomFood.fromJson(Map<String, dynamic>.from(v)),
        ),
      );
      for (final entry in newFoods.entries) {
        if (entry.key != entry.value.id) {
          throw const FormatException('Food ID mismatch');
        }
      }
      for (final entry in newLogs.entries) {
        final ids = <String>{};
        for (final food in entry.value.foodEntries) {
          if (food.date != entry.key || !ids.add(food.id)) {
            throw const FormatException('Food date or ID mismatch');
          }
        }
      }
      final newBodyRecords = _parseBodyRecords(j);
      // Legacy dates capture saved defaults once; recorded water keeps its
      // historical denominator independently of later preference changes.
      for (final date in {...newLogs.keys, ...newMeals.keys}) {
        newTargets.putIfAbsent(
          date,
          () => newDefaults.copyWith(water: newLogs[date]?.waterTarget),
        );
      }
      bodyRecords
        ..clear()
        ..addAll(newBodyRecords);
      customFoods
        ..clear()
        ..addAll(newFoods);
      nutritionTargets
        ..clear()
        ..addAll(newTargets);
      proteinTarget = newDefaults.protein;
      carbsTarget = newDefaults.carbs;
      fatTarget = newDefaults.fat;
      template = newTemplate;
      plans
        ..clear()
        ..addAll(newPlans);
      logs
        ..clear()
        ..addAll(newLogs);
      mealPlans
        ..clear()
        ..addAll(newMeals);
      favorites
        ..clear()
        ..addAll(newFavorites);
      allergens
        ..clear()
        ..addAll(newAllergens);
      diet = newDiet;
      calorieTarget = newCalorieTarget;
      waterTarget = newWaterTarget;
      _loadFailed = false;
      _unreadableRaw = null;
      storageError = null;
      storageFailure = null;
    } catch (_) {
      _loadFailed = true;
      _unreadableRaw = raw;
      final backedUp = await _backupUnreadablePayload();
      storageFailure = StorageFailure.load;
      storageError = backedUp
          ? '本地记录读取失败，原始数据已自动备份。重试将重新读取原始记录。'
          : '本地记录读取失败，原始数据仍保留；备份未确认，暂不覆盖存储。重试将重新读取。';
    }
    notifyListeners();
  }

  String exportJson() => jsonEncode({
    'version': 6,
    'bodyRecords': bodyRecords.map((k, v) => MapEntry(k, v.toJson())),
    'customFoods': customFoods.map((k, v) => MapEntry(k, v.toJson())),
    'template': template.toJson(),
    'plans': plans.map((k, v) => MapEntry(k, v.toJson())),
    'logs': logs.map((k, v) => MapEntry(k, v.toJson())),
    'mealPlans': mealPlans.map(
      (k, v) => MapEntry(k, v.map((m) => m.toJson()).toList()),
    ),
    'favorites': favorites.toList(),
    'allergens': allergens.toList(),
    'diet': diet,
    'calorieTarget': calorieTarget,
    'waterTarget': waterTarget,
    'proteinTarget': proteinTarget,
    'carbsTarget': carbsTarget,
    'fatTarget': fatTarget,
    'nutritionTargets': nutritionTargets.map((k, v) => MapEntry(k, v.toJson())),
  });
  Future<void> _save() {
    _editRevision++;
    final data = exportJson();
    notifyListeners();
    _writes = _writes.then((_) async {
      // User edits may replace unreadable data only after its raw payload is
      // separately saved and read back. A retry button never takes this path.
      if (_loadFailed && !await _backupUnreadablePayload()) {
        storageFailure = StorageFailure.load;
        storageError = '本地记录读取失败，原始数据备份未确认，当前修改未覆盖存储。请重试读取。';
        notifyListeners();
        return;
      }
      try {
        final ok = await preferences.setString(storageKey, data);
        if (!ok) {
          throw StateError('storage rejected');
        }
        _loadFailed = false;
        _unreadableRaw = null;
        storageFailure = null;
        if (storageError != null) {
          storageError = null;
          notifyListeners();
        }
      } catch (_) {
        storageFailure = StorageFailure.save;
        storageError = '保存失败，请保留此页面并重试，当前修改尚未可靠保存。';
        notifyListeners();
      }
    });
    return _writes;
  }

  bool get hasPreviousBackup =>
      preferences.getString(previousBackupKey) != null;
  BackupPreview previewBackup(String raw) =>
      BackupPreview.parse(raw, today: today);
  Future<void> _flushWrites() async {
    Future<void> pending;
    do {
      pending = _writes;
      await pending;
    } while (!identical(pending, _writes));
  }

  Future<String> exportBackup() async {
    await _flushWrites();
    return BackupEnvelope.encode(exportJson(), now());
  }

  Future<void> restoreBackup(BackupPreview preview) {
    final checked = previewBackup(preview.payloadJson);
    return _replaceUserData(checked.payloadJson);
  }

  Future<void> restorePreviousBackup() async {
    await _flushWrites();
    final raw = preferences.getString(previousBackupKey);
    if (raw == null) return Future.error(StateError('没有可恢复的本地备份。'));
    return restoreBackup(previewBackup(raw));
  }

  Future<void> deleteLocalBackups() {
    final operation = _writes.then((_) async {
      for (final key in [previousBackupKey, unreadableBackupKey]) {
        if (preferences.getString(key) != null &&
            !await preferences.remove(key)) {
          throw StateError('本地备份删除失败，请重试。');
        }
      }
      await preferences.reload();
      if ([
        previousBackupKey,
        unreadableBackupKey,
      ].any((key) => preferences.getString(key) != null)) {
        throw StateError('本地备份删除未确认，请重试。');
      }
      notifyListeners();
    });
    _writes = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> clearUserData() =>
      _replaceUserData(AppState(preferences, now: now).exportJson());
  Future<void> _replaceUserData(String replacement) {
    final operation = _writes.then((_) async {
      final revision = _editRevision;
      final priorStored = preferences.getString(storageKey);
      if (_loadFailed) {
        // Explicit recovery can replace unreadable storage only after its real
        // raw payload is archived and read back. The default/live placeholder
        // must never overwrite a previously usable recovery backup.
        _unreadableRaw = priorStored ?? _unreadableRaw;
        if (_unreadableRaw != null && !await _backupUnreadablePayload()) {
          throw StateError('原始损坏数据归档未确认，记录未替换。');
        }
      } else {
        final backup = BackupEnvelope.encode(exportJson(), now());
        previewBackup(backup);
        try {
          if (!await preferences.setString(previousBackupKey, backup)) {
            throw StateError('backup rejected');
          }
          await preferences.reload();
          if (preferences.getString(previousBackupKey) != backup) {
            throw StateError('backup verification failed');
          }
          previewBackup(preferences.getString(previousBackupKey)!);
        } catch (_) {
          throw StateError('替换前备份未可靠保存，记录未替换。');
        }
      }
      if (_editRevision != revision) {
        throw StateError('备份期间记录发生变化，请重新预览后再试。');
      }
      try {
        if (!await preferences.setString(storageKey, replacement)) {
          throw StateError('replacement rejected');
        }
        await preferences.reload();
        if (preferences.getString(storageKey) != replacement ||
            _editRevision != revision) {
          throw StateError('replacement verification failed');
        }
        _applyBackupSnapshot(jsonDecode(replacement) as Map<String, dynamic>);
        storageFailure = null;
        storageError = null;
        notifyListeners();
      } catch (_) {
        try {
          final ok = priorStored == null
              ? await preferences.remove(storageKey)
              : await preferences.setString(storageKey, priorStored);
          await preferences.reload();
          if (!ok || preferences.getString(storageKey) != priorStored) {
            throw StateError('rollback rejected');
          }
        } catch (_) {
          storageFailure = StorageFailure.save;
          storageError = '替换失败且原存储恢复未确认。替换前数据已另行保留，请重试读取或使用有效备份恢复。';
          notifyListeners();
          throw StateError(storageError!);
        }
        throw StateError('替换失败，已恢复原存储，当前记录未替换。');
      }
    });
    _writes = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  void _applyBackupSnapshot(Map<String, dynamic> j) {
    final defaults = NutritionTargets(
      calories: j['calorieTarget'],
      water: j['waterTarget'],
      protein: j['proteinTarget'] ?? 120,
      carbs: j['carbsTarget'] ?? 195,
      fat: j['fatTarget'] ?? 60,
    );
    final newTemplate = TrainingPlan.fromJson(
      Map<String, dynamic>.from(j['template']),
    );
    final newPlans = (j['plans'] as Map).map(
      (k, v) => MapEntry(
        k as String,
        TrainingPlan.fromJson(Map<String, dynamic>.from(v)),
      ),
    );
    final newLogs = (j['logs'] as Map).map(
      (k, v) => MapEntry(
        k as String,
        DailyLog.fromJson(
          Map<String, dynamic>.from(v),
          defaultWaterTarget: defaults.water,
        ),
      ),
    );
    final newMeals = (j['mealPlans'] as Map).map(
      (k, v) => MapEntry(
        k as String,
        (v as List)
            .map((m) => MealPortion.fromJson(Map<String, dynamic>.from(m)))
            .toList(),
      ),
    );
    final newTargets = (j['nutritionTargets'] as Map? ?? {}).map(
      (k, v) => MapEntry(
        k as String,
        NutritionTargets.fromJson(
          Map<String, dynamic>.from(v),
          defaults: defaults,
        ),
      ),
    );
    final newFoods = (j['customFoods'] as Map? ?? {}).map(
      (k, v) => MapEntry(
        k as String,
        CustomFood.fromJson(Map<String, dynamic>.from(v)),
      ),
    );
    for (final date in {...newLogs.keys, ...newMeals.keys}) {
      newTargets.putIfAbsent(
        date,
        () => defaults.copyWith(water: newLogs[date]?.waterTarget),
      );
    }
    final newBodyRecords = _parseBodyRecords(j);
    bodyRecords
      ..clear()
      ..addAll(newBodyRecords);
    template = newTemplate;
    plans
      ..clear()
      ..addAll(newPlans);
    logs
      ..clear()
      ..addAll(newLogs);
    mealPlans
      ..clear()
      ..addAll(newMeals);
    nutritionTargets
      ..clear()
      ..addAll(newTargets);
    customFoods
      ..clear()
      ..addAll(newFoods);
    favorites
      ..clear()
      ..addAll(List<String>.from(j['favorites']));
    allergens
      ..clear()
      ..addAll(List<String>.from(j['allergens']));
    diet = j['diet'];
    calorieTarget = defaults.calories;
    waterTarget = defaults.water;
    proteinTarget = defaults.protein;
    carbsTarget = defaults.carbs;
    fatTarget = defaults.fat;
    _foodSequence = 0;
    _loadFailed = false;
    _unreadableRaw = null;
  }

  Map<String, BodyRecord> _parseBodyRecords(Map<String, dynamic> j) {
    if ((j['version'] as int? ?? 1) >= 6 && !j.containsKey('bodyRecords')) {
      throw const FormatException('第 6 版记录缺少身体记录。');
    }
    final raw = j.containsKey('bodyRecords')
        ? j['bodyRecords']
        : <String, dynamic>{};
    if (raw is! Map) throw const FormatException('身体记录必须为对象。');
    final result = raw.map(
      (k, v) => MapEntry(
        k as String,
        BodyRecord.fromJson(Map<String, dynamic>.from(v), today: today),
      ),
    );
    for (final entry in result.entries) {
      if (entry.key != entry.value.date) {
        throw const FormatException('身体记录日期键不一致。');
      }
    }
    return result;
  }

  Future<void> saveBodyRecord(BodyRecord record) async {
    record.validate(today: today);
    bodyRecords[record.date] = record;
    await _save();
  }

  Future<void> removeBodyRecord(String date) async {
    if (!canRecordDate(date)) throw ArgumentError('身体记录日期无效。');
    if (bodyRecords.remove(date) != null) await _save();
  }

  Future<void> saveProgramPlan(
    TrainingPlan value, {
    required String date,
  }) async {
    if (!validDayKey(date) || date.compareTo(today) < 0) {
      throw ArgumentError('训练方案只能用于今天或未来的有效日期。');
    }
    if (date == today &&
        (logs[today]?.completedSets.values.any((s) => s.isNotEmpty) ?? false)) {
      throw StateError('今天已有完成组记录，请将训练方案用于明天。');
    }
    final ids = exercises.map((e) => e.id).toSet();
    final seen = <String>{};
    if (value.minutes < 10 ||
        value.minutes > 90 ||
        value.days.any((d) => d < 1 || d > 7) ||
        value.days.toSet().length != value.days.length ||
        [value.title, value.goal, value.equipment].any((s) => s.length > 500)) {
      throw ArgumentError('训练方案时长、训练日或文本无效。');
    }
    for (final item in value.items) {
      if (!ids.contains(item.exerciseId) ||
          !seen.add(item.exerciseId) ||
          item.sets < 1 ||
          item.sets > 8 ||
          item.reps < 1 ||
          item.reps > 120 ||
          item.rest < 0 ||
          item.rest > 300) {
        throw ArgumentError('训练方案包含未知、重复动作或无效组数、次数、休息。');
      }
    }
    plans[date] = value.copyWith();
    await _save();
  }

  Future<void> retrySave() => _loadFailed ? load() : _save();
  Future<void> savePlan(TrainingPlan value) {
    plans[today] = value.copyWith();
    template = value.copyWith();
    return _save();
  }

  Future<void> addExercise(String id) async {
    if (plan.items.any((i) => i.exerciseId == id)) return;
    final e = exerciseById(id);
    await savePlan(
      plan.copyWith(
        items: [
          ...plan.items,
          PlanItem(id, reps: e.timed ? 30 : 12),
        ],
      ),
    );
  }

  Future<void> toggleFavorite(String id) {
    favorites.contains(id) ? favorites.remove(id) : favorites.add(id);
    return _save();
  }

  Future<void> completeSet(
    String id,
    int setIndex,
    int fatigue, {
    int seconds = 0,
    int? actualReps,
    int? actualSeconds,
    double? weightKg,
  }) async {
    final item = plan.items.where((i) => i.exerciseId == id).firstOrNull;
    if (item == null || setIndex < 0 || setIndex >= item.sets) return;
    final timed = exerciseById(id).timed;
    // Invalid input must never create or replace a completed set.
    if (fatigue < 1 ||
        fatigue > 3 ||
        seconds < 0 ||
        seconds > 7200 ||
        (actualReps != null &&
            (timed || actualReps < 1 || actualReps > 1000)) ||
        (actualSeconds != null &&
            (!timed || actualSeconds < 1 || actualSeconds > 7200)) ||
        (weightKg != null &&
            (!weightKg.isFinite || weightKg < 0 || weightKg > 1000))) {
      return;
    }
    final sets = log.completedSets.putIfAbsent(id, () => {});
    if (!sets.add(setIndex)) return;
    log.setRecords.putIfAbsent(id, () => {})[setIndex] = SetRecord(
      setIndex: setIndex,
      fatigue: fatigue.clamp(1, 3),
      elapsedSeconds: seconds.clamp(0, 7200),
      target: item.reps,
      timed: timed,
      actualReps: actualReps,
      actualSeconds: actualSeconds,
      weightKg: weightKg,
    );
    log.fatigue.add(fatigue.clamp(1, 3));
    log.trainingSeconds += seconds.clamp(0, 7200);
    await _save();
  }

  Future<void> saveRecovery(RecoveryFeedback value, {String? date}) {
    final selected = date ?? today;
    if (!canRecordDate(selected) || !value.isValid) return Future.value();
    logForDate(selected).recovery = value;
    return _save();
  }

  Future<void> addWater(int ml, {String? date}) {
    final selected = date ?? today;
    if (!canRecordDate(selected)) return Future.value();
    final entry = logForDate(selected);
    entry.waterMl = (entry.waterMl + ml).clamp(0, 6000);
    return _save();
  }

  Future<bool> saveCustomFood(CustomFood food) async {
    if (!food.isValid) return false;
    customFoods[food.id] = food;
    await _save();
    return true;
  }

  Future<bool> logFood(
    String foodId,
    double grams,
    int slot, {
    String? date,
  }) async {
    final selected = date ?? today;
    final food = customFoods[foodId];
    if (!canRecordDate(selected) ||
        slot < 0 ||
        slot >= 4 ||
        !grams.isFinite ||
        grams <= 0 ||
        grams > 10000 ||
        food == null ||
        !foodAllowed(food)) {
      return false;
    }
    String id;
    do {
      id = 'food-${now().microsecondsSinceEpoch}-${_foodSequence++}';
    } while (logs.values.any((l) => l.foodEntries.any((e) => e.id == id)));
    logForDate(selected).foodEntries.add(
      FoodEntry(
        id: id,
        date: selected,
        slot: slot,
        grams: grams,
        food: food,
        nutrients: food.per100g.scale(grams / 100),
      ),
    );
    await _save();
    return true;
  }

  Future<bool> removeFoodEntry(String id, {String? date}) async {
    final selected = date ?? today;
    if (!canRecordDate(selected)) return false;
    final entries = logs[selected]?.foodEntries;
    if (entries == null || !entries.any((e) => e.id == id)) return false;
    entries.removeWhere((e) => e.id == id);
    await _save();
    return true;
  }

  Future<void> toggleMeal(int slot, {String? date}) async {
    final selected = date ?? today;
    if (!canRecordDate(selected) || slot < 0 || slot >= 4) return;
    final portions = mealsForDate(selected);
    final entry = logForDate(selected);
    if (entry.meals.containsKey(slot)) {
      entry.meals.remove(slot);
    } else {
      final p = portions[slot];
      final m = mealById(p.mealId);
      entry.meals[slot] = MealRecord(m.title, m.nutrients.scale(p.factor));
    }
    await _save();
  }

  Future<void> setMeal(
    int slot,
    String id,
    double factor, {
    String? date,
  }) async {
    if (slot < 0 || slot >= 4 || !availableMeals(slot).any((m) => m.id == id)) {
      return;
    }
    final selected = date ?? today;
    final current = List<MealPortion>.from(mealsForDate(selected));
    current[slot] = MealPortion(id, factor.clamp(.5, 2));
    mealPlans[selected] = current;
    await _save();
  }

  Future<void> swapMeal(int slot, {String? date}) async {
    if (slot < 0 || slot >= 4) return;
    final selected = date ?? today;
    final portions = mealsForDate(selected);
    final choices = availableMeals(slot);
    final index = choices.indexWhere((m) => m.id == portions[slot].mealId);
    await setMeal(
      slot,
      choices[(index + 1) % choices.length].id,
      portions[slot].factor,
      date: selected,
    );
  }

  Future<void> savePreferences({
    required String diet,
    required Set<String> allergens,
    required int calories,
    required int water,
    int? protein,
    int? carbs,
    int? fat,
    String? date,
  }) async {
    final selected = date ?? today;
    final targets = targetsForDate(selected).copyWith(
      calories: calories,
      water: water,
      protein: protein,
      carbs: carbs,
      fat: fat,
    );
    this.diet = diet;
    this.allergens
      ..clear()
      ..addAll(allergens);
    // A dated edit updates that date. Today edits also set defaults for new dates.
    nutritionTargets[selected] = targets;
    logs[selected]?.waterTarget = targets.water;
    if (selected == today) {
      calorieTarget = targets.calories;
      waterTarget = targets.water;
      proteinTarget = targets.protein;
      carbsTarget = targets.carbs;
      fatTarget = targets.fat;
    }
    // Future choices respect new restrictions; consumed meals stay immutable snapshots.
    for (final date
        in mealPlans.keys.where((d) => d.compareTo(today) >= 0).toList()) {
      mealPlans[date] = List.generate(4, (slot) {
        final old = mealPlans[date]![slot];
        return availableMeals(slot).any((m) => m.id == old.mealId)
            ? old
            : MealPortion(availableMeals(slot).first.id);
      });
    }
    await _save();
  }

  NextRecommendation get recommendation {
    final recentTraining = recent(7).where((l) => l.setCount > 0).toList();
    final latest = recentTraining.lastOrNull;
    final tired = latest != null && latest.meanFatigue >= 2.5;
    final average = recentTraining.isEmpty
        ? 1.0
        : recentTraining
                  .map((l) => scoreFor(l).training / 100)
                  .reduce((a, b) => a + b) /
              recentTraining.length;
    final latestRecovery = recent(3)
        .where((l) => l.recovery != null)
        .lastOrNull;
    final recovery = latestRecovery?.recovery;
    final restForPain = recovery?.pain ?? false;
    final recoveryLighter = recovery?.needsReduction ?? false;
    final lighter =
        restForPain ||
        recoveryLighter ||
        tired ||
        (recentTraining.length >= 2 && average < .6);
    final lastIds = latest?.completedSets.keys.toList() ?? [];
    final lastLower = lastIds.any(
      (id) => ['腿部', '臀部'].contains(exerciseById(id).group),
    );
    final baseline = plan;
    // Two complete sessions of the same movement need actual target attainment,
    // tolerable effort and recorded good recovery before adding a small amount.
    final progressions = <String, List<DailyLog>>{};
    if (!lighter) {
      for (final item in baseline.items) {
        final sessions = recent(28)
            .where(
              (entry) =>
                  (entry.completedSets[item.exerciseId] ?? {}).isNotEmpty,
            )
            .toList();
        if (sessions.length < 2) continue;
        final pair = sessions.sublist(sessions.length - 2);
        final successful = pair.every((entry) {
          final source = plans[entry.date]?.items
              .where((i) => i.exerciseId == item.exerciseId)
              .firstOrNull;
          if (source == null ||
              source.sets < item.sets ||
              !(entry.recovery?.supportsProgression ?? false)) {
            return false;
          }
          final records = entry.setRecords[item.exerciseId] ?? {};
          return List.generate(source.sets, (i) => i).every((index) {
            final record = records[index];
            return (entry.completedSets[item.exerciseId] ?? {}).contains(
                  index,
                ) &&
                record != null &&
                record.achievedTarget &&
                record.fatigue <= 2 &&
                record.timed == exerciseById(item.exerciseId).timed &&
                (record.timed ? record.actualSeconds! : record.actualReps!) >=
                    item.reps;
          });
        });
        if (!successful) continue;
        final previous = pair.first.setRecords[item.exerciseId]!;
        final current = pair.last.setRecords[item.exerciseId]!;
        // An easier load cannot be mistaken for improvement. Missing weight is
        // kept distinct from an explicit zero-bodyweight entry.
        final consistentLoad = List.generate(item.sets, (i) => i).every((i) {
          final before = previous[i]?.weightKg;
          final after = current[i]?.weightKg;
          return before == null
              ? after == null
              : after != null && after >= before;
        });
        if (consistentLoad && item.reps < 120) {
          progressions[item.exerciseId] = pair;
        }
      }
    }
    final candidates = lastLower
        ? [
            'pushup',
            if (baseline.equipment == '哑铃') 'row',
            'plank',
            'jumping_jack',
            'kneeling_pushup',
            if (baseline.equipment == '哑铃') ...[
              'floor_press',
              'shoulder_press',
              'lateral_raise',
              'reverse_fly',
            ],
            'dead_bug',
            'bird_dog',
            'side_plank',
            'step_jack',
          ]
        : [
            'squat',
            'bridge',
            'lunge',
            'plank',
            'sumo_squat',
            'split_squat',
            'lateral_lunge',
            'calf_raise',
            'dead_bug',
            'bird_dog',
            'side_plank',
            'step_jack',
            if (baseline.equipment == '哑铃') 'romanian_deadlift',
          ];
    // Prefer less-used movements within the same available-equipment pool.
    // Read-only suggestions never alter an adopted plan or existing logs.
    final usage = <String, int>{};
    for (final log in recentTraining) {
      for (final entry in log.completedSets.entries) {
        usage.update(
          entry.key,
          (count) => count + entry.value.length,
          ifAbsent: () => entry.value.length,
        );
      }
    }
    final priority = {
      for (var i = 0; i < candidates.length; i++) candidates[i]: i,
    };
    candidates.sort((a, b) {
      final byUsage = (usage[a] ?? 0).compareTo(usage[b] ?? 0);
      return byUsage != 0 ? byUsage : priority[a]!.compareTo(priority[b]!);
    });
    final ordered = [
      ...progressions.keys,
      ...candidates.where((id) => !progressions.containsKey(id)),
    ];
    candidates
      ..clear()
      ..addAll(ordered);
    final items = <PlanItem>[];
    if (recentTraining.isEmpty || baseline.items.isEmpty) {
      items.addAll(baseline.items);
    } else {
      // Keep the user's number of exercise slots and map each original item
      // exactly once, reserving matching IDs so their targets survive a switch.
      final ids = [
        ...candidates,
        ...baseline.items
            .map((i) => i.exerciseId)
            .where((id) => !candidates.contains(id)),
      ].take(baseline.items.length).toList();
      final remaining = List<PlanItem>.of(baseline.items);
      for (final id in ids) {
        final source =
            remaining.where((i) => i.exerciseId == id).firstOrNull ??
            remaining.where((i) => !ids.contains(i.exerciseId)).firstOrNull ??
            remaining.first;
        remaining.remove(source);
        final compatible =
            exerciseById(id).timed == exerciseById(source.exerciseId).timed;
        items.add(
          PlanItem(
            id,
            sets: lighter
                ? math.max(1, (source.sets * 2 / 3).floor())
                : source.sets,
            reps: compatible ? source.reps : (exerciseById(id).timed ? 30 : 12),
            rest: tired ? math.max(90, source.rest) : source.rest,
          ),
        );
      }
    }
    if (restForPain) {
      items.clear();
    } else if (lighter && items.isNotEmpty) {
      final budget = math.max(1, (baseline.totalSets * 2 / 3).floor());
      if (items.length > budget) items.removeRange(budget, items.length);
      while (items.fold<int>(0, (n, i) => n + i.sets) > budget) {
        final index = items.lastIndexWhere((i) => i.sets > 1);
        if (index < 0) break;
        items[index] = items[index].copyWith(sets: items[index].sets - 1);
      }
      if (recoveryLighter) {
        for (var i = 0; i < items.length; i++) {
          items[i] = items[i].copyWith(
            reps: math.max(1, (items[i].reps * .8).floor()),
            rest: math.max(90, items[i].rest),
          );
        }
      }
    } else {
      for (var i = 0; i < items.length; i++) {
        if (progressions.containsKey(items[i].exerciseId)) {
          items[i] = items[i].copyWith(
            reps:
                items[i].reps +
                (exerciseById(items[i].exerciseId).timed ? 5 : 1),
          );
        }
      }
    }
    final nextTotal = items.fold<int>(0, (n, i) => n + i.sets);
    final reduced = nextTotal < baseline.totalSets;
    final reasons = <String>[
      if (restForPain)
        '${latestRecovery!.date} 反馈有疼痛或不适，建议明日休息，暂不安排训练；恢复舒适后再自行调整。'
      else if (recoveryLighter)
        '${latestRecovery!.date} 反馈${recovery!.sleepQuality == 1 ? '睡眠较差' : ''}${recovery.sleepQuality == 1 && recovery.soreness >= 2 ? '、' : ''}${recovery.soreness >= 2 ? '酸痛明显' : ''}，明日保守减量并延长休息。',
      for (final entry in progressions.entries)
        '${exerciseById(entry.key).name} 在 ${entry.value.first.date} 和 ${entry.value.last.date} 两次训练中实际达到全部目标组数，感受轻松或适中、负重未下降且恢复良好；小幅进阶${exerciseById(entry.key).timed ? '最多 5 秒' : '1 次'}，组数不增加。',
      if (baseline.items.isEmpty)
        '当前计划为空，先保留空计划；添加动作后再安排训练。'
      else if (!restForPain && recoveryLighter && recentTraining.isEmpty)
        '还没有训练记录，基于当前计划保守减量，建立恢复期间的训练基线。'
      else if (!restForPain && recentTraining.isEmpty)
        '还没有训练记录，沿用你的动作、组数、次数和休息建立基线。'
      else if (!restForPain && progressions.isNotEmpty)
        '已有同动作的进阶依据，优先保留相关动作；其余动作按近期记录轮换。'
      else if (!restForPain && lastLower)
        '最近训练以下肢为主，下一次优先切换到上肢与核心。'
      else if (!restForPain)
        '最近训练以上肢或核心为主，下一次优先安排下肢练习。',
      if (!restForPain &&
          !recoveryLighter &&
          tired &&
          baseline.items.isNotEmpty)
        reduced
            ? '你最近反馈偏吃力，训练组数从 ${baseline.totalSets} 组减到 $nextTotal 组，并预留更长休息。'
            : '你最近反馈偏吃力，当前训练量已很小，保留 $nextTotal 组并预留更长休息。'
      else if (!restForPain &&
          !recoveryLighter &&
          lighter &&
          baseline.items.isNotEmpty)
        reduced
            ? '近 7 天完成率较低，训练组数从 ${baseline.totalSets} 组减到 $nextTotal 组。'
            : '近 7 天完成率较低，保留已有的小训练量，避免增加负担。'
      else if (!lighter &&
          recentTraining.isNotEmpty &&
          baseline.items.isNotEmpty)
        '根据最近 ${recentTraining.length} 次记录，沿用你计划的 ${baseline.totalSets} 组训练量。',
      '建议可调整；训练日程由你决定。',
    ];
    final intake = recent(7).where((l) => l.mealCount > 0).toList();
    final meanIntake = intake.isEmpty
        ? null
        : intake
              .fold<Nutrients>(
                Nutrients.zero,
                (n, l) => n + nutritionForDate(l.date),
              )
              .scale(1 / intake.length);
    final mealSuggestion = suggestMeals(
      targets: nutritionTargets[tomorrow] ?? defaultNutritionTargets,
      choices: List.generate(4, availableMeals),
      current: meals,
      recentIntake: meanIntake,
      recordedDays: intake.length,
    );
    return NextRecommendation(
      date: tomorrow,
      plan: plan.copyWith(
        title: restForPain
            ? '恢复休息'
            : recentTraining.isEmpty ||
                  baseline.items.isEmpty ||
                  progressions.isNotEmpty
            ? plan.title
            : lastLower
            ? '上肢与核心'
            : '下肢与核心',
        minutes: lighter ? math.min(20, plan.minutes) : plan.minutes,
        items: items,
      ),
      meals: mealSuggestion.meals,
      reasons: reasons,
      nutritionReason:
          '${mealSuggestion.reason}沿用${diet == '素食优先' ? '素食' : '均衡'}偏好和忌口，保留现有份量和你设定的摄入目标；建议可自行调整。',
    );
  }

  Future<void> adoptRecommendation(NextRecommendation value) {
    if (value.date.compareTo(today) <= 0) return Future.value();
    plans[value.date] = value.plan.copyWith();
    mealPlans[value.date] = List.of(value.meals);
    targetsForDate(value.date);
    return _save();
  }
}
