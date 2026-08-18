import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/bootstrap/bootstrap.dart';
import 'package:flex_commander/modules/app_shell.dart';
import 'package:flex_commander/modules/legacy_commands.dart';
import 'package:flex_commander/modules/zip/zip_module.dart';
import 'package:flex_commander/settings/settings_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Привязки клавиш собираются из модулей, и порядок модулей задаёт приоритет.
///
/// Проверяется собранное приложение целиком: пока набор команд лежал в одном
/// списке, за этим следил сам список, — теперь следить нужно за сборкой.
void main() {
  late Directory temp;
  late AppRuntime runtime;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    temp = await Directory.systemTemp.createTemp('flex_commander_bindings');

    final provider = InMemoryTreeProvider([FakeEntry.directory('/home'), FakeEntry.file('/home/notes.txt', size: 10)]);

    runtime = await initModules(
      [const AppShell(), const LegacyCommands(), const ZipArchiver()],
      overrides: AppOverrides(
        provider: provider,
        store: SettingsStore(filePath: p.join(temp.path, 'settings.json'), fallbackPath: '/home'),
        window: FakeWindowService(),
      ),
    );
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await runtime.dispose();
    await temp.delete(recursive: true);
  });

  test('каждая привязка указывает на установленную команду', () {
    final ids = runtime.commands.installed.map((command) => command.id).toSet();

    for (final binding in runtime.commands.bindings) {
      expect(ids, contains(binding.commandId), reason: 'привязка $binding указывает в пустоту');
    }
  });

  test('Esc сперва отменяет операцию, а уже потом снимает пометку', () {
    final forEsc = runtime.commands.bindings.where((binding) => '${binding.keys}' == 'Esc').toList();

    // Порядок задаёт приоритет: пока панель занята, Esc достаётся отмене.
    expect(forEsc.map((binding) => binding.commandId), ['panel.cancel', 'panel.selection.clear']);
  });

  test('переход по набранному символу не перехватывает обычные клавиши', () {
    final bindings = runtime.commands.bindings;
    final anyCharacter = bindings.indexWhere((binding) => binding.keys == KeyCombination.anyCharacter);
    expect(anyCharacter, isNot(-1));

    // Привязка к конкретному символу должна стоять раньше «любого символа»,
    // иначе набор имени перехватил бы её. Клавиши без символа (F5, Tab)
    // могут идти и после: под «любой символ» они не подходят.
    final laterCharacters = bindings.sublist(anyCharacter + 1).where((binding) => binding.keys.isCharacter);
    expect(laterCharacters, isEmpty, reason: 'эти привязки уже не сработают: $laterCharacters');
  });

  test('модуль архива добавил свою схему, а не команду', () {
    // Zip виден приложению только как источник: ни одной команды он не ставит.
    expect(runtime.commands.installed.map((command) => command.id), isNot(contains('zip')));
    expect(runtime.app.left.provider, isNotNull);
  });
}
