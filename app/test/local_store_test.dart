// O guardado local do Android (arquivos no diretório do app), conferido num diretório temporário,
// e o comportamento fora do Android: sem motor e sem guardado, como o antigo stub.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/audio/engine.dart';

void main() {
  group('nome de arquivo de cada chave', () {
    test('minúsculas, dígitos, _ e - ficam; o resto vira %XX dos bytes UTF-8', () {
      expect(FileStore.fileName('doc:3f2a-9_b'), 'doc%3A3f2a-9_b');
      expect(FileStore.fileName('sample:ABC'), 'sample%3A%41%42%43');
      expect(FileStore.fileName('rec:input'), 'rec%3Ainput');
      expect(FileStore.fileName('ç'), '%C3%A7');
      expect(FileStore.fileName('..'), '%2E%2E');
      expect(FileStore.fileName('../fora'), '%2E%2E%2Ffora');
      expect(FileStore.fileName(''), '%');
    });

    test('chaves diferentes nunca dão nomes iguais, nem num sistema que ignora maiúsculas', () {
      final keys = [
        'doc:abc',
        'doc:ABC',
        'doc:Abc',
        'doc%3Aabc',
        'doc:abc.txt',
        'sample:${'a' * 64}',
        'sample:${'A' * 64}',
        '',
        '%',
        'a b',
        'a_b',
        'a-b',
        'rec:input',
      ];
      final names = {for (final k in keys) FileStore.fileName(k).toLowerCase()};
      expect(names.length, keys.length);
    });

    test('chave longa vira o sha-256 dela (nome curto, ainda único)', () {
      final a = FileStore.fileName('x' * 300), b = FileStore.fileName('${'x' * 299}y');
      expect(a, startsWith('%h-'));
      expect(a.length, lessThan(80));
      expect(a, isNot(b));
      expect(FileStore.fileName('sample:${'f' * 64}'), 'sample%3A${'f' * 64}', reason: 'as chaves do app cabem sem hash');
    });
  });

  group('arquivos', () {
    late Directory dir;
    late FileStore store;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('jopendaw_store');
      store = FileStore(() async => Directory('${dir.path}/jopendaw'));
    });

    tearDown(() => dir.delete(recursive: true));

    test('texto e bytes voltam como foram; o que nunca foi guardado é null', () async {
      final bytes = Uint8List.fromList([0, 1, 2, 255]);
      await store.put('doc:p', '{"bpm": 120, "nome": "canção"}');
      await store.put('sample:ab', bytes);
      expect(await store.get('doc:p'), '{"bpm": 120, "nome": "canção"}');
      expect(await store.get('sample:ab'), bytes);
      expect(await store.get('sample:ab'), isA<Uint8List>());
      expect(await store.get('nada'), isNull);
      // tudo dentro do diretório do guardado, com o nome seguro
      final files = [for (final f in Directory('${dir.path}/jopendaw').listSync()) f.uri.pathSegments.last]..sort();
      expect(files, ['doc%3Ap.txt', 'sample%3Aab.bin']);
    });

    test('trocar o tipo de uma chave apaga o valor antigo; apagar tira os dois', () async {
      await store.put('k', 'texto');
      await store.put('k', Uint8List.fromList([7]));
      expect(await store.get('k'), [7]);
      await store.put('k', 'de novo');
      expect(await store.get('k'), 'de novo');
      await store.delete('k');
      expect(await store.get('k'), isNull);
      await store.delete('k');
      expect(Directory('${dir.path}/jopendaw').listSync(), isEmpty);
    });

    test('gravações da mesma chave vão na ordem: a última vence e um get espera as pendentes', () async {
      final writes = [for (var i = 0; i < 20; i++) store.put('doc:p', 'versão $i')];
      expect(await store.get('doc:p'), 'versão 19');
      await Future.wait(writes);
      expect(await store.get('doc:p'), 'versão 19');
    });

    test('chave com barra ou pontos não sai do diretório', () async {
      await store.put('../../fora', 'x');
      expect(File('${dir.path}/fora.txt').existsSync(), isFalse);
      expect(await store.get('../../fora'), 'x');
    });

    test('temporário de uma gravação interrompida some ao abrir, e o valor anterior fica inteiro', () async {
      final d = Directory('${dir.path}/jopendaw')..createSync(recursive: true);
      File('${d.path}/doc%3Ap.txt').writeAsStringSync('inteiro');
      File('${d.path}/doc%3Ap.txt.tmp').writeAsStringSync('pela met');
      expect(await store.get('doc:p'), 'inteiro');
      expect(File('${d.path}/doc%3Ap.txt.tmp').existsSync(), isFalse);
    });

    test('valor que não é texto nem bytes é erro', () {
      expect(() => store.put('k', 42), throwsArgumentError);
    });

    test('um documento grande vai e volta igual (UTF-8)', () async {
      final doc = jsonEncode({
        'faixas': [for (var i = 0; i < 2000; i++) 'Faixa $i — ação'],
      });
      await store.put('doc:grande', doc);
      expect(await store.get('doc:grande'), doc);
    });
  });

  group('fora do Android', () {
    test('sem motor: não suportado, abrir e gravar dão UnsupportedError, limpar só volta', () async {
      final e = AudioEngine.instance;
      expect(e.supported, isFalse);
      await expectLater(e.start(), throwsUnsupportedError);
      await expectLater(e.decode(Uint8List(4)), throwsUnsupportedError);
      await expectLater(e.startInput(null), throwsUnsupportedError);
      await expectLater(e.inputDevices(), throwsUnsupportedError);
      await expectLater(e.enableMidi(), throwsUnsupportedError);
      await expectLater(e.saveFile('a.wav', Uint8List(1), 'audio/wav'), throwsUnsupportedError);
      await expectLater(
        e.renderOffline(calls: const [], samples: const {}, fromBeat: 0, toBeat: 1, tailSeconds: 0, outputs: const [-1], rate: 48000),
        throwsUnsupportedError,
      );
      expect(() => e.setCapture(true), throwsUnsupportedError);
      e.setCapture(false);
      await e.stopInput();
      await e.resume();
      e.cancelRender();
      e.loadSample(1, DecodedAudio([Float32List(4)], 48000));
      expect(e.latency, 0);
      expect(await e.sha256Hex(Uint8List.fromList(utf8.encode('abc'))), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    });

    test('as chamadas vão para o log quando o teste pede, e para lugar nenhum sem ele', () {
      final e = AudioEngine.instance;
      e.log = [];
      e.calls([
        ['play'],
        ['seek', 2.0],
      ]);
      expect(e.log, [
        ['play'],
        ['seek', 2.0],
      ]);
      e.log = null;
      e.calls([
        ['stop'],
      ]);
      expect(e.log, isNull);
    });

    test('sem guardado: nada fica e nada volta', () async {
      final s = LocalStore.instance;
      await s.put('doc:p', 'x');
      expect(await s.get('doc:p'), isNull);
      await s.delete('doc:p');
    });
  });
}
