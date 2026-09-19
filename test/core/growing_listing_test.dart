import 'package:fc_api/fc_api.dart';
import 'package:fc_core_api/fc_core_api.dart';
import 'package:fc_search/fc_search.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/core/panel_session.dart';
import 'package:flutter_test/flutter_test.dart';

/// Растущий список перерисовывается не чаще, чем это стоит
/// (`docs/spec/growing-listing.md`).
void main() {
  group('окно перерисовки', () {
    test('короткий список перерисовывается как прежде', () {
      // Круг ничего не стоит — значит и отодвигать нечего: остаётся обычный
      // шаг перерисовки.
      expect(growWindowFor(Duration.zero), Throttle.defaultInterval);
      expect(growWindowFor(const Duration(milliseconds: 5)), Throttle.defaultInterval);
    });

    test('дорогой круг отодвигает следующий вчетверо', () {
      // Ядро отдаёт показу четверть своего времени: круг в 100 мс — окно в 400.
      expect(growWindowFor(const Duration(milliseconds: 100)), const Duration(milliseconds: 400));
      expect(growWindowFor(const Duration(milliseconds: 40)), const Duration(milliseconds: 160));
    });

    test('дальше секунды окно не растёт', () {
      // Список, который обновляется реже раза в секунду, выглядит замершим.
      expect(growWindowFor(const Duration(milliseconds: 900)), maxGrowWindow);
      expect(growWindowFor(const Duration(seconds: 30)), maxGrowWindow);
    });
  });

  group('ограничитель спрашивает окно', () {
    test('новое окно действует со следующего события', () async {
      var window = const Duration(milliseconds: 20);
      var runs = 0;
      final throttle = Throttle(() => runs++, interval: () => window);

      throttle();
      expect(runs, 1, reason: 'первое событие проходит сразу');

      // Окно выросло между событиями — ограничитель обязан спросить его заново,
      // а не помнить то, с которым его завели.
      window = const Duration(milliseconds: 300);
      throttle();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(runs, 1, reason: 'сработал по старому окну');

      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(runs, 2, reason: 'придержанное событие пропало');
      throttle.cancel();
    });
  });

  test('прибавившееся доходит до списка, даже если пришло в середине окна', () async {
    // Ограничитель придерживает лишние круги, но последний обязан дойти:
    // иначе найденное в конце так и не появилось бы на экране.
    final disk = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.file('/home/first.txt', size: 10),
      FakeEntry.file('/home/second.txt', size: 20),
    ])..home = '/home';

    Future<FsNode> nodeAt(String path) async {
      final dir = await disk.resolvePath().run('/home') as DirectoryNode;
      final children = await disk.listChildren(dir);
      return children.firstWhere((node) => node.pathString == path);
    }

    final address = SearchAddress(where: '/home', query: const SearchQuery(mask: '*.txt'));
    final found = SearchProvider(address, title: 'Find *.txt');
    found.add([await nodeAt('/home/first.txt')]);

    final registry = ProviderRegistry(root: disk)..registerAddress(
      SearchAddress.scheme,
      needsConnection: false,
      () => TaskOperation<Uri, TreeProvider>((op, uri) async => found),
    );
    final panel = testPanel(provider: disk, registry: registry, settings: PanelSettings.defaults('/home'));
    addTearDown(panel.dispose);

    await panel.openPath(address.toString());
    await pumpEventQueue();
    expect(panel.entries.map((entry) => entry.name), contains('first.txt'));

    // Пачка пришла сразу после предыдущей перерисовки — то есть в середине
    // окна, и немедленного круга ей не достанется.
    found.add([await nodeAt('/home/second.txt')]);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await pumpEventQueue();

    await Future<void>.delayed(Throttle.defaultInterval * 3);
    await pumpEventQueue();
    expect(
      panel.entries.map((entry) => entry.name),
      contains('second.txt'),
      reason: 'прибавившееся не дошло до списка',
    );
  });
}
