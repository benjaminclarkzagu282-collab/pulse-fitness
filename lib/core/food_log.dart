import 'dart:math' as math;

import 'models.dart';

class MealSuggestion {
  final List<MealPortion> meals;
  final String reason;
  const MealSuggestion(this.meals, this.reason);
}

/// Rank complete combinations at the user's existing portions. Recent intake
/// only adjusts macro weighting; missing dates are never treated as zero intake.
MealSuggestion suggestMeals({
  required NutritionTargets targets,
  required List<List<MealChoice>> choices,
  required List<MealPortion> current,
  Nutrients? recentIntake,
  required int recordedDays,
}) {
  final goal = [targets.calories, targets.protein, targets.carbs, targets.fat];
  final weights = [.4, .2, .2, .2];
  if (recentIntake != null) {
    final intake = recentIntake.toJson();
    for (var i = 1; i < 4; i++) {
      // Prioritize dimensions most below target among the recorded estimates.
      weights[i] *= (2 - intake[i] / goal[i]).clamp(.25, 2.0);
    }
  }
  double score(Nutrients n) {
    final values = n.toJson();
    return List.generate(
      4,
      (i) => weights[i] * math.pow((values[i] - goal[i]) / goal[i], 2),
    ).fold<double>(0, (a, b) => a + b);
  }

  var bestScore = double.infinity;
  var best = List<MealPortion>.of(current);
  void search(int slot, List<MealPortion> draft, Nutrients total) {
    if (slot == choices.length) {
      final value = score(total);
      if (value < bestScore) {
        bestScore = value;
        best = List.of(draft);
      }
      return;
    }
    final options = choices[slot];
    final index = options.indexWhere((m) => m.id == current[slot].mealId);
    for (var offset = 0; offset < options.length; offset++) {
      final meal = options[(index + offset + 1) % options.length];
      final portion = MealPortion(meal.id, current[slot].factor);
      search(slot + 1, [
        ...draft,
        portion,
      ], total + meal.nutrients.scale(portion.factor));
    }
  }

  search(0, [], Nutrients.zero);
  final reason =
      '参考明日目标：热量 ${targets.calories} kcal、蛋白质 ${targets.protein} g、碳水 ${targets.carbs} g、脂肪 ${targets.fat} g，比较允许的全天搭配与目标的差距。'
      '${recentIntake == null ? '近 7 天没有实际摄入记录，先按目标选择。' : '近 7 天有 $recordedDays 天实际摄入（记录均值 ${recentIntake.kcal.round()} kcal、蛋白质 ${recentIntake.protein.round()} g、碳水 ${recentIntake.carbs.round()} g、脂肪 ${recentIntake.fat.round()} g），增加记录中较缺少的宏量营养权重。记录可能不完整，未记录日不按零摄入计算。'}';
  return MealSuggestion(List.unmodifiable(best), reason);
}
