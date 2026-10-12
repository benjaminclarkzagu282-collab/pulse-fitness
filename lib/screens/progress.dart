import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/body_metrics.dart';
import '../core/progress_summary.dart';
import '../ui/components.dart';
import '../ui/theme.dart';

class ProgressScreen extends StatefulWidget {
  final AppState state;
  const ProgressScreen({super.key, required this.state});
  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  int days = 7;
  BodyMetric metric = BodyMetric.weight;
  AppState get state => widget.state;

  Future<void> editBody([BodyRecord? record]) =>
      showAppSheet<void>(context, _BodyForm(state: state, record: record));

  Future<void> removeBody(BodyRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除身体记录？'),
        content: Text('将删除 ${record.date} 的体重、腰围和备注。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) await state.removeBodyRecord(record.date);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: state,
    builder: (context, _) {
      final summary = ProgressSummary.fromLogs(
        state.logs.values,
        today: state.today,
      );
      final records = state.bodyRecords.values.toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      final weight = BodySeries(
        records,
        today: state.today,
        days: days,
        metric: BodyMetric.weight,
      );
      final waist = BodySeries(
        records,
        today: state.today,
        days: days,
        metric: BodyMetric.waist,
      );
      final series = metric == BodyMetric.weight ? weight : waist;
      return Scaffold(
        appBar: AppBar(title: const Text('我的成长')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                children: [
                  if (state.storageError != null)
                    MaterialBanner(
                      key: const Key('progress-storage-error'),
                      backgroundColor: surface2,
                      leading: const Icon(
                        Icons.error_outline,
                        color: Color(0xFFE6AB92),
                      ),
                      content: Text(state.storageError!),
                      forceActionsBelow: true,
                      actions: [
                        TextButton(
                          key: const Key('progress-storage-retry'),
                          onPressed: state.retrySave,
                          child: Text(
                            state.storageFailure == StorageFailure.load
                                ? '重试读取'
                                : '重试保存',
                          ),
                        ),
                      ],
                    ),
                  Expanded(
                    key: const Key('progress-scroll-content'),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                      children: [
                        const Text(
                          '每一次投入，都留下了痕迹',
                          style: TextStyle(
                            color: lime,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '看见自己的成长',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '从真实训练与饮食记录中，回看你走过的路。',
                          style: TextStyle(color: muted, fontSize: 13),
                        ),
                        const SizedBox(height: 24),
                        LayoutBuilder(
                          builder: (context, constraints) => Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              _Stat(
                                width: (constraints.maxWidth - 12) / 2,
                                value: '${summary.trainingDays}',
                                label: '累计训练天数',
                                unit: '天',
                                icon: Icons.calendar_today_outlined,
                              ),
                              _Stat(
                                width: (constraints.maxWidth - 12) / 2,
                                value: '${summary.completedSets}',
                                label: '累计完成组数',
                                unit: '组',
                                icon: Icons.fitness_center,
                                accent: sky,
                              ),
                              _Stat(
                                width: (constraints.maxWidth - 12) / 2,
                                value: _duration(summary.followAlongSeconds),
                                label: '已记录跟练时间',
                                unit: '',
                                icon: Icons.timer_outlined,
                                accent: const Color(0xFFB6A6E9),
                              ),
                              _Stat(
                                width: (constraints.maxWidth - 12) / 2,
                                value: '${summary.foodDays}',
                                label: '实际饮食记录天数',
                                unit: '天',
                                icon: Icons.restaurant_outlined,
                                accent: const Color(0xFFE6AB92),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '完成组来自你的打卡；跟练时间仅统计已保存的实际秒数。',
                          style: TextStyle(color: muted, fontSize: 11),
                        ),
                        const SizedBox(height: 26),
                        const SectionTitle('我的里程碑'),
                        if (summary.earnedMilestones.isEmpty)
                          const Panel(
                            child: Row(
                              children: [
                                Icon(Icons.auto_awesome_outlined, color: lime),
                                SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                    '完成第一组训练后，点亮你的第一个里程碑。',
                                    style: TextStyle(color: muted),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          ...summary.earnedMilestones.map(
                            (milestone) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Panel(
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(11),
                                      decoration: BoxDecoration(
                                        color: lime.withValues(alpha: .1),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: const Icon(
                                        Icons.check_circle_outline,
                                        color: lime,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            milestone.title,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            milestone.detail,
                                            style: const TextStyle(
                                              color: muted,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        if (summary.earnedMilestones.length < 4) ...[
                          const SizedBox(height: 10),
                          Panel(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '下一步，按自己的节奏',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 10),
                                if (summary.trainingDays < 3)
                                  _MilestoneProgress(
                                    '训练天数',
                                    summary.trainingDays,
                                    3,
                                    '天',
                                  ),
                                if (summary.completedSets < 50)
                                  _MilestoneProgress(
                                    '累计组数',
                                    summary.completedSets,
                                    50,
                                    '组',
                                  ),
                                if (summary.foodDays < 7)
                                  _MilestoneProgress(
                                    '饮食记录',
                                    summary.foodDays,
                                    7,
                                    '天',
                                  ),
                                const Text(
                                  '按累计记录计算，无需连续每天训练。',
                                  style: TextStyle(color: muted, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 26),
                        const SectionTitle('身体记录'),
                        const Text(
                          '体重与腰围可分别记录。变化没有统一方向，按自己的节奏观察。',
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: _MetricCard(
                                title: '最新体重',
                                point: weight.latest,
                                unit: 'kg',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _MetricCard(
                                title: '最新腰围',
                                point: waist.latest,
                                unit: 'cm',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          key: const Key('add-body-record'),
                          onPressed: () => editBody(),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('记录身体数据'),
                        ),
                        const SizedBox(height: 18),
                        Panel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  ChoiceChip(
                                    label: const Text('体重'),
                                    selected: metric == BodyMetric.weight,
                                    onSelected: (_) => setState(
                                      () => metric = BodyMetric.weight,
                                    ),
                                  ),
                                  ChoiceChip(
                                    label: const Text('腰围'),
                                    selected: metric == BodyMetric.waist,
                                    onSelected: (_) => setState(
                                      () => metric = BodyMetric.waist,
                                    ),
                                  ),
                                  ChoiceChip(
                                    label: const Text('7 天'),
                                    selected: days == 7,
                                    onSelected: (_) => setState(() => days = 7),
                                  ),
                                  ChoiceChip(
                                    label: const Text('30 天'),
                                    selected: days == 30,
                                    onSelected: (_) =>
                                        setState(() => days = 30),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              if (series.points.isEmpty)
                                const SizedBox(
                                  height: 120,
                                  child: Center(
                                    child: Text(
                                      '这段时间还没有测量记录',
                                      style: TextStyle(color: muted),
                                    ),
                                  ),
                                )
                              else ...[
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '${series.maxY.toStringAsFixed(1)} ${metric == BodyMetric.weight ? 'kg' : 'cm'}',
                                      style: const TextStyle(
                                        color: muted,
                                        fontSize: 11,
                                      ),
                                    ),
                                    Text(
                                      '仅显示真实测量点',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Semantics(
                                  label: series.points
                                      .map(
                                        (p) =>
                                            '${p.date} ${_number(p.value)} ${metric == BodyMetric.weight ? 'kg' : 'cm'}',
                                      )
                                      .join('；'),
                                  child: SizedBox(
                                    height: 120,
                                    width: double.infinity,
                                    child: CustomPaint(
                                      painter: _BodyChart(series),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${series.minY.toStringAsFixed(1)} ${metric == BodyMetric.weight ? 'kg' : 'cm'}',
                                  style: const TextStyle(
                                    color: muted,
                                    fontSize: 11,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                if (series.points.length == 1)
                                  const Text(
                                    '等待下一次记录，形成趋势',
                                    style: TextStyle(
                                      color: muted,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    series.start.substring(5),
                                    style: const TextStyle(
                                      color: muted,
                                      fontSize: 11,
                                    ),
                                  ),
                                  Text(
                                    series.end.substring(5),
                                    style: const TextStyle(
                                      color: muted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                '未测量的日期留空，不补零、不推算。',
                                style: TextStyle(color: muted, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        const SectionTitle('测量历史'),
                        if (records.isEmpty)
                          const Panel(
                            child: Text(
                              '还没有身体记录。填写一次测量，开始自己的观察。',
                              style: TextStyle(color: muted),
                            ),
                          )
                        else
                          ...records.map(
                            (record) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Panel(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      record.date,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 16,
                                      runSpacing: 6,
                                      children: [
                                        if (record.weightKg != null)
                                          Text(
                                            '体重 ${_number(record.weightKg!)} kg',
                                          ),
                                        if (record.waistCm != null)
                                          Text(
                                            '腰围 ${_number(record.waistCm!)} cm',
                                          ),
                                      ],
                                    ),
                                    if (record.note.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        record.note,
                                        style: const TextStyle(
                                          color: muted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        TextButton.icon(
                                          key: Key('edit-body-${record.date}'),
                                          onPressed: () => editBody(record),
                                          icon: const Icon(
                                            Icons.edit_outlined,
                                            size: 16,
                                          ),
                                          label: const Text('编辑'),
                                        ),
                                        TextButton.icon(
                                          key: Key(
                                            'remove-body-${record.date}',
                                          ),
                                          onPressed: () => removeBody(record),
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            size: 16,
                                          ),
                                          label: const Text('删除'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

String _number(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(1);
String _duration(int seconds) {
  if (seconds < 60) return '$seconds 秒';
  if (seconds < 3600) return '${seconds ~/ 60} 分 ${seconds % 60} 秒';
  return '${seconds ~/ 3600} 时 ${(seconds % 3600) ~/ 60} 分';
}

class _Stat extends StatelessWidget {
  final double width;
  final String value, label, unit;
  final IconData icon;
  final Color accent;
  const _Stat({
    required this.width,
    required this.value,
    required this.label,
    required this.unit,
    required this.icon,
    this.accent = lime,
  });
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 22),
          const SizedBox(height: 16),
          Text(
            value,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
          ),
          if (unit.isNotEmpty)
            Text(unit, style: const TextStyle(color: muted, fontSize: 11)),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: muted, fontSize: 12)),
        ],
      ),
    ),
  );
}

class _MetricCard extends StatelessWidget {
  final String title, unit;
  final BodyPoint? point;
  const _MetricCard({
    required this.title,
    required this.point,
    required this.unit,
  });
  @override
  Widget build(BuildContext context) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: muted, fontSize: 12)),
        const SizedBox(height: 10),
        Text(
          point == null ? '—' : _number(point!.value),
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
        ),
        Text(unit, style: const TextStyle(color: muted, fontSize: 11)),
        const SizedBox(height: 6),
        Text(
          point?.date ?? '尚未测量',
          style: const TextStyle(color: muted, fontSize: 11),
        ),
      ],
    ),
  );
}

class _MilestoneProgress extends StatelessWidget {
  final String title, unit;
  final int current, target;
  const _MilestoneProgress(this.title, this.current, this.target, this.unit);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$title $current/$target · 还差 ${target - current} $unit',
          style: const TextStyle(color: muted, fontSize: 12),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: current / target,
            minHeight: 4,
            backgroundColor: surface2,
            color: sky,
          ),
        ),
      ],
    ),
  );
}

class _BodyChart extends CustomPainter {
  final BodySeries series;
  _BodyChart(this.series);
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = line
      ..strokeWidth = 1;
    for (var row = 0; row <= 2; row++) {
      final y = row * size.height / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final span = DateTime.parse(series.end)
        .difference(DateTime.parse(series.start))
        .inDays;
    for (final point in series.points) {
      final elapsed = DateTime.parse(point.date)
          .difference(DateTime.parse(series.start))
          .inDays;
      final x = 6 + (size.width - 12) * elapsed / (span == 0 ? 1 : span);
      final y =
          6 +
          (size.height - 12) *
              (1 - (point.value - series.minY) / (series.maxY - series.minY));
      canvas.drawCircle(
        Offset(x, y),
        9,
        Paint()..color = lime.withValues(alpha: .12),
      );
      canvas.drawCircle(Offset(x, y), 4, Paint()..color = lime);
    }
  }

  @override
  bool shouldRepaint(_BodyChart oldDelegate) => oldDelegate.series != series;
}

class _BodyForm extends StatefulWidget {
  final AppState state;
  final BodyRecord? record;
  const _BodyForm({required this.state, this.record});
  @override
  State<_BodyForm> createState() => _BodyFormState();
}

class _BodyFormState extends State<_BodyForm> {
  final form = GlobalKey<FormState>();
  late final TextEditingController weight, waist, note;
  late String date;
  bool saving = false;
  @override
  void initState() {
    super.initState();
    date = widget.record?.date ?? widget.state.today;
    final initial = widget.record ?? widget.state.bodyRecords[date];
    weight = TextEditingController(text: initial?.weightKg?.toString() ?? '');
    waist = TextEditingController(text: initial?.waistCm?.toString() ?? '');
    note = TextEditingController(text: initial?.note ?? '');
  }

  @override
  void dispose() {
    weight.dispose();
    waist.dispose();
    note.dispose();
    super.dispose();
  }

  String? measurement(String? text, double min, double max) {
    if (text == null || text.trim().isEmpty) return null;
    final value = double.tryParse(text.trim());
    return value == null || !value.isFinite || value < min || value > max
        ? '请输入 $min–$max 内的数值'
        : null;
  }

  Future<void> pickDate() async {
    final chosen = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(date),
      firstDate: DateTime(1900),
      lastDate: DateTime.parse(widget.state.today),
    );
    if (chosen == null || !mounted) return;
    setState(() {
      date =
          '${chosen.year}-${chosen.month.toString().padLeft(2, '0')}-${chosen.day.toString().padLeft(2, '0')}';
      final record = widget.state.bodyRecords[date];
      weight.text = record?.weightKg?.toString() ?? '';
      waist.text = record?.waistCm?.toString() ?? '';
      note.text = record?.note ?? '';
    });
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    if (weight.text.trim().isEmpty && waist.text.trim().isEmpty) {
      toast(context, '请至少填写体重或腰围。');
      return;
    }
    if (widget.record == null && widget.state.bodyRecords.containsKey(date)) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('更新该日身体记录？'),
          content: Text('$date 已有测量记录。确认后使用当前体重、腰围和备注替换该日记录；留空的测量项也会清除。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认更新'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => saving = true);
    try {
      await widget.state.saveBodyRecord(
        BodyRecord(
          date,
          weightKg: weight.text.trim().isEmpty
              ? null
              : double.parse(weight.text.trim()),
          waistCm: waist.text.trim().isEmpty
              ? null
              : double.parse(waist.text.trim()),
          note: note.text.trim(),
        ),
      );
      if (!mounted) return;
      final message = widget.state.storageError ?? '身体记录已保存。';
      Navigator.pop(context);
      toast(context, message);
    } catch (error) {
      if (mounted) {
        setState(() => saving = false);
        toast(
          context,
          error is ArgumentError ? error.message.toString() : '保存未完成，请重试。',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
    child: Form(
      key: form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.record == null ? '记录身体数据' : '编辑身体记录',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            '至少填写一项；同一天的保存会更新该日记录。',
            style: TextStyle(color: muted, fontSize: 12),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: widget.record == null && !saving ? pickDate : null,
            icon: const Icon(Icons.calendar_today_outlined, size: 18),
            label: Text(date),
          ),
          const SizedBox(height: 14),
          TextFormField(
            key: const Key('body-weight'),
            controller: weight,
            decoration: const InputDecoration(labelText: '体重（kg）'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (v) => measurement(v, 20, 350),
          ),
          const SizedBox(height: 14),
          TextFormField(
            key: const Key('body-waist'),
            controller: waist,
            decoration: const InputDecoration(labelText: '腰围（cm）'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (v) => measurement(v, 30, 250),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: note,
            decoration: const InputDecoration(labelText: '备注（可选）'),
            maxLength: 200,
            minLines: 1,
            maxLines: 3,
            validator: (v) => (v?.length ?? 0) > 200 ? '备注最多 200 字' : null,
          ),
          const SizedBox(height: 14),
          FilledButton(
            key: const Key('save-body-record'),
            onPressed: saving ? null : save,
            child: Text(saving ? '保存中…' : '保存记录'),
          ),
        ],
      ),
    ),
  );
}
