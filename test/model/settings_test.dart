import 'dart:convert';
import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:flex_commander/settings/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Читает настройки так же, как это делает `SettingsStore`: дописывает в
/// готовые умолчания то, что нашлось в источнике.
AppSettings read(Object? json, {String fallbackPath = ''}) {
  final settings = AppSettings.defaults(fallbackPath);
  extract(settings, json);
  return settings;
}

/// Пишет объект так же, как `SettingsStore`.
Map<String, dynamic> write(Serializable value) => serialize(value) as Map<String, dynamic>;

void main() {
  group('AppSettings', () {
    test('запись и чтение дают то же самое', () {
      final source = AppSettings(
        left: PanelSettings(
          path: '/Users/koldoon',
          cursor: 'notes.txt',
          columns: ColumnLayout.defaults.resize(FsColumn.size, 120).toggleVisible(FsColumn.attributes),
          sort: const SortSpec(column: FsColumn.modified, direction: SortDirection.descending),
          showHidden: true,
        ),
        right: PanelSettings.defaults('/tmp'),
        activePanel: 1,
        splitRatio: 0.35,
        sizeScanConcurrency: 4,
      );

      final restored = read(jsonDecode(jsonEncode(write(source))));

      expect(restored.left.path, '/Users/koldoon');
      expect(restored.left.cursor, 'notes.txt');
      expect(restored.left.showHidden, isTrue);
      expect(restored.left.sort.column, FsColumn.modified);
      expect(restored.left.sort.direction, SortDirection.descending);
      expect(restored.left.columns.find(FsColumn.size)?.width, 120);
      expect(restored.left.columns.find(FsColumn.attributes)?.visible, isTrue);
      expect(restored.right.path, '/tmp');
      expect(restored.activePanel, 1);
      expect(restored.splitRatio, 0.35);
      expect(restored.sizeScanConcurrency, 4);
    });

    test('пустой объект даёт умолчания', () {
      final settings = read(const <String, Object?>{}, fallbackPath: '/home');

      expect(settings.left.path, '/home');
      expect(settings.right.path, '/home');
      expect(settings.activePanel, 0);
      expect(settings.splitRatio, 0.5);
      expect(settings.sizeScanConcurrency, AppSettings.defaultSizeScanConcurrency);
    });

    test('мусор в значениях заменяется умолчаниями', () {
      final settings = read({
        'activePanel': 'левая',
        'splitRatio': 'половина',
        'sizeScanConcurrency': 'десять',
        'panels': 'нет',
      }, fallbackPath: '/home');

      expect(settings.activePanel, 0);
      expect(settings.splitRatio, 0.5);
      expect(settings.sizeScanConcurrency, AppSettings.defaultSizeScanConcurrency);
      expect(settings.left.path, '/home');
    });

    test('неполный файл остальных настроек не теряет', () {
      // Разбор дописывает в умолчания то, что нашлось, а не заменяет их целиком.
      final settings = read({'splitRatio': 0.3}, fallbackPath: '/home');

      expect(settings.splitRatio, 0.3);
      expect(settings.left.path, '/home');
      expect(settings.right.path, '/home');
      expect(settings.sizeScanConcurrency, AppSettings.defaultSizeScanConcurrency);
      expect(settings.left.columns.columns.length, ColumnLayout.defaults.columns.length);
    });

    test('панель без пути остаётся в каталоге по умолчанию', () {
      // Пустая строка в файле не должна затирать подставленный каталог, иначе
      // панель открылась бы в никуда.
      final settings = read({
        'panels': [
          {'path': '', 'showHidden': true},
        ],
      }, fallbackPath: '/home');

      expect(settings.left.path, '/home');
      expect(settings.left.showHidden, isTrue);
    });

    test('настоящий файл настроек читается без потерь', () {
      // Слепок реального settings.json: у закреплённых колонок ширины нет,
      // у остальных она дробная, окно развёрнуто, панели с разными путями.
      final settings = read({
        'version': 1,
        'activePanel': 1,
        'splitRatio': 0.5073790742024964,
        'sizeScanConcurrency': 10,
        'window': {'left': -1344.0, 'top': 310.0, 'width': 1280.0, 'height': 770.0, 'maximized': true},
        'panels': [
          {
            'path': '/Users/koldoon',
            'showHidden': true,
            'sort': {'column': 'modified', 'direction': 'descending', 'foldersFirst': true},
            'columns': [
              {'id': 'icon', 'visible': true},
              {'id': 'name', 'visible': true},
              {'id': 'ext', 'width': 51.40234375, 'visible': true},
            ],
          },
          {'path': '/Users', 'showHidden': false},
        ],
      }, fallbackPath: '/home');

      expect(settings.activePanel, 1);
      expect(settings.splitRatio, closeTo(0.5073790742024964, 1e-9));
      expect(settings.window?.left, -1344);
      expect(settings.window?.maximized, isTrue);

      expect(settings.left.path, '/Users/koldoon');
      expect(settings.left.showHidden, isTrue);
      expect(settings.left.sort.column, FsColumn.modified);
      expect(settings.left.sort.direction, SortDirection.descending);
      expect(settings.left.columns.find(FsColumn.ext)?.width, closeTo(51.40234375, 1e-9));
      // Колонок в файле три, остальные дописываются из умолчаний.
      expect(settings.left.columns.columns.length, ColumnLayout.defaults.columns.length);

      expect(settings.right.path, '/Users');
      expect(settings.right.showHidden, isFalse);
    });

    test('размер пула ограничен разумными пределами', () {
      // Ноль остановил бы подсчёт вовсе, а сотни обходов завалили бы диск.
      expect(read({'sizeScanConcurrency': 0}).sizeScanConcurrency, AppSettings.minSizeScanConcurrency);
      expect(read({'sizeScanConcurrency': 1000}).sizeScanConcurrency, AppSettings.maxSizeScanConcurrency);
    });

    test('доля разделителя ограничена разумными пределами', () {
      expect(read({'splitRatio': 0.01}).splitRatio, AppSettings.minSplitRatio);
      expect(read({'splitRatio': 42}).splitRatio, AppSettings.maxSplitRatio);
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
      // Ширина колонки с иконкой — из умолчаний, а не из файла: менять её
      // пользователь не может, а оформление со временем меняется.
      expect(layout.find(FsColumn.icon)?.width, ColumnLayout.defaults.find(FsColumn.icon)?.width);
      expect(layout.find(FsColumn.modified)?.width, 90);
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
        FsColumn.path,
        FsColumn.ext,
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

  group('WindowGeometry', () {
    WindowGeometry? readGeometry(Object? json) => extractObject(json, (_) => WindowGeometry());

    test('запись и чтение дают то же самое', () {
      final geometry = WindowGeometry(left: 120, top: 80, width: 900, height: 640);

      expect(readGeometry(write(geometry)), geometry);
    });

    test('мусор заменяется умолчаниями', () {
      final restored = readGeometry({'left': 'слева', 'top': null, 'width': 0, 'height': -5});

      expect(restored?.left, WindowGeometry.defaults.left);
      expect(restored?.width, WindowGeometry.defaults.width);
      expect(restored?.height, WindowGeometry.defaults.height);
    });

    test('слишком маленькое окно подтягивается до минимума', () {
      final restored = readGeometry({'left': 0, 'top': 0, 'width': 100, 'height': 50});

      expect(restored?.width, WindowGeometry.minWidth);
      expect(restored?.height, WindowGeometry.minHeight);
    });

    test('отсутствие раздела даёт null', () {
      expect(readGeometry(null), isNull);
      expect(read(const <String, Object?>{}).window, isNull);
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
      await store.save(
        AppSettings.defaults('/Users/koldoon')
          ..splitRatio = 0.3
          ..activePanel = 1,
      );

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
