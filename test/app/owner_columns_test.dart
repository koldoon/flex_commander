import 'package:fc_api/fc_api.dart';
import 'package:fc_panels/fc_panels.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Владелец и группа колонками (`docs/spec/owner-columns.md`).
void main() {
  late AppController app;

  /// Записи с разной осведомлённостью источника: имя, только число, ничего.
  InMemoryTreeProvider provider() => InMemoryTreeProvider([
    FakeEntry.directory('/home'),
    FakeEntry.file(
      '/home/mine.txt',
      size: 10,
      attributes: const FileAttributes(
        mode: 0x81A4,
        modeString: '-rw-r--r--',
        uid: 501,
        gid: 20,
        owner: 'koldoon',
        group: 'staff',
      ),
    ),
    FakeEntry.file(
      '/home/server.txt',
      size: 20,
      attributes: const FileAttributes(mode: 0x81A4, modeString: '-rw-r--r--', uid: 0, gid: 0),
    ),
    FakeEntry.file('/home/archived.txt', size: 30, attributes: const FileAttributes.unknown()),
  ]);

  setUp(() async {
    app =
        (await testApp(
          provider: provider(),
          modules: featureModules(),
          settings: AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home')),
        )).app;
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: app));
    await app.start();
    await tester.pumpAndSettle();
  }

  /// Текст ячейки колонки — тем же способом, каким его берёт таблица.
  String cellOf(String name, String column) {
    final entry = app.left.entries.firstWhere((row) => row.name == name);
    return app.columns.textOf(column)!(ColumnCell(entry: entry)) ?? '';
  }

  testWidgets('колонки объявлены, скрыты и сортируются', (tester) async {
    await pumpApp(tester);

    for (final id in [FsColumns.owner, FsColumns.group]) {
      final spec = app.left.columns.find(id);
      expect(spec, isNotNull, reason: 'колонка $id объявлена');
      expect(spec!.visible, isFalse, reason: 'в своём каталоге владелец у всех один');
      expect(spec.sortable, isTrue);
    }
  });

  testWidgets('показывается имя, число или ничего — по тому, что известно', (tester) async {
    await pumpApp(tester);

    expect(cellOf('mine.txt', FsColumns.owner), 'koldoon');
    expect(cellOf('mine.txt', FsColumns.group), 'staff');

    // Сервер назвал только числа — показываем их: число честнее пустоты.
    expect(cellOf('server.txt', FsColumns.owner), '0');

    // Архив о хозяине не знает вовсе; выдуманного здесь быть не должно.
    expect(cellOf('archived.txt', FsColumns.owner), '');
    expect(cellOf('archived.txt', FsColumns.group), '');
  });

  testWidgets('сортировка идёт по тому, что показано', (tester) async {
    await pumpApp(tester);

    await app.left.sortBy(FsColumns.owner);
    await tester.pumpAndSettle();

    final owners = [for (final row in app.left.entries.skip(1)) row.attributes.ownerText];
    final sorted = [...owners]..sort();
    expect(owners, sorted, reason: 'список читается по именам — и раскладывается по ним же');
  });
}
