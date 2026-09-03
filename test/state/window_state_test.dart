import 'dart:io';

import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_api/fc_api.dart';
import 'package:flex_commander/core/settings_store.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late InMemoryTreeProvider provider;
  late Directory temp;
  late SettingsStore store;
  late FakeWindowService window;
  late AppController app;

  const saveDelay = Duration(milliseconds: 10);
  final geometry = WindowGeometry(left: 120, top: 80, width: 900, height: 640);

  setUp(() async {
    provider = InMemoryTreeProvider([FakeEntry.directory('/home'), FakeEntry.file('/home/notes.txt', size: 1)]);
    temp = await Directory.systemTemp.createTemp('flex_commander_window');
    store = SettingsStore(filePath: p.join(temp.path, 'settings.json'), fallbackPath: '/home');
    window = FakeWindowService();
  });

  tearDown(() async {
    app.dispose();
    await temp.delete(recursive: true);
  });

  AppController build(AppSettings settings) =>
      app = testCore(provider: provider, settings: settings, store: store, window: window, saveDelay: saveDelay);

  Future<AppSettings> waitForSaved() async {
    final file = File(store.filePath);
    for (var attempt = 0; attempt < 100; attempt++) {
      if (await file.exists()) {
        return store.load();
      }
      await Future<void>.delayed(saveDelay);
    }
    fail('Настройки так и не были сохранены');
  }

  group('восстановление окна', () {
    test('сохранённая геометрия применяется при запуске', () async {
      build(AppSettings.defaults('/home')..window = geometry);
      await app.start();

      expect(window.restoreCalled, isTrue);
      expect(window.restored, geometry);
    });

    test('без сохранённой геометрии окно открывается по умолчанию', () async {
      build(AppSettings.defaults('/home'));
      await app.start();

      expect(window.restoreCalled, isTrue);
      expect(window.restored, isNull);
    });
  });

  group('сохранение геометрии', () {
    test('перемещение окна попадает в настройки', () async {
      build(AppSettings.defaults('/home'));
      await app.start();

      window.moveTo(geometry);
      await Future<void>.delayed(Duration.zero);

      expect(app.windowGeometry, geometry);
      expect((await waitForSaved()).window, geometry);
    });

    test('у развёрнутого окна запоминаются размеры до разворота', () async {
      build(AppSettings.defaults('/home')..window = geometry);
      await app.start();

      // Разворот приходит с размерами экрана — запоминать их нельзя, иначе
      // после сворачивания окно останется во весь экран.
      window.moveTo(WindowGeometry(left: 0, top: 0, width: 2560, height: 1440, maximized: true));
      await Future<void>.delayed(Duration.zero);

      expect(app.windowGeometry, geometry.copyWith(maximized: true));
    });

    test('при завершении сохраняется последнее известное состояние', () async {
      build(AppSettings.defaults('/home'));
      await app.start();
      window.moveTo(geometry);
      await Future<void>.delayed(Duration.zero);

      await app.shutdown();

      expect((await store.load()).window, geometry);
    });

    test('при завершении окно не опрашивается', () async {
      build(AppSettings.defaults('/home'));
      await app.start();

      // Опрос плагина в момент завершения приводит к взаимной блокировке
      // с системным обработчиком выхода, поэтому его быть не должно.
      window.geometry = geometry;
      await app.shutdown();

      expect(app.windowGeometry, isNull);
    });

    test('уход приложения на второй план обновляет геометрию', () async {
      build(AppSettings.defaults('/home'));
      await app.start();

      window.geometry = geometry;
      await app.captureWindowGeometry();

      expect(app.windowGeometry, geometry);
    });

    test('геометрия переживает перезапуск', () async {
      build(AppSettings.defaults('/home'));
      await app.start();
      window.moveTo(geometry);
      await app.shutdown();
      app.dispose();

      final restored = await store.load();
      window = FakeWindowService();
      build(restored);
      await app.start();

      expect(window.restored, geometry);
    });
  });
}
