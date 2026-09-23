import 'dart:convert';

import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_theme_editor/fc_theme_editor.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// Обмен темами: файл туда и обратно (`docs/spec/theme-editor.md`, §10).
void main() {
  late InMemoryContentProvider provider;
  late AppRuntime runtime;
  late ThemeOverlay overlay;

  setUp(() async {
    provider = InMemoryContentProvider([FakeEntry.directory('/home'), FakeEntry.directory('/home/out')])
      ..home = '/home';
    runtime = await testApp(
      provider: provider,
      modules: featureModules(),
      settings: AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home')),
    );
    await runtime.app.start();
    overlay = runtime.resolve<ThemeOverlay>();
  });

  /// Записать текст работой ядра — той самой, которой пишет выгрузка.
  Future<void> write(String folder, String name, String text) => runtime.app.runOperation().run(
    OperationSpec(
      kind: FileOperations.writeText,
      destination: Destination.path(folder),
      options: {FileOperations.name: name, FileOperations.text: text},
    ),
  );

  String read(String path) => utf8.decode(provider.entryAt(path)!.content);

  test('имя файла предлагается по названию темы', () {
    expect(themeFileName('My dark'), 'My dark.json');
    // Разделитель пути в имени — это уход из выбранного каталога, а не имя.
    expect(themeFileName('Тёмная/своя'), 'Тёмная-своя.json');
    expect(themeFileName(''), 'theme.json');
  });

  test('выгруженная тема читается обратно той же', () async {
    overlay.setColor('cursorBackground', const Color(0xFF2D6CDF));
    overlay.setMetric('rowHeight', 26);

    await write('/home/out', 'theme.json', '${const JsonEncoder.withIndent('  ').convert(overlay.exportable())}\n');
    final back = ThemeEdit.fromJson(jsonDecode(read('/home/out/theme.json')) as Map<String, dynamic>)!;

    expect(back.colors['cursorBackground'], const Color(0xFF2D6CDF));
    expect(back.metrics['rowHeight'], 26.0);
    // Название есть всегда: у правок встроенной темы своего имени нет, а файл
    // без него не сказал бы, что в нём лежит.
    expect(back.title, 'Default');
  });

  test('загруженная тема встаёт своей и не трогает ту, что на экране', () {
    overlay.setColor('cursorBackground', const Color(0xFF2D6CDF));

    final incoming =
        ThemeEdit.fromJson({
          'id': 'default',
          'base': 'default',
          'title': 'Default',
          'colors': {'cursorBackground': '#FFDE1D2E'},
        })!;
    final id = overlay.adopt(incoming);

    // Своей: загруженное никогда не затирает подобранное.
    expect(runtime.app.theme.current.id, id);
    expect(runtime.app.theme.current.title, 'Default 2', reason: 'занятое название разводится приставкой');
    expect(runtime.app.theme.current.colors.cursorBackground, const Color(0xFFDE1D2E));

    runtime.app.theme.use('default');
    expect(runtime.app.theme.current.colors.cursorBackground, const Color(0xFF2D6CDF));
  });

  test('тема с неизвестной базой ложится на базу нынешней', () {
    final incoming =
        ThemeEdit.fromJson({
          'id': 'solarized',
          'base': 'solarized',
          'title': 'Solarized',
          'metrics': {'rowHeight': 26},
        })!;

    overlay.adopt(incoming);

    // Модуль той темы здесь не стоит, а класть накладку на что-то надо.
    expect(runtime.app.theme.current.metrics.rowHeight, 26);
    expect(runtime.app.theme.current.colors.windowBackground, isNotNull);
  });

  test('файл, который не тема, темой не становится', () {
    expect(ThemeEdit.fromJson({'что-то': 'чужое'}), isNull);
    expect(ThemeEdit.fromJson('не карта вовсе'), isNull);
  });
}
