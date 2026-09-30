/// Limpeza do que um projeto apagado deixa no guardado local do aparelho.
library;

import 'dart:convert';

import '../audio/engine.dart';
import 'controller.dart';
import 'model.dart';
import 'snapshots.dart' show snapshotPrefix;

/// Apaga do aparelho o documento (`doc:<id>`), o estado de sincronização (`sync:<id>`), o modelo
/// pendente (`template:<id>`) e os áudios que só este projeto citava. Um áudio que o documento
/// local de qualquer outro projeto ainda cita fica: os de [otherProjectIds] e todo `doc:*` que o
/// guardado listar. Nunca lança: o que não deu para
/// apagar sobra como lixo inofensivo. Devolve quantos áudios foram apagados.
///
/// Os sons derivados do warp (`warp:<hash>|<parâmetros>`, ver `WarpSpec.key`) dos áudios apagados saem junto: o guardado
/// lista as chaves por prefixo e a chave começa pelo hash da origem.
Future<int> purgeLocalProject(LocalStore store, String projectId, Iterable<String> otherProjectIds) async {
  var removed = 0;
  try {
    final hashes = await _docHashes(store, projectId);
    final kept = <String>{};
    // todos os documentos guardados neste aparelho, não só os da lista carregada (ela pode estar
    // velha, vir de outra conta ou faltar projeto que só existe aqui)
    final ids = {...otherProjectIds};
    try {
      for (final k in await store.keys('doc:')) {
        ids.add(k.substring(4));
      }
    } catch (_) {}
    for (final id in ids) {
      if (id != projectId) kept.addAll(await _docHashes(store, id));
    }
    for (final key in ['doc:$projectId', 'sync:$projectId', 'template:$projectId', ...await _versionKeys(store, projectId)]) {
      try {
        await store.delete(key);
      } catch (_) {}
    }
    final gone = hashes.difference(kept);
    for (final h in gone) {
      try {
        await store.delete('sample:$h');
        removed++;
      } catch (_) {}
    }
    if (gone.isNotEmpty) {
      try {
        for (final k in await store.keys('warp:')) {
          // "warp:<hash>|…": só os derivados de áudios que saíram
          final bar = k.indexOf('|');
          if (bar > 5 && gone.contains(k.substring(5, bar))) {
            try {
              await store.delete(k);
            } catch (_) {}
          }
        }
      } catch (_) {}
    }
  } catch (_) {
    // guardado ilegível: nada a limpar
  }
  return removed;
}

/// As chaves das versões nomeadas do projeto (`snapshots:<projeto>:<id>`), com as ilegíveis também.
Future<List<String>> _versionKeys(LocalStore store, String projectId) async {
  try {
    return await store.keys(snapshotPrefix(projectId));
  } catch (_) {
    return const [];
  }
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
