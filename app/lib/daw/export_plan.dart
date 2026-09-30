/// O plano de uma exportação: quais intervalos viram arquivo (a música, o loop, o trecho entre dois marcadores ou uma
/// seção por marcador), com que nomes e com quais faixas. Tudo puro (sem motor nem tela) para o controlador renderizar
/// e a janela de opções mostrar o mesmo que vai acontecer.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'export_options.dart';
import 'model.dart';

/// Um intervalo a renderizar, já com o nome-base do arquivo (sem extensão, saneado e sem colisão com os outros).
class ExportSpan {
  final double from, to;

  /// O nome do marcador que abre o trecho (vazio na música inteira e no loop).
  final String label;

  /// A posição (1, 2, ...) entre os intervalos da exportação.
  final int n;
  final String base;
  const ExportSpan({required this.from, required this.to, required this.label, required this.n, required this.base});
}

/// O resultado de [planExport]: os intervalos, ou [problem] (texto para a pessoa) quando não há o que exportar.
class ExportPlan {
  final List<ExportSpan> spans;
  final String? problem;
  const ExportPlan(this.spans, [this.problem]);
  const ExportPlan.problem(String this.problem) : spans = const [];
}

/// Uma seção possível: o trecho de um marcador até o seguinte (o último, até o fim da música).
class ExportSection {
  /// O id do marcador que abre a seção; '' para o trecho antes do primeiro marcador ("Início").
  final String id;
  final String name;
  final double from, to;
  const ExportSection(this.id, this.name, this.from, this.to);
}

/// Abaixo disto (em batidas) dois pontos são o mesmo e um trecho é vazio.
const kSpanEpsilon = 1e-6;

/// As seções do documento, na ordem da régua. Marcadores no mesmo ponto valem um só (o primeiro com nome); seções sem
/// duração (marcador no fim da música ou depois dele) ficam de fora. Sem marcadores, não há seções.
List<ExportSection> exportSections(DawDoc d) {
  final sorted = [...d.markers]..sort((a, b) => a.beat.compareTo(b.beat));
  final starts = <({double beat, String id, String name})>[];
  for (final m in sorted) {
    if (starts.isNotEmpty && (m.beat - starts.last.beat).abs() <= kSpanEpsilon) {
      // no mesmo ponto: só empresta o nome se o primeiro não tinha
      if (starts.last.name.trim().isEmpty && m.name.trim().isNotEmpty) {
        starts[starts.length - 1] = (beat: starts.last.beat, id: starts.last.id, name: m.name.trim());
      }
      continue;
    }
    starts.add((beat: math.max(0.0, m.beat), id: m.id, name: m.name.trim()));
  }
  if (starts.isEmpty) return const [];
  final end = d.contentEnd;
  final out = <ExportSection>[];
  if (starts.first.beat > kSpanEpsilon) out.add(ExportSection('', 'Início', 0, math.min(starts.first.beat, end)));
  for (var i = 0; i < starts.length; i++) {
    final s = starts[i];
    final to = i + 1 < starts.length ? math.min(starts[i + 1].beat, end) : end;
    if (to - s.beat <= kSpanEpsilon) continue;
    out.add(ExportSection(s.id, s.name.isEmpty ? 'Marcador ${i + 1}' : s.name, s.beat, to));
  }
  return out.where((s) => s.to - s.from > kSpanEpsilon).toList();
}

final _invalidChars = RegExp(r'[\\/:*?"<>|\x00-\x1F]');
final _reserved = RegExp(r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])$', caseSensitive: false);

/// Um texto como nome de arquivo (sem extensão): sem caracteres que o sistema recusa, sem espaços e separadores
/// repetidos ou sobrando nas pontas, sem nome reservado do Windows, com no máximo [maxLength] caracteres. Vazio vira
/// [fallback].
String sanitizeExportName(String name, {String fallback = 'jopendaw', int maxLength = 100}) {
  var s = name.replaceAll(_invalidChars, '_').replaceAll(RegExp(r'\s+'), ' ');
  s = s.replaceAllMapped(RegExp(r'([-_])\1+'), (m) => m[1]!);
  s = s.replaceAll(RegExp(r'( ?[-_] ?){2,}'), '-');
  s = s.replaceAll(RegExp(r'^[\s.\-_]+|[\s.\-_]+$'), '');
  if (s.length > maxLength) s = s.substring(0, maxLength).replaceAll(RegExp(r'[\s.\-_]+$'), '');
  if (s.isEmpty) return fallback;
  // "CON", "nul.x"...: o Windows não cria arquivo com esses nomes
  if (_reserved.hasMatch(s.split('.').first.trim())) s = '_$s';
  return s;
}

/// Aplica o modelo de nome: `{projeto}`, `{marcador}` e `{n}` (sem distinguir maiúsculas; `{n}` com zeros à esquerda até
/// a largura de [count], para a ordem alfabética seguir a da música). O que for outro `{...}` some. O resultado vai por
/// [sanitizeExportName].
String expandNameTemplate(String template, {required String project, required String marker, required int n, required int count}) {
  final width = '$count'.length;
  final text = template.replaceAllMapped(RegExp(r'\{([^{}]*)\}'), (m) {
    return switch (m[1]!.trim().toLowerCase()) {
      'projeto' => project,
      'marcador' => marker,
      'n' => '$n'.padLeft(width, '0'),
      _ => '',
    };
  });
  return sanitizeExportName(text, fallback: sanitizeExportName('$project-${'$n'.padLeft(width, '0')}'));
}

/// Desempata [names] sem distinguir maiúsculas (o Windows e o macOS não distinguem): o repetido ganha " (2)", " (3)"...
/// [taken] são nomes já usados (em minúsculas) e é atualizado.
List<String> uniqueNames(List<String> names, {Set<String>? taken}) {
  final used = taken ?? <String>{};
  final out = <String>[];
  for (final name in names) {
    var candidate = name;
    for (var k = 2; used.contains(candidate.toLowerCase()); k++) {
      candidate = '$name ($k)';
    }
    used.add(candidate.toLowerCase());
    out.add(candidate);
  }
  return out;
}

/// Os índices das faixas que entram na exportação (as de [ExportOptions.trackIds], na ordem do projeto; todas se for
/// null). Ids que não existem mais são ignorados.
List<int> exportTrackIndexes(DawDoc d, ExportOptions o) {
  final ids = o.trackIds?.toSet();
  return [
    for (var i = 0; i < d.tracks.length; i++)
      if (ids == null || ids.contains(d.tracks[i].id)) i,
  ];
}

/// Monta o plano. [project] é o nome do projeto para o `{projeto}` e para o nome do arquivo.
ExportPlan planExport(DawDoc d, ExportOptions o, {required String project}) {
  if (o.trackIds != null && exportTrackIndexes(d, o).isEmpty) {
    return const ExportPlan.problem('Nenhuma faixa escolhida: marque ao menos uma faixa para exportar.');
  }
  final projectName = sanitizeExportName(project);
  final end = d.contentEnd;
  switch (o.range) {
    case ExportRange.song:
      if (!(end > kSpanEpsilon)) return const ExportPlan.problem('O projeto está vazio: não há nada para exportar.');
      return ExportPlan([ExportSpan(from: 0, to: end, label: '', n: 1, base: projectName)]);
    case ExportRange.loop:
      if (!(d.loopEnd > d.loopStart + kSpanEpsilon)) return const ExportPlan.problem('A região do loop está vazia: marque o loop antes de exportar.');
      return ExportPlan([ExportSpan(from: d.loopStart, to: d.loopEnd, label: '', n: 1, base: projectName)]);
    case ExportRange.markers:
      Marker? find(String? id) => id == null ? null : d.markers.where((m) => m.id == id).firstOrNull;
      final a = find(o.fromMarker), b = find(o.toMarker);
      if ((o.fromMarker != null && a == null) || (o.toMarker != null && b == null)) {
        return const ExportPlan.problem('Um dos marcadores escolhidos não existe mais: escolha de novo.');
      }
      var from = a?.beat ?? 0.0, to = b?.beat ?? end;
      var first = a, second = b;
      if (from > to) {
        (from, to) = (to, from);
        (first, second) = (second, first);
      }
      if (to - from <= kSpanEpsilon && a != null && b != null) {
        return const ExportPlan.problem('Os dois marcadores estão no mesmo ponto: não há trecho entre eles.');
      }
      // nada soa depois do fim da música (a cauda vem à parte): o trecho não passa dele
      to = math.min(to, end);
      from = math.max(0.0, from);
      if (to - from <= kSpanEpsilon) return const ExportPlan.problem('Não há nada para exportar nesse trecho: ele começa depois do fim da música.');
      String nameOf(Marker? m, String none) => m == null ? none : (m.name.trim().isEmpty ? 'Marcador' : m.name.trim());
      final label = second == null && first != null
          ? nameOf(first, '')
          : (first == null && second == null ? '' : '${nameOf(first, 'Início')} a ${nameOf(second, 'Fim')}');
      final base = expandNameTemplate(o.nameTemplate, project: projectName, marker: label, n: 1, count: 1);
      return ExportPlan([ExportSpan(from: from, to: to, label: label, n: 1, base: base)]);
    case ExportRange.sections:
      final all = exportSections(d);
      if (all.isEmpty) {
        return ExportPlan.problem(
          d.markers.isEmpty
              ? 'Não há marcadores: ponha marcadores na régua para dividir a música em seções.'
              : 'Os marcadores não deixam nenhuma seção com duração.',
        );
      }
      final ids = o.sectionIds?.toSet();
      final chosen = [
        for (final s in all)
          if (ids == null || ids.contains(s.id)) s,
      ];
      if (chosen.isEmpty) return const ExportPlan.problem('Nenhuma seção escolhida: marque ao menos uma.');
      final bases = uniqueNames([
        for (var i = 0; i < chosen.length; i++)
          expandNameTemplate(o.nameTemplate, project: projectName, marker: chosen[i].name, n: i + 1, count: chosen.length),
      ]);
      return ExportPlan([
        for (var i = 0; i < chosen.length; i++) ExportSpan(from: chosen[i].from, to: chosen[i].to, label: chosen[i].name, n: i + 1, base: bases[i]),
      ]);
  }
}

/// Quantos arquivos saem no máximo (as faixas em silêncio não geram stem): intervalos × (a mixagem e, com stems, as faixas).
int expectedExportFiles(DawDoc d, ExportOptions o, ExportPlan plan) => plan.spans.length * (1 + (o.stems ? exportTrackIndexes(d, o).length : 0));

/// Junta arquivos exportados num .zip. Os nomes são saneados e desempatados; os áudios já vêm compactados (WAV não
/// comprime o bastante para valer o tempo), então entram sem recompressão.
class ExportZip {
  final _files = <(String, Uint8List)>[];
  final _taken = <String>{};

  int get count => _files.length;

  /// Acrescenta [bytes] como [name] (com extensão); devolve o nome que ficou.
  String add(String name, Uint8List bytes) {
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name, ext = dot > 0 ? name.substring(dot) : '';
    final safe = uniqueNames([sanitizeExportName(stem, fallback: 'arquivo')], taken: _taken).first;
    final full = '$safe$ext';
    _files.add((full, bytes));
    return full;
  }

  Uint8List build() {
    final archive = Archive();
    for (final (name, bytes) in _files) {
      archive.add(ArchiveFile.noCompress(name, bytes.length, bytes));
    }
    return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
  }

  List<String> get names => [for (final f in _files) f.$1];
}
