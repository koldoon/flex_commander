import 'package:fc_api/fc_api.dart';
import 'package:fc_panels/fc_panels.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Краткий вид: имена столбцами.
///
/// Спецификация — `docs/spec/panel-view-brief.md`.
void main() {
  /// Имён заведомо больше, чем строк в столбце: столбцы начинаются там, где
  /// список не поместился по высоте.
  const count = 24;

  InMemoryTreeProvider provider() => InMemoryTreeProvider([
    FakeEntry.directory('/home'),
    for (var i = 1; i <= count; i++) FakeEntry.file('/home/file${'$i'.padLeft(2, '0')}.txt', size: i),
  ])..home = '/home';

  Future<AppRuntime> open(WidgetTester tester, {Size size = const Size(900, 300)}) async {
    final runtime = await testApp(provider: provider(), modules: featureModules());
    await runtime.app.start();

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();
    await runtime.app.left.setView(BriefView.viewId);
    await tester.pumpAndSettle();
    return runtime;
  }

  /// Где на экране стоит имя.
  Offset at(WidgetTester tester, String name) => tester.getTopLeft(find.text(name).first);

  testWidgets('имена идут сверху вниз, потом вправо', (tester) async {
    await open(tester);

    final first = at(tester, 'file01.txt');
    final second = at(tester, 'file02.txt');

    expect(second.dx, first.dx, reason: 'соседи по списку — соседи по столбцу');
    expect(second.dy, greaterThan(first.dy));

    // Столбец кончается там, где кончается панель: где-то в списке имя уезжает
    // вправо, и это и есть следующий столбец.
    final names = [
      for (var i = 1; i <= count; i++)
        if (find.text('file${'$i'.padLeft(2, '0')}.txt').evaluate().isNotEmpty)
          at(tester, 'file${'$i'.padLeft(2, '0')}.txt'),
    ];
    final columns = names.map((offset) => offset.dx).toSet();
    expect(columns.length, greaterThan(1), reason: 'столбцов больше одного');
    for (final column in columns) {
      final inColumn = [
        for (final offset in names)
          if (offset.dx == column) offset.dy,
      ];
      expect(inColumn, orderedEquals([...inColumn]..sort()), reason: 'внутри столбца — сверху вниз');
    }
  });

  testWidgets('число столбцов слушается настройки', (tester) async {
    final runtime = await open(tester);
    final settings = runtime.app.settings.modules.scope('fc.panels').section(PanelsSettings.new);

    settings.briefColumns = 2;
    await runtime.app.left.setView(PanelSettings.defaultView);
    await tester.pumpAndSettle();
    await runtime.app.left.setView(BriefView.viewId);
    await tester.pumpAndSettle();

    final panel = tester.getSize(find.byType(BriefView));
    final widths =
        {
            for (var i = 1; i <= count; i++)
              if (find.text('file${'$i'.padLeft(2, '0')}.txt').evaluate().isNotEmpty)
                at(tester, 'file${'$i'.padLeft(2, '0')}.txt').dx,
          }.toList()
          ..sort();
    // Два столбца — значит, второй начинается примерно с середины панели.
    expect(widths.length, greaterThanOrEqualTo(2));
    expect(widths[1] - widths[0], closeTo(panel.width / 2, panel.width / 8));
  });

  testWidgets('Left и Right ходят по столбцам, а в таблице — в начало и в конец', (tester) async {
    final runtime = await open(tester);
    final panel = runtime.app.left;

    panel.setCursorIndex(0);
    await tester.pumpAndSettle();
    final rows = panel.columnRows;
    expect(rows, greaterThan(0), reason: 'вид объявил свою раскладку');

    runtime.commands.dispatch(KeyCombination.parse('Right'));
    await tester.pumpAndSettle();
    expect(panel.cursorIndex, rows, reason: 'на столбец вправо — это на строку экрана');

    runtime.commands.dispatch(KeyCombination.parse('Left'));
    await tester.pumpAndSettle();
    expect(panel.cursorIndex, 0);

    // У края упирается, а не заворачивает.
    runtime.commands.dispatch(KeyCombination.parse('Left'));
    await tester.pumpAndSettle();
    expect(panel.cursorIndex, 0);

    // В таблице те же клавиши значат прежнее: одна клавиша, две команды.
    await panel.setView(PanelSettings.defaultView);
    await tester.pumpAndSettle();
    expect(panel.columnRows, 0);
    runtime.commands.dispatch(KeyCombination.parse('Right'));
    await tester.pumpAndSettle();
    expect(panel.cursorIndex, panel.entries.length - 1, reason: 'в таблице Right — в конец списка');
  });

  testWidgets('окно изменили — столбец с курсором остался на месте', (tester) async {
    final runtime = await open(tester, size: const Size(700, 300));
    final panel = runtime.app.left;

    // Уходим вправо, за пределы первого экрана.
    panel.setCursorToName('file20.txt');
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(find.text('file20.txt').first);

    // Высота меняет число строк в столбце — а значит, и то, в каком столбце
    // окажется каждое имя: раскладка пересобирается целиком.
    tester.view.physicalSize = const Size(700, 240);
    await tester.pumpAndSettle();

    // Столбец с курсором стоит там же, где стоял: раскладка изменилась, а
    // место, на которое человек смотрит, — нет.
    final after = tester.getTopLeft(find.text('file20.txt').first);
    expect(after.dx, closeTo(before.dx, 2), reason: 'столбец не поплыл');
  });

  testWidgets('смена вида оставляет курсор на том же имени', (tester) async {
    final runtime = await open(tester);
    final panel = runtime.app.left;

    panel.setCursorToName('file07.txt');
    await tester.pumpAndSettle();

    await panel.setView(PanelSettings.defaultView);
    await tester.pumpAndSettle();
    await panel.setView(BriefView.viewId);
    await tester.pumpAndSettle();

    expect(panel.currentEntry?.name, 'file07.txt');
  });
}
