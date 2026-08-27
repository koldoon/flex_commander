import 'package:fc_api/fc_api.dart';
import 'package:fc_panels/fc_panels.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Три жеста в одной строке заголовков: клик сортирует, протяжка переставляет
/// колонку, протяжка границы меняет её ширину.
void main() {
  late AppRuntime runtime;

  setUp(() async {
    final provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.file('/home/a.txt', size: 10),
      FakeEntry.file('/home/b.txt', size: 20),
    ])..home = '/home';

    runtime = await testApp(
      provider: provider,
      modules: featureModules(),
      settings: AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home')),
    );
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1312, 891);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await runtime.app.start();
    await tester.pumpAndSettle();
  }

  /// Живой клик мышью: с указателем, наведением и **смещением** между нажатием
  /// и отпусканием.
  ///
  /// Смещение здесь обязательно. У мыши порог перетаскивания — одна точка, и
  /// идеально неподвижное нажатие проверяет то, чего с живой рукой не бывает:
  /// сортировка по заголовку так и была сломана, пока тесты «нажимали» ровно.
  Future<void> click(WidgetTester tester, Finder target, {double jitter = 3}) async {
    final at = tester.getCenter(target);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: at);
    await tester.pump();
    await mouse.down(at);
    await tester.pump(const Duration(milliseconds: 20));
    await mouse.moveTo(at + Offset(jitter, 0));
    await tester.pump(const Duration(milliseconds: 10));
    await mouse.up();
    await tester.pumpAndSettle();
    await mouse.removePointer();
    await tester.pump();
  }

  Finder header(String title) =>
      find.descendant(of: find.byType(FileTableHeader).first, matching: find.text(title)).first;

  List<FsColumn> visibleColumns() => [for (final column in runtime.app.left.columns.visibleColumns) column.id];

  testWidgets('клик по заголовку меняет направление, даже если указатель дрогнул', (tester) async {
    await pumpApp(tester);
    expect(runtime.app.left.sort.column, FsColumn.name);
    expect(runtime.app.left.sort.direction, SortDirection.ascending);

    await click(tester, header('Name'));

    expect(runtime.app.left.sort.direction, SortDirection.descending);

    await click(tester, header('Name'));
    expect(runtime.app.left.sort.direction, SortDirection.ascending);

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('клик по другому заголовку выбирает его колонку', (tester) async {
    await pumpApp(tester);

    await click(tester, header('Size'));

    expect(runtime.app.left.sort.column, FsColumn.size);
    // Новая колонка начинает с прямого порядка, а не наследует прежний.
    expect(runtime.app.left.sort.direction, SortDirection.ascending);

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('заголовок неактивной панели делает её активной и сортирует', (tester) async {
    await pumpApp(tester);
    runtime.app.activate(runtime.app.left);

    final right = find.byType(FileTableHeader).last;
    await click(tester, find.descendant(of: right, matching: find.text('Size')).first);

    expect(runtime.app.activePanel, runtime.app.right);
    expect(runtime.app.right.sort.column, FsColumn.size);

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('протяжка переставляет колонку, а не сортирует', (tester) async {
    await pumpApp(tester);
    final before = visibleColumns();
    final sort = runtime.app.left.sort;

    // Заметное движение — это уже перестановка: «Size» уезжает в начало, левее
    // «Ext». Целиться надо в левую половину чужой колонки: полоса встаёт по
    // ближайшей границе, а правая половина «Ext» — это и есть то место, где
    // «Size» уже стоит.
    final from = tester.getCenter(header('Size'));
    final to = tester.getCenter(header('Name'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: from);
    await tester.pump();
    await mouse.down(from);
    await tester.pump(const Duration(milliseconds: 20));
    // Небольшими шагами, как ведут указатель рукой: первое движение только
    // начинает протяжку, а положение — дело последующих.
    for (var step = 1; step <= 6; step++) {
      await mouse.moveTo(Offset.lerp(from, to, step / 6)!);
      await tester.pump(const Duration(milliseconds: 10));
    }
    await mouse.up();
    await tester.pumpAndSettle();
    await mouse.removePointer();
    await tester.pump();

    expect(visibleColumns(), isNot(before), reason: 'колонка переставлена');
    expect(runtime.app.left.sort.column, sort.column, reason: 'протяжка — не клик');
    expect(runtime.app.left.sort.direction, sort.direction);

    await tester.pump(const Duration(milliseconds: 20));
  });
}
