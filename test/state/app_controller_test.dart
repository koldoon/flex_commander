import 'dart:io';

import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_api/fc_api.dart';
import 'package:flex_commander/settings/settings_store.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flex_commander/state/commands/default_commands.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late InMemoryTreeProvider provider;
  late Directory temp;
  late SettingsStore store;

  const saveDelay = Duration(milliseconds: 10);

  setUp(() async {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/docs'),
      FakeEntry.directory('/work'),
      FakeEntry.file('/home/notes.txt', size: 1),
    ]);
    temp = await Directory.systemTemp.createTemp('flex_commander_app');
    store = SettingsStore(filePath: p.join(temp.path, 'settings.json'), fallbackPath: '/home');
  });

  tearDown(() => temp.delete(recursive: true));

  /// Ждёт, пока настройки окажутся на диске: запись отложена таймером и идёт
  /// в реальную файловую систему, поэтому фиксированная пауза делает тест
  /// нестабильным под нагрузкой.
  Future<AppSettings> waitForSaved() async {
    final file = File(store.filePath);
    for (var attempt = 0; attempt < 100; attempt++) {
      if (await file.exists()) {
        return store.load();
      }
      await Future<void>.delayed(saveDelay);
    }
    fail('Настройки так и не были сохранены в ${store.filePath}');
  }

  AppController build(AppSettings settings) {
    return AppController(
      left: testPanel(provider: provider, settings: settings.left),
      right: testPanel(provider: provider, settings: settings.right),
      commands: defaultCommandRegistry(),
      store: store,
      settings: settings,
      saveDelay: saveDelay,
    );
  }

  group('активная панель', () {
    test('слева по умолчанию', () {
      final app = build(AppSettings.defaults('/home'));
      addTearDown(app.dispose);

      expect(app.left.active, isTrue);
      expect(app.right.active, isFalse);
      expect(app.activePanel, app.left);
      expect(app.passivePanel, app.right);
    });

    test('Tab переключает и оставляет активной ровно одну', () {
      final app = build(AppSettings.defaults('/home'));
      addTearDown(app.dispose);

      app.toggleActivePanel();
      expect(app.left.active, isFalse);
      expect(app.right.active, isTrue);
      expect(app.activePanel, app.right);

      app.toggleActivePanel();
      expect(app.left.active, isTrue);
      expect(app.right.active, isFalse);
    });

    test('активация уже активной панели ничего не меняет', () {
      final app = build(AppSettings.defaults('/home'));
      addTearDown(app.dispose);

      var notified = 0;
      app.addListener(() => notified++);
      app.activate(app.left);

      expect(notified, 0);
    });
  });

  group('запуск', () {
    test('открывает сохранённые каталоги и активную панель', () async {
      final app = build(
        AppSettings(left: PanelSettings.defaults('/home/docs'), right: PanelSettings.defaults('/work'), activePanel: 1),
      );
      addTearDown(app.dispose);

      await app.start();

      expect(app.left.directory?.pathString, '/home/docs');
      expect(app.right.directory?.pathString, '/work');
      expect(app.activePanel, app.right);
    });

    test('недоступный путь заменяется каталогом по умолчанию', () async {
      final app = build(
        AppSettings(left: PanelSettings.defaults('/удалённый/каталог'), right: PanelSettings.defaults('/work')),
      );
      addTearDown(app.dispose);

      await app.start();

      expect(app.left.directory?.pathString, provider.homePath);
    });
  });

  group('сохранение настроек', () {
    test('изменение вида пишется на диск с задержкой', () async {
      final app = build(AppSettings.defaults('/home'));
      addTearDown(app.dispose);
      await app.start();

      app.left.setColumnLayout(app.left.columns.resize(FsColumn.size, 111));
      expect(File(store.filePath).existsSync(), isFalse);

      final saved = await waitForSaved();
      expect(saved.left.columns.find(FsColumn.size)?.width, 111);
    });

    test('движение курсора не приводит к записи', () async {
      final app = build(AppSettings.defaults('/home'));
      addTearDown(app.dispose);
      await app.start();

      app.left.moveCursor(1);
      await Future<void>.delayed(saveDelay * 10);

      expect(File(store.filePath).existsSync(), isFalse);
    });

    test('смена каталога сохраняется', () async {
      final app = build(AppSettings.defaults('/home'));
      addTearDown(app.dispose);
      await app.start();

      await app.left.openPath('/home/docs');

      expect((await waitForSaved()).left.path, '/home/docs');
    });

    test('shutdown пишет настройки немедленно', () async {
      final app = build(AppSettings.defaults('/home'));
      await app.start();

      app.setSplitRatio(0.3);
      await app.shutdown();

      final saved = await store.load();
      expect(saved.splitRatio, 0.3);
      expect(saved.activePanel, 0);
      app.dispose();
    });

    test('доля разделителя ограничена', () {
      final app = build(AppSettings.defaults('/home'));
      addTearDown(app.dispose);

      app.setSplitRatio(0.05);
      expect(app.splitRatio, AppSettings.minSplitRatio);

      app.setSplitRatio(5);
      expect(app.splitRatio, AppSettings.maxSplitRatio);
    });

    test('состояние приложения целиком попадает в настройки', () async {
      final app = build(AppSettings.defaults('/home'));
      addTearDown(app.dispose);
      await app.start();

      app.toggleActivePanel();
      app.setSplitRatio(0.35);

      expect(app.settings.activePanel, 1);
      expect(app.settings.splitRatio, 0.35);
      expect(app.settings.left.path, '/home');
    });
  });

  group('сохранение чужого', () {
    test('размер пула обхода каталогов переживает запись', () async {
      // Ядро эту настройку не меняет, но и потерять её при записи не должно:
      // снимок собирается заново, и в него нужно перенести прочитанное.
      final app = build(AppSettings.defaults('/home')..sizeScanConcurrency = 32);
      addTearDown(app.dispose);

      expect(app.settings.sizeScanConcurrency, 32);
    });

    test('разделы модулей переносятся в снимок', () async {
      final settings = AppSettings.defaults('/home');
      settings.modules.fromMap({
        'fc.ssh': {'host': 'example.org'},
      });

      final app = build(settings);
      addTearDown(app.dispose);

      expect(serialize(app.settings.modules), containsPair('fc.ssh', {'host': 'example.org'}));
    });
  });
}
