import 'dart:convert';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'editor_screen.dart';
import 'editor_settings.dart';
import 'text_file.dart';

/// Открыть файл под курсором на правку.
///
/// Идентификатор — тот же, что у заглушки оболочки (`file.edit`): реестр держит
/// прототипы по идентификатору, и модуль занимает её место вместе с `F4`.
class EditFileCommand extends AppCommand {
  EditFileCommand({required this.settings, required this.onSettingsChanged});

  static const String commandId = 'file.edit';

  final EditorSettings settings;
  final void Function() onSettingsChanged;

  @override
  String get id => commandId;

  @override
  String get label => 'Edit';

  @override
  String get description => 'Open the file under the cursor for editing';

  @override
  bool isExecutable(CommandContext context) {
    final node = context.node;
    // Править можно то, что умеют и отдать, и принять: у результатов поиска
    // байтов нет вовсе, а архив, открытый через временную копию, принять их
    // не может — изменения уехали бы вместе с копией.
    return node != null &&
        node is! DirectoryNode &&
        node is! ParentDirNode &&
        node.provider is FileContentProvider &&
        node.provider is FileContentReceiver;
  }

  @override
  Future<void> execute() async {
    final node = context.node;
    if (node == null) {
      return;
    }

    final source = node.provider;
    if (source is! FileContentProvider || node.provider is! FileContentReceiver) {
      throw FsError(node.pathString, FsErrorKind.notSupported);
    }

    if (node.size > settings.maxFileSize) {
      context.app.toasts.show(
        'File is too large: ${formatBytesLong(node.size)}, limit is ${formatSize(settings.maxFileSize)}',
      );
      return;
    }

    final TextFile file;
    try {
      file = await TextFile.read(node, source as FileContentProvider);
    } on FsError catch (error) {
      if (error.kind == FsErrorKind.notSupported) {
        // Не текст в UTF-8: правка и сохранение записали бы знаки замены
        // вместо исходных байтов, то есть испортили бы файл молча.
        context.app.toasts.show('Not a UTF-8 text file: ${node.name}');
        return;
      }
      rethrow;
    }

    context.app.screens.open(
      EditorScreen(
        node: node,
        file: file,
        wordWrap: settings.wordWrap,
        onWrapChanged: (value) {
          settings.wordWrap = value;
          onSettingsChanged();
        },
      ),
    );
  }
}

/// Записать правки в файл.
class SaveFileCommand extends AppCommand {
  static const String commandId = 'editor.save';

  Application? _app;

  @override
  bool init(Application app) {
    _app = app;
    return true;
  }

  @override
  String get id => commandId;

  @override
  String get label => 'Save';

  @override
  String get description => 'Write the changes back to the file';

  static EditorScreen? _editorOf(Application? app) {
    final screen = app?.screens.active;
    return screen is EditorScreen ? screen : null;
  }

  /// Сохранять нечего, пока ничего не меняли: кнопка приглушена, а не делает
  /// вид, что сработала.
  @override
  bool isExecutable(CommandContext context) => _editorOf(context.app)?.modified ?? false;

  @override
  Future<void> execute() async {
    final screen = _editorOf(context.app) ?? _editorOf(_app);
    if (screen == null || !screen.modified) {
      return;
    }

    await saveEditor(screen);
    context.app.toasts.show('Saved ${screen.node.name}');
  }
}

/// Записывает содержимое экрана в файл.
///
/// Через временный файл и переименование там, где источник — настоящая
/// файловая система: `openWrite` обрезает файл сразу, и обрыв на середине
/// оставил бы половину вместо целого. Там, где переименования нет (архив
/// пересобирается целиком, сервер пишет потоком), запись идёт напрямую — там
/// целостность обеспечивает сам источник.
Future<void> saveEditor(EditorScreen screen) async {
  final node = screen.node;
  final parent = node.parentDirectory;
  final provider = node.provider;

  if (parent == null || provider is! FileContentReceiver) {
    throw FsError(node.pathString, FsErrorKind.notSupported);
  }

  final bytes = utf8.encode(screen.textToSave);
  final atomic = provider.capabilities.realFileSystem && provider is NodeEditor;

  if (!atomic) {
    await _write(provider as FileContentReceiver, parent, node.name, bytes);
    screen.markSaved();
    return;
  }

  // Имя со скрывающей точкой: временный файл не должен мозолить глаза в
  // панели, если сохранение всё же оборвётся.
  final temporary = '.${node.name}.fc-save';
  final editor = provider as NodeEditor;

  await _write(provider as FileContentReceiver, parent, temporary, bytes);
  try {
    final written = await editor.lookup(parent, temporary);
    if (written == null) {
      throw FsError(node.pathString, FsErrorKind.io);
    }
    if (!await editor.renameEntry(written, parent, node.name)) {
      throw FsError(node.pathString, FsErrorKind.io);
    }
  } on Object {
    // Недописанное под своим именем выглядело бы как целый файл.
    final leftover = await editor.lookup(parent, temporary);
    if (leftover != null) {
      await editor.deleteEntry(leftover);
    }
    rethrow;
  }

  screen.markSaved();
}

Future<void> _write(FileContentReceiver receiver, DirectoryNode parent, String name, List<int> bytes) async {
  final sink = await receiver.openWrite(parent, name, length: bytes.length);
  await sink.addStream(Stream<List<int>>.value(bytes));
  await sink.close();
}

/// Переключить перенос строк.
///
/// Не на `F2`, как в просмотрщике: там `F2` свободна, а здесь за ней
/// сохранение — то, ради чего редактор и открывают.
class ToggleEditorWrapCommand extends AppCommand {
  static const String commandId = 'editor.wrap';

  Application? _app;

  @override
  bool init(Application app) {
    _app = app;
    return true;
  }

  @override
  String get id => commandId;

  @override
  String get label => _editorOf(_app)?.wordWrap == true ? 'Unwrap' : 'Wrap';

  @override
  String get description => 'Wrap long lines in the editor';

  static EditorScreen? _editorOf(Application? app) {
    final screen = app?.screens.active;
    return screen is EditorScreen ? screen : null;
  }

  @override
  bool isExecutable(CommandContext context) => _editorOf(context.app) != null;

  @override
  Future<void> execute() async => _editorOf(context.app)?.toggleWordWrap();
}

/// Закрыть редактор; при несохранённом — спросить.
class CloseEditorCommand extends AppCommand {
  static const String commandId = 'editor.close';

  @override
  String get id => commandId;

  @override
  String get label => 'Quit';

  @override
  String get description => 'Close the editor';

  EditorScreen? get _screen {
    final screen = context.app.screens.active;
    return screen is EditorScreen ? screen : null;
  }

  @override
  bool isExecutable(CommandContext context) => context.app.screens.active?.id == EditorScreen.screenId;

  /// Вопрос задаётся только тогда, когда есть что терять.
  @override
  bool get hasDialog => _screen?.modified ?? false;

  @override
  String get dialogTitle => 'Unsaved changes';

  @override
  Widget? getDialog(BuildContext context) {
    final screen = _screen;
    if (screen == null) {
      return null;
    }

    return ListenableBuilder(
      listenable: this,
      builder:
          (context, _) => CommandDialogConfirm(
            message: '${screen.node.name} has unsaved changes. Close and lose them?',
            confirmLabel: 'Discard',
            error: error,
            onCancel: dismiss,
            onConfirm: submit,
          ),
    );
  }

  @override
  Future<void> execute() async => context.app.screens.close(EditorScreen.screenId);
}
