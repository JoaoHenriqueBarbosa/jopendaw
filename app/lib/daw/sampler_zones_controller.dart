/// Edição das zonas do sampler pelo controlador: acrescentar, editar, remover, fatiar. Tudo entra
/// no desfazer (o documento inteiro é o instantâneo) e vai ao motor pelo sync (`zones_clear` e
/// `zone_add`, ver `_syncZones` em `controller.dart`).
library;

import 'package:file_picker/file_picker.dart';

import '../audio/engine_types.dart';
import 'controller.dart';
import 'instruments.dart';
import 'model.dart';
import 'presets.dart' show SamplerId;
import 'sampler_zones.dart';

extension SamplerZonesEdit on DawController {
  DawTrack? _samplerTrack(int track) => track >= 0 && track < doc.tracks.length && doc.tracks[track].kind == TrackKind.sampler ? doc.tracks[track] : null;

  /// As zonas da faixa (vazia se não é um sampler).
  List<SamplerZone> zonesOf(int track) => _samplerTrack(track)?.zones ?? const [];

  /// Acrescenta uma zona que toca o áudio [sample] (uma chave de `doc.samples`) numa faixa livre do
  /// teclado (ver [nextZoneRange]); com o teclado todo coberto divide a zona mais larga ao meio e, sem
  /// nem isso, sobrepõe. Nos dois últimos casos [onNotice] recebe o aviso para o usuário. Devolve a zona,
  /// ou null se a faixa não é um sampler, o áudio não é do projeto ou as zonas já estão no limite.
  SamplerZone? addZone(int track, String sample, {void Function(String notice)? onNotice}) {
    final t = _samplerTrack(track);
    if (t == null || !doc.samples.containsKey(sample) || t.zones.length >= maxZones) return null;
    final r = nextZoneRange(t.zones);
    final z = SamplerZone(id: newId(), sample: sample, root: r.root, lo: r.lo, hi: r.hi);
    final cut = r.divides;
    final cutName = cut == null ? null : doc.samples[cut.sample]?.name ?? 'sem nome';
    edit((_) {
      if (cut != null) cut.hi = r.lo - 1;
      t.zones.add(z);
    });
    if (cut != null) {
      onNotice?.call(
        'O teclado já estava coberto: a zona "$cutName" foi dividida e a nova ficou com ${noteName(r.lo)} a ${noteName(r.hi)}. Ajuste as faixas no mapa.',
      );
    } else if (r.overlaps) {
      onNotice?.call('Não há faixa livre nem zona para dividir: a nova zona ficou por cima das outras, em ${noteName(r.lo)} a ${noteName(r.hi)}.');
    }
    return z;
  }

  /// Divide a zona [zoneId] em [n] camadas de velocidade iguais (ver [velocityLayers]): ela fica com a
  /// primeira faixa e [n] − 1 cópias (mesmo áudio e mesmas notas; troque o áudio de cada uma) vão logo
  /// depois com as outras. Devolve as zonas novas (vazio se não coube nos [maxZones] ou [n] < 2).
  List<SamplerZone> splitZoneLayers(int track, String zoneId, int n) {
    final t = _samplerTrack(track);
    final i = t?.zones.indexWhere((z) => z.id == zoneId) ?? -1;
    final layers = velocityLayers(n);
    if (t == null || i < 0 || layers.length < 2 || t.zones.length + layers.length - 1 > maxZones) return const [];
    final copies = [for (var k = 1; k < layers.length; k++) t.zones[i].copy(id: newId())..vlo = layers[k].$1];
    edit((_) {
      final z = t.zones[i];
      for (var k = 0; k < layers.length; k++) {
        final target = k == 0 ? z : copies[k - 1];
        target
          ..vlo = layers[k].$1
          ..vhi = layers[k].$2;
      }
      t.zones.insertAll(i + 1, copies);
    });
    return copies;
  }

  /// Faz do áudio único da faixa a primeira zona (a nota base do instrumento, o teclado todo).
  SamplerZone? zoneFromTrackSample(int track) {
    final t = _samplerTrack(track);
    final s = t?.sample;
    if (t == null || s == null || !doc.samples.containsKey(s) || t.zones.isNotEmpty) return null;
    final z = SamplerZone(id: newId(), sample: s, root: t.param(SamplerId.root).round());
    edit((_) => t.zones.add(z));
    return z;
  }

  /// Muda uma zona: [fn] mexe nos campos e a zona volta às faixas válidas. [undoable] falso nos
  /// passos de um arraste (o ponto de desfazer é o `checkpoint` do começo dele).
  void editZone(int track, String zoneId, void Function(SamplerZone z) fn, {bool undoable = true}) {
    final z = _samplerTrack(track)?.zones.where((z) => z.id == zoneId).firstOrNull;
    if (z == null) return;
    void apply(_) {
      fn(z);
      z.normalize();
    }

    if (undoable) {
      edit(apply);
    } else {
      mutate(apply);
    }
  }

  void removeZone(int track, String zoneId) {
    final t = _samplerTrack(track);
    if (t == null || !t.zones.any((z) => z.id == zoneId)) return;
    edit((_) => t.zones.removeWhere((z) => z.id == zoneId));
  }

  /// Uma cópia da zona, logo depois dela e na mesma faixa de notas.
  SamplerZone? duplicateZone(int track, String zoneId) {
    final t = _samplerTrack(track);
    final i = t?.zones.indexWhere((z) => z.id == zoneId) ?? -1;
    if (t == null || i < 0 || t.zones.length >= maxZones) return null;
    final copy = t.zones[i].copy(id: newId());
    edit((_) => t.zones.insert(i + 1, copy));
    return copy;
  }

  void clearZones(int track) {
    final t = _samplerTrack(track);
    if (t == null || t.zones.isEmpty) return;
    edit((_) => t.zones.clear());
  }

  /// Escolhe um arquivo, importa para o projeto e o acrescenta como zona.
  Future<SamplerZone?> addZoneFromFile(int track, {void Function(String notice)? onNotice}) async {
    final files = await FilePicker.pickFiles(dialogTitle: 'Áudio da zona', type: FileType.custom, allowedExtensions: DawController.audioExtensions);
    if (files.isEmpty) return null;
    final f = files.first;
    final hash = await importSampleFile(f.name, await f.readAsBytes());
    return hash == null ? null : addZone(track, hash, onNotice: onNotice);
  }

  /// Os cortes que o fatiamento faria no áudio [sample] (em segundos), para a prévia: [count]
  /// fatias iguais ou, sem ele, um corte por transiente. Null se o áudio não está neste aparelho.
  List<double>? slicePreview(String sample, {int? count, double sensitivity = 0.5}) {
    final DecodedAudio? audio = decodedAudio(sample);
    return audio == null ? null : slicePoints(audio, count: count, sensitivity: sensitivity);
  }

  /// Troca as zonas da faixa por uma por fatia de [sample], uma nota cada a partir de C1 (modo
  /// até o fim, cada uma tocando só a sua fatia). Devolve quantas zonas criou (0: nada mudou).
  int createSlices(int track, String sample, List<double> points) {
    final t = _samplerTrack(track);
    if (t == null || !doc.samples.containsKey(sample)) return 0;
    final zones = sliceZones(sample, points, newId);
    if (zones.isEmpty) return 0;
    edit((_) => t.zones = zones);
    return zones.length;
  }
}
