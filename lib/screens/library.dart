import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/catalog.dart';
import '../core/models.dart';
import '../ui/components.dart';
import '../ui/exercise_view.dart';
import '../ui/theme.dart';

class LibraryScreen extends StatefulWidget {
  final AppState state;
  const LibraryScreen({super.key, required this.state});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final searchController = TextEditingController();
  String search = '', group = '全部', equipment = '全部器材';
  bool favoritesOnly = false;
  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = exercises
        .where(
          (e) =>
              (group == '全部' || group == e.group) &&
              (equipment == '全部器材' ||
                  e.requiredEquipment.contains(equipment)) &&
              (!favoritesOnly || widget.state.favorites.contains(e.id)) &&
              '${e.name} ${e.group} ${e.equipment}'.contains(search.trim()),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageTitle(
          eyebrow: 'UNDERSTAND EVERY MOVEMENT',
          title: '3D 动作库',
          subtitle: '看清动作，再开始训练',
          trailing: Tag('${exercises.length} 个动作'),
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: searchController,
                onChanged: (s) => setState(() => search = s),
                decoration: const InputDecoration(
                  hintText: '搜索动作、训练部位或器材',
                  prefixIcon: Icon(Icons.search, color: muted, size: 20),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 44,
              child: OutlinedButton(
                onPressed: () => setState(() => favoritesOnly = !favoritesOnly),
                style: OutlinedButton.styleFrom(
                  backgroundColor: favoritesOnly
                      ? lime.withValues(alpha: .12)
                      : null,
                  foregroundColor: favoritesOnly ? lime : muted,
                ),
                child: Icon(
                  favoritesOnly ? Icons.bookmark : Icons.bookmark_border,
                  size: 20,
                  semanticLabel: favoritesOnly ? '显示全部动作' : '只看收藏动作',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ['全部', ...exerciseGroups]
              .map(
                (g) => Pill(
                  g,
                  active: g == group,
                  onTap: () => setState(() => group = g),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ['全部器材', ...exerciseEquipment]
              .map(
                (e) => Pill(
                  e,
                  active: e == equipment,
                  onTap: () => setState(() => equipment = e),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Text(
              favoritesOnly ? '我的收藏' : '全部动作',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            Text(
              '${items.length}',
              style: const TextStyle(color: muted, fontSize: 12),
            ),
            const Spacer(),
            const Icon(Icons.touch_app_outlined, color: muted, size: 14),
            const SizedBox(width: 5),
            const Text(
              '点击查看 3D 示范',
              style: TextStyle(color: muted, fontSize: 10),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (items.isEmpty)
          EmptyHint(
            icon: Icons.search_off,
            title: '暂时没有匹配动作',
            detail: favoritesOnly ? '点击动作卡片右上角，即可收藏。' : '试试其他关键词或筛选条件。',
            action: TextButton(
              onPressed: () => setState(() {
                group = '全部';
                equipment = '全部器材';
                favoritesOnly = false;
                search = '';
                searchController.clear();
              }),
              child: const Text('重置筛选'),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, c) {
              final columns = c.maxWidth > 1050
                  ? 4
                  : c.maxWidth > 650
                  ? 3
                  : 2;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: .96,
                ),
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final e = items[i];
                  final added = widget.state.plan.items.any(
                    (p) => p.exerciseId == e.id,
                  );
                  final favorite = widget.state.favorites.contains(e.id);
                  return Material(
                    color: surface,
                    borderRadius: BorderRadius.circular(20),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () =>
                          showExerciseDetails(context, widget.state, e),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: line.withValues(alpha: .65),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: DecoratedBox(
                                      decoration: const BoxDecoration(
                                        gradient: RadialGradient(
                                          center: Alignment(0, .5),
                                          radius: .85,
                                          colors: [Color(0xFF30383A), surface],
                                        ),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          8,
                                          14,
                                          8,
                                          0,
                                        ),
                                        child: ExerciseThumb(
                                          e,
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const Positioned(
                                    top: 10,
                                    left: 10,
                                    child: Tag('3D'),
                                  ),
                                  Positioned(
                                    right: 3,
                                    top: 0,
                                    child: IconButton(
                                      tooltip: favorite
                                          ? '取消收藏${e.name}'
                                          : '收藏${e.name}',
                                      onPressed: () =>
                                          widget.state.toggleFavorite(e.id),
                                      icon: Icon(
                                        favorite
                                            ? Icons.bookmark
                                            : Icons.bookmark_border,
                                        color: favorite ? lime : ink,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(11, 7, 3, 9),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          e.name,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          '${e.group} · ${e.equipment}',
                                          style: const TextStyle(
                                            color: muted,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: added ? '已加入计划' : '加入计划',
                                    onPressed: added
                                        ? null
                                        : () async {
                                            await widget.state.addExercise(
                                              e.id,
                                            );
                                            if (context.mounted) {
                                              toast(
                                                context,
                                                '${e.name}已加入今日计划',
                                              );
                                            }
                                          },
                                    icon: Icon(
                                      added
                                          ? Icons.check_circle_outline
                                          : Icons.add_circle_outline,
                                      size: 22,
                                      color: added ? muted : lime,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        const SizedBox(height: 22),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: muted, size: 14),
            SizedBox(width: 7),
            Expanded(
              child: Text(
                '按自己的能力选择幅度，训练时以动作质量和舒适感为先。',
                style: TextStyle(color: muted, fontSize: 10, height: 1.6),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

Future<void> showExerciseDetails(
  BuildContext context,
  AppState state,
  Exercise exercise,
) => showAppSheet(context, _ExerciseDetails(state, exercise));

class _ExerciseDetails extends StatefulWidget {
  final AppState state;
  final Exercise exercise;
  const _ExerciseDetails(this.state, this.exercise);
  @override
  State<_ExerciseDetails> createState() => _ExerciseDetailsState();
}

class _ExerciseDetailsState extends State<_ExerciseDetails> {
  bool playing = true;
  bool videoFallback = false;
  late bool side;
  double speed = 1;
  int cameraRevision = 0;
  @override
  void initState() {
    super.initState();
    side = widget.exercise.prefersSideView || widget.exercise.id == 'row';
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.exercise;
    final added = widget.state.plan.items.any((i) => i.exerciseId == e.id);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .86,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    e.name,
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
            Text(
              e.subtitle,
              style: const TextStyle(color: muted, fontSize: 12),
            ),
            const SizedBox(height: 18),
            ExerciseView(
              e,
              key: ValueKey(e.id),
              cameraRevision: cameraRevision,
              playing: playing,
              speed: speed,
              onFallbackChanged: (value) {
                if (mounted && videoFallback != value) {
                  setState(() => videoFallback = value);
                }
              },
              orbit: side ? '90deg 75deg 110%' : '0deg 75deg 110%',
              height: 320,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Pill(
                  playing ? '暂停' : '播放',
                  icon: playing ? Icons.pause : Icons.play_arrow,
                  onTap: () => setState(() => playing = !playing),
                ),
                Pill(
                  '$speed×',
                  onTap: () => setState(() => speed = speed == 1 ? .5 : 1),
                ),
                if (!videoFallback)
                  Pill(
                    '重置',
                    icon: Icons.restart_alt,
                    onTap: () => setState(() {
                      side = false;
                      cameraRevision++;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 22),
            Wrap(
              spacing: 8,
              children: [
                Tag(e.group),
                Tag(e.equipment, color: sky),
                if (e.timed) const Tag('计时动作', color: muted),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              '动作要点',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 10),
            ...e.tips.indexed.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${entry.$1 + 1}.  ${entry.$2}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: muted,
                    height: 1.7,
                  ),
                ),
              ),
            ),
            if (e.id == 'lunge')
              const Text(
                '示意模型展示单侧，练习时请两侧交替。',
                style: TextStyle(fontSize: 11, color: lime),
              ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: added
                  ? null
                  : () async {
                      await widget.state.addExercise(e.id);
                      if (mounted) {
                        setState(() {});
                        if (context.mounted) toast(context, '已加入今日计划');
                      }
                    },
              icon: Icon(added ? Icons.check : Icons.add, size: 18),
              label: Text(added ? '已在今日计划中' : '加入我的计划'),
            ),
          ],
        ),
      ),
    );
  }
}
