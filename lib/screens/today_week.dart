import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/models.dart';
import '../ui/components.dart';
import '../ui/theme.dart';

/// Reads historical snapshots without creating plans or logs on calendar taps.
class TodayWeek extends StatelessWidget {
  final AppState state;
  const TodayWeek({super.key, required this.state});
  static const weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final now = state.now();
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        children: List.generate(7, (i) {
          final date = DateTime(
            now.year,
            now.month,
            now.day - now.weekday + 1 + i,
          );
          final info = _DayInfo(state, date);
          final today = info.key == state.today;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Tooltip(
                message: '${date.month}月${date.day}日 · ${info.status}',
                child: Semantics(
                  selected: today,
                  child: Material(
                    color: today
                        ? lime.withValues(alpha: .12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(15),
                    child: InkWell(
                      onTap: () => _openDay(context, info),
                      borderRadius: BorderRadius.circular(15),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        child: Column(
                          children: [
                            Text(
                              today ? '今天' : '周${weekdays[i]}',
                              style: TextStyle(
                                fontSize: 11,
                                color: today ? lime : muted,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${date.day}',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: today ? lime : ink,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              info.completed
                                  ? '完成'
                                  : info.done > 0
                                  ? '部分'
                                  : info.recorded > 0
                                  ? '练过'
                                  : !info.trainingDay
                                  ? '休息'
                                  : info.key.compareTo(state.today) < 0
                                  ? '未记'
                                  : '训练',
                              style: TextStyle(
                                fontSize: 10,
                                color: today ? lime : info.color,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  void _openDay(BuildContext context, _DayInfo info) {
    showAppSheet(
      context,
      SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${info.date.month}月${info.date.day}日 · 周${weekdays[info.date.weekday - 1]}',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(info.icon, color: info.color, size: 19),
                const SizedBox(width: 8),
                Text(
                  info.status,
                  style: TextStyle(color: info.color, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (info.log?.hasActivity ?? false) ...[
              Text(
                info.plan?.title ?? '当天记录',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text('训练已记录 ${info.recorded} 组'),
              const SizedBox(height: 8),
              Text(
                '餐食已记录 ${info.log!.mealCount} 餐 · ${state.nutritionForDate(info.key).kcal.round()} kcal',
              ),
              const SizedBox(height: 8),
              Text('饮水 ${info.log!.waterMl} ml'),
            ] else ...[
              Text(
                info.future
                    ? (info.trainingDay
                          ? '计划训练 · ${info.schedule.title}'
                          : '留一些时间休息恢复')
                    : '这一天没有记录',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                info.plan == null
                    ? '日程标记参考当前每周设置；没有记录的日期不推断实际完成情况。'
                    : '${info.plan!.title} · ${info.plan!.minutes} 分钟\n尚未记录训练、餐食或饮水。',
                style: const TextStyle(color: muted, fontSize: 13, height: 1.7),
              ),
            ],
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayInfo {
  final AppState state;
  final DateTime date;
  _DayInfo(this.state, this.date);
  String get key => dayKey(date);
  TrainingPlan? get plan => state.plans[key];
  TrainingPlan get schedule => plan ?? state.template;
  DailyLog? get log => state.logs[key];
  bool get future => key.compareTo(state.today) > 0;
  bool get trainingDay =>
      schedule.days.contains(date.weekday) && schedule.items.isNotEmpty;
  int get recorded => log?.setCount ?? 0;
  int get done =>
      plan?.items.fold<int>(
        0,
        (n, item) =>
            n +
            (log?.completedSets[item.exerciseId] ?? <int>{})
                .where((v) => v >= 0 && v < item.sets)
                .length,
      ) ??
      log?.setCount ??
      0;
  bool get completed => (plan?.totalSets ?? 0) > 0 && done >= plan!.totalSets;
  String get status => completed
      ? '已完成'
      : done > 0
      ? '部分完成'
      : recorded > 0
      ? '已训练'
      : !trainingDay
      ? '休息日'
      : key.compareTo(state.today) < 0
      ? '未记录'
      : '训练日';
  IconData get icon => completed
      ? Icons.check_circle_rounded
      : recorded > 0
      ? Icons.timelapse_rounded
      : !trainingDay
      ? Icons.nights_stay_outlined
      : Icons.circle_outlined;
  Color get color => completed || recorded > 0
      ? lime
      : !trainingDay
      ? sky
      : muted;
}
