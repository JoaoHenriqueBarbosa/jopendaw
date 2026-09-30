import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/daw/effects.dart';
import 'package:jopendaw_app/daw/instruments.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/daw/project_file.dart';
import 'package:jopendaw_app/daw/project_file_ui.dart';
import 'package:jopendaw_app/models/project.dart';

import 'fake_engine.dart';

Uint8List audio(int seed, [int n = 300]) => Uint8List.fromList([for (var i = 0; i < n; i++) (i * 31 + seed * 7 + (i ~/ 256)) & 0xff]);
String hashOf(List<int> b) => sha256.convert(b).toString();

/// Documento com de tudo: áudio (com tomadas), sampler, MIDI, efeitos, envio, saída, automações e marcadores.
DawDoc richDoc(Map<String, Uint8List> files) {
  for (final b in [audio(1), audio(2), audio(3)]) {
    files[hashOf(b)] = b;
  }
  final h = files.keys.toList();
  final fx = EffectSlot(id: 'fx1', kind: EffectKind.reverb, bypass: true);
  final bus = DawTrack(id: 'bus', name: 'Reverb', color: 3, kind: TrackKind.bus, effects: [fx]);
  final a = DawTrack(
    id: 'a1',
    name: 'Voz',
    color: 1,
    gain: 0.7,
    pan: -0.25,
    clips: [
      AudioClip(
        id: 'c1',
        sample: h[0],
        start: 1.5,
        offset: 0.1,
        length: 0.5,
        gain: 0.9,
        fadeIn: 0.01,
        takes: [h[0], h[1]],
        warp: true,
        sourceBpm: 100,
        pitch: 2,
        reverse: true,
      ),
    ],
    sends: [Send(target: 'bus', level: 0.3, pre: true)],
    output: 'bus',
    lanes: [
      AutoLane(
        id: 'l1',
        target: const AutoTarget(AutoKind.send, ref: 'bus'),
        points: [AutoPoint(beat: 0, value: 0.5), AutoPoint(beat: 4, value: 1, curve: 0.3)],
      ),
      AutoLane(id: 'l2', target: const AutoTarget(AutoKind.volume)),
    ],
  );
  final s = DawTrack(
    id: 's1',
    name: 'Sampler',
    color: 2,
    kind: TrackKind.sampler,
    sample: h[2],
    midi: [
      MidiClip(id: 'm1', name: 'riff', start: 0, length: 4, scale: '0:major', notes: [MidiNote(pitch: 60, start: 0, length: 1, velocity: 0.5)]),
    ],
    lanes: [
      AutoLane(
        id: 'l3',
        target: const AutoTarget(AutoKind.effect, ref: 'fx1', param: 2),
      ),
    ],
  );
  return DawDoc(
    bpm: 133.5,
    beatsPerBar: 3,
    tracks: [a, s, bus],
    samples: {h[0]: const SampleInfo('voz.WAV', 1.25), h[1]: const SampleInfo('take.mp3', 2), h[2]: const SampleInfo('kick sem extensão', 0.5)},
    loopOn: true,
    loopStart: 4,
    loopEnd: 8,
    metronome: true,
    masterGain: 0.8,
    masterPan: 0.1,
    countIn: false,
    recLatencyMs: 12.5,
    masterEffects: [EffectSlot(id: 'mfx', kind: EffectKind.reverb)],
    masterLanes: [
      AutoLane(
        id: 'ml',
        target: const AutoTarget(AutoKind.effect, ref: 'mfx', param: 1),
      ),
    ],
    markers: [
      Marker(id: 'k2', beat: 2, name: 'intro'),
      Marker(id: 'k1', beat: 8, name: 'refrão'),
    ],
  );
}

Future<Uint8List?> Function(String) loader(Map<String, Uint8List> files) =>
    (h) async => files[h];

Uint8List zipOf(Map<String, Object> entries) {
  final a = Archive();
  for (final e in entries.entries) {
    final v = e.value;
    a.addFile(v is String ? ArchiveFile.string(e.key, v) : ArchiveFile.bytes(e.key, v as List<int>));
  }
  return ZipEncoder().encodeBytes(a);
}

/// project.json e manifest.json válidos para os [files] dados.
Map<String, Object> validEntries(DawDoc doc, Map<String, Uint8List> files) => {
  'project.json': jsonEncode({'format': 1, 'name': 'X', 'app_version': '0', 'exported_at': '2026-01-01T00:00:00Z', 'doc': doc.toJson()}),
  'manifest.json': jsonEncode({
    'format': 1,
    'samples': [
      for (final e in files.entries) {'hash': e.key, 'size': e.value.length, 'name': 'a.wav', 'file': 'samples/${e.key}.wav'},
    ],
    'missing': [],
  }),
  for (final e in files.entries) 'samples/${e.key}.wav': e.value,
};

void expectRejected(Uint8List bytes, Pattern message, {ProjectFileLimits limits = const ProjectFileLimits(), String? reason}) {
  expect(() => parseProjectFile(bytes, limits: limits), throwsA(isA<ProjectFileException>().having((e) => e.message, 'message', matches(message))));
}

bool _nameAt(Uint8List b, int at, List<int> name) {
  if (at + name.length > b.length) return false;
  for (var i = 0; i < name.length; i++) {
    if (b[at + i] != name[i]) return false;
  }
  return true;
}

class _FailingStore extends MemoryStore {
  int puts = 0;
  @override
  Future<void> put(String key, Object value) async {
    if (key.startsWith('sample:') && ++puts == 2) throw StateError('disco cheio');
    await super.put(key, value);
  }
}

Project proj(String id, String name, {int bpm = 120, int bpb = 4}) => Project.fromJson({
  'id': id,
  'name': name,
  'bpm': bpm,
  'beats_per_bar': bpb,
  'beat_unit': 4,
  'sample_rate': 48000,
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-01T00:00:00Z',
});

Future<ProjectBundle> bundleOf(Map<String, Uint8List> files, DawDoc doc, {String name = 'Beat'}) async =>
    parseProjectFile((await buildProjectFile(name: name, doc: doc, loadSample: loader(files))).bytes);

void main() {
  group('montar e ler', () {
    test('ida e volta exata do documento, dos áudios e do nome', () async {
      final files = <String, Uint8List>{};
      final doc = richDoc(files);
      final before = jsonEncode(doc.toJson());
      final built = await buildProjectFile(name: 'Minha música', doc: doc, loadSample: loader(files), now: DateTime.utc(2026, 5, 1, 12));
      expect(built.missing, isEmpty);
      expect(built.sampleCount, 3);
      expect(jsonEncode(doc.toJson()), before, reason: 'exportar não mexe no documento');

      final b = parseProjectFile(built.bytes);
      expect(b.name, 'Minha música');
      expect(b.format, 1);
      expect(b.exportedAt, DateTime.utc(2026, 5, 1, 12));
      expect(jsonEncode(b.doc.toJson()), before);
      expect(b.samples.keys.toSet(), files.keys.toSet());
      for (final e in files.entries) {
        expect(b.samples[e.key], e.value);
      }
      expect(b.missing, isEmpty);
    });

    test('nomes dos áudios no zip: extensão conhecida ou .bin, dedupe por sha-256', () async {
      final files = <String, Uint8List>{};
      final doc = richDoc(files);
      // dois clipes citando o mesmo áudio não duplicam o arquivo
      doc.tracks[0].clips.add(AudioClip(id: 'c2', sample: doc.tracks[0].clips[0].sample, start: 8, length: 0.5));
      final built = await buildProjectFile(name: 'x', doc: doc, loadSample: loader(files));
      final names = ZipDecoder().decodeBytes(built.bytes).map((f) => f.name).toList()..sort();
      final h = files.keys.toList();
      final expected = ['manifest.json', 'project.json', 'samples/${h[0]}.wav', 'samples/${h[1]}.mp3', 'samples/${h[2]}.bin']..sort();
      expect(names, expected);
    });

    test('projeto sem nenhum áudio', () async {
      final doc = DawDoc(
        bpm: 120,
        beatsPerBar: 4,
        tracks: [DawTrack(id: 't', name: 'Vazia', color: 0)],
      );
      final built = await buildProjectFile(name: 'Vazio', doc: doc, loadSample: (_) async => null);
      expect(built.sampleCount, 0);
      final b = parseProjectFile(built.bytes);
      expect(b.samples, isEmpty);
      expect(b.missing, isEmpty);
      expect(jsonEncode(b.doc.toJson()), jsonEncode(doc.toJson()));
    });

    test('projeto com muitos áudios', () async {
      final files = <String, Uint8List>{};
      final doc = DawDoc(
        bpm: 90,
        beatsPerBar: 4,
        tracks: [DawTrack(id: 't', name: 'Muitos', color: 0)],
      );
      for (var i = 0; i < 300; i++) {
        final b = audio(i + 10, 40 + i);
        final h = hashOf(b);
        files[h] = b;
        doc.samples[h] = SampleInfo('s$i.wav', 0.1);
        doc.tracks[0].clips.add(AudioClip(id: 'c$i', sample: h, start: i.toDouble(), length: 0.1));
      }
      var last = (0, 0);
      final built = await buildProjectFile(name: 'Muitos', doc: doc, loadSample: loader(files), onProgress: (d, t) => last = (d, t));
      expect(last, (300, 300));
      final b = parseProjectFile(built.bytes);
      expect(b.samples.length, 300);
      expect(jsonEncode(b.doc.toJson()), jsonEncode(doc.toJson()));
    });

    test('áudio que falta na exportação vai para "missing" e o arquivo ainda abre', () async {
      final files = <String, Uint8List>{};
      final doc = richDoc(files);
      final gone = files.keys.first;
      final built = await buildProjectFile(name: 'x', doc: doc, loadSample: (h) async => h == gone ? null : files[h]);
      expect(built.missing, [gone]);
      expect(built.sampleCount, 2);
      final b = parseProjectFile(built.bytes);
      expect(b.missing, {gone});
      expect(b.samples.containsKey(gone), isFalse);
    });

    test('hash que não é sha-256 no documento não vira arquivo de nome estranho', () async {
      final doc = DawDoc(bpm: 120, beatsPerBar: 4, samples: {'../../etc/passwd': const SampleInfo('x.wav', 1)});
      var asked = false;
      final built = await buildProjectFile(
        name: 'x',
        doc: doc,
        loadSample: (_) async {
          asked = true;
          return audio(1);
        },
      );
      expect(asked, isFalse);
      expect(built.sampleCount, 0);
      expect(built.missing, ['../../etc/passwd']);
      expect(parseProjectFile(built.bytes).missing, {'../../etc/passwd'});
    });
  });

  group('arquivo inválido', () {
    late Map<String, Uint8List> files;
    late DawDoc doc;
    setUp(() {
      files = {};
      doc = richDoc(files);
    });

    test('vazio, lixo, truncado', () async {
      expectRejected(Uint8List(0), 'vazio');
      expectRejected(Uint8List.fromList(utf8.encode('isto não é um zip, é só texto comprido o bastante')), 'não parece');
      final built = await buildProjectFile(name: 'x', doc: doc, loadSample: loader(files));
      for (final cut in [built.bytes.length ~/ 2, built.bytes.length - 10, 30, 4]) {
        expect(() => parseProjectFile(Uint8List.sublistView(built.bytes, 0, cut)), throwsA(isA<ProjectFileException>()), reason: 'corte em $cut');
      }
    });

    test('zip válido sem project.json ou sem manifest.json', () {
      final ok = validEntries(doc, files);
      expectRejected(zipOf({...ok}..remove('project.json')), 'project.json');
      expectRejected(zipOf({...ok}..remove('manifest.json')), 'manifest.json');
      expectRejected(zipOf({'foto.png': audio(1)}), 'project.json');
    });

    test('formato maior que o suportado: mensagem clara em português', () {
      final e = validEntries(doc, files);
      e['project.json'] = jsonEncode({'format': 2, 'name': 'X', 'doc': doc.toJson()});
      expectRejected(zipOf(e), RegExp('versão mais nova.*formato 2.*até o 1.*Atualize'));
    });

    test('documento de uma versão mais nova', () {
      final e = validEntries(doc, files);
      e['project.json'] = jsonEncode({
        'format': 1,
        'name': 'X',
        'doc': {...doc.toJson(), 'version': 99},
      });
      expectRejected(zipOf(e), RegExp('documento.*mais nova'));
    });

    test('json ilegível, formato ausente, documento ausente ou quebrado', () {
      final ok = validEntries(doc, files);
      expectRejected(zipOf({...ok, 'project.json': '{não é json'}), 'corrompido');
      expectRejected(zipOf({...ok, 'project.json': '[1,2]'}), 'corrompido');
      expectRejected(
        zipOf({
          ...ok,
          'project.json': jsonEncode({'name': 'X', 'doc': doc.toJson()}),
        }),
        RegExp('format'),
      );
      expectRejected(
        zipOf({
          ...ok,
          'project.json': jsonEncode({'format': 1, 'name': 'X'}),
        }),
        'não traz o documento',
      );
      expectRejected(
        zipOf({
          ...ok,
          'project.json': jsonEncode({
            'format': 1,
            'doc': {'bpm': 'rápido'},
          }),
        }),
        RegExp('documento.*não pôde ser lido'),
      );
      expectRejected(zipOf({...ok, 'manifest.json': '{"samples": 3}'}), 'não lista os áudios');
      expectRejected(zipOf({...ok, 'manifest.json': '{"samples": [42]}'}), RegExp('ilegível'));
    });

    test('nomes hostis dentro do zip são recusados', () {
      final ok = validEntries(doc, files);
      for (final bad in ['../evil.txt', 'samples/../../evil', '/etc/passwd', 'C:/x', 'a/../b', 'samples/..']) {
        expectRejected(zipOf({...ok, bad: 'x'}), RegExp('suspeitos'), reason: bad);
      }
    });

    test('manifesto com caminho de áudio fora do padrão é recusado (nunca abre o que ele manda)', () {
      final ok = validEntries(doc, files);
      final h = files.keys.first;
      for (final file in ['../$h.wav', '/tmp/$h.wav', 'samples/$h', 'samples/../$h.wav', 'samples/${'0' * 64}.wav', 'project.json']) {
        final m = jsonDecode(ok['manifest.json'] as String) as Map<String, dynamic>;
        (m['samples'] as List)[0] = {'hash': h, 'size': files[h]!.length, 'name': 'x', 'file': file};
        expectRejected(zipOf({...ok, 'manifest.json': jsonEncode(m)}), RegExp('caminho de áudio inválido|dados inválidos|suspeitos'));
      }
    });

    test('áudio que o manifesto lista e o zip não tem: arquivo incompleto', () {
      final ok = validEntries(doc, files);
      ok.remove('samples/${files.keys.last}.wav');
      expectRejected(zipOf(ok), 'truncado ou incompleto');
    });

    test('sha-256 divergente e tamanho divergente', () {
      final ok = validEntries(doc, files);
      final h = files.keys.first;
      final tampered = Uint8List.fromList(files[h]!)..[5] ^= 1;
      expectRejected(zipOf({...ok, 'samples/$h.wav': tampered}), RegExp('sha-256'));
      expectRejected(zipOf({...ok, 'samples/$h.wav': Uint8List.sublistView(files[h]!, 0, 10)}), 'tamanho diferente');
    });

    test('hash malformado no manifesto', () {
      final ok = validEntries(doc, files);
      final m = jsonDecode(ok['manifest.json'] as String) as Map<String, dynamic>;
      (m['samples'] as List)[0] = {'hash': 'ABC', 'size': 1, 'name': 'x', 'file': 'samples/ABC.wav'};
      expectRejected(zipOf({...ok, 'manifest.json': jsonEncode(m)}), 'dados inválidos');
    });

    test('zip bomb honesta: tamanho declarado acima do limite', () {
      final bomb = Uint8List(3 << 20); // 3 MB de zeros: comprime para poucos KB
      final e = validEntries(doc, {hashOf(bomb): bomb});
      expectRejected(zipOf(e), 'grande demais', limits: const ProjectFileLimits(maxSampleBytes: 1 << 20));
      expectRejected(zipOf(e), 'grande demais', limits: const ProjectFileLimits(maxTotalBytes: 1 << 20));
    });

    test('zip bomb com cabeçalho mentindo o tamanho: a descompressão para no teto', () {
      final bomb = Uint8List(3 << 20);
      final h = hashOf(bomb);
      final e = validEntries(doc, {h: bomb});
      // o manifesto também mente (size: 10) para passar da checagem do declarado
      final m = jsonDecode(e['manifest.json'] as String) as Map<String, dynamic>;
      (m['samples'] as List)[0]['size'] = 10;
      e['manifest.json'] = jsonEncode(m);
      final zip = zipOf(e);
      // troca o tamanho descomprimido do áudio por 10 no diretório central e no cabeçalho local
      final needle = utf8.encode('samples/$h.wav');
      final bd = ByteData.sublistView(zip);
      var patched = 0;
      for (var i = 0; i < zip.length - 4; i++) {
        final sig = bd.getUint32(i, Endian.little);
        if (sig == 0x02014b50 && _nameAt(zip, i + 46, needle)) {
          bd.setUint32(i + 24, 10, Endian.little);
          patched++;
        } else if (sig == 0x04034b50 && _nameAt(zip, i + 30, needle)) {
          bd.setUint32(i + 22, 10, Endian.little);
          patched++;
        }
      }
      expect(patched, 2);
      expectRejected(zip, 'grande demais', limits: const ProjectFileLimits(maxSampleBytes: 1 << 20));
    });

    test('arquivo acima do limite de tamanho e entradas demais', () async {
      final built = await buildProjectFile(name: 'x', doc: doc, loadSample: loader(files));
      expectRejected(built.bytes, 'grande demais', limits: const ProjectFileLimits(maxFileBytes: 100));
      expectRejected(built.bytes, 'entradas demais', limits: const ProjectFileLimits(maxEntries: 2));
    });
  });

  group('ids', () {
    test('ids seguros e únicos ficam como estão', () {
      final files = <String, Uint8List>{};
      final doc = richDoc(files);
      final before = jsonEncode(doc.toJson());
      remapDocIds(doc);
      expect(jsonEncode(doc.toJson()), before);
    });

    test('ids repetidos, vazios e estranhos são refeitos, e as referências acompanham', () {
      final files = <String, Uint8List>{};
      final doc = richDoc(files);
      doc.tracks[0].id = 'x y/../z'; // inseguro
      doc.tracks[1].id = 'bus'; // repete o barramento (que vem depois): quem vem primeiro fica com o id
      doc.tracks[0].clips[0].id = '';
      doc.markers[1].id = 'k2'; // duplica o outro marcador
      doc.tracks[2].effects[0].id = 'fx1';
      remapDocIds(doc);
      final ids = <String>[
        for (final t in doc.tracks) ...[
          t.id,
          for (final c in t.clips) c.id,
          for (final c in t.midi) c.id,
          for (final e in t.effects) e.id,
          for (final l in t.lanes) l.id,
        ],
        for (final m in doc.markers) m.id,
        for (final e in doc.masterEffects) e.id,
        for (final l in doc.masterLanes) l.id,
      ];
      expect(ids.toSet().length, ids.length, reason: 'todos únicos');
      expect(ids.every((i) => RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(i)), isTrue);
      final a = doc.tracks[0];
      expect(a.id, isNot('x y/../z'));
      final trackIds = doc.tracks.map((t) => t.id).toList();
      // com 'bus' repetido, o envio e a saída resolvem para o primeiro que tinha o id (o sampler)
      expect(trackIds, contains(a.sends.single.target));
      expect(trackIds, contains(a.output));
      expect(a.lanes[0].target.ref, a.sends.single.target);
      expect(doc.tracks[2].effects.single.id, isNotEmpty);
    });

    test('referências para o que não existe: envio some, saída volta ao master, automação some', () {
      final files = <String, Uint8List>{};
      final doc = richDoc(files);
      doc.tracks[0].sends.add(Send(target: 'fantasma'));
      doc.tracks[0].output = 'fantasma';
      doc.tracks[0].lanes.add(
        AutoLane(
          id: 'lx',
          target: const AutoTarget(AutoKind.effect, ref: 'nao-existe'),
        ),
      );
      doc.tracks[0].lanes.add(
        AutoLane(
          id: 'ly',
          target: const AutoTarget(AutoKind.send, ref: 'nao-existe'),
        ),
      );
      remapDocIds(doc);
      final a = doc.tracks[0];
      expect(a.sends.map((s) => s.target), ['bus']);
      expect(a.output, isNull);
      expect(a.lanes.map((l) => l.id), ['l1', 'l2']);
    });

    test('depois de refeitos, o documento continua lendo e escrevendo igual e as referências apontam para os ids novos', () {
      final files = <String, Uint8List>{};
      final doc = richDoc(files);
      for (final t in doc.tracks) {
        t.id = '';
      }
      remapDocIds(doc);
      final again = DawDoc.fromJson(jsonDecode(jsonEncode(doc.toJson())) as Map<String, dynamic>);
      expect(jsonEncode(again.toJson()), jsonEncode(doc.toJson()));
      // todos os ids de faixa eram '': as referências resolvem para a primeira; nada fica solto
      final trackIds = doc.tracks.map((t) => t.id).toSet();
      expect(trackIds.length, 3);
      for (final t in doc.tracks) {
        for (final s in t.sends) {
          expect(trackIds, contains(s.target));
        }
        if (t.output != null) expect(trackIds, contains(t.output));
      }
    });

    test('ids distintos mas todos ruins: as referências acompanham a faixa certa', () {
      final files = <String, Uint8List>{};
      final doc = richDoc(files);
      doc.tracks[2].id = 'barramento de reverb'; // o barramento ganha um id inseguro
      doc.tracks[0].sends[0].target = 'barramento de reverb';
      doc.tracks[0].output = 'barramento de reverb';
      doc.tracks[0].lanes[0].target = const AutoTarget(AutoKind.send, ref: 'barramento de reverb');
      remapDocIds(doc);
      final bus = doc.tracks[2].id;
      expect(bus, isNot('barramento de reverb'));
      expect(doc.tracks[0].sends[0].target, bus);
      expect(doc.tracks[0].output, bus);
      expect(doc.tracks[0].lanes[0].target.ref, bus);
    });
  });

  group('nomes', () {
    test('nome do projeto importado', () {
      expect(importedProjectName('Beat', ['Outro']), 'Beat');
      expect(importedProjectName('Beat', ['beat']), 'Beat (importado)');
      expect(importedProjectName('Beat', ['Beat', 'Beat (importado)']), 'Beat (importado 2)');
      expect(importedProjectName('  ', []), 'Projeto importado');
      final long = 'a' * 200;
      expect(importedProjectName(long, []).length, 120);
      expect(importedProjectName(long, ['a' * 120]).length, lessThanOrEqualTo(120));
      expect(importedProjectName(long, ['a' * 120]), endsWith(' (importado)'));
    });

    test('nome do arquivo exportado', () {
      expect(projectFileName('Minha música'), 'Minha música.jopendaw');
      expect(projectFileName('a/b\\c:d*e?f"g<h>i|j'), 'a_b_c_d_e_f_g_h_i_j.jopendaw');
      expect(projectFileName('../../x'), isNot(contains('/')));
      expect(projectFileName('../../x'), isNot(startsWith('.')));
      expect(projectFileName('   '), 'projeto.jopendaw');
      expect(projectFileName('...'), 'projeto.jopendaw');
      expect(projectFileName('a' * 300).length, 80 + '.jopendaw'.length);
    });
  });

  group('importar', () {
    test('cria projeto novo, ajusta andamento e compasso, grava áudios e documento no aparelho', () async {
      final files = <String, Uint8List>{};
      final doc = richDoc(files);
      final b = await bundleOf(files, doc);
      final store = MemoryStore();
      final created = <String>[];
      final patches = <Map<String, dynamic>>[];
      final p = await importProjectBundle(
        b,
        existingNames: ['Beat'],
        createProject: (n) async {
          created.add(n);
          return proj('novo', n);
        },
        patchProject: (id, patch) async {
          patches.add(patch);
          return proj(id, 'Beat (importado)', bpm: patch['bpm'], bpb: patch['beats_per_bar']);
        },
        deleteProject: (_) async => fail('não devia apagar'),
        store: store,
      );
      expect(created, ['Beat (importado)']);
      expect(patches, [
        {'bpm': 134, 'beats_per_bar': 3},
      ]);
      expect(p.id, 'novo');
      for (final e in files.entries) {
        expect(store.data['sample:${e.key}'], e.value);
      }
      final saved = DawDoc.fromJson(jsonDecode(store.data['doc:novo'] as String) as Map<String, dynamic>);
      expect(saved.tracks.map((t) => t.name), ['Voz', 'Sampler', 'Reverb']);
      expect(saved.bpm, 134);
      expect(saved.beatsPerBar, 3);
      expect(saved.markers.map((m) => m.name), ['intro', 'refrão']);
    });

    test('não sobrescreve um áudio que o aparelho já tem e não mexe em outro projeto', () async {
      final files = <String, Uint8List>{};
      final doc = richDoc(files);
      final b = await bundleOf(files, doc);
      final store = MemoryStore();
      final other = Uint8List.fromList([1, 2, 3]);
      store.data['doc:antigo'] = 'documento antigo';
      store.data['sample:${files.keys.first}'] = other;
      await importProjectBundle(
        b,
        existingNames: const [],
        createProject: (n) async => proj('novo', n, bpm: 134, bpb: 3),
        patchProject: (id, patch) async => fail('andamento já igual: sem patch'),
        deleteProject: (_) async {},
        store: store,
      );
      expect(store.data['doc:antigo'], 'documento antigo');
      expect(store.data['sample:${files.keys.first}'], other, reason: 'mesmo sha-256 = mesmo conteúdo; o que já existe fica');
      expect(store.data.containsKey('doc:novo'), isTrue);
    });

    test('falha no meio: o projeto criado é apagado e o erro segue', () async {
      final files = <String, Uint8List>{};
      final doc = richDoc(files);
      final b = await bundleOf(files, doc);
      final deleted = <String>[];
      final store = _FailingStore();
      await expectLater(
        importProjectBundle(
          b,
          existingNames: const [],
          createProject: (n) async => proj('novo', n, bpm: 134, bpb: 3),
          patchProject: (id, patch) async => proj(id, 'x'),
          deleteProject: (id) async => deleted.add(id),
          store: store,
        ),
        throwsA(isA<StateError>()),
      );
      expect(deleted, ['novo']);
      expect(store.data.containsKey('doc:novo'), isFalse, reason: 'o documento é o último a ser gravado');
    });

    test('importar duas vezes cria dois projetos', () async {
      final files = <String, Uint8List>{};
      final doc = richDoc(files);
      final store = MemoryStore();
      var n = 0;
      final names = <String>[];
      for (var i = 0; i < 2; i++) {
        final b = await bundleOf(files, doc);
        await importProjectBundle(
          b,
          existingNames: names,
          createProject: (name) async {
            names.add(name);
            return proj('p${n++}', name, bpm: 134, bpb: 3);
          },
          patchProject: (id, patch) async => proj(id, 'x'),
          deleteProject: (_) async {},
          store: store,
        );
      }
      expect(names, ['Beat', 'Beat (importado)']);
      expect(store.data.keys.where((k) => k.startsWith('doc:')).toSet(), {'doc:p0', 'doc:p1'});
    });

    test('ProjectImporter: arquivo inválido não cria nada', () async {
      var created = 0;
      final imp = ProjectImporter(
        existingNames: () => const [],
        createProject: (n) async {
          created++;
          return proj('x', n);
        },
        patchProject: (id, p) async => proj(id, 'x'),
        deleteProject: (_) async {},
        store: MemoryStore(),
      );
      await expectLater(imp.import(Uint8List.fromList([1, 2, 3])), throwsA(isA<ProjectFileException>()));
      expect(created, 0);
    });
  });

  group('janela de exportar', () {
    Future<void> open(WidgetTester t, {required Future<void> Function(String, Uint8List, String) save, Future<DawDoc> Function()? loadDoc}) async {
      final files = <String, Uint8List>{};
      final doc = richDoc(files);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExportProjectDialog(
              name: 'Meu/projeto',
              loadDoc: loadDoc ?? () async => doc,
              loadSample: (h) async => h == files.keys.first ? null : files[h],
              save: save,
            ),
          ),
        ),
      );
    }

    testWidgets('monta, salva como <nome>.jopendaw e avisa do áudio que ficou de fora', (t) async {
      final saved = <(String, Uint8List, String)>[];
      await open(t, save: (n, b, m) async => saved.add((n, b, m)));
      await t.pumpAndSettle();
      expect(saved.single.$1, 'Meu_projeto.jopendaw');
      expect(saved.single.$3, projectFileMime);
      expect(parseProjectFile(saved.single.$2).missing.length, 1);
      expect(find.byKey(const Key('export-done')), findsOneWidget);
      expect(find.textContaining('1 áudio não está'), findsOneWidget);
      expect(find.text('Fechar'), findsOneWidget);
    });

    testWidgets('erro fica dentro da janela e dá para tentar de novo', (t) async {
      var calls = 0;
      await open(
        t,
        save: (n, b, m) async {
          if (++calls == 1) throw UnsupportedError('Salvar arquivos não funciona neste sistema.');
        },
      );
      await t.pumpAndSettle();
      expect(find.text('Salvar arquivos não funciona neste sistema.'), findsOneWidget);
      expect(find.text('Tentar de novo'), findsOneWidget);
      await t.tap(find.text('Tentar de novo'));
      await t.pumpAndSettle();
      expect(calls, 2);
      expect(find.byKey(const Key('export-done')), findsOneWidget);
      expect(find.text('Tentar de novo'), findsNothing);
    });

    testWidgets('projeto sem documento no aparelho nem no servidor: mensagem clara', (t) async {
      await open(
        t,
        save: (n, b, m) async {},
        loadDoc: () => loadDocLocalOrServer('p', store: MemoryStore(), remote: (_) async => null),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('ainda não tem nada para exportar'), findsOneWidget);
    });
  });

  group('ler do aparelho ou do servidor', () {
    test('áudio: aparelho primeiro, depois servidor, e falha de rede vira ausente', () async {
      final store = MemoryStore()..data['sample:a'] = audio(1);
      expect(await loadSampleLocalOrServer('a', store: store, remote: (_) async => fail('não devia ir ao servidor')), audio(1));
      expect(await loadSampleLocalOrServer('b', store: store, remote: (_) async => audio(2)), audio(2));
      expect(await loadSampleLocalOrServer('c', store: store, remote: (_) async => throw Exception('sem rede')), isNull);
    });

    test('documento: o do aparelho, senão o do servidor', () async {
      final files = <String, Uint8List>{};
      final doc = richDoc(files);
      final store = MemoryStore()..data['doc:p'] = jsonEncode(doc.toJson());
      expect(jsonEncode((await loadDocLocalOrServer('p', store: store, remote: (_) async => fail('não'))).toJson()), jsonEncode(doc.toJson()));
      final fromServer = await loadDocLocalOrServer('q', store: store, remote: (_) async => doc.toJson());
      expect(fromServer.tracks.length, 3);
    });
  });
}
