import 'dart:convert';
import 'dart:io';

import 'package:flex_commander/model/panel/column_spec.dart';
import 'package:flex_commander/model/panel/sort_spec.dart';
import 'package:flex_commander/model/settings/app_settings.dart';
import 'package:flex_commander/model/settings/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('AppSettings', () {
    test('запись и чтение дают то же самое', () {
      final source = AppSettings(
        left: PanelSettings(
          path: '/Users/koldoon',
          columns: ColumnLayout.defaults.resize(FsColumn.size, 120).toggleVisible(FsColumn.attributes),
          sort: const SortSpec(column: FsColumn.modified, direction: SortDirection.descending),
          showHidden: true,
        ),
        right: PanelSettings.defaults('/tmp'),
        activePanel: 1,
        splitRatio: 0.35,
        themeMode: AppThemeMode.dark,
      );

      final restored = AppSettings.fromJson(jsonDecode(jsonEncode(source.toJson())));

      expect(restored.left.path, '/Users/koldoon');
      expect(restored.left.showHidden, isTrue);
      expect(restored.left.sort.column, FsColumn.modified);
      expect(restored.left.sort.direction, SortDirection.descending);
      expect(restored.left.columns.find(FsColumn.size)?.width, 120);
      expect(restored.left.columns.find(FsColumn.attributes)?.visible, isTrue);
      expect(restored.right.path, '/tmp');
      expect(restored.activePanel, 1);
      expect(restored.splitRatio, 0.35);
      expect(restored.themeMode, AppThemeMode.dark);
    });

    test('пустой объект даёт умолчания', () {
      final settings = AppSettings.fromJson(const <String, Object?>{}, fallbackPath: '/home');

      expect(settings.left.path, '/home');
      expect(settings.right.path, '/home');
      expect(settings.activePanel, 0);
      expect(settings.splitRatio, 0.5);
      expect(settings.themeMode, AppThemeMode.system);
    });

    test('мусор в значениях заменяется умолчаниями', () {
      final settings = AppSettings.fromJson({
        'activePanel': 'левая',
        'splitRatio': 'половина',
        'themeMode': 'неоновая',
        'panels': 'нет',
      }, fallbackPath: '/home');

      expect(settings.activePanel, 0);
      expect(settings.splitRatio, 0.5);
      expect(settings.themeMode, AppThemeMode.system);
      expect(settings.left.path, '/home');
    });

    test('доля разделителя ограничена разумными пределами', () {
      expect(AppSettings.fromJson({'splitRatio': 0.01}).splitRatio, AppSettings.minSplitRatio);
      expect(AppSettings.fromJson({'splitRatio': 42}).splitRatio, AppSettings.maxSplitRatio);
    });
  });

  group('ColumnLayout.fromJson', () {
    test('порядок колонок берётся из настроек', () {
      final layout = ColumnLayout.fromJson([
        {'id': 'icon', 'width': 24, 'visible': true},
        {'id': 'name', 'width': 0, 'visible': true},
        {'id': 'modified', 'width': 90, 'visible': true},
        {'id': 'ext', 'width': 40, 'visible': false},
      ]);

      expect(layout.columns.take(4).map((c) => c.id), [FsColumn.icon, FsColumn.name, FsColumn.modified, FsColumn.ext]);
      expect(layout.find(FsColumn.modified)?.width, 90);
      expect(layout.find(FsColumn.ext)?.visible, isFalse);
    });

    test('колонки, которых не было в файле, добавляются следом', () {
      final layout = ColumnLayout.fromJson([
        {'id': 'name', 'width': 0, 'visible': true},
      ]);

      expect(layout.columns.first.id, FsColumn.name);
      expect(layout.columns.map((c) => c.id), containsAll(FsColumn.values));
    });

    test('неизвестные колонки игнорируются', () {
      final layout = ColumnLayout.fromJson([
        {'id': 'rating', 'width': 50, 'visible': true},
        {'id': 'name', 'width': 0, 'visible': true},
      ]);

      expect(layout.columns.length, FsColumn.values.length);
      expect(layout.columns.first.id, FsColumn.name);
    });

    test('обязательные колонки нельзя спрятать через файл настроек', () {
      final layout = ColumnLayout.fromJson([
        {'id': 'name', 'width': 0, 'visible': false},
      ]);

      expect(layout.find(FsColumn.name)?.visible, isTrue);
    });

    test('не список даёт раскладку по умолчанию', () {
      expect(ColumnLayout.fromJson('нет').columns.map((c) => c.id), ColumnLayout.defaults.columns.map((c) => c.id));
    });
  });

  group('перестановка колонок', () {
    test('колонка встаёт на указанную позицию', () {
      final layout = ColumnLayout.defaults;
      final moved = layout.moveColumn(layout.indexOf(FsColumn.modified), 2);

      expect(moved.columns.map((c) => c.id).take(5), [
        FsColumn.icon,
        FsColumn.name,
        FsColumn.modified,
        FsColumn.ext,
        FsColumn.size,
      ]);
    });

    test('обязательные колонки не двигаются', () {
      final layout = ColumnLayout.defaults;
      final moved = layout.moveColumn(layout.indexOf(FsColumn.name), 4);

      expect(moved.columns.map((c) => c.id), layout.columns.map((c) => c.id));
    });

    test('другие колонки не встают перед обязательными', () {
      final layout = ColumnLayout.defaults;
      final moved = layout.moveColumn(layout.indexOf(FsColumn.size), 0);

      expect(moved.columns.map((c) => c.id).take(3), [FsColumn.icon, FsColumn.name, FsColumn.size]);
      expect(layout.firstMovableIndex, 2);
    });

    test('порядок колонок переживает сохранение', () {
      final layout = ColumnLayout.defaults;
      final moved = layout.moveColumn(layout.indexOf(FsColumn.modified), 2);
      final restored = ColumnLayout.fromJson(moved.toJson());

      expect(restored.columns.map((c) => c.id), moved.columns.map((c) => c.id));
    });
  });

  group('SettingsStore', () {
    late Directory temp;
    late SettingsStore store;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('flex_commander_settings');
      store = SettingsStore(filePath: p.join(temp.path, 'settings.json'), fallbackPath: '/home');
    });

    tearDown(() => temp.delete(recursive: true));

    test('отсутствующий файл даёт умолчания', () async {
      final settings = await store.load();
      expect(settings.left.path, '/home');
    });

    test('сохранение и загрузка', () async {
      await store.save(AppSettings.defaults('/Users/koldoon').copyWith(splitRatio: 0.3, activePanel: 1));

      final settings = await store.load();
      expect(settings.left.path, '/Users/koldoon');
      expect(settings.splitRatio, 0.3);
      expect(settings.activePanel, 1);
    });

    test('файл человекочитаемый', () async {
      await store.save(AppSettings.defaults('/home'));

      final content = await File(store.filePath).readAsString();
      expect(content, contains('\n  "panels"'));
      expect(content, endsWith('\n'));
    });

    test('битый файл не мешает запуску', () async {
      final errors = <Object>[];
      store = SettingsStore(filePath: p.join(temp.path, 'settings.json'), fallbackPath: '/home', onError: errors.add);
      await File(store.filePath).writeAsString('{ это не json ');

      final settings = await store.load();
      expect(settings.left.path, '/home');
      expect(errors, hasLength(1));
    });

    test('пустой файл не мешает запуску', () async {
      await File(store.filePath).writeAsString('   ');
      expect((await store.load()).left.path, '/home');
    });

    test('после записи не остаётся временных файлов', () async {
      await store.save(AppSettings.defaults('/home'));

      final files = temp.listSync().map((e) => p.basename(e.path)).toList();
      expect(files, ['settings.json']);
    });

    test('недоступный для записи путь не роняет приложение', () async {
      final errors = <Object>[];
      final broken = SettingsStore(
        // Каталог настроек не может быть создан: на пути обычный файл.
        filePath: p.join(temp.path, 'settings.json', 'nested', 'settings.json'),
        onError: errors.add,
      );
      await File(p.join(temp.path, 'settings.json')).writeAsString('x');

      await broken.save(AppSettings.defaults('/home'));
      expect(errors, hasLength(1));
    });

    test('путь по умолчанию лежит в домашнем каталоге', () {
      final store = SettingsStore.forHome('/Users/koldoon');
      expect(store.filePath, '/Users/koldoon/.flex-commander/settings.json');
      expect(store.fallbackPath, '/Users/koldoon');
    });
  });
}
