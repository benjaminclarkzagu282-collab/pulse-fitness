import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/catalog.dart';
import '../core/models.dart';
import '../ui/components.dart';
import '../ui/theme.dart';
import 'nutrition.dart' show chooseMealPortion;
import 'progress.dart';

class InsightsScreen extends StatefulWidget {
  final AppState state;
  const InsightsScreen({super.key, required this.state});
  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  int _period = 1;
  String? _recoveryDate;
  NextRecommendation? _draft;
  bool _edited = false;
  bool _saving = false;
  AppState get state => widget.state;

  NextRecommendation get _recommendation {
    if (_draft?.date != state.tomorrow) {
      _draft = null;
      _edited = false;
    }
    final base = _draft ?? state.recommendation;
    final storedPlan = !_edited ? state.plans[state.tomorrow] : null;
    final storedMeals = !_edited ? state.mealPlans[state.tomorrow] : null;
    final sourceMeals = storedMeals ?? base.meals;
    // Preference edits can arrive while an unsaved recommendation is open.
    // Keep that local draft within the same filtered catalog as the picker.
    final meals = List<MealPortion>.generate(sourceMeals.length, (slot) {
      final portion = sourceMeals[slot];
      final available = state.availableMeals(slot);
      return available.any((meal) => meal.id == portion.mealId)
          ? portion
          : MealPortion(available.first.id, portion.factor);
    });
    return NextRecommendation(
      date: base.date,
      plan: storedPlan ?? base.plan,
      meals: meals,
      reasons: storedPlan == null
          ? base.reasons
          : const ['以已保存的训练方案为起点；仅你明确采用的调整会更新它。'],
      nutritionReason: base.nutritionReason,
    );
  }

  void _change(
    NextRecommendation base, {
    TrainingPlan? plan,
    List<MealPortion>? meals,
  }) {
    setState(() {
      _draft = NextRecommendation(
        date: base.date,
        plan: plan ?? base.plan,
        meals: meals ?? base.meals,
        reasons: base.reasons,
        nutritionReason: base.nutritionReason,
      );
      _edited = true;
    });
  }

  void _explanation(BuildContext context) {
    showAppSheet<void>(
      context,
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('完成度如何计算', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 20),
            const Text(
              '60% 训练：当天计划中已完成组数的比例。\n30% 餐食：四个餐次的记录完整度。\n10% 饮水：已记录饮水与自设目标的比例。',
              style: TextStyle(height: 2),
            ),
            const SizedBox(height: 18),
            const Text(
              '这项分数表示计划执行与记录情况，不代表生理健康，也不评价饮食是否“好”或“坏”。少吃不会获得额外分数，能量摄入不参与评分。',
              style: TextStyle(color: muted),
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('我知道了'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editTraining(NextRecommendation recommendation) async {
    var minutes = recommendation.plan.minutes;
    var items = List<PlanItem>.from(recommendation.plan.items);
    final result = await showAppSheet<TrainingPlan>(
      context,
      StatefulBuilder(
        builder: (context, update) => ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .85,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('调整明日训练', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  '${recommendation.date} · 调整会先保留为草稿',
                  style: const TextStyle(color: muted),
                ),
                const SizedBox(height: 20),
                Text(
                  '安排时长  $minutes 分钟',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Slider(
                  value: minutes.toDouble(),
                  min: 10,
                  max: 90,
                  divisions: 16,
                  label: '$minutes 分钟',
                  onChanged: (v) => update(() => minutes = v.round()),
                ),
                ...List.generate(items.length, (index) {
                  final item = items[index];
                  final exercise = exerciseById(item.exerciseId);
                  return Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Panel(
                      color: surface2,
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  exercise.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: '移除此动作',
                                onPressed: () =>
                                    update(() => items.removeAt(index)),
                                icon: const Icon(Icons.close, size: 18),
                              ),
                            ],
                          ),
                          _adjuster(
                            '组数',
                            item.sets,
                            1,
                            8,
                            '',
                            (v) => update(
                              () => items[index] = item.copyWith(sets: v),
                            ),
                          ),
                          _adjuster(
                            exercise.timed ? '每组时长' : '每组次数',
                            item.reps,
                            1,
                            120,
                            exercise.timed ? '秒' : '次',
                            (v) => update(
                              () => items[index] = item.copyWith(reps: v),
                            ),
                          ),
                          _adjuster(
                            '组间休息',
                            item.rest,
                            0,
                            300,
                            '秒',
                            (v) => update(
                              () => items[index] = item.copyWith(rest: v),
                            ),
                            step: 15,
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      '已移除全部动作。采用后明日为休息安排。',
                      style: TextStyle(color: sky),
                    ),
                  ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => Navigator.pop(
                    context,
                    recommendation.plan.copyWith(
                      minutes: minutes,
                      items: items,
                    ),
                  ),
                  child: const Text('保留训练调整'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result != null && mounted) _change(recommendation, plan: result);
  }

  Widget _adjuster(
    String label,
    int value,
    int min,
    int max,
    String unit,
    ValueChanged<int> change, {
    int step = 1,
  }) => Row(
    children: [
      Expanded(
        child: Text(label, style: const TextStyle(color: muted, fontSize: 12)),
      ),
      IconButton(
        onPressed: value > min
            ? () => change((value - step).clamp(min, max))
            : null,
        icon: const Icon(Icons.remove_circle_outline, size: 20),
      ),
      SizedBox(
        width: 62,
        child: Text(
          '$value $unit',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      IconButton(
        onPressed: value < max
            ? () => change((value + step).clamp(min, max))
            : null,
        icon: const Icon(Icons.add_circle_outline, size: 20),
      ),
    ],
  );

  Widget _scoreBar(IconData icon, String title, int score, String weight) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: surface2,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 19, color: ink),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title, style: const TextStyle(fontSize: 12)),
                      const SizedBox(width: 6),
                      Text(
                        weight,
                        style: const TextStyle(fontSize: 10, color: muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ThinBar(score / 100),
                ],
              ),
            ),
            const SizedBox(width: 7),
            SizedBox(
              width: 30,
              child: Text(
                '$score',
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );

  String _recoverySummary(RecoveryFeedback? feedback) => feedback == null
      ? '尚未记录睡眠、酸痛和疼痛或不适'
      : '睡眠${['较差', '一般', '良好'][feedback.sleepQuality - 1]} · '
            '酸痛${['无', '轻微', '明显', '较强'][feedback.soreness]} · '
            '${feedback.pain ? '有疼痛或不适' : '无疼痛或不适'}';

  Future<void> _editRecovery(String date) async {
    final previous = state.logs[date]?.recovery;
    var sleep = previous?.sleepQuality ?? 2;
    var soreness = previous?.soreness ?? 0;
    var pain = previous?.pain ?? false;
    var saving = false;
    await showAppSheet<void>(
      context,
      StatefulBuilder(
        builder: (sheetContext, update) => ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .85,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '恢复反馈 · $date',
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                const Text(
                  '按当天感受填写，可随时修改。反馈用于调整训练安排。',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                const SizedBox(height: 18),
                const Text(
                  '睡眠质量',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (var i = 1; i <= 3; i++)
                      ChoiceChip(
                        label: Text(['较差', '一般', '良好'][i - 1]),
                        selected: sleep == i,
                        onSelected: saving
                            ? null
                            : (_) => update(() => sleep = i),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                const Text(
                  '酸痛程度',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (var i = 0; i <= 3; i++)
                      ChoiceChip(
                        label: Text(['无', '轻微', '明显', '较强'][i]),
                        selected: soreness == i,
                        onSelected: saving
                            ? null
                            : (_) => update(() => soreness = i),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                const Text(
                  '疼痛或不适',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('无疼痛或不适'),
                      selected: !pain,
                      onSelected: saving
                          ? null
                          : (_) => update(() => pain = false),
                    ),
                    ChoiceChip(
                      label: const Text('有疼痛或不适'),
                      selected: pain,
                      onSelected: saving
                          ? null
                          : (_) => update(() => pain = true),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          update(() => saving = true);
                          await state.saveRecovery(
                            RecoveryFeedback(
                              sleepQuality: sleep,
                              soreness: soreness,
                              pain: pain,
                            ),
                            date: date,
                          );
                          if (sheetContext.mounted) Navigator.pop(sheetContext);
                          if (mounted) setState(() {});
                        },
                  child: Text(saving ? '正在保存…' : '保存恢复反馈'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _recovery() {
    final date = _recoveryDate ?? state.today;
    final feedback = state.logs[date]?.recovery;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '每日恢复',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.parse(date),
                    firstDate: DateTime(state.now().year - 10),
                    lastDate: DateTime(
                      state.now().year,
                      state.now().month,
                      state.now().day,
                    ),
                  );
                  if (picked != null && mounted) {
                    setState(() => _recoveryDate = dayKey(picked));
                  }
                },
                icon: const Icon(Icons.calendar_today_outlined, size: 16),
                label: Text(date),
              ),
            ],
          ),
          Text(
            _recoverySummary(feedback),
            style: const TextStyle(color: muted, fontSize: 12, height: 1.6),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _editRecovery(date),
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: Text(feedback == null ? '记录恢复' : '修改恢复反馈'),
          ),
        ],
      ),
    );
  }

  Widget _history() {
    final byDate = {for (final log in state.recent(_period)) log.date: log};
    final dates = List.generate(
      _period,
      (i) => dayKey(
        DateTime(
          state.now().year,
          state.now().month,
          state.now().day - _period + 1 + i,
        ),
      ),
    );
    final active = byDate.values.where((l) => l.hasActivity).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final values = dates.map<double?>((date) {
      final log = byDate[date];
      return log == null || !log.hasActivity
          ? null
          : state.scoreFor(log).total.toDouble();
    }).toList();
    final labels = _period == 1
        ? [dates.single.substring(5)]
        : _period == 7
        ? dates.map((d) => d.substring(5).replaceAll('-', '.')).toList()
        : [
            dates.first.substring(5),
            dates[9].substring(5),
            dates[19].substring(5),
            dates.last.substring(5),
          ];
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _period == 1 ? '今日记录' : '最近 $_period 天',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          if (active.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  Icon(Icons.insights_outlined, color: lime, size: 26),
                  SizedBox(height: 8),
                  Text(
                    '这段时间还没有记录',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 6),
                  Text(
                    '完成训练、记录餐食或饮水后，趋势从真实记录开始。',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: muted, fontSize: 11),
                  ),
                ],
              ),
            )
          else ...[
            MiniChart(values, labels),
            const SizedBox(height: 8),
            Text(
              '${active.length} 天有记录 · 空白日期表示未记录',
              style: const TextStyle(color: muted, fontSize: 10),
            ),
            ...active
                .take(3)
                .map(
                  (log) => Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        Text(
                          log.date.substring(5),
                          style: const TextStyle(fontSize: 10),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${log.setCount} 组 · ${log.mealCount} 餐 · ${log.waterMl} ml 水 · ${_time(log.trainingSeconds)}',
                            style: const TextStyle(color: muted, fontSize: 10),
                          ),
                        ),
                        Text(
                          '${state.scoreFor(log).total} 分',
                          style: const TextStyle(color: lime, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ),
            TextButton(
              onPressed: () => _showHistory(active),
              child: const Text('查看全部实际记录'),
            ),
          ],
        ],
      ),
    );
  }

  String _time(int seconds) =>
      seconds < 60 ? '$seconds 秒' : '${seconds ~/ 60} 分 ${seconds % 60} 秒';

  void _showHistory(List<DailyLog> entries) {
    showAppSheet<void>(
      context,
      ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .8,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('实际记录', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              ...entries.map(
                (log) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(log.date),
                      subtitle: Text(
                        '${log.setCount} 组训练 · ${log.mealCount} 餐\n${log.waterMl} ml 水 · ${_time(log.trainingSeconds)}训练',
                      ),
                      trailing: Text('${state.scoreFor(log).total} 分'),
                    ),
                    if (log.recovery != null)
                      Text(
                        _recoverySummary(log.recovery),
                        style: const TextStyle(color: sky, fontSize: 12),
                      ),
                    ...log.completedSets.entries.expand((entry) {
                      final indices = entry.value.toList()..sort();
                      return indices.map((index) {
                        final record = log.setRecords[entry.key]?[index];
                        final actual = record == null
                            ? '仅完成标记，未记录实际次数或时长'
                            : record.timed
                            ? (record.actualSeconds == null
                                  ? '实际秒数未记录'
                                  : '${record.actualSeconds} 秒')
                            : (record.actualReps == null
                                  ? '实际次数未记录'
                                  : '${record.actualReps} 次');
                        final weight = record?.weightKg;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '${exerciseById(entry.key).name} · 第 ${index + 1} 组 · $actual · '
                            '${weight == null ? '重量未记录' : '${weight == weight.roundToDouble() ? weight.toInt() : weight} kg'}'
                            '${record == null ? '' : ' · ${['轻松', '适中', '吃力'][record.fatigue - 1]}'}',
                            style: const TextStyle(
                              color: muted,
                              fontSize: 12,
                              height: 1.6,
                            ),
                          ),
                        );
                      });
                    }),
                    const Divider(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _reasons(NextRecommendation recommendation) {
    showAppSheet<void>(
      context,
      ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .8,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('安排依据', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 14),
              ...recommendation.reasons.map(
                (reason) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    reason,
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                ),
              ),
              Text(
                recommendation.nutritionReason,
                style: const TextStyle(color: muted, fontSize: 12),
              ),
              const SizedBox(height: 14),
              const Text(
                '明日草稿不会改动今天的训练与餐食记录。',
                style: TextStyle(color: sky, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _nextTraining(NextRecommendation recommendation) => Panel(
    padding: const EdgeInsets.all(10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '下一次训练',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          recommendation.plan.items.isEmpty
              ? '休息安排'
              : recommendation.plan.title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          recommendation.plan.items.isEmpty
              ? '明日暂不安排训练动作'
              : '${recommendation.plan.minutes} 分钟 · ${recommendation.plan.items.length} 个动作 · ${recommendation.plan.totalSets} 组',
          style: const TextStyle(color: muted, fontSize: 10),
        ),
        const SizedBox(height: 8),
        Text(
          recommendation.reasons.first,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: muted, fontSize: 10, height: 1.5),
        ),
        if (recommendation.plan.items.isNotEmpty)
          ExerciseThumb(
            exerciseById(recommendation.plan.items.first.exerciseId),
            height: 92,
          ),
        OutlinedButton.icon(
          onPressed: () => _editTraining(recommendation),
          icon: const Icon(Icons.edit_outlined, size: 16),
          label: const Text('调整'),
        ),
      ],
    ),
  );

  Widget _nextMeals(NextRecommendation recommendation) => Panel(
    padding: const EdgeInsets.all(10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '下一次饮食',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          '沿用偏好，调整餐食搭配',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        ...List.generate(recommendation.meals.length, (slot) {
          final portion = recommendation.meals[slot];
          final meal = mealById(portion.mealId);
          return Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: InkWell(
              onTap: () async {
                final value = await chooseMealPortion(
                  context,
                  state,
                  slot,
                  portion,
                );
                if (value != null && mounted) {
                  final meals = List<MealPortion>.from(recommendation.meals)
                    ..[slot] = value;
                  _change(recommendation, meals: meals);
                }
              },
              child: Row(
                children: [
                  MealThumbnail(meal, size: 33),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${mealSlots[slot]} · ${meal.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 10,
                          ),
                        ),
                        Text(
                          '${portion.factor} × · ${meal.nutrients.scale(portion.factor).kcal.round()} kcal',
                          style: const TextStyle(color: muted, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
        const Text('点击餐食替换搭配与份量', style: TextStyle(color: muted, fontSize: 10)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final score = state.score;
    final recommendation = _recommendation;
    final saved = state.tomorrowAdopted && !_edited;
    final trainingSaved = state.tomorrowTrainingAdopted && !_edited;
    final mealsSaved = state.tomorrowMealsAdopted && !_edited;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageTitle(
          eyebrow: 'INSIGHTS',
          title: '复盘与下次安排',
          subtitle: '回看真实记录，按自己的节奏调整。',
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ProgressScreen(state: state),
              ),
            ),
            icon: const Icon(Icons.insights_rounded, color: lavender),
            label: const Text('身体趋势与成长里程碑'),
          ),
        ),
        Row(
          children: [
            for (final period in [1, 7, 30]) ...[
              Expanded(
                child: Pill(
                  period == 1 ? '今日' : '$period 天',
                  active: _period == period,
                  onTap: () => setState(() => _period = period),
                ),
              ),
              if (period != 30) const SizedBox(width: 6),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Panel(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  ScoreRing(score.total, size: 90),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      children: [
                        _scoreBar(
                          Icons.fitness_center,
                          '训练',
                          score.training,
                          '',
                        ),
                        _scoreBar(
                          Icons.restaurant_outlined,
                          '餐食',
                          score.nutrition,
                          '',
                        ),
                        _scoreBar(
                          Icons.water_drop_outlined,
                          '饮水',
                          score.habits,
                          '',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: () => _explanation(context),
                    child: const Text('评分说明 ›', style: TextStyle(fontSize: 11)),
                  ),
                  const Spacer(),
                  const Flexible(
                    child: Text(
                      '权重 60% / 30% / 10%',
                      textAlign: TextAlign.right,
                      style: TextStyle(color: muted, fontSize: 10),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _history(),
        const SizedBox(height: 10),
        _recovery(),
        const SizedBox(height: 10),
        Row(
          children: [
            const Expanded(
              child: Text(
                '明日安排',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
            Tag(
              saved
                  ? '已采用'
                  : _edited
                  ? '已调整 · 待采用'
                  : trainingSaved
                  ? '训练已保存 · 餐食待确认'
                  : mealsSaved
                  ? '餐食已保存 · 训练待确认'
                  : '建议草稿',
            ),
          ],
        ),
        const SizedBox(height: 7),
        Text(
          '${recommendation.date} · ${saved
              ? '下方显示已保存的训练与餐食，可继续调整后再次采用。'
              : trainingSaved
              ? '训练沿用已保存的方案；下方餐食尚未保存，确认后再采用。'
              : mealsSaved
              ? '餐食沿用已保存的安排；下方训练尚未保存，确认后再采用。'
              : '查看理由，按自己的节奏调整，再决定是否采用。'}',
          style: const TextStyle(color: muted, fontSize: 12),
        ),
        const SizedBox(height: 16),
        TwoColumns(
          leftFlex: 1,
          rightFlex: 1,
          breakAt: 600,
          left: _nextTraining(recommendation),
          right: _nextMeals(recommendation),
        ),
        TextButton.icon(
          onPressed: () => _reasons(recommendation),
          icon: const Icon(Icons.lightbulb_outline, size: 16),
          label: const Text('查看安排依据'),
        ),
        const SizedBox(height: 6),
        FilledButton.icon(
          onPressed: _saving || saved
              ? null
              : () async {
                  setState(() => _saving = true);
                  await state.adoptRecommendation(recommendation);
                  if (!context.mounted) return;
                  setState(() {
                    _saving = false;
                    _edited = false;
                    _draft = recommendation;
                  });
                  toast(
                    context,
                    state.storageError ?? '已采用 ${recommendation.date} 的训练与餐食安排',
                  );
                },
          icon: Icon(
            saved ? Icons.check_circle_outline : Icons.arrow_forward,
            size: 19,
          ),
          label: Text(
            _saving
                ? '正在保存…'
                : saved
                ? '已保存 · 调整后可再次采用'
                : trainingSaved
                ? '保存餐食并保留训练'
                : mealsSaved
                ? '保存训练并保留餐食'
                : '采用下次安排',
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          '建议依据近期记录生成，训练日程由你决定。点击采用只保存明日安排。',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted, fontSize: 11),
        ),
      ],
    );
  }
}
