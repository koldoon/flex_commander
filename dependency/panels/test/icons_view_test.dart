import 'dart:math' as math;

import 'package:fc_api/fc_api.dart';
import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:fc_panels/fc_panels.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Вид «Значки»: сетка плиток.
///
/// Спецификация — `docs/spec/panel-view-icons.md`.
void main() {
  /// Плиток заведомо больше, чем помещается в ряд и на экран.
  const count = 40;

  String name(int at) => 'file${'$at'.padLeft(2, '0')}.txt';

  InMemoryTreeProvider provider() => InMemoryTreeProvider([
    FakeEntry.directory('/home'),
    for (var i = 1; i <= count; i++) FakeEntry.file('/home/${name(i)}', size: i),
  ])..home = '/home';

  /// Окно просторное нарочно: набор в прогоне шире экранного, и на девятистах
  /// точках в ряд встают две плитки — сравнивать в таком ряду нечего.
  Future<AppRuntime> open(
    WidgetTester tester, {
    Size size = const Size(1400, 700),
    InMemoryTreeProvider? source,
  }) async {
    final runtime = await testApp(provider: source ?? provider(), modules: featureModules());
    await runtime.app.start();

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();
    await runtime.app.left.setView(IconsView.viewId);
    await tester.pumpAndSettle();
    return runtime;
  }

  PanelsSettings settingsOf(AppRuntime runtime) =>
      runtime.app.settings.modules.scope('fc.panels').section(PanelsSettings.new);

  /// Где на экране стоит плитка с этим именем.
  Offset at(WidgetTester tester, String label) => tester.getTopLeft(find.text(label).first);

  /// Видимые плитки — по их именам.
  List<String> shown() => [
    for (var i = 1; i <= count; i++)
      if (find.text(name(i)).evaluate().isNotEmpty) name(i),
  ];

  testWidgets('плитки идут слева направо, потом вниз', (tester) async {
    await open(tester);

    final first = at(tester, name(1));
    final second = at(tester, name(2));

    expect(second.dy, first.dy, reason: 'соседи по списку — соседи по ряду');
    expect(second.dx, greaterThan(first.dx));

    // Ряд кончается там, где кончается ширина панели: где-то в списке плитка
    // уезжает вниз, и это следующий ряд.
    final places = [for (final label in shown()) at(tester, label)];
    final rows = places.map((offset) => offset.dy).toSet();
    expect(rows.length, greaterThan(1), reason: 'рядов больше одного');
    for (final row in rows) {
      final inRow = [
        for (final offset in places)
          if (offset.dy == row) offset.dx,
      ];
      expect(inRow, orderedEquals([...inRow]..sort()), reason: 'внутри ряда — слева направо');
    }
  });

  testWidgets('просвет между плитками одинаковый, а остаток остаётся справа', (tester) async {
    await open(tester);

    // Второй ряд, а не первый: в первом первая плитка — «..».
    final places = [for (final label in shown()) at(tester, label)];
    final second = places.map((offset) => offset.dy).toSet().toList()..sort();
    final row = [
      for (final offset in places)
        if (offset.dy == second[1]) offset.dx,
    ]..sort();
    expect(row.length, greaterThan(2), reason: 'в ряду есть что сравнивать');

    final steps = [for (var i = 1; i < row.length; i++) row[i] - row[i - 1]];
    for (final step in steps) {
      expect(step, closeTo(steps.first, 0.5), reason: 'единый шаг, а не растянутые просветы');
    }

    // Остаток справа: правый край последней плитки не упирается в край панели.
    final panel = tester.getRect(find.byType(IconsView));
    expect(row.last, lessThan(panel.width), reason: 'плитки не вылезли за панель');
  });

  testWidgets('содержимое отбито от краёв тем же полем, что и плитки друг от друга', (tester) async {
    await open(tester);

    final gap = const DefaultMetrics().tileGap;
    final view = tester.getRect(find.byType(IconsView));
    final tiles = [for (final one in find.byType(IconTile).evaluate()) tester.getRect(find.byWidget(one.widget))];
    final top = tiles.where((tile) => tile.top == tiles.first.top).toList()..sort((a, b) => a.left.compareTo(b.left));

    expect(top.first.left - view.left, closeTo(gap, 0.5), reason: 'крайняя плитка не прижата к раме');
    expect(
      top.first.top - view.top,
      closeTo(gap + const DefaultMetrics().panelTopPadding, 0.5),
      reason: 'сверху к полю добавлено место под плашкой пути: вид занимает раму целиком',
    );
    expect(top[1].left - top.first.right, closeTo(gap, 0.5), reason: 'и от соседки отбита тем же');
    expect(
      view.right - top.last.right,
      greaterThanOrEqualTo(gap - 0.5),
      reason: 'справа поле не меньше: остаток места добавляется к нему, а не съедает его',
    );
  });

  testWidgets('плитка шире панели даёт один столбец, а не ноль', (tester) async {
    // Размер взят крупнее, чем помещается: в панели шириной в треть окна
    // плитка в 256 точек не встаёт даже одна.
    final runtime = await open(tester, size: const Size(760, 700));
    settingsOf(runtime).iconTileSize = PanelsSettings.maxIconTileSize;
    await runtime.app.left.setView(PanelSettings.defaultView);
    await tester.pumpAndSettle();
    await runtime.app.left.setView(IconsView.viewId);
    await tester.pumpAndSettle();

    expect(runtime.app.left.cursorSteps.down, 1, reason: 'один столбец, а не ноль');
    expect(shown(), isNotEmpty, reason: 'плитки видны, а не схлопнулись в ничто');
  });

  testWidgets('ряд не вылезает за панель ни при какой ширине окна', (tester) async {
    // Ширина окна — не круглое число: столбцы считаются делением, и остаток
    // ряда обязан оставаться внутри, а не выпирать на просвет за последней
    // плиткой. Ровно на этом приложение и ругалось живьём, на полтора пикселя.
    final runtime = await open(tester, size: const Size(1000, 700));

    for (var width = 900.0; width <= 1400; width += 7) {
      tester.view.physicalSize = Size(width, 700);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'ширина $width');

      final view = tester.getRect(find.byType(IconsView));
      final tiles = [for (final one in find.byType(IconTile).evaluate()) tester.getRect(find.byWidget(one.widget))];
      final right = tiles.map((tile) => tile.right).reduce(math.max);
      expect(right, lessThanOrEqualTo(view.right + 0.5), reason: 'ширина $width: плитка вылезла за панель');
    }

    expect(runtime.app.left.cursorSteps.down, greaterThan(0));
  });

  testWidgets('сетка листается во всю раму и уезжает под плашку пути', (tester) async {
    final runtime = await open(tester, size: const Size(1000, 700));
    final panel = runtime.app.left;

    final plate = tester.getRect(find.byType(FcPathPlate).first);
    final list = tester.getRect(find.byType(Scrollable).first);
    expect(list.top, lessThan(plate.bottom), reason: 'область промотки заходит под плашку');

    // Первый ряд при этом стоит ниже плашки: его должно быть видно целиком.
    final first = tester.getRect(find.byType(IconTile).first);
    expect(first.top, greaterThanOrEqualTo(plate.bottom), reason: 'иначе верхние плитки наполовину под плашкой');

    // Курсор, уехавший вниз и вернувшийся наверх, тоже не прячется под неё.
    panel.setCursorIndex(panel.entries.length - 1);
    await tester.pumpAndSettle();
    panel.setCursorIndex(1);
    await tester.pumpAndSettle();

    final cursor = find.ancestor(of: find.text(name(1)), matching: find.byType(IconTile)).first;
    expect(
      tester.getRect(cursor).top,
      greaterThanOrEqualTo(plate.bottom - 0.5),
      reason: 'курсор виден, а не под плашкой',
    );
  });

  testWidgets('вбок курсор шагает на плитку, вниз — на ряд', (tester) async {
    final runtime = await open(tester);
    final panel = runtime.app.left;
    final columns = panel.cursorSteps.down;
    expect(columns, greaterThan(1), reason: 'вид объявил шаг ряда');
    expect(panel.cursorSteps.across, 1, reason: 'вбок — соседняя строка списка');

    panel.setCursorIndex(0);
    await tester.pumpAndSettle();

    runtime.commands.dispatch(KeyCombination.parse('Right'));
    await tester.pumpAndSettle();
    expect(panel.cursorIndex, 1);

    runtime.commands.dispatch(KeyCombination.parse('Down'));
    await tester.pumpAndSettle();
    expect(panel.cursorIndex, 1 + columns, reason: 'вниз — целый ряд');

    runtime.commands.dispatch(KeyCombination.parse('Up'));
    await tester.pumpAndSettle();
    expect(panel.cursorIndex, 1);

    // У верхнего края — упор, а не соскальзывание вбок.
    runtime.commands.dispatch(KeyCombination.parse('Up'));
    await tester.pumpAndSettle();
    expect(panel.cursorIndex, 1, reason: 'боковой прыжок под вертикальной клавишей читался бы ошибкой');
  });

  testWidgets('из неполного последнего ряда вниз ведёт на последнюю плитку', (tester) async {
    final runtime = await open(tester);
    final panel = runtime.app.left;
    final columns = panel.cursorSteps.down;

    // Предпоследний ряд, столбец заведомо правее последней плитки списка.
    panel.setCursorIndex(panel.entries.length - 1);
    await tester.pumpAndSettle();
    final last = panel.cursorIndex;

    panel.setCursorIndex((last ~/ columns) * columns - columns + (columns - 1));
    await tester.pumpAndSettle();
    runtime.commands.dispatch(KeyCombination.parse('Down'));
    await tester.pumpAndSettle();

    expect(panel.cursorIndex, lessThanOrEqualTo(last));
    expect(panel.cursorIndex, greaterThan(last - columns), reason: 'встал в последнем ряду, а не мимо');
  });

  testWidgets('в таблице те же клавиши значат прежнее', (tester) async {
    final runtime = await open(tester);
    final panel = runtime.app.left;

    await panel.setView(PanelSettings.defaultView);
    await tester.pumpAndSettle();
    panel.setCursorIndex(3);
    await tester.pumpAndSettle();

    runtime.commands.dispatch(KeyCombination.parse('Down'));
    await tester.pumpAndSettle();
    expect(panel.cursorIndex, 4, reason: 'в списке вниз — одна строка');

    runtime.commands.dispatch(KeyCombination.parse('Up'));
    await tester.pumpAndSettle();
    expect(panel.cursorIndex, 3);
  });

  testWidgets('страница — целое число рядов', (tester) async {
    final runtime = await open(tester);
    final panel = runtime.app.left;
    final columns = panel.cursorSteps.down;

    panel.setCursorIndex(0);
    await tester.pumpAndSettle();
    runtime.commands.dispatch(KeyCombination.parse('PgDn'));
    await tester.pumpAndSettle();

    expect(panel.cursorIndex % columns, 0, reason: 'иначе страница уводила бы курсор вбок');
    expect(panel.cursorIndex, greaterThan(0));
  });

  testWidgets('размер плитки слушается настройки', (tester) async {
    final runtime = await open(tester);
    final small = shown().length;

    settingsOf(runtime).iconTileSize = 128;
    await runtime.app.left.setView(PanelSettings.defaultView);
    await tester.pumpAndSettle();
    await runtime.app.left.setView(IconsView.viewId);
    await tester.pumpAndSettle();

    expect(shown().length, lessThan(small), reason: 'крупнее плитки — меньше их на экране');
  });

  testWidgets('окно шире — плиток больше, а не шире', (tester) async {
    final runtime = await open(tester, size: const Size(1000, 700));
    final narrow = tester.getRect(find.byType(IconTile).first).width;
    final columns = runtime.app.left.cursorSteps.down;

    tester.view.physicalSize = const Size(1600, 700);
    await tester.pumpAndSettle();

    expect(
      tester.getRect(find.byType(IconTile).first).width,
      closeTo(narrow, 0.5),
      reason: 'ширина плитки — про имя, а не про панель',
    );
    expect(
      runtime.app.left.cursorSteps.down,
      greaterThan(columns),
      reason: 'свободное место уходит в новые столбцы, а не в просветы',
    );
  });

  testWidgets('короткое имя не утаскивает плитку к левому краю', (tester) async {
    // Имена разной длины в одном каталоге: текст рисуется по содержимому, и
    // без явной ширины короткое имя тянуло бы за собой всю плитку — столбцы
    // переставали бы читаться столбцами.
    await open(
      tester,
      source: InMemoryTreeProvider([
        FakeEntry.directory('/home'),
        FakeEntry.file('/home/a.txt', size: 1),
        FakeEntry.file('/home/b.txt', size: 2),
        FakeEntry.file('/home/имя подлиннее прочих.txt', size: 3),
        FakeEntry.file('/home/c.txt', size: 4),
      ])..home = '/home',
    );

    // Плитки одной ширины: иначе короткое имя сжимает свою, и столбцы
    // перестают быть столбцами.
    final tiles = [for (final tile in find.byType(IconTile).evaluate()) tester.getRect(find.byWidget(tile.widget))];
    expect(tiles.length, greaterThan(3));
    for (final tile in tiles) {
      expect(tile.width, closeTo(tiles.first.width, 0.5), reason: 'все плитки одной ширины');
    }

    for (final label in ['a.txt', 'b.txt', 'имя подлиннее прочих.txt', 'c.txt']) {
      final text = find.text(label).first;
      final tile = find.ancestor(of: text, matching: find.byType(IconTile)).first;
      expect(
        tester.getRect(text).center.dx,
        closeTo(tester.getRect(tile).center.dx, 0.5),
        reason: 'имя «$label» стоит по середине своей плитки',
      );
    }
  });

  testWidgets('ширина имени слушается настройки', (tester) async {
    final runtime = await open(tester);
    final auto = tester.getRect(find.byType(IconTile).first).width;

    settingsOf(runtime).iconNameWidth = PanelsSettings.nameWidths.last;
    await runtime.app.left.setView(PanelSettings.defaultView);
    await tester.pumpAndSettle();
    await runtime.app.left.setView(IconsView.viewId);
    await tester.pumpAndSettle();

    expect(
      tester.getRect(find.byType(IconTile).first).width,
      greaterThan(auto),
      reason: 'потолок подняли — плитка доросла до самого длинного имени',
    );
  });

  testWidgets('пометка не двигает имя и не отнимает у него места', (tester) async {
    final runtime = await open(tester);
    final panel = runtime.app.left;

    final text = find.text(name(3));
    final before = tester.getRect(text);

    panel.mark(panel.entries.firstWhere((entry) => entry.name == name(3)));
    await tester.pumpAndSettle();

    expect(tester.getRect(text), before, reason: 'место под полосу отведено заранее, а не отнято у имени');

    // Полоса — над именем, поверх плашки и во всю её ширину.
    final tile = find.ancestor(of: text, matching: find.byType(IconTile)).first;
    final plate = find.descendant(of: tile, matching: find.byType(ClipRRect)).first;
    final bar = find.descendant(of: tile, matching: find.byType(ColoredBox)).first;
    const metrics = DefaultMetrics();

    expect(tester.getSize(bar).height, metrics.markedBarWidth);
    expect(tester.getSize(bar).width, closeTo(tester.getSize(plate).width, 0.5), reason: 'во всю ширину плашки');
    expect(tester.getRect(bar).top, closeTo(tester.getRect(plate).top, 0.5), reason: 'по верхнему краю плашки');
    expect(
      tester.getRect(plate).top,
      closeTo(tester.getRect(bar).top, 0.5),
      reason: 'плашка приросла ровно на полосу, без лишнего отступа',
    );
  });

  testWidgets('щелчок ставит курсор на ту плитку, по которой щёлкнули', (tester) async {
    final runtime = await open(tester);
    final panel = runtime.app.left;
    panel.setCursorIndex(0);
    await tester.pumpAndSettle();

    await tester.tap(find.text(name(3)).first);
    await tester.pumpAndSettle();

    expect(panel.currentEntry?.name, name(3));
  });
}
