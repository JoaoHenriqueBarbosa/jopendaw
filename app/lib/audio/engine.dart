/// O motor de áudio visto do Flutter. Na web ele roda em WASM num AudioWorklet
/// (`web/engine/`); no Android, o mesmo motor em Rust entra como biblioteca nativa (ainda por vir).
library;

export 'engine_types.dart';
export 'engine_stub.dart' if (dart.library.js_interop) 'engine_web.dart';
