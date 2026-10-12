import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_fitness/core/catalog.dart';
import 'package:pulse_fitness/core/muscle_guidance.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'bundled guidance covers every library exercise and the full clip',
    () async {
      final guidance = await MuscleGuidance.load();
      final duration = (guidance.catalog['duration'] as num).toDouble();
      expect(
        guidance.exercises.keys.toSet(),
        exercises.map((e) => e.id).toSet(),
      );
      expect(guidance.controllerScript, contains('root.PulseMuscles'));
      for (final entry in guidance.exercises.entries) {
        final exercise = entry.value;
        expect(exercise.regions, isNotEmpty, reason: entry.key);
        expect(exercise.phases, isNotEmpty, reason: entry.key);
        expect(exercise.phases.first.start, 0, reason: entry.key);
        expect(exercise.phases.last.end, duration, reason: entry.key);
        for (var i = 0; i < exercise.phases.length; i++) {
          final phase = exercise.phases[i];
          expect(phase.end, greaterThan(phase.start), reason: entry.key);
          expect(phase.label, isNotEmpty);
          expect(phase.text, isNotEmpty);
          if (i > 0) {
            expect(phase.start, exercise.phases[i - 1].end, reason: entry.key);
          }
        }
        expect(
          exercise.regions.map((r) => r.id).toSet().length,
          exercise.regions.length,
          reason: '${entry.key} has no duplicate selectable regions',
        );
        for (final region in exercise.regions) {
          expect(['primary', 'stabilizer'], contains(region.role));
          expect(['front', 'back', 'side'], contains(region.view));
          expect(region.description, isNotEmpty);
        }
      }
    },
  );

  test('hold and back-focus guidance remain specific to each action', () async {
    final guidance = await MuscleGuidance.load();
    final plank = guidance.exercises['plank']!;
    expect(plank.phases, hasLength(1));
    expect(plank.regions.singleWhere((r) => r.id == 'core').stabilizer, false);
    final squat = guidance.exercises['squat']!;
    expect(squat.regions.singleWhere((r) => r.id == 'core').stabilizer, true);
    expect(squat.regions.singleWhere((r) => r.id == 'glutes').view, 'back');
    final row = guidance.exercises['row']!;
    expect(row.regions.singleWhere((r) => r.id == 'lats').view, 'back');
    expect(row.defaultView, 'side');
  });

  test('native overhead motion fits vertically on a wide viewport', () {
    final camera = MuscleCamera.fromJson({
      'floor': false,
      'minDistance': 2.8,
      'motionWidth': 1.2,
      'motionHeight': 2.4,
      'depthMargin': .85,
    });
    final orbit = exerciseCameraOrbit('0deg 75deg 110%', 1.8, camera);
    final distance = double.parse(orbit.split(' ').last.replaceAll('m', ''));
    final phi = 75 * math.pi / 180;
    for (final y in [0.0, 2.4]) {
      for (final z in [-.3, .3]) {
        final up = (y - 1.2) * math.sin(phi) - z * math.cos(phi);
        final depth = distance - (y - 1.2) * math.cos(phi) - z * math.sin(phi);
        expect(up.abs() / (depth * math.tan(math.pi / 12)), lessThan(.96));
      }
    }
    expect(orbit, startsWith('0deg 75deg '));
    expect(orbit, endsWith('m'));
  });

  test('every motion declares a fixed camera envelope and side previews are explicit', () async {
    final guidance = await MuscleGuidance.load();
    for (final entry in (guidance.catalog['exercises'] as Map).entries) {
      final definition = entry.value as Map;
      expect(definition['camera'], isA<Map>(), reason: entry.key);
      final camera = definition['camera'] as Map;
      expect(camera['floor'], isA<bool>(), reason: entry.key);
      expect(
        camera['minDistance'],
        greaterThanOrEqualTo(2.8),
        reason: entry.key,
      );
      expect(camera['motionWidth'], greaterThan(0), reason: entry.key);
    }
    for (final id in [
      'lunge',
      'split_squat',
      'single_arm_row',
      'bird_dog',
      'side_plank',
    ]) {
      expect(
        guidance.catalog['exercises'][id]['demoNote'],
        contains('单侧'),
        reason: id,
      );
    }
    expect(guidance.exercises['side_plank']!.phases, hasLength(1));
  });

  test(
    'jumping-jack front view fits the full motion envelope at all widths',
    () async {
      final camera =
          (await MuscleGuidance.load()).exercises['jumping_jack']!.camera;
      // Project the full motion envelope into the default front camera's 30° perspective.
      // This catches clipping even when the chosen distance looks plausible.
      expect(
        exerciseCameraOrbit('90deg 75deg 110%', 1, camera),
        startsWith('90deg 75deg '),
      );
      for (final aspect in [.6, 1.0, 1.6]) {
        final orbit = exerciseCameraOrbit('0deg 75deg 110%', aspect, camera);
        expect(orbit, startsWith('0deg 75deg '));
        final distance = double.parse(
          orbit.split(' ').last.replaceAll('m', ''),
        );
        final phi = 75 * math.pi / 180;
        for (final x in [-.9, .9]) {
          for (final y in [0.0, 1.95]) {
            for (final z in [-.25, .25]) {
              final up = (y - .95) * math.sin(phi) - z * math.cos(phi);
              final depth =
                  distance - (y - .95) * math.cos(phi) - z * math.sin(phi);
              final halfHeight = depth * math.tan(math.pi / 12);
              expect(up.abs() / halfHeight, lessThan(.96));
              expect(x.abs() / (halfHeight * aspect), lessThan(.96));
            }
          }
        }
      }
    },
  );

  test(
    'new motion envelopes fit at front, side and back angles on mobile',
    () async {
      final guidance = await MuscleGuidance.load();
      // Rounded outward from the 361-sample exported mesh bounds, in glTF axes.
      const bounds = {
        'sumo_squat': [
          [-.40, 0, -.19],
          [.40, 1.43, .48],
        ],
        'split_squat': [
          [-.24, 0, -.49],
          [.24, 1.36, .37],
        ],
        'lateral_lunge': [
          [-.43, 0, -.35],
          [.43, 1.43, .48],
        ],
        'calf_raise': [
          [-.24, 0, -.13],
          [.24, 1.52, .15],
        ],
        'floor_press': [
          [-.44, 0, -.71],
          [.44, .64, .66],
        ],
        'shoulder_press': [
          [-.45, 0, -.13],
          [.45, 1.74, .17],
        ],
        'lateral_raise': [
          [-.70, 0, -.13],
          [.70, 1.48, .11],
        ],
        'reverse_fly': [
          [-.69, 0, -.26],
          [.69, 1.01, .47],
        ],
        'romanian_deadlift': [
          [-.31, 0, -.33],
          [.31, 1.48, .39],
        ],
        'incline_pushup': [
          [-.41, 0, -.84],
          [.41, .93, .71],
        ],
        'single_arm_row': [
          [-.29, 0, -.26],
          [.40, .99, .46],
        ],
        'kneeling_pushup': [
          [-.32, 0, -.77],
          [.32, .57, .67],
        ],

        'dead_bug': [
          [-.24, 0, -.89],
          [.24, .66, .85],
        ],
        'bird_dog': [
          [-.24, 0, -.92],
          [.25, .52, .92],
        ],
        'side_plank': [
          [-.11, 0, -.88],
          [.33, .70, .58],
        ],
        'step_jack': [
          [-.76, 0, -.14],
          [.76, 1.59, .22],
        ],
      };
      for (final entry in bounds.entries) {
        final definition = guidance.exercises[entry.key]!;
        final targetY = double.parse(
          definition.cameraTarget.split(' ')[1].replaceAll('m', ''),
        );
        for (final aspect in [.6, 1.0, 1.6]) {
          for (final angle in [0, 45, 90, 135, 180, 225, 270, 315]) {
            final orbit = exerciseCameraOrbit(
              '${angle}deg 75deg 110%',
              aspect,
              definition.camera,
            );
            final distance = double.parse(
              orbit.split(' ').last.replaceAll('m', ''),
            );
            final theta = angle * math.pi / 180;
            final phi = 75 * math.pi / 180;
            for (final x in [entry.value[0][0], entry.value[1][0]]) {
              for (final y in [entry.value[0][1], entry.value[1][1]]) {
                for (final z in [entry.value[0][2], entry.value[1][2]]) {
                  final horizontal = x * math.cos(theta) - z * math.sin(theta);
                  final radial = x * math.sin(theta) + z * math.cos(theta);
                  final up =
                      (y - targetY) * math.sin(phi) - radial * math.cos(phi);
                  final depth =
                      distance -
                      (y - targetY) * math.cos(phi) -
                      radial * math.sin(phi);
                  final halfHeight = depth * math.tan(math.pi / 12);
                  expect(
                    up.abs() / halfHeight,
                    lessThan(.96),
                    reason: '${entry.key}: vertical, $angle°, $aspect',
                  );
                  expect(
                    horizontal.abs() / (halfHeight * aspect),
                    lessThan(.96),
                    reason: '${entry.key}: horizontal, $angle°, $aspect',
                  );
                }
              }
            }
          }
        }
      }
    },
  );
}
