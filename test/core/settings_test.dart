import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/core/core_server.dart';
import 'package:flex_commander/core/panel_session.dart';
import 'package:flex_commander/core/settings_hub.dart';
import 'package:flex_commander/link/link.dart';
import 'package:flex_commander/link/loopback_link.dart';
import 'package:flutter_test/flutter_test.dart';

/// Настройки через границу: файл у ядра, экранная половина — разговором.
void main() {
  late InMemoryTreeProvider provider;
  late InMemorySettingsStore store;
  late CoreServer core;
  late Link link;
  late PanelSession left;
  late PanelSession right;

  /// Задержка короткая: ждать секунду в прогоне незачем, а ноль превратил бы
  /// отложенную запись в немедленную и перестал бы проверять саму отсрочку.
  const saveDelay = Duration(milliseconds: 10);

  void assemble(AppSettings settings) {
    final registry = ProviderRegistry(root: provider);
    const editor = TreeTransferEngine();
    left = PanelSession(settings: settings.left, registry: registry, editor: editor);
    right = PanelSession(settings: settings.right, registry: registry, editor: editor);
    final sessions = {PanelId.left: left, PanelId.right: right};
    core = CoreServer(
      left: left,
      right: right,
      registry: registry,
      settings: SettingsHub(
        store: store,
        stored: settings,
        panelSettings: (panel) => sessions[panel]!.settings,
        saveDelay: saveDelay,
      ),
    );
    link = LoopbackLink(core);
  }

  setUp(() {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/docs'),
      FakeEntry.directory('/work'),
      FakeEntry.file('/home/notes.txt', size: 1),
    ])..home = '/home';
    store = InMemorySettingsStore();
    assemble(AppSettings.defaults('/home'));
  });

  tearDown(() async {
    await link.dispose();
    await core.dispose();
  });

  /// Ждёт отложенной записи: она идёт таймером, и фиксированная пауза сделала
  /// бы прогон неустойчивым под нагрузкой.
  Future<AppSettings> waitForSaved() async {
    for (var attempt = 0; attempt < 100; attempt++) {
      if (store.saved case final saved?) {
        return saved;
      }
      await Future<void>.delayed(saveDelay);
    }
    fail('Настройки так и не были записаны');
  }

  group('запуск', () {
    test('ядро само открывает панели там, где их оставили', () async {
      assemble(
        AppSettings(left: PanelSettings.defaults('/home/docs'), right: PanelSettings.defaults('/work'), activePanel: 1),
      );

      await link.call(const StartCore());

      // До всякого экрана: интерфейс подписывается на готовое, а не смотрит,
      // как оно собирается.
      expect(left.path, '/home/docs');
      expect(right.path, '/work');
    });

    test('недоступный путь заменяется домашним каталогом', () async {
      assemble(AppSettings(left: PanelSettings.defaults('/удалённый/каталог')));

      await link.call(const StartCore());

      expect(left.path, '/home');
    });

    test('открытие панелей само по себе записи не требует', () async {
      await link.call(const StartCore());
      await Future<void>.delayed(saveDelay * 5);

      // В файле ровно то, что там и лежало: восстановление — не изменение.
      expect(store.saved, isNull);
    });
  });

  group('рукопожатие', () {
    test('везёт экранную половину настроек', () async {
      assemble(
        AppSettings.defaults('/home')
          ..activePanel = 1
          ..splitRatio = 0.35
          ..window = WindowGeometry(left: 10, top: 20, width: 800, height: 600),
      );

      final ready = await link.call(const Handshake()) as CoreReady;

      // Второго экземпляра файла у экрана нет: своё он получает отсюда.
      expect(ready.ui.activePanel, 1);
      expect(ready.ui.splitRatio, 0.35);
      expect(ready.ui.window?.width, 800);
    });
  });

  group('правки', () {
    test('экранная половина приезжает сообщением и уходит в файл', () async {
      await link.call(const StartCore());

      link.tell(const ChangeSettings(UiSettings(activePanel: 1, splitRatio: 0.3)));

      final saved = await waitForSaved();
      expect(saved.splitRatio, 0.3);
      expect(saved.activePanel, 1);
    });

    test('запись отложена: подряд идущие правки сливаются в одну', () async {
      await link.call(const StartCore());

      link.tell(const ChangeSettings(UiSettings(splitRatio: 0.3)));
      expect(store.saved, isNull, reason: 'сразу писать незачем — правка ещё идёт');

      link.tell(const ChangeSettings(UiSettings(splitRatio: 0.4)));

      expect((await waitForSaved()).splitRatio, 0.4);
    });

    test('та же правка второй раз записи не заводит', () async {
      await link.call(const StartCore());
      link.tell(const ChangeSettings(UiSettings(splitRatio: 0.3)));
      await waitForSaved();
      store.forget();

      link.tell(const ChangeSettings(UiSettings(splitRatio: 0.3)));
      await Future<void>.delayed(saveDelay * 5);

      expect(store.saved, isNull);
    });

    test('смена каталога — тоже правка, и о ней экран не спрашивают', () async {
      await link.call(const StartCore());

      await left.openPath('/home/docs');

      expect((await waitForSaved()).left.path, '/home/docs');
    });

    test('движение курсора записи не заводит', () async {
      await link.call(const StartCore());

      left.setCursorIndex(1);
      await Future<void>.delayed(saveDelay * 5);

      // Ходят по панели постоянно: таймер записи на каждый шаг стрелкой
      // означал бы диск под непрерывной нагрузкой.
      expect(store.saved, isNull);
    });
  });

  group('выключение', () {
    test('просьба записать ждёт самой записи', () async {
      await link.call(const StartCore());
      link.tell(const ChangeSettings(UiSettings(splitRatio: 0.42)));

      await link.call(const SaveSettings());

      // Без ожидания: процесс уходит, и отложенному таймеру сработать было бы
      // уже негде.
      expect(store.saved?.splitRatio, 0.42);
    });

    test('записывать нечего — и не записываем', () async {
      await link.call(const StartCore());

      await link.call(const SaveSettings());

      expect(store.saved, isNull);
    });
  });
}
