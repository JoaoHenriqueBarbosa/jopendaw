import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Na web (dart2js) o `<<` dos inteiros tem 32 bits: `1 << 62` dá 0 e `2 << 30` dá negativo. A VM
/// dos testes não mostra isso, então o teste varre o código atrás de constantes assim. O fatiamento
/// de samples e o limite de tamanho do `.jopendaw` já quebraram no navegador por esse motivo.
void main() {
  test('nenhuma constante `N << K` passa de 31 bits (quebra no navegador)', () {
    final shift = RegExp(r'\b(\d+)\s*<<\s*(\d+)\b');
    final bad = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      var n = 0;
      for (final line in f.readAsLinesSync()) {
        n++;
        if (line.trimLeft().startsWith('//')) continue;
        for (final m in shift.allMatches(line)) {
          final base = int.parse(m.group(1)!), by = int.parse(m.group(2)!);
          if (by >= 31 || base * (BigInt.one << by).toInt() >= (1 << 31)) bad.add('${f.path}:$n: ${m.group(0)}');
        }
      }
    }
    expect(bad, isEmpty, reason: 'use multiplicação (1024 * 1024 * 1024), não deslocamento, para valores de 32 bits ou mais');
  });
}
