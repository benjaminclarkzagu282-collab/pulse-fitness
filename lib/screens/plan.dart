import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/catalog.dart';
import '../core/models.dart';
import '../ui/components.dart';
import '../ui/theme.dart';
import 'programs.dart';

class PlanScreen extends StatefulWidget {
  final AppState state;
  final VoidCallback openLibrary;
  const PlanScreen({super.key, required this.state, required this.openLibrary});
  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  late TrainingPlan draft;
  late String draftDay;
  String? expanded;
  bool dirty = false;
  @override
  void initState() {
    super.initState();
    draftDay = widget.state.today;
    draft = widget.state.plan.copyWith();
    expanded = draft.items.firstOrNull?.exerciseId;
  }

  @override
  void didUpdateWidget(covariant PlanScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (draftDay != widget.state.today) _loadCurrentDay();
  }

  void _loadCurrentDay() {
    draftDay = widget.state.today;
    draft = widget.state.plan.copyWith();
    dirty = false;
    expanded = null;
  }

  bool _checkDay() {
    if (draftDay == widget.state.today) return true;
    setState(_loadCurrentDay);
    toast(context, '日期已更新，已载入今天的计划');
    return false;
  }

  void update(TrainingPlan value) {
    if (!_checkDay()) return;
    setState(() {
      draft = value;
      dirty = true;
    });
  }

  Future<void> settings() async {
    if (!_checkDay()) return;
    final openedDay = draftDay;
    final value = await showPlanSettings(context, draft);
    if (!mounted || value == null) return;
    if (openedDay != widget.state.today) {
      setState(_loadCurrentDay);
      toast(context, '日期已更新，昨天的编辑未覆盖今天的计划');
      return;
    }
    update(value);
  }

  Future<void> openPrograms() async {
    if (!_checkDay()) return;
    final openedDay = draftDay;
    if (dirty) {
      final browse = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('有尚未保存的修改'),
          content: const Text('浏览后返回会保留草稿；若采纳到今天，将载入新方案并替换草稿。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('继续编辑'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('保留草稿并浏览'),
            ),
          ],
        ),
      );
      if (!mounted || browse != true) return;
      if (!_checkDay()) return;
    }
    final before = jsonEncode(
      (widget.state.plans[openedDay] ?? widget.state.template).toJson(),
    );
    var adoptedToday = false;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ProgramsScreen(
          state: widget.state,
          onAdopted: (date) {
            if (date == openedDay) adoptedToday = true;
          },
        ),
      ),
    );
    if (!mounted || !_checkDay()) return;
    final after = jsonEncode(
      (widget.state.plans[openedDay] ?? widget.state.template).toJson(),
    );
    if (adoptedToday || before != after) setState(_loadCurrentDay);
  }

  Future<bool> save() async {
    if (!_checkDay()) return false;
    await widget.state.savePlan(draft);
    if (mounted) {
      setState(() => dirty = false);
      toast(context, '训练计划已保存');
    }
    return true;
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      PageTitle(
        eyebrow: 'YOUR PLAN, YOUR PACE',
        title: '我的训练计划',
        subtitle: '按你的时间和目标安排',
        trailing: IconButton(
          tooltip: '计划设置',
          onPressed: settings,
          icon: const Icon(Icons.tune, color: lime),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: OutlinedButton.icon(
          key: const Key('open-programs'),
          onPressed: openPrograms,
          icon: const Icon(Icons.explore_outlined, color: lime, size: 18),
          label: const Text('浏览训练方案'),
        ),
      ),
      TwoColumns(
        leftFlex: 5,
        rightFlex: 3,
        left: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children:
                  [
                        draft.goal,
                        draft.equipment == '徒手' ? '居家训练' : '哑铃训练',
                        '每周 ${draft.days.length} 天',
                      ].indexed
                      .map(
                        (entry) => Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                              right: entry.$1 == 2 ? 0 : 7,
                            ),
                            child: Material(
                              color: surface2,
                              borderRadius: BorderRadius.circular(9),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(9),
                                onTap: settings,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 11,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          entry.$2,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                      ),
                                      const Icon(
                                        Icons.keyboard_arrow_down,
                                        size: 16,
                                        color: muted,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
            ),
            const SizedBox(height: 16),
            const Text(
              '每周安排',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Row(
              children: List.generate(7, (i) {
                final active = draft.days.contains(i + 1);
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: i == 6 ? 0 : 6),
                    child: Material(
                      color: active ? lime : surface,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        onTap: () {
                          final days = List<int>.from(draft.days);
                          active ? days.remove(i + 1) : days.add(i + 1);
                          days.sort();
                          update(draft.copyWith(days: days));
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          child: Column(
                            children: [
                              Text(
                                '周${['一', '二', '三', '四', '五', '六', '日'][i]}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: active ? bg : muted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Icon(
                                active
                                    ? Icons.check_circle
                                    : Icons.circle_outlined,
                                size: 15,
                                color: active ? bg : line,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text(
                    draft.title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '预计 ${draft.minutes} 分钟',
                  style: const TextStyle(color: muted, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 5),
            const Text(
              '点击编辑组数和次数，拖动右侧手柄调整顺序',
              style: TextStyle(color: muted, fontSize: 11),
            ),
            const SizedBox(height: 16),
            if (draft.items.isEmpty)
              const EmptyHint(
                icon: Icons.add_circle_outline,
                title: '你的计划，由你开始',
                detail: '添加喜欢的动作，组合成一场训练。',
              ),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: draft.items.length,
              onReorderItem: (old, target) {
                final items = List<PlanItem>.from(draft.items);

                items.insert(target, items.removeAt(old));
                update(draft.copyWith(items: items));
              },
              itemBuilder: (context, i) {
                final item = draft.items[i];
                final e = exerciseById(item.exerciseId);
                final open = expanded == e.id;
                return Padding(
                  key: ValueKey(e.id),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Panel(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Text(
                              '${i + 1}',
                              style: const TextStyle(
                                color: muted,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(width: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: ExerciseThumb(
                                e,
                                width: 66,
                                height: 52,
                                fit: BoxFit.contain,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    e.name,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    '${item.sets} 组 × ${item.reps} ${e.timed ? '秒' : '次'} · ${e.group}',
                                    style: const TextStyle(
                                      color: muted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: '编辑${e.name}',
                              onPressed: () =>
                                  setState(() => expanded = open ? null : e.id),
                              icon: Icon(
                                open
                                    ? Icons.keyboard_arrow_up
                                    : Icons.edit_outlined,
                                size: 18,
                                color: open ? lime : muted,
                              ),
                            ),
                            ReorderableDragStartListener(
                              index: i,
                              child: const Padding(
                                padding: EdgeInsets.all(6),
                                child: Icon(
                                  Icons.drag_handle,
                                  size: 19,
                                  color: muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 180),
                          child: open
                              ? Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Column(
                                    children: [
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 10,
                                        children: [
                                          NumberStepper(
                                            label: '组数',
                                            value: item.sets,
                                            min: 1,
                                            max: 8,
                                            onChanged: (n) => changeItem(
                                              i,
                                              item.copyWith(sets: n),
                                            ),
                                          ),
                                          NumberStepper(
                                            label: e.timed ? '每组秒数' : '每组次数',
                                            value: item.reps,
                                            min: 1,
                                            max: 120,
                                            step: e.timed ? 5 : 1,
                                            onChanged: (n) => changeItem(
                                              i,
                                              item.copyWith(reps: n),
                                            ),
                                          ),
                                          NumberStepper(
                                            label: '组间休息 / 秒',
                                            value: item.rest,
                                            min: 0,
                                            max: 300,
                                            step: 15,
                                            onChanged: (n) => changeItem(
                                              i,
                                              item.copyWith(rest: n),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: TextButton.icon(
                                          onPressed: () {
                                            final items = List<PlanItem>.from(
                                              draft.items,
                                            )..removeAt(i);
                                            update(
                                              draft.copyWith(items: items),
                                            );
                                          },
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            size: 15,
                                            color: muted,
                                          ),
                                          label: const Text(
                                            '从计划移除',
                                            style: TextStyle(
                                              color: muted,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: () async {
                if (!_checkDay()) return;
                if (dirty && !await save()) return;
                if (!mounted) return;
                widget.openLibrary();
              },
              icon: const Icon(Icons.add, size: 18, color: lime),
              label: const Text('添加动作', style: TextStyle(color: lime)),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('save-plan'),
                onPressed: save,
                icon: const Icon(Icons.check_rounded, size: 18),
                label: Text(dirty ? '保存修改' : '保存计划'),
              ),
            ),
          ],
        ),
        right: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Tag('PLAN OVERVIEW'),
                  const SizedBox(height: 20),
                  const Text(
                    '让训练适应生活',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '每次安排一点可完成的运动，比追求一次完美更重要。',
                    style: TextStyle(color: muted, fontSize: 12, height: 1.8),
                  ),
                  const SizedBox(height: 26),
                  Row(
                    children: [
                      Expanded(child: Stat('${draft.items.length}', '动作')),
                      Expanded(child: Stat('${draft.totalSets}', '总组数')),
                      Expanded(child: Stat('${draft.days.length} 天', '每周训练')),
                    ],
                  ),
                  const SizedBox(height: 25),
                  const Divider(),
                  const SizedBox(height: 12),
                  const Row(
                    children: [
                      Icon(Icons.touch_app_outlined, color: lime, size: 18),
                      SizedBox(width: 8),
                      Text('每一个动作，都能按需调整', style: TextStyle(fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '这里的组数与次数是你的计划目标，跟练时由你确认每组完成。',
                    style: TextStyle(fontSize: 11, color: muted, height: 1.7),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Panel(
              color: const Color(0xFF242D1D),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.event_available_outlined, color: lime),
                  const SizedBox(height: 12),
                  Text(
                    draft.days.isEmpty
                        ? '本周自由安排'
                        : '每周 ${draft.days.length} 天，按自己的节奏',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '休息日也可以浏览动作与记录饮食。日程是提醒，不是必须完成的压力。',
                    style: TextStyle(color: muted, fontSize: 12, height: 1.8),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (widget.state.tomorrowTrainingAdopted)
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Tag('下一次已安排'),
                    const SizedBox(height: 10),
                    Text(
                      widget.state.plans[widget.state.tomorrow]!.title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '在「记录」中查看或修改下一次安排。今天的编辑不会覆盖它。',
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ],
  );
  void changeItem(int i, PlanItem item) {
    final items = List<PlanItem>.from(draft.items);
    items[i] = item;
    update(draft.copyWith(items: items));
  }
}

class NumberStepper extends StatelessWidget {
  final String label;
  final int value, min, max, step;
  final ValueChanged<int> onChanged;
  const NumberStepper({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.step = 1,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: muted, fontSize: 10)),
      const SizedBox(height: 7),
      Container(
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: line),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              constraints: const BoxConstraints(minWidth: 30, minHeight: 36),
              padding: const EdgeInsets.all(6),
              tooltip: '减少$label',
              onPressed: value > min
                  ? () => onChanged((value - step).clamp(min, max))
                  : null,
              icon: const Icon(Icons.remove, size: 15),
            ),
            SizedBox(
              width: 26,
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              constraints: const BoxConstraints(minWidth: 30, minHeight: 36),
              padding: const EdgeInsets.all(6),
              tooltip: '增加$label',
              onPressed: value < max
                  ? () => onChanged((value + step).clamp(min, max))
                  : null,
              icon: const Icon(Icons.add, size: 15),
            ),
          ],
        ),
      ),
    ],
  );
}

Future<TrainingPlan?> showPlanSettings(
  BuildContext context,
  TrainingPlan plan,
) => showAppSheet<TrainingPlan>(context, _PlanSettings(plan));

class _PlanSettings extends StatefulWidget {
  final TrainingPlan plan;
  const _PlanSettings(this.plan);
  @override
  State<_PlanSettings> createState() => _PlanSettingsState();
}

class _PlanSettingsState extends State<_PlanSettings> {
  late TrainingPlan draft;
  late TextEditingController title;
  @override
  void initState() {
    super.initState();
    draft = widget.plan;
    title = TextEditingController(text: draft.title);
  }

  @override
  void dispose() {
    title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          '让计划更适合你',
          style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: title,
          maxLength: 18,
          decoration: const InputDecoration(labelText: '计划名称'),
        ),
        const SizedBox(height: 16),
        const Text('训练目标', style: TextStyle(color: muted, fontSize: 12)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ['保持活力', '增肌塑形', '提升耐力']
              .map(
                (g) => Pill(
                  g,
                  active: g == draft.goal,
                  onTap: () => setState(() => draft = draft.copyWith(goal: g)),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 20),
        const Text('可用器材', style: TextStyle(color: muted, fontSize: 12)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: ['徒手', '哑铃']
              .map(
                (e) => Pill(
                  e,
                  active: e == draft.equipment,
                  onTap: () =>
                      setState(() => draft = draft.copyWith(equipment: e)),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 23),
        Text(
          '每次可用时间  ${draft.minutes} 分钟',
          style: const TextStyle(fontSize: 13),
        ),
        Slider(
          value: draft.minutes.toDouble(),
          min: 10,
          max: 90,
          divisions: 16,
          label: '${draft.minutes} 分钟',
          onChanged: (n) =>
              setState(() => draft = draft.copyWith(minutes: n.round())),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            draft.copyWith(
              title: title.text.trim().isEmpty
                  ? draft.title
                  : title.text.trim(),
            ),
          ),
          child: const Text('应用设置'),
        ),
      ],
    ),
  );
}
