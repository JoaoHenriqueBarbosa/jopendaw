/// O texto do andamento e do compasso, num lugar só: a barra do transporte, o cabeçalho do projeto, o warp e o diálogo
/// do .mid mostram os mesmos números do mesmo jeito.
library;

import 'model.dart';

/// O andamento como se mostra: arredondado a uma casa e sem o ",0" quando ela é zero ("120", "97,5"). 120,04 e 119,96
/// aparecem como "120"; 120,05 como "120,1". Vírgula decimal.
String formatBpm(double v) {
  final t = (v * 10).round() / 10;
  return (t == t.roundToDouble() ? t.toStringAsFixed(0) : t.toStringAsFixed(1)).replaceAll('.', ',');
}

/// "4/4", "6/8": tempos por compasso e a figura do tempo.
String formatMeter(int numerator, int denominator) => '$numerator/$denominator';

/// O compasso inicial do documento, com a figura que ele realmente tem (não um "/4" fixo).
String formatDocMeter(DawDoc d) {
  final m = d.meter.changeAt(1);
  return formatMeter(m.numerator, m.denominator);
}
