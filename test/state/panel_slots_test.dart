import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flex_commander/core/settings_store.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Сторона держит несколько сессий (`docs/spec/panel-slots.md`).
///
/// Видимого изменения от этого нет: пока сессия в слоте одна, приложение
/// ведёт себя как прежде. Здесь проверяется то, что становится **можно**.
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
      FakeEntry.file('/work/report.txt', size: 2),
    ]);
    temp = await Directory.systemTemp.createTemp('flex_commander_slots');
    store = SettingsStore(filePath: p.join(temp.path, 'settings.json'), fallbackPath: '/home');
  });

  tearDown(() => temp.delete(recursive: true));

  Future<AppController> build([AppSettings? settings]) async {
    final app = testCore(
      provider: provider,
      settings: settings ?? AppSettings.defaults('/home'),
      store: store,
      saveDelay: saveDelay,
    );
    addTearDown(app.dispose);
    await app.start();
    return app;
  }

  group('слот', () {
    test('пока сессия одна, сторона выглядит как прежде', () async {
      final app = await build();

      expect(app.panelsAt(ViewportPosition.left), [app.left]);
      expect(app.panelsAt(ViewportPosition.right), [app.right]);
      expect(app.view.panelAt(ViewportPosition.left), same(app.left));
    });

    test('заведённая сессия встаёт по образцу показанной', () async {
      final app = await build();
      await app.left.openPath('/work');

      final second = await app.openPanel(ViewportPosition.left);

      expect(second.currentPath, '/work', reason: 'по образцу — значит там же, где панель');
      expect(app.panelsAt(ViewportPosition.left), [app.left, second]);
      // Заведённая не показывается сама: слот показывает ту, что была.
      expect(app.left, isNot(same(second)));
    });

    test('сессии одного слота живут порознь', () async {
      final app = await build();
      final first = app.left;
      final second = await app.openPanel(ViewportPosition.left);

      await second.openPath('/home/docs');
      second.setCursorIndex(0);
      first.setCursorToName('notes.txt');
      first.toggleCurrentMark();

      expect(first.currentPath, '/home');
      expect(second.currentPath, '/home/docs');
      expect(first.markedPaths.isEmpty, isFalse);
      expect(second.markedPaths.isEmpty, isTrue, reason: 'пометка — своя у каждой сессии');
    });

    test('показать другую — это ничего не перечитать', () async {
      final app = await build();
      final first = app.left;
      final second = await app.openPanel(ViewportPosition.left);
      await second.openPath('/work');

      app.showPanel(second);

      expect(app.left, same(second), reason: 'левая панель — это показанная сессия');
      expect(app.view.panelAt(ViewportPosition.left), same(second));
      // Прежняя жива и стоит там же: её каталог никто не перечитывал.
      expect(first.currentPath, '/home');
      expect(app.panelsAt(ViewportPosition.left), [first, second]);

      app.showPanel(first);
      expect(app.left, same(first));
    });

    test('показанная сессия остаётся активной стороной', () async {
      final app = await build();
      final second = await app.openPanel(ViewportPosition.left);

      app.showPanel(second);

      expect(app.left.active, isTrue, reason: 'активна сторона, а не отдельная сессия');
      expect(app.activePanel, same(second));
      app.toggleActivePanel();
      expect(app.activePanel, same(app.right));
    });

    test('последняя сессия слота не закрывается', () async {
      final app = await build();
      final only = app.left;

      app.closePanel(only);

      expect(app.panelsAt(ViewportPosition.left), [only], reason: 'сторона без панели — состояние, которого нет');
    });

    test('закрытая уходит, а показанной становится соседка', () async {
      final app = await build();
      final first = app.left;
      final second = await app.openPanel(ViewportPosition.left);
      app.showPanel(second);

      app.closePanel(second);

      expect(app.panelsAt(ViewportPosition.left), [first]);
      expect(app.left, same(first));
      expect(app.view.panelAt(ViewportPosition.left), same(first));
    });
  });

  group('настройки', () {
    /// Ждёт записи: она отложена таймером и идёт в настоящий файл.
    Future<AppSettings> waitForSaved() async {
      final file = File(store.filePath);
      for (var attempt = 0; attempt < 100; attempt++) {
        if (await file.exists()) {
          return store.load();
        }
        await Future<void>.delayed(saveDelay);
      }
      fail('Настройки так и не были записаны');
    }

    test('в файл уходят все сессии стороны и та, что показана', () async {
      final app = await build();
      final second = await app.openPanel(ViewportPosition.left);
      await second.openPath('/work');
      app.showPanel(second);

      final saved = await waitForSaved();

      expect(saved.slots[0].currentTab.panels.map((panel) => panel.path), ['/home', '/work']);
      expect(saved.slots[0].currentTab.current, 1, reason: 'показана вторая');
      expect(saved.slots[1].currentTab.panels.length, 1);
      // И привычное короткое имя означает показанную.
      expect(saved.left.path, '/work');
    });

    test('старый файл читается как одна сессия на сторону', () {
      final settings = AppSettings.defaults('/home');
      settings.fromMap({
        'panels': [
          {'path': '/work'},
          {'path': '/home/docs'},
        ],
      });

      expect(settings.slots.length, 2);
      expect(settings.slots[0].currentTab.panels.map((panel) => panel.path), ['/work']);
      expect(settings.left.path, '/work');
      expect(settings.right.path, '/home/docs');
    });

    test('новый файл возвращает обе сессии и показанную', () {
      final settings = AppSettings.defaults('/home');
      settings.fromMap({
        'panels': [
          {
            'panels': [
              {'path': '/home'},
              {'path': '/work'},
            ],
            'current': 1,
          },
          {
            'panels': [
              {'path': '/home/docs'},
            ],
          },
        ],
      });

      expect(settings.slots[0].currentTab.panels.map((panel) => panel.path), ['/home', '/work']);
      expect(settings.left.path, '/work', reason: 'показана вторая');
      expect(settings.right.path, '/home/docs');
    });

    test('вкладки переживают перезапуск вместе с закреплением', () async {
      final first = await build();
      final tab = await first.openTab(ViewportPosition.left);
      await tab.panel.openPath('/work');
      first.setTabPinned(tab, true);
      await waitForSaved();
      await first.save();

      final saved = await store.load();
      expect(saved.slots[0].tabs.length, 2);
      expect(saved.slots[0].tabs[1].panels.first.path, '/work');
      expect(saved.slots[0].tabs[1].pinned, isTrue);
      expect(saved.slots[0].current, 1, reason: 'показана заведённая');

      final restored = await build(saved);
      expect(restored.tabsAt(ViewportPosition.left).length, 2);
      expect(restored.left.currentPath, '/work');
      expect(restored.tabsAt(ViewportPosition.left)[1].pinned, isTrue);
    });

    test('сохранённые сессии восстанавливаются при запуске', () async {
      final first = await build();
      final second = await first.openPanel(ViewportPosition.left);
      await second.openPath('/work');
      first.showPanel(second);
      await waitForSaved();
      await first.save();

      final restored = await build(await store.load());

      expect(restored.panelsAt(ViewportPosition.left).length, 2);
      expect(restored.left.currentPath, '/work', reason: 'показана та же, что и была');
      expect(restored.panelsAt(ViewportPosition.left).first.currentPath, '/home');
    });
  });

  group('ядро', () {
    test('рукопожатие везёт каждую сессию', () async {
      final app = await build();
      await app.openPanel(ViewportPosition.left);

      final ready = await app.link!.call(const Handshake()) as CoreReady;

      expect(ready.states.length, 3);
      expect(ready.listings.length, 3);
      expect(ready.ui.slots[0].panels.length, 2, reason: 'раскладку ядро возвращает такой, какой ему сказали');
    });

    test('закрытая сессия уходит из ядра', () async {
      final app = await build();
      final second = await app.openPanel(ViewportPosition.left);

      app.closePanel(second);
      await Future<void>.delayed(Duration.zero);

      final ready = await app.link!.call(const Handshake()) as CoreReady;
      expect(ready.states.length, 2);
    });
  });
}
