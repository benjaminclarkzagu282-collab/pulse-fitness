import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:pulse_fitness/core/catalog.dart';
import 'package:pulse_fitness/ui/fallback_video.dart';

class FakeVideoPlatform extends VideoPlayerPlatform {
  final events = StreamController<VideoEvent>();
  final speeds = <double>[];
  final sources = <DataSource>[];
  bool playing = false, disposed = false;
  Completer<void>? firstSpeedGate;
  double? appliedSpeed;
  bool resumeOnSpeedWrite = false;
  @override
  Future<void> init() async {}
  @override
  Future<void> setMixWithOthers(bool value) async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    sources.add(options.dataSource);
    events.add(
      VideoEvent(
        eventType: VideoEventType.initialized,
        duration: const Duration(seconds: 6),
        size: const Size(256, 320),
      ),
    );
    return 1;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int id) => events.stream;
  @override
  Future<void> dispose(int id) async {
    disposed = true;
    await events.close();
  }

  @override
  Future<void> play(int id) async {
    playing = true;
  }

  @override
  Future<void> pause(int id) async {
    playing = false;
  }

  @override
  Future<void> setLooping(int id, bool value) async {}
  @override
  Future<void> setVolume(int id, double value) async {}
  @override
  Future<void> setPlaybackSpeed(int id, double value) async {
    speeds.add(value);
    if (value == .5 && firstSpeedGate != null) await firstSpeedGate!.future;
    appliedSpeed = value;
    if (resumeOnSpeedWrite) playing = true;
  }

  @override
  Future<Duration> getPosition(int id) async => Duration.zero;
  @override
  Future<void> seekTo(int id, Duration value) async {}
  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const SizedBox();
}

void main() {
  testWidgets('background pause bypasses an unfinished native rate update', (
    tester,
  ) async {
    final previous = VideoPlayerPlatform.instance;
    final fake = FakeVideoPlatform()
      ..firstSpeedGate = Completer<void>()
      ..resumeOnSpeedWrite = true;
    VideoPlayerPlatform.instance = fake;
    addTearDown(() => VideoPlayerPlatform.instance = previous);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 256,
          height: 320,
          child: FallbackVideo(
            exercise: exerciseById('squat'),
            playing: true,
            speed: .5,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    });
    expect(fake.speeds, contains(.5));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(fake.playing, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    fake.firstSpeedGate!.complete();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    });
    await tester.pumpAndSettle();
    expect(fake.playing, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    });
  });
  testWidgets('a speed edit during initialization applies the latest value', (
    tester,
  ) async {
    final previous = VideoPlayerPlatform.instance;
    final fake = FakeVideoPlatform()..firstSpeedGate = Completer<void>();
    VideoPlayerPlatform.instance = fake;
    addTearDown(() => VideoPlayerPlatform.instance = previous);
    Widget view(double speed) => MaterialApp(
      home: SizedBox(
        width: 256,
        height: 320,
        child: FallbackVideo(
          exercise: exerciseById('squat'),
          playing: true,
          speed: speed,
        ),
      ),
    );
    await tester.pumpWidget(view(.5));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    });
    expect(fake.speeds, contains(.5));
    await tester.pumpWidget(view(1));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    });
    fake.firstSpeedGate!.complete();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    });
    await tester.pumpAndSettle();
    expect(fake.appliedSpeed, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    });
  });
  testWidgets('fallback honors speed, pauses and releases its local video', (
    tester,
  ) async {
    final previous = VideoPlayerPlatform.instance;
    final fake = FakeVideoPlatform();
    VideoPlayerPlatform.instance = fake;
    addTearDown(() => VideoPlayerPlatform.instance = previous);
    Widget view(bool playing, double speed) => MaterialApp(
      home: SizedBox(
        width: 256,
        height: 320,
        child: FallbackVideo(
          exercise: exerciseById('squat'),
          playing: playing,
          speed: speed,
        ),
      ),
    );
    await tester.pumpWidget(view(true, .5));
    await tester.pumpAndSettle();
    expect(fake.sources.single.asset, 'assets/videos/squat.mp4');
    expect(fake.speeds.last, .5);
    expect(fake.playing, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(fake.playing, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(fake.playing, isFalse);
    await tester.pumpWidget(view(false, 1));
    await tester.pumpAndSettle();
    final dynamic video = tester.state(find.byType(FallbackVideo));
    expect(video.controller.value.playbackSpeed, 1);
    expect(fake.playing, isFalse);
    await tester.pumpWidget(view(true, 1));
    await tester.pumpAndSettle();
    expect(fake.playing, isTrue);
    expect(fake.appliedSpeed, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    });
    expect(fake.disposed, isTrue);
  });
}
