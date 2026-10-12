import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/catalog.dart';
import '../core/models.dart';
import '../ui/components.dart';
import '../ui/theme.dart';

class FoodLogScreen extends StatelessWidget {
  final AppState state;
  final String date;
  final int initialSlot;
  const FoodLogScreen({
    super.key,
    required this.state,
    required this.date,
    this.initialSlot = 0,
  });

  Future<void> _edit(BuildContext context, [CustomFood? food]) async {
    final result = await showAppSheet<CustomFood>(
      context,
      _FoodEditor(
        food: food,
        id: food?.id ?? 'custom-${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    if (result != null) {
      await state.saveCustomFood(result);
      if (context.mounted) {
        toast(context, state.storageError ?? '已保存食物；过去记录保留原值');
      }
    }
  }

  Future<void> _log(BuildContext context, CustomFood food) async {
    final result = await showAppSheet<_FoodPortion>(
      context,
      _PortionEditor(
        state: state,
        food: food,
        date: date,
        initialSlot: initialSlot,
      ),
    );
    if (result == null) return;
    final saved = await state.logFood(
      food.id,
      result.grams,
      result.slot,
      date: date,
    );
    if (context.mounted) {
      toast(
        context,
        state.storageError ?? (saved ? '已加入实际摄入' : '未记录，请检查日期与饮食偏好'),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('食物记录与食物库')),
    body: AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final entries = state.logs[date]?.foodEntries ?? <FoodEntry>[];
        final future = !state.canRecordDate(date);
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(date, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              '根据你填写的来源与每 100 g 营养估算实际摄入。克数请按与来源一致的食物状态填写（如生重或熟重）；新增食物独立计入，编辑食物库不改变过去记录。',
              style: TextStyle(color: muted, fontSize: 12),
            ),
            if (future)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  '未来日期只能维护食物库，当天再记录实际摄入。',
                  style: TextStyle(color: sky),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _edit(context),
              icon: const Icon(Icons.add),
              label: const Text('新建食物'),
            ),
            const SizedBox(height: 16),
            const Text('我的食物库', style: TextStyle(fontWeight: FontWeight.w700)),
            if (state.customFoods.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  '先填写包装标签或其他明确来源，建立你的食物。',
                  style: TextStyle(color: muted),
                ),
              ),
            ...state.customFoods.values.map(
              (food) => Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              food.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: '编辑${food.name}',
                            onPressed: () => _edit(context, food),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                        ],
                      ),
                      Text(
                        '来源：${food.source}',
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                      Text(
                        '每 100 g：${food.per100g.kcal.round()} kcal · 蛋白质 ${food.per100g.protein.round()} g · 碳水 ${food.per100g.carbs.round()} g · 脂肪 ${food.per100g.fat.round()} g',
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                      Text(
                        '${food.vegetarian ? '素食' : '非素食'} · 过敏原：${food.allergens.isEmpty ? '用户未填写' : food.allergens.join('、')}',
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                      if (!state.foodAllowed(food))
                        const Text(
                          '已按当前偏好与忌口排除，编辑后可重新选择。',
                          style: TextStyle(color: sky, fontSize: 12),
                        ),
                      TextButton(
                        onPressed: future || !state.foodAllowed(food)
                            ? null
                            : () => _log(context, food),
                        child: const Text('记录克数'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '所选日期实际摄入',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              '整餐快照与单条食物相加。如果食物已包含在整餐里，请勿重复添加；整餐可单独撤销，单条食物也可分别移除。',
              style: TextStyle(color: muted, fontSize: 12),
            ),
            ...List.generate(4, (slot) {
              final meal = state.logs[date]?.meals[slot];
              final foods = entries.where((e) => e.slot == slot).toList();
              if (meal == null && foods.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        mealSlots[slot],
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (meal != null) ...[
                        Text(
                          '整餐：${meal.title} · ${meal.nutrients.kcal.round()} kcal',
                        ),
                        TextButton(
                          onPressed: future
                              ? null
                              : () => state.toggleMeal(slot, date: date),
                          child: const Text('仅撤销整餐记录'),
                        ),
                      ],
                      ...foods.map(
                        (entry) => Row(
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${entry.food.name} · ${entry.grams} g · ${entry.nutrients.kcal.round()} kcal',
                                    ),
                                    Text(
                                      '当次来源：${entry.food.source}',
                                      style: const TextStyle(
                                        color: muted,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: '移除此条摄入',
                              onPressed: future
                                  ? null
                                  : () => state.removeFoodEntry(
                                      entry.id,
                                      date: date,
                                    ),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            if (entries.isEmpty && (state.logs[date]?.meals.isEmpty ?? true))
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('这一天还没有实际摄入记录。', style: TextStyle(color: muted)),
              ),
          ],
        );
      },
    ),
  );
}

class _FoodEditor extends StatefulWidget {
  final CustomFood? food;
  final String id;
  const _FoodEditor({required this.id, this.food});
  @override
  State<_FoodEditor> createState() => _FoodEditorState();
}

class _FoodEditorState extends State<_FoodEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name, _source, _allergens;
  late final List<TextEditingController> _values;
  late bool _vegetarian;
  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.food?.name);
    _source = TextEditingController(text: widget.food?.source);
    _allergens = TextEditingController(text: widget.food?.allergens.join('、'));
    _values = List.generate(
      4,
      (i) => TextEditingController(
        text: widget.food?.per100g.toJson()[i].toString(),
      ),
    );
    _vegetarian = widget.food?.vegetarian ?? false;
  }

  @override
  void dispose() {
    for (final c in [_name, _source, _allergens, ..._values]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .85,
    ),
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.food == null ? '新建食物' : '编辑食物',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              '请照来源填写每 100 g 数值，不确定时先查标签。保存仅更新食物库，过去摄入保留原始快照。',
              style: TextStyle(color: muted, fontSize: 12),
            ),
            TextFormField(
              key: const ValueKey('food-name'),
              controller: _name,
              maxLength: 100,
              decoration: const InputDecoration(labelText: '食物名称'),
              validator: (v) => v == null || v.trim().isEmpty ? '请填写名称' : null,
            ),
            TextFormField(
              key: const ValueKey('food-source'),
              controller: _source,
              maxLength: 500,
              decoration: const InputDecoration(labelText: '营养来源（如包装标签）'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? '请填写明确来源' : null,
            ),
            ...List.generate(
              4,
              (i) => Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextFormField(
                  key: ValueKey(
                    'food-${['kcal', 'protein', 'carbs', 'fat'][i]}',
                  ),
                  controller: _values[i],
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText:
                        '每 100 g ${['热量 kcal', '蛋白质 g', '碳水 g', '脂肪 g'][i]}',
                  ),
                  validator: (v) {
                    final n = double.tryParse(v ?? '');
                    return n == null ||
                            !n.isFinite ||
                            n < 0 ||
                            n > (i == 0 ? 1000 : 100)
                        ? '请填写 0–${i == 0 ? 1000 : 100} 之间的数值'
                        : null;
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _allergens,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: '过敏原（用顿号或逗号分隔）',
                hintText: '如乳制品、大豆、坚果',
              ),
              validator: (v) =>
                  (v ?? '')
                      .split(RegExp('[、,，]'))
                      .where((v) => v.trim().isNotEmpty)
                      .any((v) => v.trim().length > 100)
                  ? '每个过敏原最多 100 字'
                  : null,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('这是素食食物'),
              value: _vegetarian,
              onChanged: (v) => setState(() => _vegetarian = v),
            ),
            FilledButton(
              onPressed: () {
                if (!_form.currentState!.validate()) return;
                final v = _values.map((c) => double.parse(c.text)).toList();
                final food = CustomFood(
                  id: widget.id,
                  name: _name.text.trim(),
                  source: _source.text.trim(),
                  per100g: Nutrients(v[0], v[1], v[2], v[3]),
                  allergens: _allergens.text
                      .split(RegExp('[、,，]'))
                      .map((v) => v.trim())
                      .where((v) => v.isNotEmpty)
                      .toSet()
                      .toList(),
                  vegetarian: _vegetarian,
                );
                if (food.isValid) {
                  Navigator.pop(context, food);
                } else {
                  toast(context, '请检查食物数值与过敏原（最多 30 项）');
                }
              },
              child: const Text('保存食物'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _FoodPortion {
  final int slot;
  final double grams;
  const _FoodPortion(this.slot, this.grams);
}

class _PortionEditor extends StatefulWidget {
  final AppState state;
  final CustomFood food;
  final String date;
  final int initialSlot;
  const _PortionEditor({
    required this.state,
    required this.food,
    required this.date,
    required this.initialSlot,
  });
  @override
  State<_PortionEditor> createState() => _PortionEditorState();
}

class _PortionEditorState extends State<_PortionEditor> {
  final _grams = TextEditingController(text: '100');
  late int _slot;
  @override
  void initState() {
    super.initState();
    _slot = widget.initialSlot;
  }

  @override
  void dispose() {
    _grams.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final grams = double.tryParse(_grams.text);
    final valid =
        grams != null && grams.isFinite && grams > 0 && grams <= 10000;
    final meal = widget.state.logs[widget.date]?.meals[_slot];
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
              '记录 ${widget.food.name}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '${widget.date} · 来源：${widget.food.source}',
              style: const TextStyle(color: muted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(
                4,
                (slot) => ChoiceChip(
                  label: Text(mealSlots[slot]),
                  selected: _slot == slot,
                  onSelected: (_) => setState(() => _slot = slot),
                ),
              ),
            ),
            TextField(
              key: const ValueKey('food-grams'),
              controller: _grams,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: '实际克数 g',
                errorText: valid ? null : '填写大于 0 且不超过 10000 的克数',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            if (valid)
              Text(
                '估算 ${widget.food.per100g.scale(grams / 100).kcal.round()} kcal · 按来源每 100 g × 克数 / 100',
              ),
            const SizedBox(height: 12),
            Text(
              meal == null
                  ? '单条食物独立计入本餐；如果之后记录整餐，请确认食物没有包含其中。'
                  : '本餐已记录 ${meal.title}。这条食物会额外相加；若已包含在整餐里，请勿重复添加。你可在记录列表仅撤销整餐。',
              style: const TextStyle(color: sky, fontSize: 12),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: valid
                  ? () => Navigator.pop(context, _FoodPortion(_slot, grams))
                  : null,
              child: const Text('加入所选日期'),
            ),
          ],
        ),
      ),
    );
  }
}
