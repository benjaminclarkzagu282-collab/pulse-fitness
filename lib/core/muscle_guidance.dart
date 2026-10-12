import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';

/// Fits a fixed full-motion envelope at 30° without following animation phase.
String exerciseCameraOrbit(
  String orbit,
  double aspectRatio,
  MuscleCamera camera,
) {
  assert(aspectRatio > 0 && aspectRatio.isFinite);
  final perspective = 2 * math.tan(math.pi / 12);
  final distance = math.max(
    camera.minDistance,
    math.max(
          camera.motionWidth * 1.16 / (perspective * aspectRatio),
          camera.motionHeight * 1.16 / perspective,
        ) +
        camera.depthMargin +
        .3,
  );
  return orbit.replaceFirst(RegExp(r'\S+$'), '${distance.toStringAsFixed(3)}m');
}

class MuscleCamera {
  final bool floor;
  final double minDistance, motionWidth, motionHeight, depthMargin;
  const MuscleCamera({
    required this.floor,
    required this.minDistance,
    required this.motionWidth,
    this.motionHeight = 0,
    this.depthMargin = 0,
  });
  factory MuscleCamera.fromJson(Map<String, dynamic> json) => MuscleCamera(
    floor: json['floor'] as bool,
    minDistance: (json['minDistance'] as num).toDouble(),
    motionWidth: (json['motionWidth'] as num).toDouble(),
    motionHeight: (json['motionHeight'] as num?)?.toDouble() ?? 0,
    depthMargin: (json['depthMargin'] as num?)?.toDouble() ?? 0,
  );
}

class MuscleRegion {
  final String id, name, role, description, view;
  const MuscleRegion({
    required this.id,
    required this.name,
    required this.role,
    required this.description,
    required this.view,
  });
  factory MuscleRegion.fromJson(Map<String, dynamic> json) => MuscleRegion(
    id: json['id'] as String,
    name: json['name'] as String,
    role: json['role'] as String,
    description: json['description'] as String,
    view: json['view'] as String,
  );
  bool get stabilizer => role == 'stabilizer';
}

class MusclePhase {
  final double start, end;
  final String label, text;
  const MusclePhase(this.start, this.end, this.label, this.text);
  factory MusclePhase.fromJson(Map<String, dynamic> json) => MusclePhase(
    (json['start'] as num).toDouble(),
    (json['end'] as num).toDouble(),
    json['label'] as String,
    json['text'] as String,
  );
}

class MuscleExercise {
  final List<MuscleRegion> regions;
  final List<MusclePhase> phases;
  final String defaultView, cameraTarget;
  final String? demoNote;
  final MuscleCamera camera;
  const MuscleExercise({
    required this.regions,
    required this.phases,
    required this.defaultView,
    required this.cameraTarget,
    required this.camera,
    this.demoNote,
  });
  factory MuscleExercise.fromJson(Map<String, dynamic> json) => MuscleExercise(
    regions: (json['regions'] as List)
        .map((v) => MuscleRegion.fromJson(Map<String, dynamic>.from(v)))
        .toList(growable: false),
    phases: (json['phases'] as List)
        .map((v) => MusclePhase.fromJson(Map<String, dynamic>.from(v)))
        .toList(growable: false),
    defaultView: json['defaultView'] as String,
    cameraTarget: json['cameraTarget'] as String,
    camera: MuscleCamera.fromJson(
      Map<String, dynamic>.from(json['camera'] as Map),
    ),
    demoNote: json['demoNote'] as String?,
  );
}

/// One local catalog and controller serve both web and native viewers.
class MuscleGuidance {
  final Map<String, dynamic> catalog;
  final String controllerScript;
  late final Map<String, MuscleExercise> exercises =
      (catalog['exercises'] as Map<String, dynamic>).map(
        (id, value) => MapEntry(
          id,
          MuscleExercise.fromJson(Map<String, dynamic>.from(value)),
        ),
      );
  MuscleGuidance(this.catalog, this.controllerScript);

  static Future<MuscleGuidance>? _cached;
  static Future<MuscleGuidance> load() =>
      _cached ??= _load().onError((Object e, StackTrace s) {
        _cached = null;
        Error.throwWithStackTrace(e, s);
      });
  static Future<MuscleGuidance> _load() async {
    final values = await Future.wait([
      rootBundle.loadString('assets/muscles/catalog.json'),
      rootBundle.loadString('assets/muscles/controller.js'),
    ]);
    return MuscleGuidance(
      jsonDecode(values[0]) as Map<String, dynamic>,
      values[1],
    );
  }
}
