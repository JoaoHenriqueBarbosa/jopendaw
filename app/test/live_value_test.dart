import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/daw/effects.dart';
import 'package:jopendaw_app/daw/model.dart';

import 'controller_test.dart' show newController;

void main() {
  test('parâmetro de efeito automatizado: tocando vale a curva, parado o fixo', () {
    final c = newController();
    final fx = c.addEffect(0, EffectKind.reverb);
    final target = AutoTarget(AutoKind.effect, ref: fx.id, param: 0); // mistura
    expect(c.automatedTarget(0, target), isFalse);
    c.addLane(0, target).points.addAll([AutoPoint(beat: 0, value: 0), AutoPoint(beat: 4, value: 1)]);
    expect(c.automatedTarget(0, target), isTrue);
    expect(c.automatedTarget(0, AutoTarget(AutoKind.effect, ref: fx.id, param: 1)), isFalse, reason: 'outro parâmetro');
    c.beat.value = 2;
    expect(c.liveTargetValue(0, target, 0.25), 0.25, reason: 'parado vale o fixo');
    c.playing.value = true;
    expect(c.liveTargetValue(0, target, 0.25), closeTo(0.5, 1e-9));
  });
}
