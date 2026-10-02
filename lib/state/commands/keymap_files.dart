import 'dart:async';
import 'dart:convert';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';

import '../keymaps.dart';

/// Выгрузка набора клавиш в файл и загрузка обратно
/// (`docs/spec/keymaps.md`, §4).
///
/// Каталог человек выбирает **деревом**, начиная с домашнего: набирать путь
/// руками в файловом менеджере — насмешка, а своего системного диалога у
/// приложения нет и не будет. Ветви перечисляет панель: её провайдер знает и
/// `ssh://`, и нутро архива.

/// Имя файла, которое предлагается для набора.
String keymapFileName(String name) => safeFileName(name, fallback: 'keymap');

/// Выгрузить набор: спросить каталог и имя, потом записать.
Future<void> exportKeymap(Application app, Strings strings, Keymap keymap) {
  final text = '${const JsonEncoder.withIndent('  ').convert(serialize(keymap))}\n';

  return askFile(
    app,
    strings,
    id: 'keymap.export',
    title: strings.tr('Export keymap'),
    submitLabel: strings.tr('Export'),
    destinationLabel: 'Save to',
    formatError: 'This is not a keymap: the file does not read',
    name: keymapFileName(keymap.name),
    run: (folder, name) async {
      await app.runOperation().run(
        OperationSpec(
          kind: FileOperations.writeText,
          destination: Destination.path(folder),
          options: {FileOperations.name: name, FileOperations.text: text},
        ),
      );
      app.toasts.show(strings.tr('Keymap «{name}» exported', args: {'name': keymap.name}));
    },
  );
}

/// Загрузить набор из файла: прочитать, разобрать, поставить своим и выбрать.
///
/// Читается и прежний файл пресета: у него те же `name` и `keys`.
Future<void> importKeymap(Application app, Strings strings, Keymaps keymaps) {
  // Имя под курсором — только если оно похоже на набор: курсор стоит где
  // угодно, хоть на «..», и подставленное «..» выглядело бы как поломка.
  final cursor = app.activePanel.currentEntry;
  final suggested =
      cursor != null && cursor.kind == EntryKind.file && cursor.name.toLowerCase().endsWith('.json')
          ? cursor.name
          : keymapFileName('keymap');

  return askFile(
    app,
    strings,
    id: 'keymap.import',
    title: strings.tr('Import keymap'),
    submitLabel: strings.tr('Import'),
    destinationLabel: 'Read from',
    formatError: 'This is not a keymap: the file does not read',
    // Набор лежит в json — их в дереве и показываем.
    picks: (entry) => entry.name.toLowerCase().endsWith('.json'),
    name: suggested,
    run: (folder, name) async {
      final keymap = await _read(app, '$folder/$name');
      final given = keymaps.add(keymap);
      app.toasts.show(strings.tr('Keymap «{name}» imported', args: {'name': given}));
    },
  );
}

/// Прочитать набор по адресу.
Future<Keymap> _read(Application app, String path) async {
  final keymap = Keymap()..fromMap(await readJsonFile(app, path));
  if (!keymap.isSane) {
    throw const FormatException();
  }
  return keymap;
}
