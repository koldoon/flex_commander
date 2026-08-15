import 'dart:io';

import 'package:flex_commander/app_context.dart';
import 'package:flex_commander/model/app/application.dart';
import 'package:flex_commander/model/app/panel.dart';
import 'package:flex_commander/model/app/panel_selection.dart';
import 'package:flex_commander/model/settings/app_settings.dart';
import 'package:flex_commander/model/settings/settings_store.dart';
import 'package:flex_commander/model/tree/tree_provider.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flex_commander/state/commands/command_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logecom/logecom.dart';
import 'package:path/path.dart' as p;

import 'fake/fake_window_service.dart';
import 'fake/in_memory_tree_provider.dart';

void main() {
  late InMemoryTreeProvider provider;
  late Directory temp;
  late SettingsStore store;
  late FakeWindowService window;

  setUp(() async {
    provider = InMemoryTreeProvider([FakeEntry.directory('/home'), FakeEntry.file('/home/notes.txt', size: 1)]);
    temp = await Directory.systemTemp.createTemp('flex_commander_context');
    store = SettingsStore(filePath: p.join(temp.path, 'settings.json'), fallbackPath: '/home');
    window = FakeWindowService();
  });

  tearDown(() => temp.delete(recursive: true));

  Future<AppContext> init() => AppContext.init(provider: provider, store: store, window: window);

  test('контейнер собирает всё приложение', () async {
    final context = await init();
    final app = context.get<AppController>();
    addTearDown(app.dispose);

    expect(app.left, isNot(same(app.right)));
    expect(app.left.provider, same(provider));
    expect(app.right.provider, same(provider));
    expect(app.store, same(store));
    expect(app.window, same(window));
    expect(app.commands.installed, isNotEmpty);
  });

  test('зависимости создаются один раз', () async {
    final context = await init();

    expect(context.get<TreeProvider>(), same(context.get<TreeProvider>()));
    expect(context.get<CommandRegistry>(), same(context.get<CommandRegistry>()));
    expect(context.get<AppController>(), same(context.get<AppController>()));
    addTearDown(context.get<AppController>().dispose);
  });

  test('зависимости создаются лениво', () {
    // Сборка контекста ничего не инстанцирует: службы по умолчанию — реальные,
    // и служба окна при создании обращается к плагину, которого в тестах нет.
    expect(AppContext.new, returnsNormally);
  });

  test('панели получают свои настройки', () async {
    final context = AppContext(provider: provider, store: store, window: window)..bind<AppSettings>(
      to: (c) => AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/')),
    );

    final app = context.get<AppController>();
    addTearDown(app.dispose);
    await app.start();

    expect(app.left.directory?.pathString, '/home');
    expect(app.right.directory?.pathString, '/');
  });

  test('настройки читаются до сборки приложения', () async {
    await store.save(AppSettings.defaults('/home').copyWith(splitRatio: 0.3, activePanel: 1));

    final context = await init();
    final app = context.get<AppController>();
    addTearDown(app.dispose);

    expect(context.get<AppSettings>().splitRatio, 0.3);
    expect(app.splitRatio, 0.3);
    expect(app.activePanel, app.right);
  });

  test('приложение доступно и как интерфейс, и как реализация', () async {
    final context = await init();
    final app = context.get<AppController>();
    addTearDown(app.dispose);

    // Команды пишутся против Application; контейнер отдаёт тот же экземпляр.
    expect(context.get<Application>(), same(app));
    expect(app, isA<Application>());
    expect(app.left, isA<Panel>());
    expect(app.left.selection, isA<PanelSelection>());
  });

  test('логгер получает категорию по имени потребителя', () {
    final context = AppContext(provider: provider, store: store, window: window);
    expect(context.get<Logger>(), isA<Logger>());
  });

  test('подменённые зависимости доходят до потребителей', () async {
    final context = await init();
    final app = context.get<AppController>();
    addTearDown(app.dispose);

    // Ни одна из служб не создаёт себе зависимости сама: панели работают
    // с тем же провайдером, что связан в контейнере.
    expect(app.left.provider, same(context.get<TreeProvider>()));
  });
}
