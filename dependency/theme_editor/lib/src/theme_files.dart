import 'dart:convert';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';

import 'theme_editor_commands.dart';
import 'theme_overlay.dart';
import 'theme_overrides.dart';

/// Обмен темами — файлом через панели (`docs/spec/theme-editor.md`, §10).
///
/// Тем же, чем возят наборы выбора: каталог выбирают деревом, имя правят
/// строкой, запись ведёт ядро. У приложения уже есть файловый менеджер, и
/// заводить рядом с ним второй выбор файла было бы смешно.

/// Имя файла, предлагаемое по названию темы.
String themeFileName(String title) => safeFileName(title, fallback: 'theme');

/// Выгрузить тему, что на экране: спросить каталог и имя, потом записать.
Future<void> exportTheme(Application app, Strings strings, ThemeOverlay overlay) {
  final text = '${const JsonEncoder.withIndent('  ').convert(overlay.exportable())}\n';
  final title = app.theme.current.title;

  return askFile(
    app,
    strings,
    id: ExportThemeCommand.commandId,
    title: strings.tr('Export theme'),
    submitLabel: strings.tr('Export'),
    destinationLabel: 'Save to',
    formatError: 'This is not a theme: the file does not read',
    name: themeFileName(title),
    run: (folder, name) async {
      await app.runOperation().run(
        OperationSpec(
          kind: FileOperations.writeText,
          destinationPath: folder,
          options: {FileOperations.name: name, FileOperations.text: text},
        ),
      );
      app.toasts.show(strings.tr('Theme «{name}» exported', args: {'name': title}));
    },
  );
}

/// Загрузить тему из файла: прочитать, разобрать, поставить в список.
Future<void> importTheme(Application app, Strings strings, ThemeOverlay overlay) {
  // Имя под курсором — только если оно похоже на тему: курсор стоит где
  // угодно, хоть на «..», и подставленное «..» выглядело бы как поломка.
  final cursor = app.activePanel.currentEntry;
  final suggested =
      cursor != null && cursor.kind == EntryKind.file && cursor.name.toLowerCase().endsWith('.json')
          ? cursor.name
          : themeFileName('theme');

  return askFile(
    app,
    strings,
    id: ImportThemeCommand.commandId,
    title: strings.tr('Import theme'),
    submitLabel: strings.tr('Import'),
    destinationLabel: 'Read from',
    formatError: 'This is not a theme: the file does not read',
    // Тема лежит в json — их в дереве и показываем.
    picks: (entry) => entry.name.toLowerCase().endsWith('.json'),
    name: suggested,
    run: (folder, name) async {
      final stored = await readJsonFile(app, '$folder/$name');
      final incoming = ThemeEdit.fromJson(stored);
      if (incoming == null) {
        // Не тема — отказ словами, а не пустая тема молчанием.
        throw const FormatException();
      }
      final id = overlay.adopt(incoming);
      final given = app.theme.available.firstWhere((theme) => theme.id == id).title;
      app.toasts.show(strings.tr('Theme «{name}» imported', args: {'name': given}));
    },
  );
}
