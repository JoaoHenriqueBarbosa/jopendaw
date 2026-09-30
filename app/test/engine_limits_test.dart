// Os limites do motor (16 efeitos por cadeia, 16 envios por faixa) não passam em silêncio: o
// controlador recusa o 17º, e a tela desabilita o botão com a dica.
import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/effects.dart';

import 'fake_engine.dart';

void main() {
  test('a 17ª inserção numa cadeia é recusada (faixa e master)', () {
    final c = fakeController(FakeEngine());
    for (final track in [0, -1]) {
      for (var i = 0; i < DawController.maxEffectsPerChain; i++) {
        expect(c.canAddEffect(track), isTrue, reason: 'faixa $track, efeito $i');
        c.addEffect(track, EffectKind.eq);
      }
      expect(c.canAddEffect(track), isFalse);
      expect(() => c.addEffect(track, EffectKind.reverb), throwsA(isA<StateError>()));
      expect(c.effectsOf(track), hasLength(DawController.maxEffectsPerChain));
    }
    expect(DawController.effectLimitHint, 'Limite de 16 efeitos por faixa');
  });

  test('o 17º envio de uma faixa é recusado; os que existem seguem editáveis', () {
    final c = fakeController(FakeEngine());
    final buses = [for (var i = 0; i < DawController.maxSendsPerTrack + 1; i++) c.addBusTrack()];
    for (var i = 0; i < DawController.maxSendsPerTrack; i++) {
      expect(c.canAddSend(0), isTrue);
      expect(c.setSend(0, buses[i].id), isTrue, reason: 'envio $i');
    }
    expect(c.canAddSend(0), isFalse);
    expect(c.setSend(0, buses.last.id), isFalse);
    expect(c.doc.tracks[0].sends, hasLength(DawController.maxSendsPerTrack));
    // mudar o nível de um que existe continua valendo
    expect(c.setSend(0, buses.first.id, level: 0.5), isTrue);
    expect(c.canAddSend(-1), isFalse);
  });
}
