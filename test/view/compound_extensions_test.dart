import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flex_commander/state/shell_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Составные расширения в живом приложении.
///
/// Проверяется не разбор (для него есть отдельный тест), а то, что словарь
/// доехал до тех, кто показывает: колонок и сортировки.
void main() {
  late AppController app;
  late ShellSettings shell;

  setUp(() async {
    final provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.file('/home/archive.tar.gz', size: 300, modified: DateTime(2020, 1, 1)),
      FakeEntry.file('/home/photo.gz', size: 100, modified: DateTime(2020, 1, 1)),
      FakeEntry.file('/home/server.cfg.json', size: 200, modified: DateTime(2020, 1, 1)),
    ]);

    final settings = AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home'));
    shell = settings.modules.scope('fc.shell').section(ShellSettings.new);
    app = (await testApp(provider: provider, modules: featureModules(), settings: settings)).app;
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 621);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: app));
    await app.start();
    await tester.pumpAndSettle();
  }

  /// Перерисовка после правки настроек — тем же путём, что и в жизни: окно
  /// закрылось, панели перерисовались.
  Future<void> repaint(WidgetTester tester) async {
    app.activate(app.right);
    app.activate(app.left);
    await tester.pumpAndSettle();
  }

  testWidgets('в колонке расширения стоит составное, а в имени — основа', (tester) async {
    await pumpApp(tester);

    expect(find.text('archive'), findsWidgets);
    expect(find.text('tar.gz'), findsWidgets);
    // `photo.gz` под словарь не попадает: совпадение только по границе точки.
    expect(find.text('photo'), findsWidgets);
  });

  testWidgets('колонку расширения выключили — имя показывается целиком', (tester) async {
    await pumpApp(tester);

    app.left.setColumnLayout(app.left.columns.toggleVisible(FsColumn.ext));
    await tester.pumpAndSettle();

    expect(find.text('archive.tar.gz'), findsWidgets);
  });

  testWidgets('правка словаря видна со следующей перерисовки', (tester) async {
    await pumpApp(tester);
    expect(find.text('server.cfg'), findsWidgets);

    shell.compoundExtensions = ['cfg.json'];
    await repaint(tester);

    expect(find.text('server'), findsWidgets);
    expect(find.text('cfg.json'), findsWidgets);
  });

  testWidgets('встроенный список можно выключить', (tester) async {
    await pumpApp(tester);

    shell.useBuiltinExtensions = false;
    await repaint(tester);

    expect(find.text('archive.tar'), findsWidgets);
  });

  testWidgets('сортировка по расширению держит составное вместе', (tester) async {
    await pumpApp(tester);

    app.left.sortBy(FsColumn.ext);
    await tester.pumpAndSettle();

    // Порядок по расширению: `gz`, `json`, `tar.gz`. Составное стоит своим
    // расширением, а не сливается с `gz`, — иначе `archive.tar.gz` оказался бы
    // рядом с `photo.gz`, показываясь при этом как `tar.gz`.
    expect(app.left.entries.map((node) => node.name).toList(), ['..', 'photo.gz', 'server.cfg.json', 'archive.tar.gz']);
  });

  test('реестр провайдеров словаря не видит', () {
    // `a.tar.gz` монтируется как `gz`, а `tar` разбирается уже внутри —
    // цепочкой. Скажи реестру «это `tar.gz`» — и он искал бы провайдера,
    // которого нет.
    expect(extensionOf('archive.tar.gz'), 'gz');
  });
}
