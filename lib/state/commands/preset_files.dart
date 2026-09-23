import 'dart:async';
import 'dart:convert';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';

import '../presets.dart';

/// Выгрузка набора в файл и загрузка обратно
/// (`docs/spec/settings-presets.md`, §7–8).
///
/// Каталог человек выбирает **деревом**, начиная с домашнего: набирать путь
/// руками в файловом менеджере — насмешка, а своего системного диалога у
/// приложения нет и не будет. Ветви перечисляет панель: её провайдер знает и
/// `ssh://`, и нутро архива.

/// Имя файла, которое предлагается для набора.
String presetFileName(String name) => safeFileName(name, fallback: 'preset');

/// Выгрузить набор: спросить каталог и имя, потом записать.
Future<void> exportPreset(Application app, Strings strings, Preset preset) {
  final text = '${const JsonEncoder.withIndent('  ').convert(serialize(preset))}\n';

  return askFile(
    app,
    strings,
    id: 'preset.export',
    title: strings.tr('Export set'),
    submitLabel: strings.tr('Export'),
    destinationLabel: 'Save to',
    formatError: 'This is not a set: the file does not read',
    name: presetFileName(preset.name),
    run: (folder, name) async {
      await app.runOperation().run(
        OperationSpec(
          kind: FileOperations.writeText,
          destination: Destination.path(folder),
          options: {FileOperations.name: name, FileOperations.text: text},
        ),
      );
      app.toasts.show(strings.tr('Set «{name}» exported', args: {'name': preset.name}));
    },
  );
}

/// Загрузить набор из файла: прочитать, разобрать, поставить в список.
Future<void> importPreset(Application app, Strings strings, Presets presets) {
  // Имя под курсором — только если оно похоже на набор: курсор стоит где
  // угодно, хоть на «..», и подставленное «..» выглядело бы как поломка.
  final cursor = app.activePanel.currentEntry;
  final suggested =
      cursor != null && cursor.kind == EntryKind.file && cursor.name.toLowerCase().endsWith('.json')
          ? cursor.name
          : presetFileName('preset');

  return askFile(
    app,
    strings,
    id: 'preset.import',
    title: strings.tr('Import set'),
    submitLabel: strings.tr('Import'),
    destinationLabel: 'Read from',
    formatError: 'This is not a set: the file does not read',
    // Набор лежит в json — их в дереве и показываем: искать его среди картинок
    // и архивов человеку незачем.
    picks: (entry) => entry.name.toLowerCase().endsWith('.json'),
    name: suggested,
    run: (folder, name) async {
      final preset = await _read(app, '$folder/$name');
      final given = presets.add(preset);
      app.toasts.show(strings.tr('Set «{name}» imported', args: {'name': given}));
    },
  );
}

/// Прочитать набор по адресу.
Future<Preset> _read(Application app, String path) async {
  final preset = Preset()..fromMap(await readJsonFile(app, path));
  if (!preset.isSane) {
    throw const FormatException();
  }
  return preset;
}
