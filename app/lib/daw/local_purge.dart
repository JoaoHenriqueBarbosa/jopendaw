/// Limpeza do que um projeto apagado deixa no guardado local do aparelho.
library;

import 'dart:convert';

import '../audio/engine.dart';
import 'controller.dart';
import 'model.dart';

/// Apaga do aparelho o documento (`doc:<id>`), o estado de sincronização (`sync:<id>`), o modelo
/// pendente (`template:<id>`) e os áudios que só este projeto citava. Um áudio que o documento
/// local de qualquer projeto de [otherProjectIds] ainda cita fica. Nunca lança: o que não deu para
/// apagar sobra como lixo inofensivo. Devolve quantos áudios foram apagados.
///
/// Os sons derivados do warp (`warp:<chave>`) não entram: o guardado não lista chaves, e eles se
/// refazem a partir do original.
Future<int> purgeLocalProject(LocalStore store, String projectId, Iterable<String> otherProjectIds) async {
  var removed = 0;
  try {
    final hashes = await _docHashes(store, projectId);
    final kept = <String>{};
    for (final id in otherProjectIds) {
      if (id != projectId) kept.addAll(await _docHashes(store, id));
    }
    for (final key in ['doc:$projectId', 'sync:$projectId', 'template:$projectId']) {
      try {
        await store.delete(key);
      } catch (_) {}
    }
    for (final h in hashes.difference(kept)) {
      try {
        await store.delete('sample:$h');
        removed++;
      } catch (_) {}
    }
  } catch (_) {
    // guardado ilegível: nada a limpar
  }
  return removed;
}

Future<Set<String>> _docHashes(LocalStore store, String projectId) async {
  try {
    final raw = await store.get('doc:$projectId');
    if (raw is! String) return {};
    return DawController.hashesOf(DawDoc.fromJson(jsonDecode(raw)));
  } catch (_) {
    return {};
  }
}
