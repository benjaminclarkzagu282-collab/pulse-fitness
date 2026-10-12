import 'dart:async';

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/muscle_guidance.dart';
import '../core/model_assets.dart';
import 'components.dart';
import 'exercise_surface.dart';
import 'theme.dart';
import 'action_teaching_card.dart';
import 'fallback_video.dart';

const _primaryMuscle = Color(0xFFFF642B);
const _stabilizerMuscle = Color(0xFF20BA8A);

class ExerciseView extends StatefulWidget {
  final Exercise exercise;
  final bool playing, muscles;
  final double speed, height;
  final String orbit, selectedRegion;
  final int cameraRevision;
  final ValueChanged<bool>? onFallbackChanged;
  const ExerciseView(
    this.exercise, {
    super.key,
    this.playing = true,
    this.muscles = true,
    this.selectedRegion = 'all',
    this.speed = 1,
    this.height = 340,
    this.orbit = '35deg 75deg 110%',
    this.cameraRevision = 0,
    this.onFallbackChanged,
  });
  @override
  State<ExerciseView> createState() => _ExerciseViewState();
}

class _ExerciseViewState extends State<ExerciseView>
    with WidgetsBindingObserver {
  bool loaded = false;
  late bool muscles = widget.muscles;
  late String selectedRegion = widget.selectedRegion;
  MuscleGuidance? guidance;
  String? error;
  int retry = 0;
  Timer? deadline;
  final phaseIndex = ValueNotifier<int>(0);
  ModelLocation? location;
  ModelRequest? request;
  int generation = 0, received = 0, total = 0;
  String stage = '准备动作';
  bool interrupted = false, observing = false, fallback = false;
  double? seekTime;
  String? inspectionOrbit;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    loadGuidance();
    resolveModel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onFallbackChanged?.call(false);
    });
  }

  Future<void> resolveModel() async {
    final revision = ++generation;
    request?.cancel();
    request = ModelRequest();
    final token = request!;
    location?.release();
    location = null;
    deadline?.cancel();
    try {
      final store = await ModelAssets.shared;
      final result = await store.resolve(
        widget.exercise.id,
        request: token,
        onProgress: (value, size, label) {
          if (mounted && revision == generation) {
            setState(() {
              received = value;
              total = size;
              stage = label;
            });
          }
        },
      );
      if (!mounted || revision != generation) {
        result.release();
        return;
      }
      setState(() {
        location = result;
        stage = '准备 3D 播放';
      });
      startDeadline();
    } on ModelDownloadCancelled {
      /* A newer action or disposal owns the UI. */
    } catch (failure) {
      if (mounted && revision == generation) {
        setState(
          () => error = failure is ModelAssetException
              ? failure.message
              : '动作暂时无法载入，请重试。',
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && mounted && !interrupted) {
      setState(() => interrupted = true);
    }
  }

  void retryModel() {
    setState(() {
      error = null;
      loaded = false;
      fallback = false;
      retry++;
    });
    widget.onFallbackChanged?.call(false);
    if (guidance == null) loadGuidance();
    resolveModel();
  }

  void useFallback() {
    generation++;
    request?.cancel();
    deadline?.cancel();
    location?.release();
    setState(() {
      location = null;
      fallback = true;
      error = null;
      observing = false;
      seekTime = null;
    });
    widget.onFallbackChanged?.call(true);
  }

  Future<void> loadGuidance() async {
    try {
      final value = await MuscleGuidance.load();
      if (mounted) {
        setState(() {
          guidance = value;
          normalizeSelection();
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = '动作资料暂时无法载入，请点击重试。');
    }
  }

  void normalizeSelection() {
    if (!(guidance?.exercises[widget.exercise.id]?.regions.any(
          (region) => region.id == selectedRegion,
        ) ??
        false)) {
      selectedRegion = 'all';
    }
  }

  void startDeadline() {
    deadline?.cancel();
    deadline = Timer(const Duration(seconds: 30), () {
      if (mounted && !loaded) {
        setState(() => error = '载入时间较长，请检查设备的 3D 支持后重试。');
      }
    });
  }

  @override
  void didUpdateWidget(ExerciseView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.exercise.id != widget.exercise.id) {
      loaded = false;
      error = null;
      selectedRegion = 'all';
      inspectionOrbit = null;
      seekTime = null;
      observing = false;
      fallback = false;
      phaseIndex.value = 0;
      resolveModel();
    } else if (oldWidget.selectedRegion != widget.selectedRegion) {
      selectedRegion = widget.selectedRegion;
      normalizeSelection();
    }
    if (oldWidget.muscles != widget.muscles) muscles = widget.muscles;
    if (oldWidget.orbit != widget.orbit ||
        oldWidget.cameraRevision != widget.cameraRevision) {
      inspectionOrbit = null;
    }
    if (!oldWidget.playing && widget.playing) interrupted = false;
  }

  @override
  void dispose() {
    deadline?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    generation++;
    request?.cancel();
    location?.release();
    phaseIndex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final exercise = guidance?.exercises[widget.exercise.id];
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                fallback
                    ? '轻量动作示范'
                    : muscles
                    ? '肌群参与示意'
                    : '3D 动作示意',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (!fallback) ...[
              _mode('普通 NORMAL', false),
              const SizedBox(width: 5),
              _mode('肌群 MUSCLE', true),
            ],
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final aspect = constraints.maxWidth / widget.height;
            final orbit = exercise == null
                ? widget.orbit
                : exerciseCameraOrbit(
                    inspectionOrbit ?? widget.orbit,
                    aspect,
                    exercise.camera,
                  );
            return ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                height: widget.height,
                child: Stack(
                  children: [
                    if (guidance != null &&
                        exercise != null &&
                        location != null &&
                        !fallback &&
                        error == null)
                      Positioned.fill(
                        child: ExerciseSurface(
                          key: ValueKey('${widget.exercise.id}-$retry'),
                          src: location!.src,
                          exerciseId: widget.exercise.id,
                          guidance: guidance!,
                          muscles: muscles,
                          selectedRegion: selectedRegion,
                          reducedMotion: reducedMotion,
                          playing: widget.playing && !interrupted && !observing,
                          seekTime: seekTime,
                          speed: widget.speed,
                          orbit: orbit,
                          cameraRevision: widget.cameraRevision,
                          target: exercise.cameraTarget,
                          onPhase: (index) {
                            if (mounted && phaseIndex.value != index) {
                              phaseIndex.value = index;
                            }
                          },
                          onLoaded: () {
                            if (mounted) {
                              setState(() {
                                loaded = true;
                                error = null;
                              });
                            }
                            deadline?.cancel();
                          },
                          onError: (value) {
                            if (mounted) setState(() => error = value);
                          },
                        ),
                      ),
                    if (!loaded && error == null && !fallback)
                      Positioned.fill(
                        child: ColoredBox(
                          color: Color(0xFF171D18),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: lime,
                                ),
                                SizedBox(height: 12),
                                Text(
                                  total > 0
                                      ? '$stage ${(received / total * 100).clamp(0, 100).round()}%'
                                      : stage,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: muted,
                                  ),
                                ),
                                if (total > 0)
                                  Text(
                                    '${(received / 1048576).toStringAsFixed(1)} / ${(total / 1048576).toStringAsFixed(1)} MB',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: muted,
                                    ),
                                  ),
                                TextButton(
                                  onPressed: useFallback,
                                  child: const Text('先看轻量视频'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (error != null)
                      Positioned.fill(
                        child: ColoredBox(
                          color: surface,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.view_in_ar_outlined,
                                    color: muted,
                                    size: 36,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    error!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: retryModel,
                                    child: const Text('重新载入'),
                                  ),
                                  TextButton(
                                    onPressed: useFallback,
                                    child: const Text('查看轻量视频'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (fallback)
                      Positioned.fill(
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: FallbackVideo(
                                key: ValueKey(widget.exercise.id),
                                exercise: widget.exercise,
                                speed: widget.speed,
                                playing:
                                    widget.playing &&
                                    !interrupted &&
                                    !reducedMotion,
                              ),
                            ),
                            Positioned(
                              left: 12,
                              right: 12,
                              bottom: 8,
                              child: Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      '轻量示范 · 配合下方动作要点',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: muted,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: retryModel,
                                    child: const Text('切换 3D'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (muscles && !fallback)
                      const Positioned(
                        left: 12,
                        top: 12,
                        child: IgnorePointer(
                          child: Row(
                            children: [
                              Tag('主要参与', color: _primaryMuscle),
                              SizedBox(width: 6),
                              Tag('辅助稳定', color: _stabilizerMuscle),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        if (interrupted)
          TextButton.icon(
            onPressed: () => setState(() => interrupted = false),
            icon: const Icon(Icons.play_arrow),
            label: const Text('继续播放'),
          ),
        if (exercise != null && !fallback) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final entry in const {
                '正面': '0deg',
                '侧面': '90deg',
                '背面': '180deg',
              }.entries)
                Pill(
                  entry.key,
                  active: inspectionOrbit?.startsWith(entry.value) ?? false,
                  onTap: () => setState(
                    () => inspectionOrbit = '${entry.value} 75deg 110%',
                  ),
                ),
              if (observing)
                Pill(
                  '继续示范',
                  active: true,
                  onTap: () => setState(() {
                    observing = false;
                    seekTime = null;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final phase in exercise.phases)
                Pill(
                  phase.label,
                  active:
                      observing && seekTime == (phase.start + phase.end) / 2,
                  onTap: () => setState(() {
                    observing = true;
                    seekTime = (phase.start + phase.end) / 2;
                  }),
                ),
            ],
          ),
        ],
        if (exercise?.demoNote case final note?) ...[
          const SizedBox(height: 8),
          Text(
            note,
            style: const TextStyle(fontSize: 11, color: muted, height: 1.6),
          ),
        ],
        if (guidance != null)
          ActionTeachingCard(exercise: widget.exercise, guidance: guidance!),
        if (muscles && exercise != null && !fallback) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _regionChip('all', '全部肌群', lime),
              for (final region in exercise.regions)
                _regionChip(
                  region.id,
                  region.name,
                  region.stabilizer ? _stabilizerMuscle : _primaryMuscle,
                ),
            ],
          ),
          const SizedBox(height: 10),
          ValueListenableBuilder<int>(
            valueListenable: phaseIndex,
            builder: (context, index, child) {
              final phase = exercise.phases.isEmpty
                  ? null
                  : exercise.phases[index.clamp(0, exercise.phases.length - 1)];
              final region = exercise.regions
                  .where((region) => region.id == selectedRegion)
                  .firstOrNull;
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: surface2,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (phase != null) ...[
                      Text(
                        '${phase.label} · 参与示意',
                        style: const TextStyle(
                          fontSize: 12,
                          color: ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        phase.text,
                        style: const TextStyle(
                          fontSize: 11,
                          color: muted,
                          height: 1.6,
                        ),
                      ),
                    ],
                    if (region != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        '${region.name} · ${region.description}',
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.6,
                          color: region.stabilizer
                              ? _stabilizerMuscle
                              : _primaryMuscle,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    const Text(
                      '颜色标示肌群参与位置，亮度仅用于提示动作阶段。',
                      style: TextStyle(fontSize: 9, color: muted),
                    ),
                    if (reducedMotion)
                      const Text(
                        '已按系统设置减少动态效果',
                        style: TextStyle(fontSize: 9, color: muted),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _mode(String label, bool value) => Semantics(
    selected: muscles == value,
    button: true,
    child: InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: () => setState(() => muscles = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
        decoration: BoxDecoration(
          color: muscles == value ? lime : surface2,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: muscles == value ? bg : muted,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ),
  );

  Widget _regionChip(String id, String name, Color color) => ChoiceChip(
    label: Text(name),
    selected: selectedRegion == id,
    showCheckmark: false,
    labelStyle: TextStyle(
      fontSize: 10,
      color: selectedRegion == id ? color : muted,
    ),
    selectedColor: color.withValues(alpha: .13),
    backgroundColor: surface,
    side: BorderSide(color: selectedRegion == id ? color : line),
    visualDensity: VisualDensity.compact,
    onSelected: (_) => setState(() => selectedRegion = id),
  );
}
