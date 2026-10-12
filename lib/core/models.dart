import 'dart:math' as math;

String dayKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

class Exercise {
  final String id, name, group, equipment, subtitle;
  final List<String> tips;
  final bool timed, sideView;
  const Exercise(
    this.id,
    this.name,
    this.group,
    this.equipment,
    this.subtitle,
    this.tips, {
    this.timed = false,
    this.sideView = false,
  });
  String get model => 'assets/models/athlete_$id.glb';
  String get image => 'assets/images/athlete_$id.png';
  List<String> get requiredEquipment => equipment.split('＋');
  bool get prefersSideView =>
      sideView || const {'pushup', 'plank', 'bridge', 'row'}.contains(id);
}

class PlanItem {
  final String exerciseId;
  final int sets, reps, rest;
  const PlanItem(
    this.exerciseId, {
    this.sets = 3,
    this.reps = 12,
    this.rest = 60,
  });
  PlanItem copyWith({int? sets, int? reps, int? rest}) => PlanItem(
    exerciseId,
    sets: (sets ?? this.sets).clamp(1, 8),
    reps: (reps ?? this.reps).clamp(1, 120),
    rest: (rest ?? this.rest).clamp(0, 300),
  );
  Map<String, dynamic> toJson() => {
    'id': exerciseId,
    'sets': sets,
    'reps': reps,
    'rest': rest,
  };
  factory PlanItem.fromJson(Map<String, dynamic> j) => PlanItem(
    j['id'] as String,
    sets: j['sets'] as int,
    reps: j['reps'] as int,
    rest: j['rest'] as int,
  ).copyWith();
}

class TrainingPlan {
  final String title, goal, equipment;
  final int minutes;
  final List<int> days;
  final List<PlanItem> items;
  TrainingPlan({
    this.title = '下肢与核心',
    this.goal = '保持活力',
    this.equipment = '徒手',
    this.minutes = 30,
    this.days = const [1, 3, 6],
    required List<PlanItem> items,
  }) : items = List.unmodifiable(items);
  TrainingPlan copyWith({
    String? title,
    String? goal,
    String? equipment,
    int? minutes,
    List<int>? days,
    List<PlanItem>? items,
  }) => TrainingPlan(
    title: title ?? this.title,
    goal: goal ?? this.goal,
    equipment: equipment ?? this.equipment,
    minutes: (minutes ?? this.minutes).clamp(10, 90),
    days: List.of(days ?? this.days),
    items: items ?? this.items,
  );
  Map<String, dynamic> toJson() => {
    'title': title,
    'goal': goal,
    'equipment': equipment,
    'minutes': minutes,
    'days': days,
    'items': items.map((i) => i.toJson()).toList(),
  };
  factory TrainingPlan.fromJson(Map<String, dynamic> j) => TrainingPlan(
    title: j['title'],
    goal: j['goal'],
    equipment: j['equipment'],
    minutes: j['minutes'],
    days: List<int>.from(j['days']),
    items: (j['items'] as List)
        .map((e) => PlanItem.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
  );
  int get totalSets => items.fold(0, (n, i) => n + i.sets);
}

class Nutrients {
  final double kcal, protein, carbs, fat;
  const Nutrients(this.kcal, this.protein, this.carbs, this.fat);
  static const zero = Nutrients(0, 0, 0, 0);
  Nutrients operator +(Nutrients other) => Nutrients(
    kcal + other.kcal,
    protein + other.protein,
    carbs + other.carbs,
    fat + other.fat,
  );
  Nutrients scale(double factor) =>
      Nutrients(kcal * factor, protein * factor, carbs * factor, fat * factor);
  List<double> toJson() => [kcal, protein, carbs, fat];
  factory Nutrients.fromJson(List list) => Nutrients(
    (list[0] as num).toDouble(),
    (list[1] as num).toDouble(),
    (list[2] as num).toDouble(),
    (list[3] as num).toDouble(),
  );
}

/// User-entered reference goals, snapshotted separately for each date.
class NutritionTargets {
  final int calories, protein, carbs, fat, water;
  const NutritionTargets({
    this.calories = 1800,
    this.protein = 120,
    this.carbs = 195,
    this.fat = 60,
    this.water = 2000,
  });
  NutritionTargets copyWith({
    int? calories,
    int? protein,
    int? carbs,
    int? fat,
    int? water,
  }) => NutritionTargets(
    calories: (calories ?? this.calories).clamp(1000, 4000),
    protein: (protein ?? this.protein).clamp(1, 300),
    carbs: (carbs ?? this.carbs).clamp(1, 600),
    fat: (fat ?? this.fat).clamp(1, 200),
    water: (water ?? this.water).clamp(500, 4000),
  );
  Map<String, dynamic> toJson() => {
    'calories': calories,
    'protein': protein,
    'carbs': carbs,
    'fat': fat,
    'water': water,
  };
  factory NutritionTargets.fromJson(
    Map<String, dynamic> j, {
    NutritionTargets defaults = const NutritionTargets(),
  }) => defaults.copyWith(
    calories: j['calories'] as int?,
    protein: j['protein'] as int?,
    carbs: j['carbs'] as int?,
    fat: j['fat'] as int?,
    water: j['water'] as int?,
  );
}

class MealChoice {
  final String id, title, detail, emoji;
  final int slot;
  final Nutrients nutrients;
  final bool vegetarian;
  final List<String> allergens;
  const MealChoice(
    this.id,
    this.slot,
    this.title,
    this.detail,
    this.emoji,
    this.nutrients, {
    this.vegetarian = false,
    this.allergens = const [],
  });
}

class MealPortion {
  final String mealId;
  final double factor;
  const MealPortion(this.mealId, [this.factor = 1]);
  Map<String, dynamic> toJson() => {'id': mealId, 'factor': factor};
  factory MealPortion.fromJson(Map<String, dynamic> j) =>
      MealPortion(j['id'], (j['factor'] as num).toDouble().clamp(0.5, 2));
}

class MealRecord {
  final String title;
  final Nutrients nutrients;
  MealRecord(this.title, this.nutrients);
  Map<String, dynamic> toJson() => {
    'title': title,
    'nutrients': nutrients.toJson(),
  };
  factory MealRecord.fromJson(Map<String, dynamic> j) =>
      MealRecord(j['title'], Nutrients.fromJson(j['nutrients']));
}

/// A named user reference. Values are estimates per 100 g from a declared source.
class CustomFood {
  final String id, name, source;
  final Nutrients per100g;
  final List<String> allergens;
  final bool vegetarian;
  CustomFood({
    required this.id,
    required this.name,
    required this.source,
    required this.per100g,
    List<String> allergens = const [],
    this.vegetarian = false,
  }) : allergens = List.unmodifiable(allergens);
  bool get isValid =>
      id.trim().isNotEmpty &&
      id.length <= 100 &&
      name.trim().isNotEmpty &&
      name.length <= 100 &&
      source.trim().isNotEmpty &&
      source.length <= 500 &&
      per100g.toJson().every((v) => v.isFinite && v >= 0) &&
      per100g.kcal <= 1000 &&
      per100g.protein <= 100 &&
      per100g.carbs <= 100 &&
      per100g.fat <= 100 &&
      allergens.length <= 30 &&
      allergens.every((v) => v.trim().isNotEmpty && v.length <= 100);
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'source': source,
    'per100g': per100g.toJson(),
    'allergens': allergens,
    'vegetarian': vegetarian,
  };
  factory CustomFood.fromJson(Map<String, dynamic> j) {
    final food = CustomFood(
      id: j['id'] as String,
      name: j['name'] as String,
      source: j['source'] as String,
      per100g: Nutrients.fromJson(j['per100g'] as List),
      allergens: List<String>.from(j['allergens'] as List),
      vegetarian: j['vegetarian'] as bool,
    );
    if (!food.isValid) throw const FormatException('Invalid custom food');
    return food;
  }
}

/// Full reference and nutrition snapshot: editing a food never rewrites intake.
class FoodEntry {
  final String id, date;
  final int slot;
  final double grams;
  final CustomFood food;
  final Nutrients nutrients;
  const FoodEntry({
    required this.id,
    required this.date,
    required this.slot,
    required this.grams,
    required this.food,
    required this.nutrients,
  });
  bool get isValid =>
      id.trim().isNotEmpty &&
      id.length <= 100 &&
      validDayKey(date) &&
      slot >= 0 &&
      slot < 4 &&
      grams.isFinite &&
      grams > 0 &&
      grams <= 10000 &&
      food.isValid &&
      List.generate(
        4,
        (i) =>
            (nutrients.toJson()[i] -
                    food.per100g.scale(grams / 100).toJson()[i])
                .abs() <=
            .000001,
      ).every((v) => v);
  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date,
    'slot': slot,
    'grams': grams,
    'food': food.toJson(),
    'nutrients': nutrients.toJson(),
  };
  factory FoodEntry.fromJson(Map<String, dynamic> j) {
    final entry = FoodEntry(
      id: j['id'] as String,
      date: j['date'] as String,
      slot: j['slot'] as int,
      grams: (j['grams'] as num).toDouble(),
      food: CustomFood.fromJson(Map<String, dynamic>.from(j['food'])),
      nutrients: Nutrients.fromJson(j['nutrients'] as List),
    );
    if (!entry.isValid) throw const FormatException('Invalid food entry');
    return entry;
  }
}

bool validDayKey(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
  final parsed = DateTime.tryParse(value);
  return parsed != null && dayKey(parsed) == value;
}

/// Immutable actual values; null actuals identify older completion-only entries.
class SetRecord {
  final int setIndex, fatigue, elapsedSeconds, target;
  final bool timed;
  final int? actualReps, actualSeconds;
  final double? weightKg;
  const SetRecord({
    required this.setIndex,
    required this.fatigue,
    required this.elapsedSeconds,
    required this.target,
    required this.timed,
    this.actualReps,
    this.actualSeconds,
    this.weightKg,
  });
  SetRecord withIndex(int index) => SetRecord(
    setIndex: index,
    fatigue: fatigue,
    elapsedSeconds: elapsedSeconds,
    target: target,
    timed: timed,
    actualReps: actualReps,
    actualSeconds: actualSeconds,
    weightKg: weightKg,
  );
  bool get achievedTarget =>
      (timed ? actualSeconds : actualReps) != null &&
      (timed ? actualSeconds! : actualReps!) >= target;
  Map<String, dynamic> toJson() => {
    'setIndex': setIndex,
    'fatigue': fatigue,
    'elapsedSeconds': elapsedSeconds,
    'target': target,
    'timed': timed,
    'actualReps': actualReps,
    'actualSeconds': actualSeconds,
    'weightKg': weightKg,
  };
  factory SetRecord.fromJson(Map<String, dynamic> j) {
    final value = SetRecord(
      setIndex: j['setIndex'] as int,
      fatigue: j['fatigue'] as int,
      elapsedSeconds: j['elapsedSeconds'] as int,
      target: j['target'] as int,
      timed: j['timed'] as bool,
      actualReps: j['actualReps'] as int?,
      actualSeconds: j['actualSeconds'] as int?,
      weightKg: (j['weightKg'] as num?)?.toDouble(),
    );
    if (value.setIndex < 0 ||
        value.fatigue < 1 ||
        value.fatigue > 3 ||
        value.elapsedSeconds < 0 ||
        value.elapsedSeconds > 7200 ||
        value.target < 1 ||
        value.target > 120 ||
        (value.actualReps != null &&
            (value.timed ||
                value.actualReps! < 1 ||
                value.actualReps! > 1000)) ||
        (value.actualSeconds != null &&
            (!value.timed ||
                value.actualSeconds! < 1 ||
                value.actualSeconds! > 7200)) ||
        (value.weightKg != null &&
            (!value.weightKg!.isFinite ||
                value.weightKg! < 0 ||
                value.weightKg! > 1000))) {
      throw const FormatException('Invalid actual set record');
    }
    return value;
  }
}

/// Self-reported recovery for one date, independent of training completion.
class RecoveryFeedback {
  final int sleepQuality, soreness;
  final bool pain;
  const RecoveryFeedback({
    required this.sleepQuality,
    required this.soreness,
    required this.pain,
  });
  bool get isValid =>
      sleepQuality >= 1 && sleepQuality <= 3 && soreness >= 0 && soreness <= 3;
  bool get needsReduction => sleepQuality == 1 || soreness >= 2;
  bool get supportsProgression => !pain && sleepQuality >= 2 && soreness <= 1;
  Map<String, dynamic> toJson() => {
    'sleepQuality': sleepQuality,
    'soreness': soreness,
    'pain': pain,
  };
  factory RecoveryFeedback.fromJson(Map<String, dynamic> j) {
    final value = RecoveryFeedback(
      sleepQuality: j['sleepQuality'] as int,
      soreness: j['soreness'] as int,
      pain: j['pain'] as bool,
    );
    if (!value.isValid) {
      throw const FormatException('Invalid recovery feedback');
    }
    return value;
  }
}

class DailyLog {
  final String date;
  final Map<String, Set<int>> completedSets;
  final Map<int, MealRecord> meals;
  final List<FoodEntry> foodEntries;
  final Map<String, Map<int, SetRecord>> setRecords;
  final List<int> fatigue;
  RecoveryFeedback? recovery;
  int waterMl, waterTarget, trainingSeconds;
  DailyLog(
    this.date, {
    Map<String, Set<int>>? completedSets,
    Map<int, MealRecord>? meals,
    List<FoodEntry>? foodEntries,
    Map<String, Map<int, SetRecord>>? setRecords,
    List<int>? fatigue,
    this.recovery,
    this.waterMl = 0,
    this.waterTarget = 2000,
    this.trainingSeconds = 0,
  }) : completedSets = completedSets ?? {},
       meals = meals ?? {},
       foodEntries = foodEntries ?? [],
       setRecords = setRecords ?? {},
       fatigue = fatigue ?? [];
  bool get hasActivity =>
      completedSets.values.any((s) => s.isNotEmpty) ||
      meals.isNotEmpty ||
      foodEntries.isNotEmpty ||
      waterMl > 0 ||
      recovery != null;
  Set<int> get completedMealSlots => {
    ...meals.keys,
    ...foodEntries.map((e) => e.slot),
  }.where((slot) => slot >= 0 && slot < 4).toSet();
  int get mealCount => completedMealSlots.length;
  double get meanFatigue =>
      fatigue.isEmpty ? 0 : fatigue.reduce((a, b) => a + b) / fatigue.length;
  int get setCount => completedSets.values.fold(0, (n, s) => n + s.length);
  Map<String, dynamic> toJson() => {
    'date': date,
    'sets': completedSets.map((k, v) => MapEntry(k, v.toList())),
    'meals': meals.map((k, v) => MapEntry('$k', v.toJson())),
    'foodEntries': foodEntries.map((e) => e.toJson()).toList(),
    'setRecords': setRecords.map(
      (id, records) => MapEntry(
        id,
        records.map((index, record) => MapEntry('$index', record.toJson())),
      ),
    ),
    'fatigue': fatigue,
    'recovery': recovery?.toJson(),
    'water': waterMl,
    'waterTarget': waterTarget,
    'seconds': trainingSeconds,
  };
  factory DailyLog.fromJson(
    Map<String, dynamic> j, {
    int defaultWaterTarget = 2000,
  }) => DailyLog(
    j['date'],
    completedSets: (j['sets'] as Map).map(
      (k, v) => MapEntry(k as String, Set<int>.from(v)),
    ),
    meals: (j['meals'] as Map).map(
      (k, v) => MapEntry(
        int.parse(k),
        MealRecord.fromJson(Map<String, dynamic>.from(v)),
      ),
    ),
    foodEntries: (j['foodEntries'] as List? ?? [])
        .map((e) => FoodEntry.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    setRecords: (j['setRecords'] as Map? ?? {}).map(
      (id, records) => MapEntry(
        id as String,
        (records as Map).map(
          (index, record) => MapEntry(
            int.parse(index as String),
            SetRecord.fromJson(Map<String, dynamic>.from(record)),
          ),
        ),
      ),
    ),
    fatigue: List<int>.from(j['fatigue']),
    recovery: j['recovery'] == null
        ? null
        : RecoveryFeedback.fromJson(Map<String, dynamic>.from(j['recovery'])),
    waterMl: j['water'],
    waterTarget: (j['waterTarget'] as int? ?? defaultWaterTarget).clamp(
      500,
      4000,
    ),
    trainingSeconds: j['seconds'],
  );
}

class CompletionScore {
  final int training, nutrition, habits;
  const CompletionScore(this.training, this.nutrition, this.habits);
  int get total => (training * .6 + nutrition * .3 + habits * .1).round();
  static int percent(num done, num target) => target <= 0
      ? 0
      : math.min(100, math.max(0, (done / target * 100).round()));
}

class NextRecommendation {
  final String date;
  final TrainingPlan plan;
  final List<MealPortion> meals;
  final List<String> reasons;
  final String nutritionReason;
  const NextRecommendation({
    required this.date,
    required this.plan,
    required this.meals,
    required this.reasons,
    required this.nutritionReason,
  });
}
