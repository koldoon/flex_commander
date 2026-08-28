import 'package:fc_api/fc_api.dart';
import 'package:fc_panels/fc_panels.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/modules/dnd/system_drag_and_drop.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Файлы, брошенные в панель из системы.
///
/// Нативной части здесь нет — она в раннере, — но весь путь после неё
/// настоящий: событие приходит тем же каналом и теми же значениями, что шлёт
/// `MainFlutterWindow`, и дальше работают те же приёмник, панель и команда
/// копирования.
late AppRuntime runtime;
late InMemoryTreeProvider provider;

Application get app => runtime.app;

void main() {
  setUp(() async {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/docs'),
      FakeEntry.file('/home/note.txt', size: 4),
      FakeEntry.directory('/outside'),
      FakeEntry.file('/outside/dropped.txt', size: 7),
    ])..home = '/home';
    runtime = await testApp(provider: provider, modules: featureModules());
    await runtime.app.start();
  });

  /// То же, что шлёт раннер: имя события, точка в логических координатах и
  /// пути.
  Future<void> sendDrop(WidgetTester tester, String event, {Offset? at, List<String> paths = const []}) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      SystemDropService.channelName,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall(event, at == null ? null : {'x': at.dx, 'y': at.dy, 'paths': paths}),
      ),
      (_) {},
    );
    await tester.pumpAndSettle();
  }

  /// Точка в середине строки с таким именем — в левой панели.
  Offset rowCenter(WidgetTester tester, String name) {
    final table = tester.getRect(find.byType(FileTable).first);
    final metrics = FcTheme.of(tester.element(find.byType(FileTable).first)).metrics;
    final index = runtime.app.left.nodes.indexWhere((node) => node.name == name);
    expect(index, isNonNegative, reason: 'в панели нет строки «$name»');
    return Offset(
      table.left + table.width / 2,
      table.top + metrics.headerRowHeight + index * metrics.rowHeight + metrics.rowHeight / 2,
    );
  }

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(802, 621);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();
  }

  testWidgets('брошенное на строку-каталог копируется в неё', (tester) async {
    await pumpApp(tester);

    final target = rowCenter(tester, 'docs');
    await sendDrop(tester, 'dragEntered', at: target, paths: const ['/outside/dropped.txt']);
    await sendDrop(tester, 'drop', at: target, paths: const ['/outside/dropped.txt']);
    await tester.pumpAndSettle();

    expect(provider.entryAt('/home/docs/dropped.txt'), isNotNull, reason: 'файл должен лечь в каталог под курсором');
    // Копия, а не перенос: из Finder объекты не исчезают.
    expect(provider.entryAt('/outside/dropped.txt'), isNotNull);
  });

  testWidgets('брошенное мимо строк копируется в каталог панели', (tester) async {
    await pumpApp(tester);

    final table = tester.getRect(find.byType(FileTable).first);
    final empty = Offset(table.left + table.width / 2, table.bottom - 4);
    await sendDrop(tester, 'drop', at: empty, paths: const ['/outside/dropped.txt']);
    await tester.pumpAndSettle();

    expect(provider.entryAt('/home/dropped.txt'), isNotNull);
  });

  testWidgets('бросок в панель делает её активной', (tester) async {
    await pumpApp(tester);

    app.activate(app.right);
    final table = tester.getRect(find.byType(FileTable).first);
    await sendDrop(
      tester,
      'drop',
      at: Offset(table.left + table.width / 2, table.bottom - 4),
      paths: const ['/outside/dropped.txt'],
    );
    await tester.pumpAndSettle();

    expect(app.left.active, isTrue, reason: 'работа идёт в ту панель, в которую бросили — её и видно активной');
  });

  testWidgets('без модуля перетаскивания панели работают как раньше', (tester) async {
    final plain = await testApp(
      provider: InMemoryTreeProvider([FakeEntry.directory('/home'), FakeEntry.file('/home/note.txt', size: 4)])
        ..home = '/home',
      modules: [
        for (final module in featureModules())
          if (module.id != 'fc.dnd') module,
      ],
    );
    await plain.app.start();

    await tester.pumpWidget(FlexCommanderApp(controller: plain.app));
    await tester.pumpAndSettle();

    expect(plain.app.dragAndDrop, isNull);
    expect(find.byType(FileTable), findsWidgets);
  });
}
