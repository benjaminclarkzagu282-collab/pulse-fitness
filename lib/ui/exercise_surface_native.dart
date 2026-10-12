import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/muscle_guidance.dart';

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
  WebViewController? controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      controller?.runJavaScript(
        'window.pulseMuscles?.update({playing:false});',
      );
    }
  }

  Map<String, Object> get controls => {
    'exerciseId': widget.exerciseId,
    'playing': widget.playing,
    'speed': widget.speed,
    'muscles': widget.muscles,
    'selectedRegion': widget.selectedRegion,
    'reducedMotion': widget.reducedMotion,
    if (widget.seekTime != null) 'seekTime': widget.seekTime!,
  };

  @override
  void didUpdateWidget(ExerciseSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    final patch = <String, Object>{
      ...controls,
      if (oldWidget.orbit != widget.orbit ||
          oldWidget.cameraRevision != widget.cameraRevision)
        'orbit': widget.orbit,
      if (oldWidget.target != widget.target) 'target': widget.target,
    };
    controller?.runJavaScript(
      'window.pulseMuscles?.update(${jsonEncode(patch)});',
    );
  }

  void handleMessage(JavaScriptMessage message) {
    if (!mounted) return;
    final payload = jsonDecode(message.message) as Map<String, dynamic>;
    if (payload['type'] == 'loaded') {
      controller?.runJavaScript(
        'window.pulseMuscles?.update(${jsonEncode(controls)});',
      );
      widget.onLoaded();
    } else if (payload['type'] == 'phase') {
      if (payload['exerciseId'] == widget.exerciseId) {
        widget.onPhase(payload['index'] as int);
      }
    } else if (payload['type'] == 'error') {
      widget.onError('模型暂时无法载入，请重试。');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller?.runJavaScript('window.pulseMuscles?.dispose();');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ModelViewer(
    key: ValueKey(widget.src),
    src: widget.src,
    alt: '三维运动与肌群参与示意',
    autoPlay: false,
    animationName: 'Exercise',
    cameraOrbit: widget.orbit,
    cameraTarget: widget.target,
    fieldOfView: '30deg',
    minCameraOrbit: 'auto 15deg 1.5m',
    maxCameraOrbit: 'auto 95deg 20m',
    cameraControls: true,
    disablePan: true,
    interactionPrompt: InteractionPrompt.none,
    backgroundColor: const Color(0xFF171D18),
    shadowIntensity: .9,
    exposure: 1.1,
    debugLogging: false,
    javascriptChannels: {
      JavascriptChannel('PulseViewer', onMessageReceived: handleMessage),
    },
    onWebViewCreated: (c) => controller = c,
    relatedJs:
        '''
${widget.guidance.controllerScript}
(function () {
  const viewer = document.querySelector('model-viewer');
  const options = ${jsonEncode({...controls, 'catalog': widget.guidance.catalog}).replaceAll('<', r'\u003c')};
  options.onPhase = phase => PulseViewer.postMessage(JSON.stringify({type:'phase', ...phase}));
  window.pulseMuscles = PulseMuscles.create(viewer, options);
  viewer.addEventListener('load', () => PulseViewer.postMessage(JSON.stringify({type:'loaded'})));
  viewer.addEventListener('error', () => PulseViewer.postMessage(JSON.stringify({type:'error'})));
  window.addEventListener('pagehide', () => window.pulseMuscles.dispose(), {once:true});
})();
''',
  );
}
