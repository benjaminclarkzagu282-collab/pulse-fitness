import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../core/muscle_guidance.dart';

@JS('PulseMuscles.create')
external _MuscleController _createMuscles(JSObject viewer, JSObject options);

extension type _MuscleController(JSObject _) implements JSObject {
  external void update(JSObject options);
  external void dispose();
}

extension type _Options(JSObject _) implements JSObject {
  external set onPhase(JSFunction value);
}

extension type _Phase(JSObject _) implements JSObject {
  external String get exerciseId;
  external int get index;
}

class ExerciseSurface extends StatefulWidget {
  final String src, exerciseId;
  final bool playing, muscles, reducedMotion;
  final String selectedRegion;
  final double speed;
  final double? seekTime;
  final String orbit, target;
  final int cameraRevision;
  final MuscleGuidance guidance;
  final VoidCallback onLoaded;
  final ValueChanged<String> onError;
  final ValueChanged<int> onPhase;
  const ExerciseSurface({
    super.key,
    required this.src,
    required this.exerciseId,
    required this.playing,
    required this.speed,
    this.seekTime,
    required this.orbit,
    required this.target,
    required this.cameraRevision,
    required this.guidance,
    required this.muscles,
    required this.selectedRegion,
    required this.reducedMotion,
    required this.onLoaded,
    required this.onError,
    required this.onPhase,
  });
  @override
  State<ExerciseSurface> createState() => _ExerciseSurfaceState();
}

class _ExerciseSurfaceState extends State<ExerciseSurface>
    with WidgetsBindingObserver {
  web.HTMLElement? element;
  JSFunction? loadedHandler, errorHandler;
  _MuscleController? musclesController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      musclesController?.update({'playing': false}.jsify() as JSObject);
    }
  }

  @override
  void didUpdateWidget(ExerciseSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.src != widget.src) {
      element?.setAttribute('src', source);
    }
    final patch = <String, Object>{
      'exerciseId': widget.exerciseId,
      'playing': widget.playing,
      'speed': widget.speed,
      'muscles': widget.muscles,
      'selectedRegion': widget.selectedRegion,
      'reducedMotion': widget.reducedMotion,
      if (widget.seekTime != null && widget.seekTime != oldWidget.seekTime)
        'seekTime': widget.seekTime!,
      if (oldWidget.orbit != widget.orbit ||
          oldWidget.cameraRevision != widget.cameraRevision)
        'orbit': widget.orbit,
      if (oldWidget.target != widget.target) 'target': widget.target,
    };
    musclesController?.update(patch.jsify() as JSObject);
  }

  String get source =>
      widget.src.startsWith('assets/') ? 'assets/${widget.src}' : widget.src;

  void create(Object object) {
    final e = object as web.HTMLElement;
    element = e;
    if (web.document.getElementById('pulse-muscle-controller') == null) {
      final script = web.HTMLScriptElement()
        ..id = 'pulse-muscle-controller'
        ..text = widget.guidance.controllerScript;
      web.document.head!.appendChild(script);
    }
    e.style
      ..width = '100%'
      ..height = '100%'
      ..backgroundColor = '#171d18'
      ..setProperty('--poster-color', '#171d18');
    e.setAttribute('src', source);
    e.setAttribute('alt', '可旋转的三维运动与肌群参与示意');
    e.setAttribute('camera-controls', '');
    e.setAttribute('disable-pan', '');
    e.setAttribute('touch-action', 'pan-y');
    e.setAttribute('animation-name', 'Exercise');
    e.setAttribute('shadow-intensity', '0.9');
    e.setAttribute('shadow-softness', '1');
    e.setAttribute('exposure', '1.1');
    e.setAttribute('interaction-prompt', 'none');
    e.setAttribute('camera-orbit', widget.orbit);
    e.setAttribute('camera-target', widget.target);
    e.setAttribute('field-of-view', '30deg');
    // Runtime morph basis bounds differ from the evaluated native character.
    // Explicit metre limits keep the catalog's measured fit authoritative.
    e.setAttribute('min-camera-orbit', 'auto 15deg 1.5m');
    e.setAttribute('max-camera-orbit', 'auto 95deg 20m');
    final options = _Options(
      {
            'catalog': widget.guidance.catalog,
            'exerciseId': widget.exerciseId,
            'playing': widget.playing,
            'speed': widget.speed,
            'muscles': widget.muscles,
            'selectedRegion': widget.selectedRegion,
            'reducedMotion': widget.reducedMotion,
            if (widget.seekTime != null) 'seekTime': widget.seekTime!,
          }.jsify()
          as JSObject,
    );
    options.onPhase = ((JSObject value) {
      final phase = _Phase(value);
      if (mounted && phase.exerciseId == widget.exerciseId) {
        widget.onPhase(phase.index);
      }
    }).toJS;
    musclesController = _createMuscles(e, options);
    loadedHandler = ((web.Event _) {
      if (mounted) widget.onLoaded();
    }).toJS;
    errorHandler = ((web.Event _) {
      if (mounted) widget.onError('模型暂时无法载入，请点击重试。');
    }).toJS;
    e.addEventListener('load', loadedHandler);
    e.addEventListener('error', errorHandler);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    musclesController?.dispose();
    if (loadedHandler != null) {
      element?.removeEventListener('load', loadedHandler);
    }
    if (errorHandler != null) {
      element?.removeEventListener('error', errorHandler);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView.fromTagName(
    tagName: 'model-viewer',
    onElementCreated: create,
  );
}
