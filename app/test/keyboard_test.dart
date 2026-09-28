import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/daw/controller.dart';

void main() {
  test('fileira do meio brancas, de cima pretas, dó central na tecla A na oitava 4', () {
    final layout = {
      PhysicalKeyboardKey.keyA: 60,
      PhysicalKeyboardKey.keyW: 61,
      PhysicalKeyboardKey.keyS: 62,
      PhysicalKeyboardKey.keyE: 63,
      PhysicalKeyboardKey.keyD: 64,
      PhysicalKeyboardKey.keyF: 65,
      PhysicalKeyboardKey.keyT: 66,
      PhysicalKeyboardKey.keyG: 67,
      PhysicalKeyboardKey.keyY: 68,
      PhysicalKeyboardKey.keyH: 69,
      PhysicalKeyboardKey.keyU: 70,
      PhysicalKeyboardKey.keyJ: 71,
      PhysicalKeyboardKey.keyK: 72,
      PhysicalKeyboardKey.keyO: 73,
      PhysicalKeyboardKey.keyL: 74,
      PhysicalKeyboardKey.keyP: 75,
    };
    for (final e in layout.entries) {
      expect(keyboardNote(e.key, 4), e.value, reason: '${e.key.debugName}');
    }
  });

  test('a oitava desloca de 12 em 12', () {
    expect(keyboardNote(PhysicalKeyboardKey.keyA, 0), 12);
    expect(keyboardNote(PhysicalKeyboardKey.keyA, 3), 48);
    expect(keyboardNote(PhysicalKeyboardKey.keyP, 8), 123);
  });

  test('teclas fora do teclado de notas não tocam', () {
    for (final k in [PhysicalKeyboardKey.keyQ, PhysicalKeyboardKey.keyZ, PhysicalKeyboardKey.keyX, PhysicalKeyboardKey.space, PhysicalKeyboardKey.digit1]) {
      expect(keyboardNote(k, 4), isNull);
    }
  });

  test('nota fora da faixa MIDI não toca', () {
    expect(keyboardNote(PhysicalKeyboardKey.keyA, 10), isNull);
    expect(keyboardNote(PhysicalKeyboardKey.keyA, -2), isNull);
  });
}
