import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../ui/components.dart';
import '../ui/theme.dart';
import 'today_week.dart';
import 'workout.dart';
import 'programs.dart';
import 'progress.dart';

class TodayScreen extends StatelessWidget {
  final AppState state;
  final ValueChanged<int> navigate;
  const TodayScreen({super.key, required this.state, required this.navigate});

  @override
  Widget build(BuildContext context) {
    final date = state.now();
    final plan = state.plan;
    final done = plan.items.fold<int>(
      0,
      (n, item) => n + state.completedSetsFor(item.exerciseId),
    );
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final training = _TrainingCard(
      state: state,
      done: done,
      navigate: navigate,
    );
    final quick = _QuickRecords(state: state, navigate: navigate);
    final progress = _Progress(state: state, onTap: () => navigate(4));
    final next = _NextSession(state: state, onTap: () => navigate(4));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageTitle(
          eyebrow: 'MAKE ROOM FOR YOURSELF',
          title: '今天，也要动起来',
          subtitle:
              '${date.month}月${date.day}日 · 周${TodayWeek.weekdays[date.weekday - 1]} · 按自己的节奏',
        ),
        TodayWeek(state: state),
        if (wide) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: Column(children: [training])),
              const SizedBox(width: 24),
              Expanded(flex: 5, child: Column(children: [quick])),
            ],
          ),
        ] else ...[
          training,
          const SizedBox(height: 24),
          _QuickActions(state: state, navigate: navigate),
          const SizedBox(height: 24),
          quick,
        ],
        if (wide) ...[
          const SizedBox(height: 24),
          _QuickActions(state: state, navigate: navigate),
        ],
        const SizedBox(height: 24),
        _OverviewStrip(state: state),
        const SizedBox(height: 24),
        TwoColumns(
          leftFlex: 1,
          rightFlex: 1,
          breakAt: 700,
          left: Panel(child: progress),
          right: next,
        ),
      ],
    );
  }
}

class _TrainingCard extends StatelessWidget {
  final AppState state;
  final int done;
  final ValueChanged<int> navigate;
  const _TrainingCard({
    required this.state,
    required this.done,
    required this.navigate,
  });

  @override
  Widget build(BuildContext context) {
    final plan = state.plan;
    final restDay = !plan.days.contains(state.now().weekday);
    final complete = plan.totalSets > 0 && done >= plan.totalSets;
    if (plan.items.isEmpty) {
      return EmptyHint(
        icon: Icons.self_improvement,
        title: '今天，留一点时间给自己',
        detail: '可以休息，也可以添加动作，按你的节奏安排训练。',
        action: FilledButton(
          onPressed: () => navigate(2),
          child: const Text('添加动作'),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/editorial-training-v1.png',
              fit: BoxFit.cover,
              alignment: Alignment.centerRight,
              excludeFromSemantics: true,
              errorBuilder: (_, _, _) => const ColoredBox(color: surface),
            ),
          ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xE6111214),
                    Color(0x88111214),
                    Color(0xD9111214),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Tag('今日训练'),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => navigate(1),
                      icon: const Icon(Icons.tune_rounded, size: 15),
                      label: const Text('调整计划', style: TextStyle(fontSize: 11)),
                      style: TextButton.styleFrom(foregroundColor: ink),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Text(
                  plan.title,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.9,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 14,
                  runSpacing: 8,
                  children: [
                    _HeroFact(Icons.schedule_rounded, '预计 ${plan.minutes} 分钟'),
                    _HeroFact(Icons.fitness_center_rounded, plan.equipment),
                    _HeroFact(
                      Icons.layers_outlined,
                      '${plan.items.length} 个动作 · ${plan.totalSets} 组',
                    ),
                  ],
                ),
                const SizedBox(height: 26),
                Text(
                  complete
                      ? '今日训练已完成'
                      : done > 0
                      ? '已完成 $done / ${plan.totalSets} 组'
                      : restDay
                      ? '休息日 · 自主安排'
                      : '准备好，开始今天的训练',
                  style: const TextStyle(
                    fontSize: 12,
                    color: lime,
                    height: 1.6,
                  ),
                ),
                if (done > 0) ...[
                  const SizedBox(height: 10),
                  ThinBar(done / plan.totalSets, height: 5),
                ],
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: () => openWorkout(context, state),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        complete
                            ? '查看今日训练'
                            : done > 0
                            ? '继续训练'
                            : '开始训练',
                      ),
                      const Icon(Icons.arrow_forward_rounded, size: 20),
                    ],
                  ),
                ),
                if (restDay && done == 0) ...[
                  const SizedBox(height: 10),
                  const Text(
                    '今天按周计划休息，也可以按状态自主训练。',
                    style: TextStyle(fontSize: 11, color: muted, height: 1.5),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroFact extends StatelessWidget {
  final IconData icon;
  final String text;
  const _HeroFact(this.icon, this.text);
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: ink),
      const SizedBox(width: 6),
      Text(text, style: const TextStyle(fontSize: 11, color: ink)),
    ],
  );
}

class _QuickActions extends StatelessWidget {
  final AppState state;
  final ValueChanged<int> navigate;
  const _QuickActions({required this.state, required this.navigate});
  void open(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth < 580 ? 2 : 4;
      final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
      final entries = <(String, String, IconData, Color, VoidCallback, Key)>[
        (
          '训练方案',
          '预览 · 按需采用',
          Icons.dashboard_customize_outlined,
          lime,
          () => open(context, ProgramsScreen(state: state)),
          const Key('open-programs'),
        ),
        (
          '身体记录',
          '体重 · 腰围趋势',
          Icons.monitor_weight_outlined,
          lavender,
          () => open(context, ProgressScreen(state: state)),
          const Key('quick-progress'),
        ),
        (
          '动作示范',
          '24 个动作 · 分阶段',
          Icons.view_in_ar_rounded,
          sky,
          () => navigate(2),
          const Key('quick-library'),
        ),
        (
          '饮食记录',
          '按克数记录摄入',
          Icons.restaurant_menu_rounded,
          coral,
          () => navigate(3),
          const Key('quick-nutrition'),
        ),
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle('按你的节奏探索'),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final entry in entries)
                SizedBox(
                  width: width,
                  child: Material(
                    color: surface,
                    borderRadius: BorderRadius.circular(18),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      key: entry.$6,
                      onTap: entry.$5,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(entry.$3, color: entry.$4, size: 25),
                            const SizedBox(height: 14),
                            Text(
                              entry.$1,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              entry.$2,
                              style: const TextStyle(
                                fontSize: 10,
                                color: muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      );
    },
  );
}

class _OverviewStrip extends StatelessWidget {
  final AppState state;
  const _OverviewStrip({required this.state});
  @override
  Widget build(BuildContext context) {
    final recent = state.recent(7);
    final trainingDays = recent.where((log) => log.setCount > 0).length;
    final sets = recent.fold<int>(0, (total, log) => total + log.setCount);
    final foodDays = recent.where((log) => log.mealCount > 0).length;
    final metrics = [
      ('$trainingDays', '训练天数', lime),
      ('$sets', '完成组数', sky),
      ('$foodDays', '饮食记录天数', coral),
    ];
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '最近 7 天',
            style: TextStyle(
              color: muted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final (index, metric) in metrics.indexed) ...[
                if (index > 0)
                  Container(
                    width: 1,
                    height: 39,
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    color: line,
                  ),
                Expanded(child: Stat(metric.$1, metric.$2, color: metric.$3)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickRecords extends StatelessWidget {
  final AppState state;
  final ValueChanged<int> navigate;
  const _QuickRecords({required this.state, required this.navigate});

  @override
  Widget build(BuildContext context) {
    final targets = state.targetsForDate(state.today);
    final hasMeals = state.log.completedMealSlots.isNotEmpty;
    final food = state.nutrition;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '补充能量，也别忘了喝水',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 13),
        _QuietCard(
          color: const Color(0xFF22251E),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.restaurant_rounded, size: 22, color: lime),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      hasMeals ? '已摄入 ${food.kcal.round()} kcal' : '尚未记录餐食',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (hasMeals)
                    Text(
                      '${state.log.mealCount} 餐',
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '目标 ${targets.calories} kcal${hasMeals ? ' · 按已记录餐食统计' : ' · 记录后查看摄入情况'}',
                style: const TextStyle(fontSize: 12, color: muted, height: 1.6),
              ),
              if (hasMeals) ...[
                const SizedBox(height: 8),
                Text(
                  '蛋白质 ${food.protein.round()}g  ·  碳水 ${food.carbs.round()}g  ·  脂肪 ${food.fat.round()}g',
                  style: const TextStyle(color: ink, fontSize: 12, height: 1.6),
                ),
              ],
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => navigate(3),
                child: Text(hasMeals ? '继续记录餐食' : '记录第一餐'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _QuietCard(
          color: const Color(0xFF1C252C),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.water_drop_outlined, color: sky, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '今日饮水',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${state.log.waterMl} / ${targets.water} ml',
                          style: const TextStyle(fontSize: 12, color: muted),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    key: const Key('quick-water'),
                    onPressed: () => _water(context),
                    style: TextButton.styleFrom(
                      foregroundColor: sky,
                      minimumSize: const Size(90, 44),
                      backgroundColor: sky.withValues(alpha: .09),
                    ),
                    child: const Text(
                      '+ 250 ml',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ThinBar(state.log.waterMl / targets.water, height: 4, color: sky),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _water(BuildContext context) async {
    final date = state.today;
    final before = state.log.waterMl;
    final save = state.addWater(250, date: date);
    final added = (state.logs[date]?.waterMl ?? before) - before;
    await save;
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(added > 0 ? '已记录 $added ml 饮水' : '今日饮水记录已达上限'),
          action: added > 0
              ? SnackBarAction(
                  label: '撤销',
                  textColor: bg,
                  onPressed: () => state.addWater(-added, date: date),
                )
              : null,
        ),
      );
  }
}

class _Progress extends StatelessWidget {
  final AppState state;
  final VoidCallback onTap;
  const _Progress({required this.state, required this.onTap});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          const Expanded(
            child: Text(
              '今日进度',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
          TextButton(
            onPressed: onTap,
            child: const Text('查看评分 ›', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
      const SizedBox(height: 3),
      Row(
        children: [
          if (state.log.hasActivity) ...[
            Text(
              '${state.score.total}',
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: lime,
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(left: 5, right: 14),
              child: Text(
                '/ 100',
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ),
          ] else ...[
            const Icon(Icons.eco_outlined, color: lime, size: 24),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              state.log.hasActivity ? '每一份记录，都算进今天的进步' : '还没开始，按自己的节奏来',
              style: const TextStyle(fontSize: 13, color: muted, height: 1.6),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      ThinBar(state.score.total / 100, height: 5),
    ],
  );
}

class _NextSession extends StatelessWidget {
  final AppState state;
  final VoidCallback onTap;
  const _NextSession({required this.state, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final saved = state.tomorrowTrainingAdopted;
    final recommendation = state.recommendation;
    final next = state.plans[state.tomorrow] ?? recommendation.plan;
    final date = DateTime.parse(state.tomorrow);
    final reasons = recommendation.reasons
        .where((r) => !r.startsWith('建议可调整'))
        .toList();
    // Surface the training-load change before the muscle rotation when applicable.
    if (reasons.length > 1) {
      final load = reasons.removeAt(1);
      reasons.insert(0, load);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '接下来，怎么安排',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 13),
        _QuietCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    saved ? Icons.event_available : Icons.auto_awesome_outlined,
                    color: lime,
                    size: 19,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '明日 · ${date.month}月${date.day}日 · ${saved ? '已保存' : '待确认'}',
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                next.title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '${next.minutes} 分钟 · ${next.totalSets} 组${next.days.contains(date.weekday) ? '' : ' · 按周计划为休息日'}',
                style: const TextStyle(fontSize: 12, color: muted),
              ),
              const SizedBox(height: 12),
              Text(
                saved
                    ? state.tomorrowAdopted
                          ? '已保存你的安排，可在记录页继续调整。'
                          : '训练已保存，可在记录页确认明日餐食。'
                    : reasons.join('\n'),
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFFBDC8B8),
                  height: 1.7,
                ),
              ),
              if (!saved) ...[
                const SizedBox(height: 10),
                Text(
                  '餐食：参考热量、蛋白质、碳水和脂肪目标及近期摄入，沿用偏好与份量；在建议页查看依据。',
                  style: const TextStyle(
                    fontSize: 12,
                    color: muted,
                    height: 1.7,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: onTap,
                child: Text(saved ? '查看明日安排' : '查看并调整建议'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuietCard extends StatelessWidget {
  final Widget child;
  final Color color;
  const _QuietCard({required this.child, this.color = surface});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: line.withValues(alpha: .45)),
    ),
    child: child,
  );
}
