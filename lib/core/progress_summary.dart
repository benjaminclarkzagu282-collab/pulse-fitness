import 'models.dart';

class ProgressMilestone {
  final String id, title, detail;
  const ProgressMilestone(this.id, this.title, this.detail);
}

/// Computed each time from actual logs; earning does not create stored counters.
class ProgressSummary {
  final int trainingDays, completedSets, followAlongSeconds, foodDays;
  final List<ProgressMilestone> earnedMilestones;
  const ProgressSummary._(
    this.trainingDays,
    this.completedSets,
    this.followAlongSeconds,
    this.foodDays,
    this.earnedMilestones,
  );
  factory ProgressSummary.fromLogs(
    Iterable<DailyLog> logs, {
    required String today,
  }) {
    final byDate = <String, DailyLog>{
      for (final log in logs)
        if (validDayKey(log.date) && log.date.compareTo(today) <= 0)
          log.date: log,
    };
    var trainingDays = 0, sets = 0, seconds = 0, foodDays = 0;
    for (final log in byDate.values) {
      final count = log.completedSets.values.fold<int>(
        0,
        (n, s) => n + s.where((index) => index >= 0 && index < 8).length,
      );
      if (count > 0) trainingDays++;
      sets += count;
      if (log.trainingSeconds > 0) seconds += log.trainingSeconds;
      if (log.meals.isNotEmpty || log.foodEntries.isNotEmpty) foodDays++;
    }
    final earned = <ProgressMilestone>[
      if (sets > 0)
        const ProgressMilestone('first-set', '第一组，已完成', '从一次真实行动开始'),
      if (trainingDays >= 3)
        const ProgressMilestone('three-days', '累计训练 3 天', '每次回到训练，都算成长'),
      if (sets >= 50)
        const ProgressMilestone('fifty-sets', '累计完成 50 组', '你记录的投入正在积累'),
      if (foodDays >= 7)
        const ProgressMilestone('seven-food-days', '记录饮食 7 天', '慢慢认识自己的饮食节奏'),
    ];
    return ProgressSummary._(
      trainingDays,
      sets,
      seconds,
      foodDays,
      List.unmodifiable(earned),
    );
  }
}
