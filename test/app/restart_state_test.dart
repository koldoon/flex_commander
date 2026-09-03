import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/bootstrap/bootstrap.dart';
import 'package:flex_commander/core/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Состояние панелей переживает перезапуск — целиком.
///
/// Настоящая сборка и настоящий файл: то, что видит человек, закрывая и
/// открывая приложение. Проверок такого рода не хватало — панельные проверки
/// шли на `testCore`, где настройки у сторон общие, и подмена одной половины
/// другой оставалась незаметной.
void main() {
  late Directory temp;
  late SettingsStore store;
  late InMemoryTreeProvider provider;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('fc_restart');
    store = SettingsStore(filePath: p.join(temp.path, 'settings.json'), fallbackPath: '/home');
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/docs'),
      FakeEntry.directory('/work'),
      FakeEntry.file('/home/notes.txt', size: 1),
      FakeEntry.file('/home/report.txt', size: 2),
    ])..home = '/home';
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  Future<AppRuntime> launch() async {
    final runtime = await initModules(
      backendModules(),
      frontendModules(),
      overrides: AppOverrides(provider: provider, store: store, window: FakeWindowService()),
    );
    await runtime.app.start();
    return runtime;
  }

  test('каталоги, курсор, активная панель и разделитель переживают перезапуск', () async {
    final first = await launch();
    await first.app.left.openPath('/home/docs');
    await first.app.right.openPath('/work');
    first.app.left.setCursorToName('..');
    first.app.activate(first.app.right);
    first.app.setSplitRatio(0.35);
    await first.dispose();

    final saved = await store.load();
    expect(saved.left.path, '/home/docs', reason: 'левая панель записана');
    expect(saved.right.path, '/work', reason: 'правая панель записана');
    expect(saved.activePanel, 1, reason: 'активная панель записана');
    expect(saved.splitRatio, 0.35, reason: 'разделитель записан');

    final second = await launch();
    expect(second.app.left.path, '/home/docs');
    expect(second.app.right.path, '/work');
    expect(second.app.activePanel, second.app.right);
    expect(second.app.splitRatio, 0.35);
    await second.dispose();
  });

  test('курсор возвращается туда, где его оставили', () async {
    final first = await launch();
    first.app.left.setCursorToName('report.txt');
    await first.dispose();

    expect((await store.load()).left.cursor, 'report.txt');

    final second = await launch();
    expect(second.app.left.currentEntry?.name, 'report.txt');
    await second.dispose();
  });

  test('вид панели — колонки, сортировка, скрытые — переживает перезапуск', () async {
    final first = await launch();
    await first.app.left.setShowHidden(true);
    await first.app.left.sortBy(FsColumn.size);
    await first.dispose();

    final saved = await store.load();
    expect(saved.left.showHidden, isTrue);
    expect(saved.left.sort.column, FsColumn.size);

    final second = await launch();
    expect(second.app.left.showHidden, isTrue);
    expect(second.app.left.sort.column, FsColumn.size);
    await second.dispose();
  });
}
