import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/app.dart';
import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:fc_panels/fc_panels.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InMemoryTreeProvider provider;
  late AppRuntime runtime;
  late AppController app;

  setUp(() async {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/bin'),
      FakeEntry.file('/home/a.txt', size: 300, modified: DateTime(2020, 1, 1)),
      FakeEntry.file('/home/b.txt', size: 100, modified: DateTime(2026, 1, 1)),
      FakeEntry.file('/home/c.txt', size: 200, modified: DateTime(2023, 1, 1)),
    ]);

    final settings = AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home'));
    runtime = await testApp(provider: provider, modules: featureModules(), settings: settings);
    app = runtime.app;
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(802, 621);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: app));
    await app.start();
    await tester.pumpAndSettle();
  }

  /// Заголовок колонки в левой панели.
  Finder headerOf(String title) => find.descendant(
    of: find.byType(FileTableHeader).first,
    matching: find.ancestor(of: find.text(title), matching: find.byType(FileTableHeaderCell)),
  );

  List<String> namesOf(Panel panel) => panel.entries.map((node) => node.name).toList();

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
      expect(app.core!.settings!.left.sort.column, FsColumn.modified);
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

      expect(app.core!.settings!.left.columns.find(FsColumn.size)?.width, app.left.columns.find(FsColumn.size)?.width);
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
    /// Окно выбора вида левой панели: там же, где человек их и меняет.
    Future<void> openViewDialog(WidgetTester tester) async {
      runtime.commands.dispatch(KeyCombination.parse('Alt-F1'));
      await tester.pumpAndSettle();
    }

    testWidgets('окно вида показывает колонки и скрывает выбранную', (tester) async {
      await pumpApp(tester);
      expect(find.text('Ext'), findsWidgets);

      await openViewDialog(tester);

      // Перечислены все колонки, включая скрытые.
      expect(find.descendant(of: find.byType(FcCheckbox), matching: find.text('Attributes')), findsOneWidget);

      await tester.tap(find.descendant(of: find.byType(FcCheckbox), matching: find.text('Ext')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 20));

      expect(app.left.columns.find(FsColumn.ext)?.visible, isFalse);
      expect(app.left.columns.visibleColumns.map((c) => c.id), isNot(contains(FsColumn.ext)));
    });

    testWidgets('иконку и имя не выключить: без них строка нечитаема', (tester) async {
      await pumpApp(tester);
      await openViewDialog(tester);

      // У колонки значка заголовка нет — в списке она названа «Icon», иначе
      // первый флажок стоял бы безымянным.
      final icon = find.ancestor(of: find.text('Icon'), matching: find.byType(FcCheckbox));
      expect(tester.widget<FcCheckbox>(icon).onChanged, isNull);

      final name = find.ancestor(
        of: find.descendant(of: find.byType(TableViewOptions), matching: find.text('Name')),
        matching: find.byType(FcCheckbox),
      );
      expect(tester.widget<FcCheckbox>(name).onChanged, isNull);
      expect(tester.widget<FcCheckbox>(name).value, isTrue);
    });

    testWidgets('колонки идут столбцом под подписью, по левому краю окна', (tester) async {
      await pumpApp(tester);
      await openViewDialog(tester);

      Rect inDialog(String text) =>
          tester.getRect(find.descendant(of: find.byType(TableViewOptions), matching: find.text(text)));
      final title = inDialog('Columns visible');
      final icon = inDialog('Icon');
      final name = inDialog('Name');

      // Подпись над столбцом, флажки под ней — и всё по одной левой границе,
      // той же, по которой отбито содержимое окна (список видов над ними).
      final view = tester.getRect(find.descendant(of: find.byType(FcPickList), matching: find.byType(RichText)).first);
      expect(name.top, greaterThan(icon.top), reason: 'столбиком, а не в строку');
      expect(icon.top, greaterThan(title.top));
      expect(title.left, closeTo(view.left, 0.5));
    });

    testWidgets('колонки правой панели — свои', (tester) async {
      await pumpApp(tester);

      // Окно открыто для левой: правая своей раскладки не теряет.
      await openViewDialog(tester);
      await tester.tap(find.descendant(of: find.byType(FcCheckbox), matching: find.text('Ext')));
      await tester.pumpAndSettle();

      expect(app.left.columns.find(FsColumn.ext)?.visible, isFalse);
      expect(app.right.columns.find(FsColumn.ext)?.visible, isTrue);
    });
  });
}
