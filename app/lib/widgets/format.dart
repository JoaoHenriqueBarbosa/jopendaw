/// Textos e números como a tela mostra: plural, milhar com ponto e datas curtas.
library;

import 'package:flutter/foundation.dart';

/// Tecla de modificador do sistema como aparece nos textos: ⌘ no Mac e no iOS, Ctrl nos outros.
String get modKey => defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS ? '⌘' : 'Ctrl';

/// Troca o "Ctrl" de um texto de atalho pela tecla do sistema ("Ctrl+Z" → "⌘+Z" no Mac).
String withMod(String text) => text.replaceAll('Ctrl', modKey);

/// `plural(3, 'faixa')` → "3 faixas"; o plural irregular vai no terceiro argumento.
String plural(int n, String one, [String? many]) => '${fmtInt(n)} ${n == 1 ? one : many ?? '${one}s'}';

/// Inteiro com ponto no milhar: 1025 → "1.025".
String fmtInt(int n) {
  final s = n.abs().toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

/// Dia e mês: "07/10".
String shortDate(DateTime d) {
  final l = d.toLocal();
  return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}';
}

/// "agora", "há 5 min", "há 3 h" ou o dia.
String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'agora';
  if (d.inHours < 1) return 'há ${d.inMinutes} min';
  if (d.inDays < 1) return 'há ${d.inHours} h';
  return shortDate(t);
}

/// Frase a partir da mensagem crua da API ("nome obrigatório" → "Nome obrigatório.").
String sentence(String s) {
  final t = s.trim();
  if (t.isEmpty) return t;
  final cap = '${t[0].toUpperCase()}${t.substring(1)}';
  return RegExp(r'[.!?]$').hasMatch(cap) ? cap : '$cap.';
}

/// Tamanho em bytes como a pessoa lê: "0 B", "12,3 MB", "3,9 GB" (base 1024, vírgula decimal).
String fmtBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = bytes.toDouble(), u = 0;
  while (v >= 1024 && u < units.length - 1) {
    v /= 1024;
    u++;
  }
  if (u == 0) return '$bytes B';
  return '${v.toStringAsFixed(v >= 100 ? 0 : 1).replaceAll('.', ',')} ${units[u]}';
}

/// Tooltip do botão do teclado do computador (barra de transporte e painel do instrumento): o mesmo
/// texto nos dois. [octave] e [velocityPercent] só aparecem com o teclado ligado.
String keyboardTooltip({required bool on, required int octave, required int velocityPercent}) => withMod(
  on
      ? 'Teclado tocando: atalhos suspensos (C L S X Z E F K J e Shift+H/L). A a P tocam a partir do C$octave, '
            'Z/X mudam a oitava, C/V a intensidade ($velocityPercent%). Ctrl+K desliga'
      : 'Tocar com o teclado do computador (Ctrl+K)',
);
