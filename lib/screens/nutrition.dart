import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/catalog.dart';
import '../core/models.dart';
import '../ui/components.dart';
import '../ui/theme.dart';
import 'food_log.dart';

/// A local selection: callers decide whether it updates today or a future draft.
Future<MealPortion?> chooseMealPortion(
  BuildContext context,
  AppState state,
  int slot,
  MealPortion initial,
) {
  final choices = state.availableMeals(slot);
  var selected = choices.any((m) => m.id == initial.mealId)
      ? initial.mealId
      : choices.first.id;
  var factor = initial.factor;
  return showAppSheet<MealPortion>(
    context,
    StatefulBuilder(
      builder: (context, update) {
        final nutrients = mealById(selected).nutrients.scale(factor);
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .85,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '安排${mealSlots[slot]}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text('以下搭配已按饮食偏好与忌口筛选。', style: TextStyle(color: muted)),
                const SizedBox(height: 16),
                ...choices.map(
                  (meal) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: selected == meal.id
                          ? lime.withValues(alpha: .08)
                          : surface2,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => update(() => selected = meal.id),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              MealThumbnail(meal, size: 42),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      meal.title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      meal.detail,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: muted,
                                      ),
                                    ),
                                    Text(
                                      '${meal.nutrients.kcal.round()} kcal / 标准份',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                selected == meal.id
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                color: selected == meal.id ? lime : muted,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('份量', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [.5, 1.0, 1.5, 2.0]
                      .map(
                        (v) => Pill(
                          '${v == v.roundToDouble() ? v.toInt() : v} ×',
                          active: factor == v,
                          onTap: () => update(() => factor = v),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 16),
                Text(
                  '${nutrients.kcal.round()} kcal · 蛋白质 ${nutrients.protein.round()} g · 碳水 ${nutrients.carbs.round()} g · 脂肪 ${nutrients.fat.round()} g',
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(context, MealPortion(selected, factor)),
                  child: const Text('确认搭配与份量'),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class NutritionScreen extends StatefulWidget {
  final AppState state;
  const NutritionScreen({super.key, required this.state});
  @override
  State<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends State<NutritionScreen> {
  String? _selected;
  AppState get state => widget.state;
  String get date => _selected ?? state.today;
  bool get future => !state.canRecordDate(date);

  Future<void> _preferences(BuildContext context, {bool goals = false}) async {
    final selected = date;
    final targets = state.targetsForDate(selected);
    var diet = state.diet;
    final exclusions = Set<String>.from(state.allergens);
    var calories = targets.calories, water = targets.water;
    var protein = targets.protein, carbs = targets.carbs, fat = targets.fat;
    final save = await showAppSheet<bool>(
      context,
      StatefulBuilder(
        builder: (context, update) {
          Widget goal(
            String label,
            int value,
            int min,
            int max,
            int divisions,
            String unit,
            ValueChanged<int> onChange,
          ) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$label  $value $unit',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Slider(
                value: value.toDouble(),
                min: min.toDouble(),
                max: max.toDouble(),
                divisions: divisions,
                label: '$value $unit',
                onChanged: (v) => update(() => onChange(v.round())),
              ),
            ],
          );
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .85,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    goals ? '我的目标 · $selected' : '我的饮食偏好',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    goals
                        ? '目标由你设定，营养数值为食材与份量估算，不是饮食处方。保存仅更新所选日期；今天的目标也作为新日期的默认值。'
                        : '偏好与忌口适用于今天和未来的待选搭配；已记录餐食保留原始快照。',
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                  const SizedBox(height: 18),
                  if (goals) ...[
                    goal(
                      '能量',
                      calories,
                      1000,
                      4000,
                      60,
                      'kcal',
                      (v) => calories = v,
                    ),
                    goal('蛋白质', protein, 1, 300, 299, 'g', (v) => protein = v),
                    goal('碳水', carbs, 1, 600, 599, 'g', (v) => carbs = v),
                    goal('脂肪', fat, 1, 200, 199, 'g', (v) => fat = v),
                    goal('饮水', water, 500, 4000, 14, 'ml', (v) => water = v),
                  ] else ...[
                    const Text(
                      '饮食方式',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: ['均衡饮食', '素食优先']
                          .map(
                            (v) => Pill(
                              v,
                              active: diet == v,
                              onTap: () => update(() => diet = v),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      '排除食材 / 过敏原',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: ['鸡蛋', '乳制品', '大豆', '坚果', '海鲜']
                          .map(
                            (v) => Pill(
                              v,
                              active: exclusions.contains(v),
                              onTap: () => update(
                                () => exclusions.contains(v)
                                    ? exclusions.remove(v)
                                    : exclusions.add(v),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(goals ? '保存所选日期目标' : '保存偏好与目标'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (save == true) {
      await state.savePreferences(
        diet: diet,
        allergens: exclusions,
        calories: calories,
        water: water,
        protein: protein,
        carbs: carbs,
        fat: fat,
        date: selected,
      );
      if (context.mounted) toast(context, state.storageError ?? '已保存');
    }
  }

  Future<void> _editMeal(int slot) async {
    final selected = date;
    final result = await chooseMealPortion(
      context,
      state,
      slot,
      state.mealsForDate(selected)[slot],
    );
    if (result != null) {
      await state.setMeal(slot, result.mealId, result.factor, date: selected);
    }
  }

  void _openFoodLog([int slot = 0]) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            FoodLogScreen(state: state, date: date, initialSlot: slot),
      ),
    );
  }

  Widget _meal(int slot) {
    final portion = state.mealsForDate(date)[slot];
    final meal = mealById(portion.mealId);
    final n = meal.nutrients.scale(portion.factor);
    final recorded = state.logs[date]?.meals[slot];
    final additions =
        state.logs[date]?.foodEntries.where((e) => e.slot == slot).toList() ??
        <FoodEntry>[];
    final changed =
        recorded != null &&
        (recorded.title != meal.title || recorded.nutrients.kcal != n.kcal);
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Panel(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Row(
              children: [
                InkWell(
                  onTap: () => _editMeal(slot),
                  child: MealThumbnail(meal, size: 58),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: () => _editMeal(slot),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mealSlots[slot],
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          recorded?.title ?? meal.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: muted, fontSize: 11),
                        ),
                        Text(
                          '${(recorded?.nutrients ?? n).kcal.round()} kcal · ${portion.factor} × 计划',
                          style: const TextStyle(color: muted, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: future
                          ? null
                          : () => state.toggleMeal(slot, date: date),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        minimumSize: const Size(72, 32),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            recorded == null
                                ? Icons.radio_button_unchecked
                                : Icons.check_circle,
                            size: 16,
                            color: recorded == null ? muted : lime,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            future
                                ? '计划'
                                : recorded == null
                                ? '记录餐食'
                                : '撤销记录',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    InkWell(
                      onTap: () => _editMeal(slot),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Text(
                          '更换 / 份量 ›',
                          style: TextStyle(color: muted, fontSize: 10),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (additions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '单条食物 ${additions.length} 条 · ${additions.fold<double>(0, (n, e) => n + e.nutrients.kcal).round()} kcal${recorded == null ? '，独立计入本餐' : '，与已记录整餐相加'}。撤销整餐保留单条食物。',
                  style: const TextStyle(color: sky, fontSize: 10),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: future ? null : () => _openFoodLog(slot),
                child: Text(additions.isEmpty ? '添加实际食物' : '管理本餐单条食物'),
              ),
            ),
            if (changed)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '更换计划不会改写摄入；已记录 ${recorded.title}。更新请先撤销。',
                  style: const TextStyle(color: sky, fontSize: 10),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _macro(String label, double value, int target, {Color color = lime}) =>
      Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: muted, fontSize: 11)),
              const SizedBox(height: 3),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${value.round()}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextSpan(
                      text: ' / $target g',
                      style: const TextStyle(color: muted, fontSize: 10),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              ThinBar(value / target, color: color),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final targets = state.targetsForDate(date);
    final n = state.nutritionForDate(date);
    final water = state.logs[date]?.waterMl ?? 0;
    final selectedDate = DateTime.parse(date);
    final today = DateTime.parse(state.today);
    final lower = today.subtract(const Duration(days: 365));
    final upper = today.add(const Duration(days: 30));
    final label = date == state.today
        ? '今天'
        : date == state.tomorrow
        ? '明天'
        : '所选日期';
    final summary = Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            future ? '已记录摄入 · 尚未到日期' : '$label摄入',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 5),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${n.kcal.round()}',
                  style: const TextStyle(
                    fontSize: 31,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                TextSpan(
                  text: ' / ${targets.calories} kcal',
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          ThinBar(n.kcal / targets.calories, height: 8),
          const SizedBox(height: 12),
          Row(
            children: [
              _macro('蛋白质', n.protein, targets.protein),
              _macro('碳水', n.carbs, targets.carbs, color: sky),
              _macro('脂肪', n.fat, targets.fat, color: coral),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            '营养为估算 · 目标由你设定 · 计划 ${state.plannedNutritionForDate(date).kcal.round()} kcal',
            style: const TextStyle(color: muted, fontSize: 10),
          ),
        ],
      ),
    );
    final goals = Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _preferences(context, goals: true),
            icon: const Icon(Icons.track_changes, size: 18),
            label: const Text('我的目标'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _preferences(context),
            icon: const Icon(Icons.eco_outlined, size: 18),
            label: const Text('偏好与忌口'),
          ),
        ),
      ],
    );
    final hydration = Panel(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.water_drop, color: sky, size: 28),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '饮水记录',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  '$water / ${targets.water} ml',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 5),
                ThinBar(water / targets.water, color: sky),
              ],
            ),
          ),
          IconButton(
            tooltip: '− 250 ml',
            onPressed: future || water == 0
                ? null
                : () => state.addWater(-250, date: date),
            icon: const Icon(Icons.remove, size: 18),
          ),
          OutlinedButton(
            onPressed: future ? null : () => state.addWater(250, date: date),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: const Text('+ 250 ml', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
    final suggestion = Panel(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          const Icon(Icons.restaurant_outlined, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '下一餐建议',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  state.recommendation.nutritionReason,
                  style: const TextStyle(color: muted, fontSize: 10),
                ),
              ],
            ),
          ),
          MealThumbnail(
            mealById(state.recommendation.meals.last.mealId),
            size: 44,
          ),
        ],
      ),
    );
    final mealRows = <Widget>[
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          future ? '所选日期餐食计划' : '$label餐食',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      ...List.generate(4, _meal),
    ];
    final exclusions = <Widget>[
      if (state.allergens.isNotEmpty)
        Text(
          '已排除：${state.allergens.join('、')}',
          style: const TextStyle(color: muted, fontSize: 10),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageTitle(
          eyebrow: 'NUTRITION',
          title: '健康饮食',
          subtitle: '规律餐食，为训练补充能量。',
          trailing: IconButton(
            tooltip: '饮食偏好与目标',
            onPressed: () => _preferences(context),
            icon: const Icon(Icons.tune),
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => _openFoodLog(),
          icon: const Icon(Icons.playlist_add),
          label: const Text('食物记录与食物库'),
        ),
        const SizedBox(height: 10),
        Center(
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: surface,
              border: Border.all(color: line),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: '前一天',
                  onPressed: selectedDate.isAfter(lower)
                      ? () => setState(
                          () => _selected = dayKey(
                            selectedDate.subtract(const Duration(days: 1)),
                          ),
                        )
                      : null,
                  icon: const Icon(Icons.chevron_left, size: 20),
                ),
                Text(
                  '$label · ${date.substring(5).replaceAll('-', '.')}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                IconButton(
                  tooltip: '后一天',
                  onPressed: selectedDate.isBefore(upper)
                      ? () => setState(
                          () => _selected = dayKey(
                            selectedDate.add(const Duration(days: 1)),
                          ),
                        )
                      : null,
                  icon: const Icon(Icons.chevron_right, size: 20),
                ),
              ],
            ),
          ),
        ),
        if (future)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              '未来仅安排计划，当天再记录实际摄入与饮水。',
              style: TextStyle(color: sky, fontSize: 11),
            ),
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 900) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 350,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        summary,
                        const SizedBox(height: 8),
                        goals,
                        ...exclusions,
                        const SizedBox(height: 10),
                        hydration,
                      ],
                    ),
                  ),
                  const SizedBox(width: 22),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ...mealRows,
                        const SizedBox(height: 8),
                        suggestion,
                      ],
                    ),
                  ),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                summary,
                const SizedBox(height: 8),
                goals,
                ...exclusions,
                const SizedBox(height: 10),
                ...mealRows,
                hydration,
                const SizedBox(height: 8),
                suggestion,
              ],
            );
          },
        ),
      ],
    );
  }
}
