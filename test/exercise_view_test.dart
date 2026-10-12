import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_fitness/core/catalog.dart';
import 'package:pulse_fitness/ui/exercise_view.dart';
import 'package:pulse_fitness/ui/theme.dart';

void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets('video fallback remains actionable at $width px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: pulseTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ExerciseView(exerciseById('row'), playing: false),
              ),
            ),
          ),
        ),
      );
      // This button must receive input even while the model is loading.
      await tester.tap(find.text('先看轻量视频'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('切换 3D'), findsOneWidget);
      expect(find.text('轻量动作示范'), findsOneWidget);
      expect(find.text('全部肌群'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  }
  testWidgets(
    'viewer requires explicit resume after returning from background',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ExerciseView(exerciseById('row')),
            ),
          ),
        ),
      );
      final dynamic viewer = tester.state(find.byType(ExerciseView));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(viewer.interrupted, isTrue);
      await tester.pump();
      await tester.tap(find.text('继续播放'));
      await tester.pump();
      expect(viewer.interrupted, isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
}
