import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flex_commander/core/settings_store.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Открытые сессии одним списком (`docs/spec/panel-sessions.md`).
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
    temp = await Directory.systemTemp.createTemp('flex_commander_sessions');
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

  group('список наборов', () {
    test('при запуске их два — по одному на сторону', () async {
      final app = await build();

      expect(app.panels.length, 2);
      expect(app.panelAt(ViewportPosition.left).session, same(app.left));
      expect(app.panelAt(ViewportPosition.right).session, same(app.right));
    });

    test('заведённый встаёт рядом и показывается здесь же', () async {
      final app = await build();
      final was = app.left;
      await app.left.openPath('/work');

      final opened = await app.openPanel(ViewportPosition.left);

      expect(app.panels.length, 3);
      expect(app.panels[1], same(opened), reason: 'рядом с нынешним, а не в конце');
      expect(app.left, same(opened.session));
      expect(opened.session.currentPath, '/work', reason: 'по образцу показанного');
      expect(was.currentPath, '/work', reason: 'прежний жив и стоит там же');
    });

    test('один набор можно показать в обеих панелях', () async {
      final app = await build();
      final both = app.panelAt(ViewportPosition.left);

      app.showPanel(ViewportPosition.right, both);

      expect(app.left, same(app.right), reason: 'сессия одна на две панели');
      expect(app.panels.length, 2, reason: 'а наборов сколько было');
    });

    test('закрытие показанного переводит панель на соседний', () async {
      final app = await build();
      final second = await app.openPanel(ViewportPosition.left);
      await second.session.openPath('/work');

      app.closePanel(second);

      expect(app.panels.length, 2);
      expect(app.left.currentPath, '/home', reason: 'показан соседний');
    });

    test('закрыли последний — на его место встаёт новый', () async {
      final app = await build();
      // Закрывают по порядку, и последним закроется правый: где стоял он, там
      // и встанет новый.
      await app.right.openPath('/work');
      for (final panel in app.panels.toList()) {
        app.closePanel(panel);
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(app.panels.length, 1, reason: 'панель без набора не бывает');
      expect(app.left.currentPath, '/work', reason: 'новый набор — там же, где закрытый');
      expect(app.right, same(app.left), reason: 'обеим сторонам показывать больше нечего');
    });

    test('имя даётся набору, а не месту', () async {
      final app = await build();
      final panel = app.panelAt(ViewportPosition.left);

      app.renamePanel(panel, 'сборка');
      await panel.session.openPath('/work');

      expect(panel.name, 'сборка', reason: 'каталог сменился, имя осталось');
    });
  });

  group('столбцы набора', () {
    test('заводятся и закрываются внутри набора', () async {
      final app = await build();
      final panel = app.panelAt(ViewportPosition.left);

      final column = await app.openSession(panel, at: 0);

      expect(panel.sessions.length, 2);
      expect(panel.sessions.first, same(column));
      expect(app.left, isNot(same(column)), reason: 'показанный столбец не меняется');
      expect(app.panels.length, 2, reason: 'столбец — не отдельный набор');

      app.closeSession(column);
      expect(panel.sessions.length, 1);
    });

    test('последний столбец не закрывается', () async {
      final app = await build();
      final panel = app.panelAt(ViewportPosition.left);

      app.closeSession(panel.session);

      expect(panel.sessions.length, 1);
    });
  });

  group('настройки', () {
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

    test('в файл уходят все наборы, их имена и показанные', () async {
      final app = await build();
      final second = await app.openPanel(ViewportPosition.left);
      await second.session.openPath('/work');
      app.renamePanel(second, 'работа');

      final saved = await waitForSaved();

      expect(saved.panels.length, 3);
      expect(saved.panels[1].sessions.first.path, '/work');
      expect(saved.panels[1].name, 'работа');
      expect(saved.shown.first, 1, reason: 'слева показан заведённый');
      expect(saved.left.path, '/work');
    });

    test('сохранённое возвращается при запуске', () async {
      final first = await build();
      final second = await first.openPanel(ViewportPosition.left);
      await second.session.openPath('/work');
      first.renamePanel(second, 'работа');
      await waitForSaved();
      await first.save();

      final restored = await build(await store.load());

      expect(restored.panels.length, 3);
      expect(restored.left.currentPath, '/work');
      expect(restored.panels[1].name, 'работа');
    });

    test('прежние формы файла читаются наборами по одной сессии', () {
      final byPanels = AppSettings.defaults('/home')..fromMap({
        'panels': [
          {'path': '/work'},
          {'path': '/home/docs'},
        ],
      });
      expect(byPanels.panels.length, 2);
      expect(byPanels.left.path, '/work');
      expect(byPanels.right.path, '/home/docs');

      final bySlots = AppSettings.defaults('/home')..fromMap({
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
      expect(bySlots.panels.length, 2, reason: 'слот со столбцами — один набор');
      expect(bySlots.left.path, '/work', reason: 'показан был второй столбец');

      final byTabs = AppSettings.defaults('/home')..fromMap({
        'panels': [
          {
            'tabs': [
              {
                'panels': [
                  {'path': '/home'},
                ],
              },
              {
                'panels': [
                  {'path': '/work'},
                ],
              },
            ],
            'current': 1,
          },
          {
            'tabs': [
              {
                'panels': [
                  {'path': '/home/docs'},
                ],
              },
            ],
          },
        ],
      });
      expect(byTabs.panels.length, 3, reason: 'вкладки развернулись в наборы');
      expect(byTabs.left.path, '/work', reason: 'показанной была вторая вкладка');
      expect(byTabs.right.path, '/home/docs');
    });
  });
}
