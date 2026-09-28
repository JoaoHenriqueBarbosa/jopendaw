import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'studio_test.dart' show studio, mount, flushSave;

void main() {
  testWidgets('toque longo e arrasto no cabeçalho reordena a faixa e o estado volta ao normal', (t) async {
    final c = studio();
    await mount(t, c, const Size(1400, 900));
    final at = t.getCenter(find.text('Sampler 1'));
    // como o navegador: o mouse passa por cima antes de apertar
    final g = await t.createGesture(kind: PointerDeviceKind.mouse);
    await g.addPointer(location: at);
    await g.moveTo(at);
    await t.pump();
    await g.down(at);
    await t.pump(const Duration(milliseconds: 700));
    expect(find.textContaining('para a posição'), findsOneWidget, reason: 'o toque longo liga o arraste');
    for (var i = 0; i < 4; i++) {
      await g.moveBy(const Offset(0, -20));
      await t.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await t.pump();
    expect(find.textContaining('para a posição'), findsNothing, reason: 'soltar desliga o arraste');
    expect(c.doc.tracks.map((x) => x.name).toList(), ['Áudio 1', 'Sintetizador 1', 'Sampler 1', 'Bateria 1']);
    await g.removePointer();
    await flushSave(t);
  });
}
