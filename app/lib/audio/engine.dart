/// O motor de áudio visto do Flutter. Na web ele roda em WASM num AudioWorklet (`web/engine/`,
/// `engine_web.dart`); no Android, o mesmo motor em Rust entra como biblioteca nativa pelo dart:ffi
/// (`engine_io.dart` → `engine_ffi.dart`), processando no aparelho.
library;

export 'engine_types.dart';
export 'engine_io.dart' if (dart.library.js_interop) 'engine_web.dart';
