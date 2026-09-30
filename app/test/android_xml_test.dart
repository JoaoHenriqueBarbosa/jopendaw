import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Um `--` dentro de um comentário XML é inválido e quebra o build do Android
/// (`parseDebugLocalResources`), coisa que só aparece ao compilar o APK.
void main() {
  test('nenhum recurso XML do Android tem "--" dentro de comentário', () {
    final bad = <String>[];
    final comment = RegExp(r'<!--(.*?)-->', dotAll: true);
    for (final f in Directory('android/app/src').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.xml'))) {
      for (final m in comment.allMatches(f.readAsStringSync())) {
        if (m.group(1)!.contains('--')) bad.add(f.path);
      }
    }
    expect(bad, isEmpty);
  });
}
