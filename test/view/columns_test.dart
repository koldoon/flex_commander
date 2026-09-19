import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/app.dart';
import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:fc_panels/fc_panels.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  Future<void> pumpApp(WidgetTester tester, {Size size = const Size(802, 621)}) async {
    tester.view.physicalSize = size;
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

  List<String> namesOf(Session panel) => panel.entries.map((node) => node.name).toList();

  /// Перетаскивание ровно на столько, на сколько прошёл курсор.
  ///
  /// Так тянут границу колонки: она идёт за курсором точка в точку
  /// (`DragStartBehavior.down`), и поблажка на порог распознавания здесь
  /// исказила бы проверку.
  Future<void> dragExactly(WidgetTester tester, Offset from, double dx) async {
    final gesture = await tester.startGesture(from);
    await gesture.moveBy(Offset(dx, 0));
    await gesture.up();
    await tester.pumpAndSettle();
  }

  /// Перетаскивание с учётом порога распознавания: первый сдвиг уходит на то,
  /// чтобы жест был признан перетаскиванием, и до обработчика не доходит.
  ///
  /// Так тянут **заголовок** — перестановку колонок: она о пройденном пути не
  /// отчитывается, ей важно, куда отпустили.
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
      expect(app.left.sort.column, FsColumns.name);

      await tester.tap(headerOf('Size'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 20));

      expect(app.left.sort.column, FsColumns.size);
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
      expect(app.core!.settings!.left.sort.column, FsColumns.modified);
    });
  });

  group('ширина колонок', () {
    testWidgets('перетаскивание границы меняет ширину правой колонки', (tester) async {
      await pumpApp(tester);
      final before = app.left.columns.find(FsColumns.size)!.width;

      // Граница колонки размера — её левый край.
      final sizeHeader = tester.getRect(headerOf('Size'));
      await dragExactly(tester, Offset(sizeHeader.left, sizeHeader.center.dy), -20);

      expect(app.left.columns.find(FsColumns.size)!.width, before + 20);
    });

    testWidgets('граница идёт за курсором, а не следом на отставании', (tester) async {
      // Жест признаётся перетаскиванием не сразу, и всё, что курсор прошёл до
      // этого, при `DragStartBehavior.start` пропадает: граница потом едет за
      // курсором на постоянном отставании (поймано живьём).
      await pumpApp(tester);
      final before = app.left.columns.find(FsColumns.size)!.width;

      final sizeHeader = tester.getRect(headerOf('Size'));
      await dragExactly(tester, Offset(sizeHeader.left, sizeHeader.center.dy), -40);

      expect(app.left.columns.find(FsColumns.size)!.width, closeTo(before + 40, 0.5));
    });

    testWidgets('мышь идёт мелкими шагами — граница идёт за ней', (tester) async {
      // Так двигают мышью на самом деле: два десятка мелких шагов, а не один
      // рывок. Именно здесь и вылезло, что граница почти не двигается.
      await pumpApp(tester);
      final before = app.left.columns.find(FsColumns.size)!.width;

      final sizeHeader = tester.getRect(headerOf('Size'));
      // Мышью, а не пальцем: порог распознавания у них разный, и вылезло это
      // именно на мыши.
      final gesture = await tester.startGesture(
        Offset(sizeHeader.left, sizeHeader.center.dy),
        kind: PointerDeviceKind.mouse,
      );
      for (var step = 0; step < 20; step++) {
        await gesture.moveBy(const Offset(-3, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(app.left.columns.find(FsColumns.size)!.width, closeTo(before + 60, 1));
    });

    testWidgets('в тесной панели граница всё равно идёт за курсором', (tester) async {
      // Так у человека и было: включены все колонки, резиновому имени ужиматься
      // почти некуда — и граница переставала двигаться.
      await pumpApp(tester);
      for (final id in [
        FsColumns.created,
        FsColumns.accessed,
        FsColumns.attributes,
        FsColumns.owner,
        FsColumns.group,
      ]) {
        app.left.setColumnLayout(app.left.columns.toggleVisible(id));
      }
      await tester.pumpAndSettle();

      final before = app.left.columns.find(FsColumns.size)!.width;
      final sizeHeader = tester.getRect(headerOf('Size'));
      final gesture = await tester.startGesture(
        Offset(sizeHeader.left, sizeHeader.center.dy),
        kind: PointerDeviceKind.mouse,
      );
      for (var step = 0; step < 10; step++) {
        await gesture.moveBy(const Offset(-3, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(app.left.columns.find(FsColumns.size)!.width, closeTo(before + 30, 1));
    });

    testWidgets('упёрлись в предел и пошли обратно — граница трогается сразу', (tester) async {
      // Приращения теряются, стоит упереться: лишнее движение отбрасывается, и
      // обратно граница трогается не с того места, где курсор. Дальше она так и
      // идёт с отставанием — ровно то, что было видно живьём.
      await pumpApp(tester);
      final spec = app.left.columns.find(FsColumns.size)!;
      final sizeHeader = tester.getRect(headerOf('Size'));

      final gesture = await tester.startGesture(
        Offset(sizeHeader.left, sizeHeader.center.dy),
        kind: PointerDeviceKind.mouse,
      );
      // Вправо до упора и ещё сто точек сверху: колонка уже на минимуме.
      await gesture.moveBy(const Offset(200, 0));
      await tester.pump();
      expect(app.left.columns.find(FsColumns.size)!.width, spec.minWidth);

      // И обратно ровно настолько, чтобы вернуться к исходной ширине.
      await gesture.moveBy(const Offset(-200, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        app.left.columns.find(FsColumns.size)!.width,
        closeTo(spec.width, 1),
        reason: 'вернулись курсором туда же — значит и граница там же',
      );
    });

    testWidgets('ширина не уходит ниже минимума', (tester) async {
      await pumpApp(tester);

      final sizeHeader = tester.getRect(headerOf('Size'));
      await dragExactly(tester, Offset(sizeHeader.left, sizeHeader.center.dy), 500);

      final spec = app.left.columns.find(FsColumns.size)!;
      expect(spec.width, spec.minWidth);
    });

    testWidgets('новая ширина попадает в сохраняемые настройки', (tester) async {
      await pumpApp(tester);

      final sizeHeader = tester.getRect(headerOf('Size'));
      // Заметно больше порога распознавания: короткое движение жестом не
      // считается вовсе — ни у нас, ни в системе.
      await dragExactly(tester, Offset(sizeHeader.left, sizeHeader.center.dy), -30);

      expect(
        app.core!.settings!.left.columns.find(FsColumns.size)?.width,
        app.left.columns.find(FsColumns.size)?.width,
      );
    });
  });

  group('порядок колонок', () {
    testWidgets('перетаскивание заголовка меняет порядок', (tester) async {
      await pumpApp(tester);
      expect(app.left.columns.visibleColumns.map((c) => c.id), [
        FsColumns.icon,
        FsColumns.name,
        FsColumns.ext,
        FsColumns.size,
        FsColumns.modified,
      ]);

      final modified = tester.getRect(headerOf('Modified'));
      final ext = tester.getRect(headerOf('Ext'));
      await dragBy(tester, modified.center, ext.left - modified.center.dx);

      expect(app.left.columns.visibleColumns.map((c) => c.id), [
        FsColumns.icon,
        FsColumns.name,
        FsColumns.modified,
        FsColumns.ext,
        FsColumns.size,
      ]);
    });

    testWidgets('обязательные колонки не двигаются', (tester) async {
      await pumpApp(tester);

      final name = tester.getRect(headerOf('Name'));
      final size = tester.getRect(headerOf('Size'));
      await dragBy(tester, name.center, size.center.dx - name.center.dx);

      expect(app.left.columns.columns.first.id, FsColumns.icon);
      expect(app.left.columns.columns[1].id, FsColumns.name);
    });
  });

  group('раскладка колонок не пересобирается зря', () {
    testWidgets('спрошенная дважды — та же самая', (tester) async {
      // По раскладке и списку показанных колонок вид узнаёт, что строка не
      // изменилась и собирать её заново не нужно. Новый список на каждое
      // обращение рушил это молча (`docs/spec/panel-redraw.md`, §4).
      await pumpApp(tester);

      final first = app.left.columns;
      expect(app.left.columns, same(first), reason: 'раскладка собирается заново на каждое обращение');
      expect(app.left.columns.visibleColumns, same(first.visibleColumns));
    });

    testWidgets('колонку спрятали — раскладка другая', (tester) async {
      await pumpApp(tester);

      final before = app.left.columns;
      app.left.setColumnLayout(before.toggleVisible(FsColumns.size));
      await tester.pumpAndSettle();

      expect(app.left.columns, isNot(same(before)), reason: 'память держит устаревшую раскладку');
      expect(app.left.columns.find(FsColumns.size)!.visible, isFalse);
    });
  });

  group('набор строк', () {
    testWidgets('после дерева таблица показывает каталог, а не ветви', (tester) async {
      await pumpApp(tester);

      await app.left.setView(TreeView.viewId);
      await tester.pumpAndSettle();
      expect(app.left.rows, RowsKind.tree);

      await app.left.setView(PanelSettings.defaultView);
      await tester.pumpAndSettle();

      // Вид говорит, что ему нужно; молчание значило бы «сойдёт и то, что
      // просил прежний» (`docs/spec/panel-node-list.md`, §3).
      expect(app.left.rows, RowsKind.listing);
      expect(app.left.entries.every((entry) => entry.level == 0), isTrue);
    });
  });

  group('видимость колонок', () {
    /// Окно выбора вида левой панели: там же, где человек их и меняет.
    Future<void> openViewDialog(WidgetTester tester) async {
      runtime.commands.dispatch(KeyCombination.parse('Alt-F1'));
      await tester.pumpAndSettle();
    }

    /// Нажать «OK»: правки настроек вида уходят по нему, а не живьём
    /// (`docs/spec/panel-views.md`, §7).
    Future<void> confirm(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(FcButton, 'OK'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 20));
    }

    /// Снять галочку с колонки в открытом окне.
    Future<void> toggle(WidgetTester tester, String title) async {
      await tester.tap(find.descendant(of: find.byType(FcCheckbox), matching: find.text(title)));
      await tester.pumpAndSettle();
    }

    testWidgets('окно вида показывает колонки и скрывает выбранную', (tester) async {
      await pumpApp(tester);
      expect(find.text('Ext'), findsWidgets);

      await openViewDialog(tester);

      // Перечислены все колонки, включая скрытые.
      expect(find.descendant(of: find.byType(FcCheckbox), matching: find.text('Attributes')), findsOneWidget);

      await toggle(tester, 'Ext');
      await confirm(tester);

      expect(app.left.columns.find(FsColumns.ext)?.visible, isFalse);
      expect(app.left.columns.visibleColumns.map((c) => c.id), isNot(contains(FsColumns.ext)));
    });

    /// Строка списка видов: рисуется разметкой, и по `data` её не найти — там
    /// название и пояснение одной строкой. Ищем по началу, поэтому «Tree» так
    /// не спросить: с него начинается и «Tree with contents».
    Finder viewRow(String title) => find.byWidgetPredicate(
      (widget) => widget is Text && widget.data == null && (widget.textSpan?.toPlainText() ?? '').startsWith(title),
    );

    testWidgets('щелчок по виду выбирает, а включает «OK»', (tester) async {
      await pumpApp(tester);
      await openViewDialog(tester);

      await tester.tap(viewRow('Brief'));
      await tester.pumpAndSettle();

      // Окно на месте, вид прежний: щелчок сказал «вот этот», а не «включай».
      expect(find.byType(FcPickList), findsOneWidget);
      expect(tester.widget<FcPickList>(find.byType(FcPickList)).selected, 1);
      expect(app.left.view, PanelSettings.defaultView);

      await confirm(tester);

      expect(app.left.view, 'brief');
      expect(find.byType(FcPickList), findsNothing, reason: 'окно закрылось');
    });

    testWidgets('до «OK» не меняется ничего', (tester) async {
      await pumpApp(tester);
      await openViewDialog(tester);

      await toggle(tester, 'Ext');

      // Галочка снята — а панель ещё нет: правки ждут «OK».
      expect(
        tester.widget<FcCheckbox>(find.ancestor(of: find.text('Ext').last, matching: find.byType(FcCheckbox))).value,
        isFalse,
      );
      expect(app.left.columns.find(FsColumns.ext)?.visible, isTrue);

      await confirm(tester);
      expect(app.left.columns.find(FsColumns.ext)?.visible, isFalse);
    });

    testWidgets('«Отмена» не меняет ничего', (tester) async {
      await pumpApp(tester);
      await openViewDialog(tester);

      await toggle(tester, 'Ext');
      await tester.tap(find.widgetWithText(FcButton, 'Cancel'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 20));

      expect(app.left.columns.find(FsColumns.ext)?.visible, isTrue);
    });

    testWidgets('галочки под невыбранным видом не трогают показанное', (tester) async {
      // Панель показана таблицей, курсор в окне ушёл на «Tree with contents»:
      // его настройки — это колонки будущего столбца списка, и перерисовывать
      // ими таблицу нельзя (`docs/spec/panel-views.md`, §7).
      await pumpApp(tester);
      await openViewDialog(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      // Список рисует строки разметкой, а не `Text`, — выбранное спрашиваем у
      // него самого: четвёртый вид и есть комбинированный.
      expect(tester.widget<FcPickList>(find.byType(FcPickList)).selected, 3);

      await toggle(tester, 'Ext');

      expect(app.left.view, PanelSettings.defaultView, reason: 'вид не сменился от хода курсора');
      expect(app.left.columns.find(FsColumns.ext)?.visible, isTrue, reason: 'таблица не перерисовалась');
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

      // Подпись флажка ищем внутри самого флажка: то же слово стоит теперь и
      // подписью формата — «Имя» есть и у колонки, и у формата владельца.
      Rect checkbox(String text) =>
          tester.getRect(find.descendant(of: find.byType(FcCheckbox), matching: find.text(text)).first);

      final title = tester.getRect(
        find.descendant(of: find.byType(TableViewOptions), matching: find.text('Columns visible')),
      );
      final icon = checkbox('Icon');
      final name = checkbox('Name');

      // Подпись над столбцом, флажки под ней — и всё по одной левой границе,
      // той же, по которой отбито содержимое окна (список видов над ними).
      final view = tester.getRect(find.descendant(of: find.byType(FcPickList), matching: find.byType(RichText)).first);
      expect(name.top, greaterThan(icon.top), reason: 'столбиком, а не в строку');
      expect(icon.top, greaterThan(title.top));
      expect(title.left, closeTo(view.left, 0.5));
    });

    testWidgets('формат колонки выбирают там же и применяют по «OK»', (tester) async {
      await pumpApp(tester);
      await openViewDialog(tester);

      // Список форматов стоит у колонки, которая их объявила; у имени его нет.
      final sizeFormat = find.byWidgetPredicate(
        (widget) => widget is FcSelect<String> && widget.options.containsKey('bytes'),
      );
      expect(sizeFormat, findsOneWidget);

      tester.widget<FcSelect<String>>(sizeFormat).onChanged!('bytes');
      await tester.pumpAndSettle();
      expect(app.left.columns.find(FsColumns.size)?.format, isNot('bytes'), reason: 'правки ждут «OK»');

      await confirm(tester);

      expect(app.left.columns.find(FsColumns.size)?.format, 'bytes');
      expect(app.right.columns.find(FsColumns.size)?.format, isNot('bytes'), reason: 'формат панельный, как ширина');
    });

    testWidgets('списки форматов стоят столбцом и не уезжают к краю панели', (tester) async {
      // Ряд, растянутый на всю панель, уводил списки к её правому краю, и
      // таблица читалась разреженной (поймано живьём).
      // Окно пошире: в тесном столбец флажков обязан уступить место списку, и
      // ровный столбец там невозможен — это и правильно.
      await pumpApp(tester, size: const Size(1600, 900));
      await openViewDialog(tester);

      final selects = tester.widgetList<FcSelect<String>>(find.byType(FcSelect<String>)).toList();
      expect(selects.length, greaterThan(2), reason: 'форматы есть у размера, дат, прав и владельца');

      final lefts = [
        for (final finder in find.byType(FcSelect<String>).evaluate())
          tester.getRect(find.byWidget(finder.widget)).left,
      ];
      expect(lefts.toSet(), hasLength(1), reason: 'все списки начинаются с одного места');

      // И вплотную к столбцу флажков, а не у края окна: между ними один зазор.
      final widest = tester.getRect(
        find.descendant(of: find.byType(FcCheckbox), matching: find.text('Attributes')).first,
      );
      expect(lefts.first - widest.right, lessThan(100), reason: 'списки прижаты к флажкам, а не к краю');
    });

    testWidgets('формат переживает перезапуск', (tester) async {
      await pumpApp(tester);
      await openViewDialog(tester);

      final sizeFormat = find.byWidgetPredicate(
        (widget) => widget is FcSelect<String> && widget.options.containsKey('bytes'),
      );
      tester.widget<FcSelect<String>>(sizeFormat).onChanged!('bytes');
      await tester.pumpAndSettle();
      await confirm(tester);
      await app.save();

      expect(app.core!.settings!.left.columns.find(FsColumns.size)?.format, 'bytes');
    });

    testWidgets('колонки правой панели — свои', (tester) async {
      await pumpApp(tester);

      // Окно открыто для левой: правая своей раскладки не теряет.
      await openViewDialog(tester);
      await toggle(tester, 'Ext');
      await confirm(tester);

      expect(app.left.columns.find(FsColumns.ext)?.visible, isFalse);
      expect(app.right.columns.find(FsColumns.ext)?.visible, isTrue);
    });
  });
}
