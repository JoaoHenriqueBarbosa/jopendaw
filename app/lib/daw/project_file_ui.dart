/// Telas do arquivo `.jopendaw`: a janela de exportar (com progresso e erro dentro dela) e a
/// importação do seletor de arquivos. A lógica está em `project_file.dart`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../api/client.dart';
import '../audio/engine.dart';
import '../models/project.dart';
import '../widgets/feedback.dart';
import '../widgets/format.dart';
import 'model.dart';
import 'project_file.dart';

/// Guarda o arquivo pronto: o mesmo caminho do WAV (`saveFile` do motor: download na web, "salvar
/// como"/compartilhar no Android).
typedef SaveProjectFile = Future<void> Function(String name, Uint8List bytes, String mime);

/// Octet-stream de propósito: com "application/zip" o seletor do Android pode acrescentar `.zip`.
const projectFileMime = 'application/octet-stream';

/// Abre a janela que monta e salva o `.jopendaw`. [loadDoc] entrega o documento (do editor, o que
/// está na memória; da lista, o guardado no aparelho ou, na falta, o do servidor); [loadSample], os
/// bytes de um áudio (aparelho, depois servidor).
Future<void> showExportProjectDialog(
  BuildContext context, {
  required String name,
  required Future<DawDoc> Function() loadDoc,
  required Future<Uint8List?> Function(String hash) loadSample,
  SaveProjectFile? save,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => ExportProjectDialog(name: name, loadDoc: loadDoc, loadSample: loadSample, save: save),
);

/// Áudio pelo aparelho e, se não há, pelo servidor (falha de rede conta como ausente).
Future<Uint8List?> loadSampleLocalOrServer(String hash, {LocalStore? store, Future<Uint8List?> Function(String hash)? remote}) async {
  final local = await (store ?? LocalStore.instance).get('sample:$hash');
  if (local is Uint8List) return local;
  try {
    return await (remote ?? ApiClient.instance.getSample)(hash);
  } catch (_) {
    return null;
  }
}

/// O documento de um projeto que não está aberto: o guardado no aparelho ou, se este aparelho nunca
/// o abriu, o do servidor.
Future<DawDoc> loadDocLocalOrServer(String projectId, {LocalStore? store, Future<Map<String, dynamic>?> Function(String id)? remote}) async {
  final saved = await (store ?? LocalStore.instance).get('doc:$projectId');
  if (saved is String) return DawDoc.fromJson(jsonDecode(saved) as Map<String, dynamic>);
  final Map<String, dynamic>? server = await (remote ?? (id) async => (await ApiClient.instance.projectDoc(id)).doc)(projectId);
  if (server == null) {
    throw StateError('Este projeto ainda não tem nada para exportar: abra-o e adicione algo primeiro.');
  }
  return DawDoc.fromJson(server);
}

class ExportProjectDialog extends StatefulWidget {
  final String name;
  final Future<DawDoc> Function() loadDoc;
  final Future<Uint8List?> Function(String hash) loadSample;
  final SaveProjectFile? save;
  const ExportProjectDialog({super.key, required this.name, required this.loadDoc, required this.loadSample, this.save});

  @override
  State<ExportProjectDialog> createState() => _ExportProjectDialogState();
}

class _ExportProjectDialogState extends State<ExportProjectDialog> {
  String status = 'Preparando…';
  double? progress;
  String? error;
  BuiltProjectFile? done;
  bool running = true;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    setState(() {
      running = true;
      error = null;
      done = null;
      progress = null;
      status = 'Preparando…';
    });
    try {
      final doc = await widget.loadDoc();
      final built = await buildProjectFile(
        name: widget.name,
        doc: doc,
        loadSample: widget.loadSample,
        onProgress: (d, t) {
          if (!mounted) return;
          setState(() {
            status = t == 0 ? 'Montando o arquivo…' : 'Reunindo os áudios: $d de $t';
            progress = t == 0 ? null : d / t;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        status = 'Salvando…';
        progress = null;
      });
      await (widget.save ?? AudioEngine.instance.saveFile)(projectFileName(widget.name), built.bytes, projectFileMime);
      if (!mounted) return;
      setState(() => done = built);
    } catch (e) {
      if (mounted) setState(() => error = _describe(e));
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  String _describe(Object e) => switch (e) {
    UnsupportedError(:final message?) => message,
    StateError(:final message) => message,
    _ => 'Não deu para exportar o projeto: $e',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = done;
    return AlertDialog(
      title: const Text('Exportar projeto'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (running) ...[Text(status, key: const Key('export-status')), const SizedBox(height: 12), LinearProgressIndicator(value: progress)],
            if (error != null) InlineNotice(error!),
            if (d != null) ...[
              Text('Pronto: ${projectFileName(widget.name)} (${plural(d.sampleCount, 'áudio')}).', key: const Key('export-done')),
              if (d.missing.isNotEmpty) ...[
                const SizedBox(height: 12),
                InlineNotice(
                  '${d.missing.length == 1 ? '1 áudio não está' : '${d.missing.length} áudios não estão'} neste aparelho nem no servidor e ficou de fora do arquivo: '
                  'o projeto abre, mas esse som fica em silêncio.',
                ),
              ],
              const SizedBox(height: 8),
              Text('Guarda as faixas, os clipes, a mixagem e os áudios do projeto.', style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
      actions: [
        if (error != null) TextButton(onPressed: _run, child: const Text('Tentar de novo')),
        TextButton(onPressed: running ? null : () => Navigator.pop(context), child: Text(d != null ? 'Fechar' : 'Cancelar')),
      ],
    );
  }
}

/// Escolhe um `.jopendaw` e devolve o nome e os bytes (null se a pessoa cancelou).
Future<(String, Uint8List)?> pickProjectFile() async {
  final files = await FilePicker.pickFiles(dialogTitle: 'Importar projeto', type: FileType.custom, allowedExtensions: const [projectFileExtension, 'zip']);
  if (files.isEmpty) return null;
  final f = files.first;
  return (f.name, await f.readAsBytes());
}

/// O que a tela precisa da API e do aparelho para importar (trocável nos testes).
class ProjectImporter {
  final Iterable<String> Function() existingNames;
  final Future<Project> Function(String name) createProject;
  final Future<Project> Function(String id, Map<String, dynamic> patch) patchProject;
  final Future<void> Function(String id) deleteProject;
  final LocalStore store;
  const ProjectImporter({
    required this.existingNames,
    required this.createProject,
    required this.patchProject,
    required this.deleteProject,
    required this.store,
  });

  /// Valida o arquivo (tudo ou nada) e cria o projeto novo. [onStatus] recebe o andamento.
  Future<Project> import(Uint8List bytes, {void Function(String status)? onStatus}) async {
    onStatus?.call('Conferindo o arquivo…');
    // a leitura é síncrona e pesada: deixa a tela pintar a mensagem antes
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final bundle = parseProjectFile(bytes);
    onStatus?.call('Criando o projeto…');
    return importProjectBundle(
      bundle,
      existingNames: existingNames(),
      createProject: createProject,
      patchProject: patchProject,
      deleteProject: deleteProject,
      store: store,
      onProgress: (d, t) => onStatus?.call('Guardando os áudios: $d de $t'),
    );
  }
}
