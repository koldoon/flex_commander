import 'dart:async';
import 'dart:convert';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import '../presets.dart';

/// Выгрузка набора в файл и загрузка обратно
/// (`docs/spec/settings-presets.md`, §7–8).
///
/// Каталог называет человек — полем с подставленным путём активной панели.
/// Своего файлового диалога в приложении нет и не будет: у него для этого есть
/// панели, — но **назвать** каталог, не сходя с места, человек должен уметь.

/// Имя файла, которое предлагается для набора.
String presetFileName(String name) {
  final safe = name.replaceAll(RegExp(r'[/\\:]'), '-').trim();
  return '${safe.isEmpty ? 'preset' : safe}.json';
}

/// Выгрузить набор: спросить каталог и имя, потом записать.
Future<void> exportPreset(Application app, Strings strings, Preset preset) {
  final text = '${const JsonEncoder.withIndent('  ').convert(serialize(preset))}\n';

  return _askFile(
    app,
    strings,
    title: strings.tr('Export set'),
    submitLabel: strings.tr('Export'),
    folder: app.activePanel.currentPath,
    name: presetFileName(preset.name),
    run: (folder, name) async {
      await app.runOperation().run(
        OperationSpec(
          kind: FileOperations.writeText,
          destinationPath: folder,
          options: {FileOperations.name: name, FileOperations.text: text},
        ),
      );
      app.toasts.show(strings.tr('Set «{name}» exported', args: {'name': preset.name}));
    },
  );
}

/// Загрузить набор из файла: прочитать, разобрать, поставить в список.
Future<void> importPreset(Application app, Strings strings, Presets presets) {
  final cursor = app.activePanel.currentEntry;
  final suggested = cursor != null && !cursor.isDirectory ? cursor.name : presetFileName('preset');

  return _askFile(
    app,
    strings,
    title: strings.tr('Import set'),
    submitLabel: strings.tr('Import'),
    folder: app.activePanel.currentPath,
    name: suggested,
    run: (folder, name) async {
      final preset = await _read(app, '$folder/$name');
      final given = presets.add(preset);
      app.toasts.show(strings.tr('Set «{name}» imported', args: {'name': given}));
    },
  );
}

/// Прочитать набор по адресу — тем же способом, каким читается файл после
/// жеста: разбор адреса ведёт ядро, аренду на время чтения берёт оно же.
Future<Preset> _read(Application app, String path) async {
  final content = app.contentAt(FileEntry(name: '', kind: EntryKind.file, path: path, canStream: true));
  final bytes = <int>[];
  await for (final chunk in content.read()) {
    bytes.addAll(chunk);
    // Набор — это настройки, а не том данных: файл в мегабайты означает, что
    // указали не на тот.
    if (bytes.length > _sizeLimit) {
      throw const FsError('', FsErrorKind.notSupported);
    }
  }

  final stored = jsonDecode(utf8.decode(bytes));
  if (stored is! Map<String, dynamic>) {
    throw const FormatException();
  }
  final preset = Preset()..fromMap(stored);
  if (!preset.isSane) {
    throw const FormatException();
  }
  return preset;
}

const int _sizeLimit = 4 * 1024 * 1024;

/// Окно «каталог и имя»: оба поля правятся, оба подставлены.
Future<void> _askFile(
  Application app,
  Strings strings, {
  required String title,
  required String submitLabel,
  required String folder,
  required String name,
  required Future<void> Function(String folder, String name) run,
}) {
  final view = app.view;
  final closed = Completer<void>();
  late final String dialogId;
  void close() {
    view.closeDialog(dialogId);
    if (!closed.isCompleted) {
      closed.complete();
    }
  }

  final state = _FileState(folder: folder, name: name, strings: strings, run: run);
  state.close = close;

  dialogId = view.showDialog(
    DialogSpec(
      title: title,
      takesFocus: true,
      content: _FileForm(state: state, submitLabel: submitLabel),
      onSubmit: state.submit,
      onDismiss: close,
    ),
  );
  return closed.future;
}

/// Что набрано в окне файла и чем кончилась попытка.
class _FileState extends ChangeNotifier {
  _FileState({required this.folder, required this.name, required this.strings, required this.run});

  String folder;
  String name;

  final Strings strings;
  final Future<void> Function(String folder, String name) run;

  String? error;
  bool busy = false;

  late final VoidCallback close;

  Future<void> submit() async {
    if (busy) {
      return;
    }
    error = null;
    busy = true;
    notifyListeners();
    try {
      await run(folder.trim(), name.trim());
      close();
    } on FsError catch (failure) {
      error = failure.message;
    } on FormatException {
      // Испорченный файл — ошибка в окне, а не пустой набор молчанием.
      error = strings.tr('This is not a set: the file does not read');
    } on Object catch (failure) {
      error = '$failure';
    }
    busy = false;
    notifyListeners();
  }
}

class _FileForm extends StatefulWidget {
  const _FileForm({required this.state, required this.submitLabel});

  final _FileState state;
  final String submitLabel;

  @override
  State<_FileForm> createState() => _FileFormState();
}

class _FileFormState extends State<_FileForm> {
  late final TextEditingController _folder = TextEditingController(text: widget.state.folder);
  late final TextEditingController _name = TextEditingController(text: widget.state.name)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.state.name.lastIndexOf('.').clamp(0, widget.state.name.length),
    );

  @override
  void dispose() {
    _folder.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return ListenableBuilder(
      listenable: state,
      builder:
          (context, _) => CommandDialogForm(
            onCancel: state.close,
            onSubmit: state.submit,
            submitLabel: widget.submitLabel,
            error: state.error,
            busy: state.busy,
            children: [
              CommandDialogField(
                label: context.strings.tr('Folder'),
                child: FcTextField(
                  controller: _folder,
                  onChanged: (value) => state.folder = value,
                  onSubmitted: (_) => state.submit(),
                ),
              ),
              CommandDialogField(
                label: context.strings.tr('File name'),
                child: FcTextField(
                  controller: _name,
                  autofocus: true,
                  onChanged: (value) => state.name = value,
                  onSubmitted: (_) => state.submit(),
                ),
              ),
            ],
          ),
    );
  }
}
