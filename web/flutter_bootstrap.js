{{flutter_js}}
{{flutter_build_config}}

// Bundle the renderer locally; preview updates do not wait on a stale worker.
_flutter.loader.load({config: {canvasKitBaseUrl: "canvaskit/"}});
