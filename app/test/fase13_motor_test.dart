// Fase 13, item A: o compasso único n/8 chega ao motor pelo mapa de compassos (o `tempo` reenviado a
// cada sincronização traz o número de tempos arredondado e não pode desfazê-lo).
import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/daw/tempo_map.dart';

import 'fake_engine.dart';

void main() {
  late FakeEngine e;
  setUp(() => e = FakeEngine());

  for (final num in [5, 7, 9]) {
    test('compasso único $num/8: o mapa vai ao motor sempre que o compasso inicial não é n/4', () async {
      final c = fakeController(e);
      c.setMeterMap([MeterChange(1, num, 8)]);
      await settle();
      expect(c.doc.meter.isSingle, isFalse, reason: 'um compasso único n/8 não é n/4: precisa do mapa');
      expect(e.sent('meter_point').last, ['meter_point', 1, num, 8]);
      // o `tempo` de cada sincronização segue mandando o compasso inicial arredondado; o mapa é a fonte
      expect(e.sent('tempo').last[2], isA<int>());
      expect(c.doc.meter.first, MeterChange(1, num, 8));
      // voltando a n/4 o motor recebe meter_clear e nenhum ponto
      e.log!.clear();
      c.setMeterMap(const []);
      await settle();
      expect(e.sent('meter_clear'), isNotEmpty);
      expect(e.sent('meter_point'), isEmpty);
    });
  }
}
