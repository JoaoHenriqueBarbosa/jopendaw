// Falha do motor de áudio (trap do wasm, thread de áudio morta): o controlador avisa, e "Reiniciar
// o áudio" recria o motor, manda de novo os áudios e o documento e reabre a entrada.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/daw/export_options.dart';
import 'package:jopendaw_app/daw/wav.dart';

import 'fake_engine.dart';

void main() {
  late FakeEngine e;
  setUp(() => e = FakeEngine());

  test('o aviso aparece quando o motor cai e some ao reiniciar; áudios e documento voltam ao motor novo', () async {
    final c = fakeController(e);
    await c.open();
    await c.importBytes(
      [
        ('voz.wav', encodeWav([Float32List(200)..fillRange(0, 200, 0.25)], 100, ExportFormat.wav32f)),
      ],
      at: 0,
      track: 0,
    );
    expect(c.audioFailure, isNull);
    final sampleIds = e.loaded.keys.toList();
    expect(sampleIds, isNotEmpty);

    e.onEngineFailed!('unreachable');
    expect(c.audioFailure, contains('reinicie o áudio'));

    e.log!.clear();
    await c.restartAudio();
    expect(e.restarts, 1);
    expect(c.audioFailure, isNull);
    expect(c.audioRestarting, isFalse);
    expect(e.loaded.keys.toList(), sampleIds, reason: 'os áudios foram mandados de novo ao motor novo (o restart o esvaziou)');
    expect(e.sent('tempo'), hasLength(1), reason: 'o documento foi reenviado por inteiro');
    expect(e.sent('clip_add'), hasLength(1));
    expect(e.sent('track_kind'), isNotEmpty);
    c.dispose();
  });

  test('reiniciar que falha deixa o aviso, com o motivo, para tentar de novo', () async {
    final c = fakeController(e);
    await c.open();
    e.onEngineFailed!('x');
    e.restartFailure = StateError('sem saída de áudio');
    await c.restartAudio();
    expect(c.audioFailure, contains('Não deu para reiniciar o áudio'));
    expect(c.audioRestarting, isFalse);
    e.restartFailure = null;
    await c.restartAudio();
    expect(c.audioFailure, isNull);
    c.dispose();
  });

  test('depois de fechada a tela, o gancho é solto', () async {
    final c = fakeController(e);
    await c.open();
    c.dispose();
    expect(e.onEngineFailed, isNull);
  });

  test('host.js detecta processorerror, trap do wasm e falta de estados, e reinicia (node, com fakes do navegador)', () async {
    final bool node;
    try {
      node = Process.runSync('node', ['--version']).exitCode == 0;
    } on ProcessException {
      markTestSkipped('sem node');
      return;
    }
    if (!node) return;
    final r = await Process.run('node', ['test/js/host_failure_check.mjs']);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect((r.stdout as String).trim(), 'ok');
  });
}
