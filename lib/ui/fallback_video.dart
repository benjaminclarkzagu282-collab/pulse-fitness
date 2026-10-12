import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../core/models.dart';
import 'theme.dart';

class FallbackVideo extends StatefulWidget {
  final Exercise exercise;
  final bool playing;
  final double speed;
  const FallbackVideo({
    super.key,
    required this.exercise,
    required this.playing,
    this.speed = 1,
  });
  @override
  State<FallbackVideo> createState() => _FallbackVideoState();
}

class _FallbackVideoState extends State<FallbackVideo>
    with WidgetsBindingObserver {
  late final VideoPlayerController controller;
  bool ready = false, failed = false;
  bool interrupted = false;
  Future<void> controls = Future<void>.value();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller = VideoPlayerController.asset(
      'assets/videos/${widget.exercise.id}.mp4',
      // ExerciseView owns the explicit pause/resume lifecycle. Avoid the plugin
      // automatically resuming an already interrupted demonstration.
      videoPlayerOptions: VideoPlayerOptions(allowBackgroundPlayback: true),
    );
    initialize();
  }

  Future<void> initialize() async {
    try {
      await controller.initialize();
      if (!mounted) return;
      await controller.setLooping(true);
      await controller.setVolume(0);
      if (!mounted) return;
      setState(() => ready = true);
      await syncControls();
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  Future<void> syncControls() => controls = controls
      .then((_) async {
        if (!mounted || !ready) {
          return;
        }
        await controller.setPlaybackSpeed(widget.speed);
        if (!mounted) {
          return;
        }
        if (widget.playing && !interrupted) {
          await controller.play();
          // A native rate write can finish after the background pause.
          if (mounted && (interrupted || !widget.playing)) {
            await controller.pause();
          }
        } else {
          await controller.pause();
        }
      })
      .catchError((Object _) {
        if (mounted) {
          setState(() {
            failed = true;
            ready = false;
          });
        }
      });

  @override
  void didUpdateWidget(FallbackVideo old) {
    super.didUpdateWidget(old);
    if (!old.playing && widget.playing) {
      interrupted = false;
    }
    if (ready && (old.speed != widget.speed || old.playing != widget.playing)) {
      syncControls();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      interrupted = true;
      if (ready) {
        // This pause must bypass any pending speed/play operation.
        controller.pause().catchError((Object _) {});
      }
    }
    // Pausing cannot depend on the next Flutter frame while frames are suspended.
    if (ready) {
      syncControls();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: ready
            ? Center(
                child: AspectRatio(
                  aspectRatio: controller.value.aspectRatio,
                  child: VideoPlayer(controller),
                ),
              )
            : Image.asset(widget.exercise.image, fit: BoxFit.contain),
      ),
      Positioned(
        left: 12,
        top: 12,
        child: Text(
          failed ? '静态图示' : '轻量视频 · 不可旋转',
          style: const TextStyle(fontSize: 10, color: muted),
        ),
      ),
      if (!ready && !failed)
        const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    ],
  );
}
