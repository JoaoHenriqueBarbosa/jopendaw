/// A parte de tela dos presets do usuário: a seção "Meus presets" dos menus de instrumento e de
/// efeito, o diálogo de nome, e as ações (salvar, renomear, apagar, exportar, importar). A lógica
/// e o guardado ficam em `user_presets.dart`.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../audio/engine.dart';
import '../widgets/theme.dart';
import 'user_presets.dart';

/// Guarda o `.jopreset` (o mesmo caminho do WAV e do projeto: download na web, "salvar como" no Android).
///
/// Devolve `false` se a pessoa cancelou o "salvar como" (o `saveFile` do motor devolve bool); qualquer outro valor é "guardado".
typedef SavePresetFile = Future<Object?> Function(String name, Uint8List bytes, String mime);

/// Escolhe o arquivo a importar: nome e bytes, ou null se a pessoa cancelou.
typedef PickPresetFile = Future<(String, Uint8List)?> Function();

/// Valores dos itens do menu de presets que não são "aplicar um preset de fábrica".
sealed class UserPresetChoice {
  const UserPresetChoice();
}

class ApplyUserPreset extends UserPresetChoice {
  final UserPreset preset;
  const ApplyUserPreset(this.preset);
}

class UserPresetMore extends UserPresetChoice {
  final UserPreset preset;
  const UserPresetMore(this.preset);
}

class SaveUserPreset extends UserPresetChoice {
  const SaveUserPreset();
}

class ImportUserPreset extends UserPresetChoice {
  const ImportUserPreset();
}

/// "Restaurar presets do backup…": tenta recuperar os presets da cópia do arquivo ilegível.
class RestoreUserPresets extends UserPresetChoice {
  const RestoreUserPresets();
}

/// Dispensar o aviso de carga (informativo) do topo do menu.
class DismissUserPresetNotice extends UserPresetChoice {
  const DismissUserPresetNotice();
}

/// Octet-stream de propósito (como o `.jopendaw`): com um tipo específico o seletor do Android pode
/// acrescentar uma extensão.
const userPresetMime = 'application/octet-stream';

Future<(String, Uint8List)?> pickUserPresetFile() async {
  final files = await FilePicker.pickFiles(dialogTitle: 'Importar preset', type: FileType.custom, allowedExtensions: const [userPresetExtension, 'json']);
  if (files.isEmpty) return null;
  final f = files.first;
  return (f.name, await f.readAsBytes());
}

/// As entradas que os menus põem NO TOPO, acima dos presets de fábrica (para não ficarem atrás de
/// dezenas de itens): a seção "Meus presets" e os itens "Salvar como preset…" e "Importar preset…".
/// Terminam num divisor, que já separa dos de fábrica. Os valores são [UserPresetChoice].
/// [checkWidth] é a largura da coluna do visto, para alinhar com os itens de fábrica.
///
/// [problem] (`UserPresets.problem`): aviso inline, em vermelho, quando os presets NÃO estão sendo
/// guardados neste aparelho (falha de gravação). [notice] (`UserPresets.infoNotice`): aviso de
/// carga, só informativo (o arquivo ilegível foi guardado à parte e tudo grava normalmente); toque
/// nele para dispensar. [hasBackup] (`UserPresets.hasBackup`): oferece "Restaurar presets do backup…".
List<PopupMenuEntry<Object>> userPresetEntries({
  required List<UserPreset> presets,
  UserPreset? current,
  required Color color,
  double checkWidth = 24,
  String? problem,
  String? notice,
  bool hasBackup = false,
}) {
  return [
    if (problem != null)
      PopupMenuItem<Object>(
        key: const ValueKey('user-preset-problem'),
        enabled: false,
        height: 44,
        child: Text(problem, style: const TextStyle(fontSize: 12, color: Palette.danger)),
      ),
    if (notice != null)
      PopupMenuItem<Object>(
        key: const ValueKey('user-preset-notice'),
        value: const DismissUserPresetNotice(),
        height: 56,
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 16, color: Colors.white54),
            const SizedBox(width: 8),
            Expanded(
              child: Text('$notice (toque para dispensar)', style: const TextStyle(fontSize: 12, color: Colors.white70)),
            ),
          ],
        ),
      ),
    PopupMenuItem<Object>(
      enabled: false,
      height: 26,
      child: Text(
        'MEUS PRESETS',
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.9, color: color),
      ),
    ),
    if (presets.isEmpty)
      const PopupMenuItem<Object>(
        enabled: false,
        height: 30,
        child: Text('Nenhum ainda', style: TextStyle(fontSize: 12.5, color: Colors.white38)),
      ),
    for (final p in presets)
      PopupMenuItem<Object>(
        key: ValueKey('user-preset-${p.id}'),
        value: ApplyUserPreset(p),
        height: 36,
        padding: const EdgeInsets.only(left: 16, right: 4),
        child: Row(
          children: [
            SizedBox(
              width: checkWidth,
              child: identical(p, current) ? Icon(Icons.check, size: 16, color: color) : null,
            ),
            Expanded(child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
            Builder(
              builder: (context) => IconButton(
                key: ValueKey('user-preset-more-${p.id}'),
                tooltip: 'Renomear, apagar ou exportar',
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                icon: const Icon(Icons.more_horiz, color: Colors.white54),
                onPressed: () => Navigator.pop(context, UserPresetMore(p)),
              ),
            ),
          ],
        ),
      ),
    const PopupMenuDivider(height: 8),
    const PopupMenuItem<Object>(
      key: ValueKey('user-preset-save'),
      value: SaveUserPreset(),
      height: 38,
      child: Row(
        children: [
          Icon(Icons.bookmark_add_outlined, size: 18, color: Colors.white70),
          SizedBox(width: 12),
          Text('Salvar como preset…'),
        ],
      ),
    ),
    const PopupMenuItem<Object>(
      key: ValueKey('user-preset-import'),
      value: ImportUserPreset(),
      height: 38,
      child: Row(
        children: [
          Icon(Icons.file_open_outlined, size: 18, color: Colors.white70),
          SizedBox(width: 12),
          Text('Importar preset…'),
        ],
      ),
    ),
    if (hasBackup)
      const PopupMenuItem<Object>(
        key: ValueKey('user-preset-restore'),
        value: RestoreUserPresets(),
        height: 38,
        child: Row(
          children: [
            Icon(Icons.restore, size: 18, color: Colors.white70),
            SizedBox(width: 12),
            Text('Restaurar presets do backup…'),
          ],
        ),
      ),
    const PopupMenuDivider(height: 8),
  ];
}

enum _MoreAction { rename, export, delete }

/// Trata uma escolha de [userPresetEntries] (menos [ApplyUserPreset], que cada painel aplica do
/// jeito dele). [capture] lê os valores atuais do instrumento ou do efeito para o "Salvar".
Future<void> handleUserPresetChoice(
  BuildContext context,
  UserPresetChoice choice, {
  required PresetFamily family,
  required String kind,
  required Map<int, double> Function() capture,
  UserPresets? presets,
  SavePresetFile? save,
  PickPresetFile? pick,
}) async {
  final store = presets ?? UserPresets.instance;
  switch (choice) {
    case ApplyUserPreset():
      return;
    case DismissUserPresetNotice():
      store.dismissLoadNotice();
    case RestoreUserPresets():
      final ok = await confirmPresetDialog(
        context,
        title: 'Restaurar do backup?',
        text:
            'Na abertura, o arquivo dos seus presets estava ilegível e uma cópia dele foi guardada. Vou tentar recuperar os presets das cópias (a mais recente primeiro) e somá-los '
            'aos que você tem agora (os que têm o mesmo nome no mesmo tipo ficam como estão). As cópias continuam guardadas.',
        confirm: 'Restaurar',
      );
      if (!ok || !context.mounted) return;
      try {
        final r = await store.restoreFromBackup();
        String n(int k, String one, String many) => k == 1 ? one : many;
        final skipped =
            '${r.duplicates == 0 ? '' : ' ${r.duplicates} ${n(r.duplicates, 'já existia (mesmo nome) e ficou como estava', 'já existiam (mesmo nome) e ficaram como estavam')}.'}'
            '${r.overLimit == 0 ? '' : ' ${r.overLimit} ${n(r.overLimit, 'ficou de fora', 'ficaram de fora')} porque o tipo já tem o máximo de $maxUserPresetsPerKind presets.'}';
        if (context.mounted) {
          await showPresetMessage(
            context,
            r.restored == 0 ? 'Nada novo para restaurar' : 'Presets restaurados',
            r.restored == 0
                ? 'Nenhum preset da cópia pôde ser somado.$skipped'
                : '${r.restored} preset${r.restored == 1 ? '' : 's'} restaurado${r.restored == 1 ? '' : 's'}.$skipped',
          );
        }
      } on PresetFormatException catch (e) {
        if (context.mounted) await showPresetMessage(context, 'Não foi possível restaurar', e.message);
      }
      if (context.mounted) await _warnIfNotStored(context, store);
    case SaveUserPreset():
      final name = await askPresetName(context, title: 'Salvar como preset', confirm: 'Salvar');
      if (name == null || !context.mounted) return;
      try {
        final values = capture();
        if (store.save(family, kind, name, values) == null) {
          final ok = await confirmPresetDialog(
            context,
            title: 'Substituir o preset?',
            text: 'Já existe um preset chamado "${cleanPresetName(name)}". Substituir pelos valores atuais?',
            confirm: 'Substituir',
          );
          if (!ok) return;
          store.save(family, kind, name, values, replace: true);
        }
      } on PresetFormatException catch (e) {
        if (context.mounted) await showPresetMessage(context, 'Não foi possível salvar', e.message);
        return; // nada foi para o guardado: não há o que avisar sobre gravação
      }
      if (context.mounted) await _warnIfNotStored(context, store);
    case ImportUserPreset():
      try {
        final file = await (pick ?? pickUserPresetFile)();
        if (file == null || !context.mounted) return;
        final PresetImport r;
        try {
          r = store.importBytes(file.$2);
        } on PresetFormatException catch (e) {
          if (context.mounted) await showPresetMessage(context, 'Não foi possível importar "${file.$1}"', e.message);
          return;
        }
        // o arquivo pode ser de outro tipo: ele entra no tipo dele, e o menu deste painel avisa
        final other = r.preset.family != family || r.preset.kind != kind;
        final label = presetKindLabel(r.preset.family, r.preset.kind);
        final lines = [...r.warnings, if (other) 'O preset é de outro tipo ($label): ele foi guardado, mas só aparece no menu desse tipo.'];
        if (lines.isNotEmpty && context.mounted) await showPresetMessage(context, 'Preset "${r.preset.name}" importado', lines.join('\n'));
        if (context.mounted) await _warnIfNotStored(context, store);
      } catch (e) {
        if (context.mounted) await showPresetMessage(context, 'Não foi possível abrir o arquivo', '$e');
      }
    case UserPresetMore(:final preset):
      final action = await showDialog<_MoreAction>(
        context: context,
        builder: (dialog) => SimpleDialog(
          title: Text(preset.name, maxLines: 2, overflow: TextOverflow.ellipsis),
          children: [
            SimpleDialogOption(
              key: const ValueKey('user-preset-rename'),
              onPressed: () => Navigator.pop(dialog, _MoreAction.rename),
              child: const Text('Renomear…'),
            ),
            SimpleDialogOption(
              key: const ValueKey('user-preset-export'),
              onPressed: () => Navigator.pop(dialog, _MoreAction.export),
              child: const Text('Exportar preset…'),
            ),
            SimpleDialogOption(
              key: const ValueKey('user-preset-delete'),
              onPressed: () => Navigator.pop(dialog, _MoreAction.delete),
              child: const Text('Apagar…', style: TextStyle(color: Palette.danger)),
            ),
          ],
        ),
      );
      if (action == null || !context.mounted) return;
      switch (action) {
        case _MoreAction.rename:
          final name = await askPresetName(context, title: 'Renomear preset', confirm: 'Renomear', initial: preset.name);
          if (name == null || !context.mounted) return;
          try {
            if (!store.rename(preset.id, name) && context.mounted) {
              await showPresetMessage(context, 'Nome em uso', 'Já existe outro preset chamado "${cleanPresetName(name)}".');
            }
          } on PresetFormatException catch (e) {
            if (context.mounted) await showPresetMessage(context, 'Não foi possível renomear', e.message);
            return;
          }
          if (context.mounted) await _warnIfNotStored(context, store);
        case _MoreAction.delete:
          final ok = await confirmPresetDialog(
            context,
            title: 'Apagar o preset?',
            text: 'O preset "${preset.name}" será apagado deste aparelho. Isso não pode ser desfeito.',
            confirm: 'Apagar',
            danger: true,
          );
          if (ok) {
            store.delete(preset.id);
            if (context.mounted) await _warnIfNotStored(context, store);
          }
        case _MoreAction.export:
          try {
            final saved = await (save ?? AudioEngine.instance.saveFile)(presetFileName(preset.name), store.exportBytes(preset), userPresetMime);
            // cancelou o "salvar como" (Android): nada foi gravado, e a pessoa fica sabendo
            if (saved == false && context.mounted) await showPresetMessage(context, 'Exportação cancelada', 'O preset "${preset.name}" não foi exportado.');
          } catch (e) {
            if (context.mounted) await showPresetMessage(context, 'Não foi possível exportar', '$e');
          }
      }
  }
}

/// Espera a gravação local e, se ela falhou (ou o guardado é só leitura), avisa que o preset só vale
/// até fechar o app (o menu mostra o mesmo aviso). Um aviso de carga informativo não entra aqui.
Future<void> _warnIfNotStored(BuildContext context, UserPresets store) async {
  await store.flush();
  final problem = store.problem;
  if (problem != null && context.mounted) await showPresetMessage(context, 'Presets não guardados', problem);
}

/// Pede o nome; devolve o nome já limpo (ou null se cancelou).
Future<String?> askPresetName(BuildContext context, {required String title, required String confirm, String initial = ''}) => showDialog<String>(
  context: context,
  builder: (_) => _NameDialog(title: title, confirm: confirm, initial: initial),
);

class _NameDialog extends StatefulWidget {
  final String title, confirm, initial;
  const _NameDialog({required this.title, required this.confirm, required this.initial});

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _ctl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _ok() {
    final n = cleanPresetName(_ctl.text);
    if (n.isNotEmpty) Navigator.pop(context, n);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 360,
      child: TextField(
        key: const ValueKey('user-preset-name'),
        controller: _ctl,
        autofocus: true,
        maxLength: maxUserPresetName,
        // o que `cleanPresetName` trocaria por espaço não entra: o nome guardado é o digitado
        inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'[\u0000-\u001f\u007f-\u009f\u2028\u2029\u200b-\u200f\u202a-\u202e\ufeff]'))],
        decoration: const InputDecoration(labelText: 'Nome', counterText: ''),
        textInputAction: TextInputAction.done,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _ok(),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
      FilledButton(key: const ValueKey('user-preset-name-ok'), onPressed: cleanPresetName(_ctl.text).isEmpty ? null : _ok, child: Text(widget.confirm)),
    ],
  );
}

Future<bool> confirmPresetDialog(BuildContext context, {required String title, required String text, required String confirm, bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: Text(text),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')),
        FilledButton(
          key: const ValueKey('user-preset-confirm'),
          style: danger ? FilledButton.styleFrom(backgroundColor: Palette.danger) : null,
          onPressed: () => Navigator.pop(d, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return r ?? false;
}

Future<void> showPresetMessage(BuildContext context, String title, String text) => showDialog<void>(
  context: context,
  builder: (d) => AlertDialog(
    title: Text(title),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: SingleChildScrollView(child: Text(text)),
    ),
    actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Ok'))],
  ),
);
