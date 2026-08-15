import 'dart:io';

import 'package:flex_commander/app.dart';
import 'package:flex_commander/model/panel/column_spec.dart';
import 'package:flex_commander/model/panel/sort_spec.dart';
import 'package:flex_commander/model/settings/app_settings.dart';
import 'package:flex_commander/model/settings/settings_store.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flex_commander/state/panel_controller.dart';
import 'package:flex_commander/view/panel/file_table_header.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../fake/in_memory_tree_provider.dart';

void main() {
  late InMemoryTreeProvider provider;
  late Directory temp;
  late AppController app;

  setUp(() async {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/bin'),
      FakeEntry.file('/home/a.txt', size: 300, modified: DateTime(2020, 1, 1)),
      FakeEntry.file('/home/b.txt', size: 100, modified: DateTime(2026, 1, 1)),
      FakeEntry.file('/home/c.txt', size: 200, modified: DateTime(2023, 1, 1)),
    ]);
    temp = await Directory.systemTemp.createTemp('flex_commander_columns');

    final settings = AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home'));
    app = AppController(
      left: PanelController(provider: provider, settings: settings.left),
      right: PanelController(provider: provider, settings: settings.right),
      store: SettingsStore(filePath: p.join(temp.path, 'settings.json')),
      settings: settings,
      saveDelay: const Duration(milliseconds: 5),
    );
  });

  tearDown(() async {
    app.dispose();
    await temp.delete(recursive: true);
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(802, 621);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: app, navigatorKey: GlobalKey<NavigatorState>()));
    await app.start();
    await tester.pumpAndSettle();
  }

  /// Заголовок колонки в левой панели.
  Finder headerOf(String title) => find.descendant(
    of: find.byType(FileTableHeader).first,
    matching: find.ancestor(of: find.text(title), matching: find.byType(FileTableHeaderCell)),
  );

  List<String> namesOf(PanelController panel) => panel.nodes.map((node) => node.name).toList();

  /// Перетаскивание с учётом порога распознавания: первый сдвиг уходит на то,
  /// чтобы жест был признан перетаскиванием, и до обработчика не доходит.
  Future<void> dragBy(WidgetTester tester, Offset from, double dx) async {
    final gesture = await tester.startGesture(from);
    await gesture.moveBy(Offset(dx.isNegative ? -kDragSlopDefault : kDragSlopDefault, 0));
    await gesture.moveBy(Offset(dx, 0));
    await gesture.up();
    await tester.pumpAndSettle();
  }

  group('сортировка кликом', () {
    testWidgets('клик по заголовку сортирует по колонке', (tester) async {
      await pumpApp(tester);
      expect(app.left.sort.column, FsColumn.name);

      await tester.tap(headerOf('Size'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 20));

      expect(app.left.sort.column, FsColumn.size);
      expect(app.left.sort.direction, SortDirection.ascending);
      // Каталоги всё равно выше файлов, поэтому сравниваем только файлы.
      expect(namesOf(app.left).sublist(2), ['b.txt', 'c.txt', 'a.txt']);
    });

    testWidgets('повторный клик меняет направление', (tester) async {
      await pumpApp(tester);

      await tester.tap(headerOf('Size'));
      await tester.pumpAndSettle();
      await tester.tap(headerOf('Size'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 20));

      expect(app.left.sort.direction, SortDirection.descending);
      expect(namesOf(app.left).sublist(2), ['a.txt', 'c.txt', 'b.txt']);
    });

    testWidgets('клик по заголовку делает панель активной', (tester) async {
      await pumpApp(tester);
      app.toggleActivePanel();
      expect(app.activePanel, app.right);

      await tester.tap(headerOf('Name'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 20));

      expect(app.activePanel, app.left);
    });

    testWidgets('сортировка попадает в сохраняемые настройки', (tester) async {
      await pumpApp(tester);

      await tester.tap(headerOf('Modified'));
      await tester.pumpAndSettle();

      // Саму запись на диск проверяет тест AppController: обращаться к файловой
      // системе внутри widget-теста нельзя — его поддельное асинхронное окружение
      // такого не переживает.
      expect(app.settings.left.sort.column, FsColumn.modified);
    });
  });

  group('ширина колонок', () {
    testWidgets('перетаскивание границы меняет ширину правой колонки', (tester) async {
      await pumpApp(tester);
      final before = app.left.columns.find(FsColumn.size)!.width;

      // Граница колонки размера — её левый край.
      final sizeHeader = tester.getRect(headerOf('Size'));
      await dragBy(tester, Offset(sizeHeader.left, sizeHeader.center.dy), -20);

      expect(app.left.columns.find(FsColumn.size)!.width, before + 20);
    });

    testWidgets('ширина не уходит ниже минимума', (tester) async {
      await pumpApp(tester);

      final sizeHeader = tester.getRect(headerOf('Size'));
      await dragBy(tester, Offset(sizeHeader.left, sizeHeader.center.dy), 500);

      final spec = app.left.columns.find(FsColumn.size)!;
      expect(spec.width, spec.minWidth);
    });

    testWidgets('новая ширина попадает в сохраняемые настройки', (tester) async {
      await pumpApp(tester);

      final sizeHeader = tester.getRect(headerOf('Size'));
      await dragBy(tester, Offset(sizeHeader.left, sizeHeader.center.dy), -10);

      expect(app.settings.left.columns.find(FsColumn.size)?.width, app.left.columns.find(FsColumn.size)?.width);
    });
  });

  group('порядок колонок', () {
    testWidgets('перетаскивание заголовка меняет порядок', (tester) async {
      await pumpApp(tester);
      expect(app.left.columns.visibleColumns.map((c) => c.id), [
        FsColumn.icon,
        FsColumn.name,
        FsColumn.ext,
        FsColumn.size,
        FsColumn.modified,
      ]);

      final modified = tester.getRect(headerOf('Modified'));
      final ext = tester.getRect(headerOf('Ext'));
      await dragBy(tester, modified.center, ext.left - modified.center.dx);

      expect(app.left.columns.visibleColumns.map((c) => c.id), [
        FsColumn.icon,
        FsColumn.name,
        FsColumn.modified,
        FsColumn.ext,
        FsColumn.size,
      ]);
    });

    testWidgets('обязательные колонки не двигаются', (tester) async {
      await pumpApp(tester);

      final name = tester.getRect(headerOf('Name'));
      final size = tester.getRect(headerOf('Size'));
      await dragBy(tester, name.center, size.center.dx - name.center.dx);

      expect(app.left.columns.columns.first.id, FsColumn.icon);
      expect(app.left.columns.columns[1].id, FsColumn.name);
    });
  });

  group('видимость колонок', () {
    testWidgets('правый клик открывает меню, пункт скрывает колонку', (tester) async {
      await pumpApp(tester);
      expect(find.text('Ext'), findsWidgets);

      final gesture = await tester.startGesture(
        tester.getCenter(headerOf('Size')),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      // В меню перечислены все колонки, включая скрытые.
      expect(find.text('Attributes'), findsOneWidget);

      await tester.tap(find.widgetWithText(CheckedPopupMenuItem<Object>, 'Ext'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 20));

      expect(app.left.columns.find(FsColumn.ext)?.visible, isFalse);
      expect(app.left.columns.visibleColumns.map((c) => c.id), isNot(contains(FsColumn.ext)));
    });

    testWidgets('меню возвращает раскладку по умолчанию', (tester) async {
      await pumpApp(tester);
      app.left.setColumnLayout(app.left.columns.resize(FsColumn.size, 200).toggleVisible(FsColumn.ext));
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(
        tester.getCenter(headerOf('Size')),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(PopupMenuItem<Object>, 'Reset columns'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 20));

      expect(app.left.columns.find(FsColumn.size)?.width, ColumnLayout.defaults.find(FsColumn.size)?.width);
      expect(app.left.columns.find(FsColumn.ext)?.visible, isTrue);
    });
  });
}
