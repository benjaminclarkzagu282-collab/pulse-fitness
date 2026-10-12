import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/catalog.dart';
import '../core/models.dart';
import '../core/training_programs.dart';
import '../ui/components.dart';
import '../ui/theme.dart';

class ProgramsScreen extends StatelessWidget {
  final AppState state;
  final ValueChanged<String>? onAdopted;
  const ProgramsScreen({super.key, required this.state, this.onAdopted});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('训练方案')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const PageTitle(
                  eyebrow: 'FIND YOUR NEXT SESSION',
                  title: '从一套可完成的训练开始',
                  subtitle: '四套参考方案，采纳后可在计划页调整。',
                ),
                const Text(
                  '以下为通用参考安排，请按你的状态调整组数、次数和休息。预览不会修改计划。',
                  style: TextStyle(color: muted, height: 1.7),
                ),
                const SizedBox(height: 20),
                for (final entry in trainingPrograms.indexed) ...[
                  _ProgramCard(
                    program: entry.$2,
                    color: const [lime, sky, coral, lavender][entry.$1],
                    onPreview: () async {
                      // Read the saved choice without creating any dated data.
                      final today = state.today;
                      final openedDate = DateTime.parse(today);
                      final days = (state.plans[today] ?? state.template).days;
                      final adoptedDate = await Navigator.push<String>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => _ProgramPreview(
                            state: state,
                            plan: entry.$2.createPlan(days: days),
                            description: entry.$2.description,
                            openedDay: today,
                            tomorrow: dayKey(
                              DateTime(
                                openedDate.year,
                                openedDate.month,
                                openedDate.day + 1,
                              ),
                            ),
                          ),
                        ),
                      );
                      if (context.mounted && adoptedDate != null) {
                        onAdopted?.call(adoptedDate);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _ProgramCard extends StatelessWidget {
  final TrainingProgram program;
  final Color color;
  final VoidCallback onPreview;
  const _ProgramCard({
    required this.program,
    required this.color,
    required this.onPreview,
  });

  @override
  Widget build(BuildContext context) => Panel(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Tag('可调整参考方案', color: color),
        ),
        const SizedBox(height: 14),
        Text(program.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          program.description,
          style: const TextStyle(color: muted, height: 1.7),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Tag('约 ${program.minutes} 分钟', color: color),
            Tag('器械：${program.equipment}', color: color),
            Tag(
              '${program.items.fold<int>(0, (total, item) => total + item.sets)} 组',
              color: color,
            ),
          ],
        ),
        const SizedBox(height: 16),
        for (final item in program.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '${exerciseById(item.exerciseId).name} · ${item.sets} 组 × ${item.reps} ${exerciseById(item.exerciseId).timed ? '秒' : '次'}',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: Key('preview-${program.id}'),
          onPressed: onPreview,
          icon: Icon(Icons.arrow_forward_rounded, color: color, size: 18),
          label: const Text('预览方案'),
        ),
      ],
    ),
  );
}

class _ProgramPreview extends StatefulWidget {
  final AppState state;
  final TrainingPlan plan;
  final String description, openedDay, tomorrow;
  const _ProgramPreview({
    required this.state,
    required this.plan,
    required this.description,
    required this.openedDay,
    required this.tomorrow,
  });
  @override
  State<_ProgramPreview> createState() => _ProgramPreviewState();
}

class _ProgramPreviewState extends State<_ProgramPreview> {
  late String selectedDate;
  bool saving = false;
  String? pendingDate;
  bool get todayStarted =>
      widget.state.logs[widget.openedDay]?.completedSets.values.any(
        (sets) => sets.isNotEmpty,
      ) ??
      false;
  @override
  void initState() {
    super.initState();
    selectedDate = todayStarted ? widget.tomorrow : widget.openedDay;
  }

  bool _checkDay() {
    if (widget.state.today == widget.openedDay) return true;
    Navigator.pop(context);
    toast(context, '日期已更新，请重新打开方案预览。');
    return false;
  }

  Future<void> _adopt() async {
    if (saving || !_checkDay()) return;
    if (selectedDate == widget.openedDay && todayStarted) {
      setState(() => selectedDate = widget.tomorrow);
      toast(context, '今天已有完成组记录，请将训练方案用于明天。');
      return;
    }
    final date = selectedDate;
    final previous = widget.state.plans[date];
    final previousSnapshot = previous == null
        ? null
        : jsonEncode(previous.toJson());
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(previous == null ? '采纳训练方案？' : '替换已有计划？'),
        content: Text(
          previous == null
              ? '将「${widget.plan.title}」安排到 $date。保留原有每周训练日，可在计划中调整。'
              : '$date 已有「${previous.title}」。确认用「${widget.plan.title}」替换这一天的计划？保留原有每周训练日。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('confirm-program'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(previous == null ? '确认采纳' : '确认替换'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || !_checkDay()) return;
    final current = widget.state.plans[date];
    if ((current == null ? null : jsonEncode(current.toJson())) !=
        previousSnapshot) {
      toast(context, '这一天的计划已变化，请重新确认后采纳。');
      return;
    }
    if (date == widget.openedDay && todayStarted) {
      setState(() => selectedDate = widget.tomorrow);
      toast(context, '今天已有完成组记录，请将训练方案用于明天。');
      return;
    }
    setState(() => saving = true);
    try {
      await widget.state.saveProgramPlan(widget.plan.copyWith(), date: date);
      if (!mounted) return;
      if (widget.state.storageError != null) {
        setState(() {
          saving = false;
          pendingDate = date;
        });
        toast(context, widget.state.storageError!);
        return;
      }
      _finish(date);
    } catch (error) {
      if (!mounted) return;
      setState(() => saving = false);
      toast(
        context,
        error is ArgumentError
            ? error.message.toString()
            : error is StateError
            ? error.message
            : '方案保存未完成，请重试。',
      );
    }
  }

  void _finish(String date) {
    Navigator.pop(context, date);
    toast(context, '已将「${widget.plan.title}」安排到 $date。');
  }

  Future<void> _retry() async {
    if (saving || !_checkDay()) return;
    setState(() => saving = true);
    await widget.state.retrySave();
    if (!mounted) return;
    if (widget.state.storageError == null) {
      final date = pendingDate!;
      final current = widget.state.plans[date];
      if (current == null ||
          jsonEncode(current.toJson()) != jsonEncode(widget.plan.toJson())) {
        setState(() {
          saving = false;
          pendingDate = null;
        });
        toast(context, '这一天的计划已变化，保存状态已更新，请重新确认方案。');
        return;
      }
      _finish(date);
    } else {
      setState(() => saving = false);
      toast(context, widget.state.storageError!);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.state,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('方案预览')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Tag('可调整参考方案'),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.plan.title,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.description,
                    style: const TextStyle(color: muted, height: 1.7),
                  ),
                  const SizedBox(height: 16),
                  Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '所需器械：${widget.plan.equipment}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${widget.plan.items.length} 个动作 · ${widget.plan.totalSets} 组 · 约 ${widget.plan.minutes} 分钟',
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '时长为包含准备、动作转换及休息的估计；按自己的节奏完成。交替动作按总次数计，左右均衡完成。',
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const SectionTitle('按顺序练习'),
                  for (final entry in widget.plan.items.indexed) ...[
                    Panel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${entry.$1 + 1}. ${exerciseById(entry.$2.exerciseId).name}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${entry.$2.sets} 组 × ${entry.$2.reps} ${exerciseById(entry.$2.exerciseId).timed ? '秒' : '次'} · 组间休息 ${entry.$2.rest} 秒',
                            style: const TextStyle(color: muted, fontSize: 12),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '器械：${exerciseById(entry.$2.exerciseId).equipment}',
                            style: const TextStyle(color: muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 12),
                  const SectionTitle('安排到哪一天'),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      ChoiceChip(
                        key: const Key('program-today'),
                        label: Text('今天 · ${widget.openedDay}'),
                        selected: selectedDate == widget.openedDay,
                        onSelected:
                            todayStarted || saving || pendingDate != null
                            ? null
                            : (_) => setState(
                                () => selectedDate = widget.openedDay,
                              ),
                      ),
                      ChoiceChip(
                        key: const Key('program-tomorrow'),
                        label: Text('明天 · ${widget.tomorrow}'),
                        selected: selectedDate == widget.tomorrow,
                        onSelected: saving || pendingDate != null
                            ? null
                            : (_) => setState(
                                () => selectedDate = widget.tomorrow,
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (todayStarted)
                    const Text(
                      '今天已有完成组记录，可将方案安排到明天。',
                      style: TextStyle(color: coral),
                    ),
                  const SizedBox(height: 8),
                  const Text(
                    '只更新所选日期的训练计划；每周训练日沿用当前已保存的选择。',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                  if (pendingDate != null &&
                      widget.state.storageError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      widget.state.storageError!,
                      style: const TextStyle(color: coral),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    key: const Key('adopt-program'),
                    onPressed: saving
                        ? null
                        : pendingDate != null
                        ? _retry
                        : _adopt,
                    icon: const Icon(Icons.event_available_outlined, size: 18),
                    label: Text(
                      saving
                          ? '正在保存…'
                          : pendingDate != null
                          ? '重试保存'
                          : '采纳到 $selectedDate',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
