import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/catalog.dart';
import '../core/models.dart';
import '../ui/components.dart';
import '../ui/exercise_view.dart';
import '../ui/theme.dart';
import '../ui/muscle_map.dart';

/// Keeps already recorded sets in the plan when replacing the remaining work.
Future<int> replaceWorkoutAction(AppState state, int index, String id) async {
  final items = List<PlanItem>.from(state.plan.items);
  if (index < 0 ||
      index >= items.length ||
      items.any((i) => i.exerciseId == id)) {
    return index;
  }
  final target = exerciseById(id);
  final source = items[index];
  final done = state.completedSetsFor(source.exerciseId);
  if (done >= source.sets) return index;
  final replacement = PlanItem(
    id,
    sets: source.sets - done,
    reps: exerciseById(source.exerciseId).timed == target.timed
        ? source.reps
        : target.timed
        ? 30
        : 12,
    rest: source.rest,
  );
  if (done > 0) {
    // Retained sets occupy a smaller plan segment; preserve their count even
    // when the previous completion indices were not consecutive.
    final recorded = state.log.completedSets[source.exerciseId]!;
    state.log.completedSets[source.exerciseId] = {
      for (var i = 0; i < done; i++) i,
      ...recorded.where((i) => i >= source.sets),
    };
    final records = state.log.setRecords[source.exerciseId];
    if (records != null) {
      final indices = recorded.where((i) => i < source.sets).toList()..sort();
      state.log.setRecords[source.exerciseId] = {
        for (var i = 0; i < indices.length; i++)
          if (records[indices[i]] != null) i: records[indices[i]]!.withIndex(i),
        for (final entry in records.entries)
          if (entry.key >= source.sets) entry.key: entry.value,
      };
    }
    items[index] = source.copyWith(sets: done);
    items.insert(++index, replacement);
  } else {
    items[index] = replacement;
  }
  await state.savePlan(
    state.plan.copyWith(
      items: items,
      equipment: target.equipment == '哑铃' ? '哑铃' : state.plan.equipment,
    ),
  );
  return index;
}

/// Confirm the actual work before a completion becomes a saved set.
Future<SetRecord?> promptActualSet(
  BuildContext context,
  PlanItem item, {
  required int setIndex,
  required int elapsedSeconds,
  required int fatigue,
  double? weightKg,
}) async {
  final exercise = exerciseById(item.exerciseId);
  final count = TextEditingController(text: '${item.reps}');
  final weight = TextEditingController(
    text: weightKg == null ? '' : '$weightKg',
  );
  final form = GlobalKey<FormState>();
  var effort = fatigue;
  try {
    return await showAppSheet<SetRecord>(
      context,
      StatefulBuilder(
        builder: (sheetContext, update) => ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .85,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${exercise.name} · 第 ${setIndex + 1} 组',
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '计划 ${item.reps} ${exercise.timed ? '秒' : '次'} · 默认填入计划目标，请按实际完成修改。点击「保存本组记录」即确认以上实际数值。',
                    style: const TextStyle(
                      color: muted,
                      fontSize: 12,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '秒表耗时 $elapsedSeconds 秒，仅用于统计训练时间。',
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    key: const ValueKey('actual-count'),
                    controller: count,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: exercise.timed ? '实际完成秒数' : '实际完成次数',
                    ),
                    validator: (text) {
                      final value = int.tryParse(text?.trim() ?? '');
                      final max = exercise.timed ? 7200 : 1000;
                      return value == null || value < 1 || value > max
                          ? '请输入 1–$max 的实际${exercise.timed ? '秒数' : '次数'}'
                          : null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const ValueKey('actual-weight'),
                    controller: weight,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: '本组外加总重量 (kg)',
                      helperText: '双手哑铃请填两只合计重量；徒手填 0，未知可留空。',
                    ),
                    validator: (text) {
                      if (text?.trim().isEmpty ?? true) return null;
                      final value = double.tryParse(text?.trim() ?? '');
                      return value == null ||
                              !value.isFinite ||
                              value < 0 ||
                              value > 1000
                          ? '请输入 0–1000 kg 的有限重量'
                          : null;
                    },
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    '本组感受',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (var i = 1; i <= 3; i++)
                        ChoiceChip(
                          label: Text(['轻松', '适中', '吃力'][i - 1]),
                          selected: effort == i,
                          onSelected: (_) => update(() => effort = i),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () {
                      if (!form.currentState!.validate()) return;
                      final actual = int.parse(count.text.trim());
                      Navigator.pop(
                        sheetContext,
                        SetRecord(
                          setIndex: setIndex,
                          fatigue: effort,
                          elapsedSeconds: elapsedSeconds.clamp(0, 7200),
                          target: item.reps,
                          timed: exercise.timed,
                          actualReps: exercise.timed ? null : actual,
                          actualSeconds: exercise.timed ? actual : null,
                          weightKg: weight.text.trim().isEmpty
                              ? null
                              : double.parse(weight.text.trim()),
                        ),
                      );
                    },
                    child: const Text('保存本组记录'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(
                      sheetContext,
                      SetRecord(
                        setIndex: setIndex,
                        fatigue: effort,
                        elapsedSeconds: elapsedSeconds.clamp(0, 7200),
                        target: item.reps,
                        timed: exercise.timed,
                      ),
                    ),
                    child: const Text('只标记完成，不记录实际数值'),
                  ),
                  const Text(
                    '仅保留完成状态、感受与秒表耗时，不作为进阶依据。',
                    style: TextStyle(color: muted, fontSize: 11, height: 1.5),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: const Text('返回继续训练'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  } finally {
    // Sheet exit animations may still hold the fields for one frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      count.dispose();
      weight.dispose();
    });
  }
}

void openWorkout(BuildContext context, AppState state, {String? exerciseId}) {
  if (state.plan.items.isEmpty) {
    toast(context, '先向计划添加一个动作');
    return;
  }
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => WorkoutScreen(state: state, exerciseId: exerciseId),
    ),
  );
}

class WorkoutScreen extends StatefulWidget {
  final AppState state;
  final String? exerciseId;
  const WorkoutScreen({super.key, required this.state, this.exerciseId});
  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen>
    with WidgetsBindingObserver {
  late int index;
  int fatigue = 2, info = 0;
  bool paused = false, side = false, busy = false, finished = false;
  bool videoFallback = false;
  double speed = 1;
  int cameraRevision = 0;
  int restSeconds = 0;
  DateTime? restEnd;
  final Stopwatch watch = Stopwatch();
  late final Timer timer;
  late final String sessionDay;
  bool get resting => restSeconds > 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    sessionDay = widget.state.today;
    final p = widget.state.plan;
    index = widget.exerciseId == null
        ? p.items.indexWhere(
            (i) => widget.state.completedSetsFor(i.exerciseId) < i.sets,
          )
        : p.items.indexWhere((i) => i.exerciseId == widget.exerciseId);
    if (index < 0) {
      index = 0;
      finished = true;
    }
    if (!finished) {
      final exercise = exerciseById(p.items[index].exerciseId);
      side = exercise.prefersSideView || exercise.id == 'row';
      watch.start();
    }
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (restEnd != null && !paused) {
        restSeconds = math.max(
          0,
          (restEnd!.difference(DateTime.now()).inMilliseconds / 1000).ceil(),
        );
        if (restSeconds == 0) {
          restEnd = null;
          watch
            ..reset()
            ..start();
        }
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer.cancel();
    watch.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.resumed || !mounted) return;
    // Repeated inactive/hidden/paused callbacks keep the same interruption
    // latched. Returning to the app requires the user's explicit resume.
    watch.stop();
    setState(() {
      paused = true;
      if (restEnd != null) {
        restSeconds = math.max(
          0,
          (restEnd!.difference(DateTime.now()).inMilliseconds / 1000).ceil(),
        );
        restEnd = null;
      }
    });
  }

  void togglePause() => setState(() {
    paused = !paused;
    if (paused) {
      watch.stop();
      if (resting) restEnd = null;
    } else if (resting) {
      restEnd = DateTime.now().add(Duration(seconds: restSeconds));
    } else {
      watch.start();
    }
  });
  void skipRest() => setState(() {
    restEnd = null;
    restSeconds = 0;
    if (!paused) {
      watch
        ..reset()
        ..start();
    }
  });
  Future<void> complete() async {
    if (busy || resting || finished || paused) return;
    if (widget.state.today != sessionDay) {
      toast(context, '日期已变化，请返回首页开始今天的训练');
      return;
    }
    setState(() => busy = true);
    final state = widget.state;
    final item = state.plan.items[index];
    final done = state.log.completedSets[item.exerciseId] ?? {};
    final nextSet = List.generate(
      item.sets,
      (n) => n,
    ).where((n) => !done.contains(n)).firstOrNull;
    if (nextSet != null) {
      watch.stop();
      final previous = state.log.setRecords[item.exerciseId]?.values.lastOrNull;
      final actual = await promptActualSet(
        context,
        item,
        setIndex: nextSet,
        elapsedSeconds: watch.elapsed.inSeconds,
        fatigue: fatigue,
        weightKg: previous?.weightKg,
      );
      if (!mounted) return;
      if (actual == null || state.today != sessionDay) {
        setState(() => busy = false);
        if (!paused) watch.start();
        if (state.today != sessionDay) toast(context, '日期已变化，请返回首页开始今天的训练');
        return;
      }
      fatigue = actual.fatigue;
      await state.completeSet(
        item.exerciseId,
        nextSet,
        actual.fatigue,
        seconds: actual.elapsedSeconds,
        actualReps: actual.actualReps,
        actualSeconds: actual.actualSeconds,
        weightKg: actual.weightKg,
      );
    }
    watch
      ..stop()
      ..reset();
    if (!mounted) return;
    setState(() {
      busy = false;
      if (state.completedSetsFor(item.exerciseId) >= item.sets) {
        final next = state.plan.items.indexWhere(
          (i) => state.completedSetsFor(i.exerciseId) < i.sets,
        );
        if (next < 0) {
          finished = true;
          return;
        }
        index = next;
        side = exerciseById(state.plan.items[next].exerciseId).prefersSideView;
      }
      restSeconds = item.rest;
      if (restSeconds > 0) {
        restEnd = DateTime.now().add(Duration(seconds: restSeconds));
      } else if (!paused) {
        watch.start();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    if (state.plan.items.isEmpty || index >= state.plan.items.length) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('计划已调整，请返回重新开始。')),
      );
    }
    final item = state.plan.items[index];
    final e = exerciseById(item.exerciseId);
    final done = state.completedSetsFor(e.id);
    final width = MediaQuery.sizeOf(context).width;
    final wide = width > 900;
    if (finished) {
      return Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: () => Navigator.pop(context)),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                children: [
                  const Tag('SESSION COMPLETE'),
                  const SizedBox(height: 26),
                  const Icon(Icons.check_circle_outline, size: 68, color: lime),
                  const SizedBox(height: 20),
                  const Text(
                    '今天，也向前了一步',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '每一组努力，都已经为你记下。',
                    style: TextStyle(color: muted, fontSize: 13),
                  ),
                  const SizedBox(height: 30),
                  Panel(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Stat('${state.completedExercises}', '完成动作'),
                        Stat('${state.log.setCount}', '完成组数'),
                        Stat('${state.score.total}', '今日完成度'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    '在「记录」中查看复盘和下一次训练、饮食建议。',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: muted, fontSize: 12, height: 1.7),
                  ),
                  const SizedBox(height: 26),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('完成，返回首页'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final viewer = Panel(
      padding: const EdgeInsets.all(7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExerciseView(
            e,
            key: ValueKey(e.id),
            cameraRevision: cameraRevision,
            playing: !paused && !resting,
            speed: speed,
            onFallbackChanged: (value) {
              if (mounted && videoFallback != value) {
                setState(() => videoFallback = value);
              }
            },
            orbit: side ? '90deg 75deg 110%' : '0deg 75deg 110%',
            height: wide
                ? 415
                : (MediaQuery.sizeOf(context).height * .31).clamp(220, 290),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              const Spacer(),
              if (!videoFallback)
                IconButton(
                  tooltip: '重置视角',
                  onPressed: () => setState(() {
                    side = false;
                    cameraRevision++;
                  }),
                  icon: const Icon(Icons.restart_alt, size: 21, color: muted),
                ),
              Pill(
                '${speed == 1 ? '1' : '0.5'}×',
                onTap: () => setState(() => speed = speed == 1 ? .5 : 1),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            videoFallback ? '视频示范 · 可暂停或调整速度' : '360° 拖动旋转 · 双指缩放',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 9, color: muted),
          ),
          const SizedBox(height: 3),
        ],
      ),
    );
    final controls = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: List.generate(
            3,
            (i) => Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i == 2 ? 0 : 5),
                child: Material(
                  color: info == i ? lime : surface2,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => setState(() => info = i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        ['跟练', '动作要点', '目标肌群'][i],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: info == i ? bg : muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 11),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _compactStat(
                      '第 ${math.min(done + 1, item.sets)} / ${item.sets} 组',
                      '组数',
                    ),
                  ),
                  Expanded(
                    child: _compactStat(
                      '目标 ${item.reps}${e.timed ? '秒' : '次'}',
                      '本组目标',
                    ),
                  ),
                  Expanded(child: _compactStat('组间 ${item.rest}秒', '休息时间')),
                ],
              ),
              const SizedBox(height: 10),
              ThinBar(done / item.sets, height: 3),
              const SizedBox(height: 6),
              Text(
                '已完成 $done 组  ·  本组用时 ${_duration(watch.elapsed.inSeconds)}',
                style: const TextStyle(color: muted, fontSize: 9),
              ),
            ],
          ),
        ),
        if (resting) ...[
          const SizedBox(height: 10),
          Panel(
            color: const Color(0xFF293621),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.self_improvement, color: lime),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '调整呼吸  ${_duration(restSeconds)}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: lime,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: skipRest,
                  child: const Text('跳过休息', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 11),
        Panel(
          padding: const EdgeInsets.all(13),
          child: info == 2
              ? MuscleMap(group: e.group, description: e.subtitle)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.lightbulb_outline, color: lime, size: 21),
                        SizedBox(width: 8),
                        Text(
                          '动作提示',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    ...e.tips
                        .take(info == 0 ? 2 : 3)
                        .indexed
                        .map(
                          (entry) => Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text(
                              '${entry.$1 + 1}. ${entry.$2}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: muted,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ),
                    if (e.id == 'lunge')
                      const Text(
                        '两侧交替练习，模型展示单侧。',
                        style: TextStyle(fontSize: 10, color: lime),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 13),
        const Text(
          '本组感受',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Row(
          children: List.generate(
            3,
            (i) => Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i == 2 ? 0 : 8),
                child: Material(
                  color: fatigue == i + 1 ? lime : surface2,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => fatigue = i + 1),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      child: Text(
                        ['轻松', '适中', '吃力'][i],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: fatigue == i + 1 ? bg : muted,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 13),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: busy || paused || resting ? null : complete,
                child: Text(
                  resting
                      ? '休息中'
                      : paused
                      ? '已暂停'
                      : '完成本组',
                ),
              ),
            ),
            const SizedBox(width: 9),
            SizedBox(
              width: 48,
              height: 48,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  shape: const CircleBorder(),
                ),
                onPressed: togglePause,
                child: Icon(
                  paused ? Icons.play_arrow : Icons.pause,
                  semanticLabel: paused ? '继续训练' : '暂停训练',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton.icon(
              onPressed: () => _replaceExercise(context),
              icon: const Icon(Icons.swap_horiz, size: 18),
              label: const Text('替换动作', style: TextStyle(fontSize: 11)),
            ),
            TextButton.icon(
              onPressed: () => _selectExercise(context),
              icon: const Icon(Icons.format_list_bulleted, size: 17),
              label: const Text('切换动作', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              e.name,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 19),
            ),
            Text(
              '动作 ${index + 1} / ${state.plan.items.length}',
              style: const TextStyle(color: muted, fontSize: 11),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '收藏动作',
            onPressed: () {
              state.toggleFavorite(e.id);
              setState(() {});
            },
            icon: Icon(
              state.favorites.contains(e.id)
                  ? Icons.bookmark
                  : Icons.bookmark_border,
              color: lime,
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(wide ? 30 : 14, 10, wide ? 30 : 14, 14),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(
                children: [
                  Row(
                    children: state.plan.items
                        .map(
                          (i) => Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 5),
                              child: ThinBar(
                                state.completedSetsFor(i.exerciseId) / i.sets,
                                height: 4,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  TwoColumns(
                    left: viewer,
                    right: controls,
                    breakAt: 800,
                    leftFlex: 5,
                    rightFlex: 4,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _compactStat(String value, String label) => Column(
    children: [
      Text(
        value,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 4),
      Text(label, style: const TextStyle(fontSize: 10, color: muted)),
    ],
  );

  Future<void> _replaceExercise(BuildContext context) async {
    if (sessionDay != widget.state.today) {
      toast(context, '日期已变化，请返回首页开始今天的训练');
      return;
    }
    final state = widget.state;
    final current = state.plan.items[index];
    final options = exercises
        .where((e) => !state.plan.items.any((p) => p.exerciseId == e.id))
        .toList();
    final id = await showAppSheet<String>(
      context,
      SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionTitle('替换接下来的动作'),
            const Text(
              '已完成的组数会保留，替换只影响剩余训练。',
              style: TextStyle(color: muted, fontSize: 11),
            ),
            const SizedBox(height: 10),
            if (options.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('所有动作都已在计划中，可使用“切换动作”。'),
              ),
            for (final e in options)
              ListTile(
                leading: ExerciseThumb(e, width: 52, height: 54),
                title: Text(e.name, style: const TextStyle(fontSize: 14)),
                subtitle: Text(
                  '${e.group} · ${e.equipment}',
                  style: const TextStyle(fontSize: 11, color: muted),
                ),
                trailing: const Icon(Icons.add_circle_outline, color: lime),
                onTap: () => Navigator.pop(context, e.id),
              ),
          ],
        ),
      ),
    );
    if (id == null || !mounted) return;
    if (sessionDay != state.today ||
        index >= state.plan.items.length ||
        state.plan.items[index].exerciseId != current.exerciseId) {
      toast(this.context, '计划已变化，请重新选择动作');
      return;
    }
    final next = await replaceWorkoutAction(state, index, id);
    if (!mounted) return;
    setState(() {
      index = next;
      side = exerciseById(id).prefersSideView || id == 'row';
      restSeconds = 0;
      restEnd = null;
      cameraRevision++;
      watch
        ..stop()
        ..reset();
      if (!paused) watch.start();
    });
  }

  String _duration(int seconds) =>
      '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  void _selectExercise(BuildContext context) => showAppSheet(
    context,
    SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 25),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SectionTitle('选择接下来练习的动作'),
            ...widget.state.plan.items.indexed.map((entry) {
              final e = exerciseById(entry.$2.exerciseId);
              return ListTile(
                leading: ExerciseThumb(e, width: 42, height: 45),
                title: Text(e.name, style: const TextStyle(fontSize: 14)),
                subtitle: Text(
                  '已完成 ${widget.state.completedSetsFor(e.id)} / ${entry.$2.sets} 组',
                  style: const TextStyle(color: muted, fontSize: 11),
                ),
                trailing: index == entry.$1
                    ? const Icon(Icons.check, color: lime)
                    : null,
                onTap: () {
                  setState(() {
                    index = entry.$1;
                    side = e.prefersSideView || e.id == 'row';
                    restSeconds = 0;
                    restEnd = null;
                    watch
                      ..stop()
                      ..reset();
                    if (!paused) watch.start();
                  });
                  Navigator.pop(context);
                },
              );
            }),
          ],
        ),
      ),
    ),
  );
}
