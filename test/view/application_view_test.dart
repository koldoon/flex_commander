import 'dart:io';

import 'package:flex_commander/app.dart';
import 'package:flex_commander/model/async/async_operation.dart';
import 'package:flex_commander/model/settings/app_settings.dart';
import 'package:flex_commander/model/settings/settings_store.dart';
import 'package:flex_commander/model/tree/fs_node.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flex_commander/state/panel_controller.dart';
import 'package:flex_commander/view/function_bar/function_bar.dart';
import 'package:flex_commander/view/panel/file_table_row.dart';
import 'package:flex_commander/view/panel/file_type_icon.dart';
import 'package:flex_commander/view/panel/panel_path_header.dart';
import 'package:flex_commander/view/panel/panel_status_bar.dart';
import 'package:flex_commander/view/panel/panel_view.dart';
import 'package:flex_commander/view/theme/fc_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../fake/in_memory_tree_provider.dart';

/// Провайдер, у которого подсчёт размера не заканчивается мгновенно.
///
/// В памяти обход занимает доли микросекунды, и надпись «(Scanning…)» не
/// успевает попасть ни в один кадр — проверить её было бы нечем.
class _SlowSizeProvider extends InMemoryTreeProvider {
  _SlowSizeProvider(super.entries);

  @override
  AsyncOperation<int> calculateSize(List<FsNode> nodes) {
    return TaskOperation<int>((op) async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      op.checkCanceled();
      return super.calculateSize(nodes).result;
    });
  }
}

void main() {
  late InMemoryTreeProvider provider;
  late Directory temp;
  late AppController app;

  setUp(() async {
    provider = _SlowSizeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/bin'),
      FakeEntry.directory('/home/docs'),
      FakeEntry.file('/home/notes.txt', size: 92262, modified: DateTime(2018, 2, 19)),
      FakeEntry.file('/home/report.xlsx', size: 6144, modified: DateTime(2026, 5, 1)),
      FakeEntry.link('/home/link-to-bin', '/home/bin'),
      FakeEntry.file('/home/docs/readme.md', size: 128, modified: DateTime(2026, 3, 3)),
      FakeEntry.file('/home/docs/spec.md', size: 256, modified: DateTime(2026, 3, 4)),
    ]);
    temp = await Directory.systemTemp.createTemp('flex_commander_view');

    final settings = AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home/docs'));
    app = AppController(
      left: PanelController(provider: provider, settings: settings.left),
      right: PanelController(provider: provider, settings: settings.right),
      store: SettingsStore(filePath: p.join(temp.path, 'settings.json')),
      settings: settings,
      // Короткая задержка: иначе отложенная запись настроек остаётся висящим
      // таймером и тест падает на проверке незавершённых таймеров.
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

    await tester.pumpWidget(FlexCommanderApp(controller: app));
    await app.start();
    await tester.pumpAndSettle();
  }

  testWidgets('окно состоит из двух панелей и ряда F-кнопок', (tester) async {
    await pumpApp(tester);

    expect(find.byType(PanelView), findsNWidgets(2));
    expect(find.byType(FunctionBar), findsOneWidget);
    for (final label in ['Help', 'Menu', 'View', 'Edit', 'Copy', 'Move', 'Mk Dir', 'Delete']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('-'), findsWidgets); // F9 и F10 пока пусты
    expect(find.text('F1'), findsOneWidget);
    expect(find.text('F10'), findsOneWidget);
  });

  testWidgets('текст строки опущен относительно иконки', (tester) async {
    await pumpApp(tester);

    // У Consolas на некоторых кеглях смещена базовая линия, поэтому текст
    // сдвинут вниз — иначе он не стоит на одной линии с иконкой.
    final row = find.byType(FileTableRow).first;
    final icon = tester.getCenter(find.descendant(of: row, matching: find.byType(FileTypeIcon)).first);
    final name = tester.getCenter(find.descendant(of: row, matching: find.text('..')).first);

    expect(name.dy, greaterThan(icon.dy));
  });

  testWidgets('панель показывает путь, заголовки и содержимое каталога', (tester) async {
    await pumpApp(tester);

    expect(find.byType(PanelPathHeader), findsNWidgets(2));
    expect(find.text('Name'), findsNWidgets(2));
    expect(find.text('Ext'), findsNWidgets(2));
    expect(find.text('Size'), findsNWidgets(2));
    expect(find.text('Modified'), findsNWidgets(2));

    // Имя показано без расширения, оно вынесено в свою колонку.
    expect(find.text('report'), findsOneWidget);
    expect(find.text('xlsx'), findsOneWidget);
    expect(find.text('90.1K'), findsOneWidget);
    expect(find.text('19-02-2018'), findsOneWidget);
    expect(find.text('..'), findsWidgets);
  });

  testWidgets('строка состояния показывает объект под курсором', (tester) async {
    await pumpApp(tester);

    app.left.setCursorToName('notes.txt');
    await tester.pump();

    expect(find.text('notes.txt'), findsWidgets);
  });

  testWidgets('строка состояния показывает сводку по помеченным', (tester) async {
    await pumpApp(tester);

    app.left.setCursorToName('notes.txt');
    app.left.toggleCurrentMark();
    await tester.pump();

    expect(find.text('Selected 1 item, 90.1 KB'), findsOneWidget);
  });

  testWidgets('ссылка в строке состояния показана стрелкой из шрифта', (tester) async {
    await pumpApp(tester);

    app.left.setCursorToName('link-to-bin');
    await tester.pump();

    final status = tester.widget<Text>(
      find.descendant(of: find.byType(PanelStatusBar).first, matching: find.byType(Text)),
    );
    final span = status.textSpan!;

    // Пара знаков «->» распадается на разные шрифты и стрелкой не выглядит.
    expect(span.toPlainText(), 'link-to-bin ${FcIcons.glyph(FcIcons.angleRight)} /home/bin');
    expect(span.toPlainText(), isNot(contains('->')));

    // Глиф должен быть набран шрифтом иконок, иначе на его месте пустой квадрат.
    final arrow = (span as TextSpan).children!.firstWhere(
      (child) => (child as TextSpan).text!.contains(FcIcons.glyph(FcIcons.angleRight)),
    );
    expect((arrow as TextSpan).style?.fontFamily, FcIcons.fontFamily);
  });

  testWidgets('пока каталоги считаются, об этом сказано прямо', (tester) async {
    await pumpApp(tester);

    app.left.setCursorToName('docs');
    app.left.toggleCurrentMark();
    await tester.pump();

    // Размер каталога считается фоном, и пока он не досчитан, сумма неполная.
    expect(find.textContaining('(Scanning…)'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    // Досчитали: содержимое каталога вошло в сумму, оговорки больше нет.
    expect(find.textContaining('(Scanning…)'), findsNothing);
    expect(find.text('Selected 1 item, 384 B'), findsOneWidget);
  });

  testWidgets('клик по строке делает панель активной и ставит курсор', (tester) async {
    await pumpApp(tester);
    expect(app.activePanel, app.left);

    final rightRows = find.descendant(
      of: find.byWidget(tester.widget<PanelView>(find.byType(PanelView).last)),
      matching: find.byType(FileTableRow),
    );
    await tester.tap(rightRows.at(1));
    await tester.pump();
    // Смена активной панели планирует отложенную запись настроек: даём таймеру
    // сработать, иначе тест упрётся в проверку незавершённых таймеров.
    await tester.pump(const Duration(milliseconds: 20));

    expect(app.activePanel, app.right);
    expect(app.right.cursorIndex, 1);
  });

  testWidgets('двойной клик по каталогу открывает его', (tester) async {
    await pumpApp(tester);

    final row = find.ancestor(of: find.text('bin'), matching: find.byType(FileTableRow));
    await tester.tap(row);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(row);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 20));

    expect(app.left.directory?.pathString, '/home/bin');
  });

  testWidgets('курсор рисуется только в активной панели', (tester) async {
    await pumpApp(tester);

    final rows = tester.widgetList<FileTableRow>(find.byType(FileTableRow));
    final withCursor = rows.where((row) => row.underCursor && row.panelActive);
    expect(withCursor, hasLength(1));
  });

  testWidgets('помеченная строка отмечена и в неактивной панели', (tester) async {
    await pumpApp(tester);

    app.right.markAll();
    await tester.pump();

    final marked = tester.widgetList<FileTableRow>(find.byType(FileTableRow)).where((row) => row.marked);
    expect(marked, isNotEmpty);
    expect(marked.every((row) => !row.panelActive), isTrue);
  });
}
