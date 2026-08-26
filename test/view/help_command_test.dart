import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/app.dart';
import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Справка: таблица текущих настроек и привязок клавиш.
void main() {
  late InMemoryTreeProvider provider;
  late AppController app;

  setUp(() async {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/bin'),
      FakeEntry.file('/home/notes.txt', size: 10),
    ]);

    final settings = AppSettings(
      left: PanelSettings.defaults('/home'),
      right: PanelSettings.defaults('/home/bin'),
      window: WindowGeometry(left: 40, top: 20, width: 1024, height: 700),
    );
    app = (await testApp(provider: provider, modules: featureModules(), settings: settings)).app;
  });

  Future<void> pumpApp(WidgetTester tester, {Size size = const Size(802, 621)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: app));
    await app.start();
    await tester.pumpAndSettle();
  }

  Future<void> openHelp(WidgetTester tester, {Size size = const Size(802, 621)}) async {
    await pumpApp(tester, size: size);
    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await tester.pumpAndSettle();
  }

  /// Поиск внутри окна справки: те же подписи есть и на кнопках нижней
  /// панели — «F5» там номер клавиши, а не строка таблицы.
  Finder inHelp(Finder finder) => find.descendant(of: find.byType(FcKeyValueTable), matching: finder);

  /// Вся строка таблицы, кроме названия, — по порядку слева направо.
  ///
  /// Ищется по вертикали, а не по устройству таблицы: тест должен проверять
  /// то, что видит пользователь, — что значения стоят напротив названия.
  List<String> rowOf(WidgetTester tester, String name) {
    // Первое вхождение: то же слово может встретиться ниже — «Hidden files»
    // есть и в настройках, и среди команд.
    final top = tester.getTopLeft(inHelp(find.text(name)).first).dy;
    final cells = <(double, String)>[];

    for (final element in inHelp(find.byType(Text)).evaluate()) {
      final text = element.widget as Text;
      final origin = tester.getTopLeft(find.byWidget(text));
      if (text.data == name || (origin.dy - top).abs() >= 0.5) {
        continue;
      }
      cells.add((origin.dx, text.data ?? ''));
    }

    cells.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final cell in cells) cell.$2];
  }

  /// Значение в той же строке, что и название.
  String valueOf(WidgetTester tester, String name) => rowOf(tester, name).firstOrNull ?? '';

  group('окно', () {
    testWidgets('F1 открывает справку с одной кнопкой', (tester) async {
      await openHelp(tester);

      expect(find.byType(FcKeyValueTable), findsOneWidget);
      expect(find.text('Help'), findsWidgets);
      expect(inHelp(find.text('Settings')), findsOneWidget);
      // Команды показаны по модулям: заголовок раздела — название модуля, а не
      // общее «Commands». Первым — тот, кто объявлен первым.
      expect(inHelp(find.text('Application shell')), findsOneWidget);
      // Единственная кнопка: закрыть. Ни отмены, ни подтверждения — читать
      // справку нечем, кроме глаз.
      expect(find.byType(FcButton), findsOneWidget);
      expect(find.widgetWithText(FcButton, 'Close'), findsOneWidget);
    });

    testWidgets('кнопка по размеру подписи и прижата вправо, как в других окнах', (tester) async {
      await openHelp(tester, size: const Size(1400, 900));

      final button = find.widgetWithText(FcButton, 'Close');
      final size = tester.getSize(button);
      final dialog = tester.getRect(find.byType(FcKeyValueTable));

      // `FcButton` — это Container с alignment: под ограниченной по ширине
      // разметкой он растягивается во всю ширину окна. Ряд кнопок этого не
      // допускает, и проверять надо именно ширину, а не факт наличия кнопки.
      expect(size.width, lessThan(dialog.width / 3));
      expect(tester.getRect(button).right, closeTo(dialog.right - 16, 4));
    });

    testWidgets('кнопка закрывает окно', (tester) async {
      await openHelp(tester);

      await tester.tap(find.widgetWithText(FcButton, 'Close'));
      await tester.pumpAndSettle();

      expect(find.byType(FcKeyValueTable), findsNothing);
    });

    testWidgets('Esc и Enter тоже закрывают: делать в справке нечего', (tester) async {
      await openHelp(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(FcKeyValueTable), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.f1);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.byType(FcKeyValueTable), findsNothing);
    });

    /// Окно целиком, вместе с полосой заголовка.
    Size frameSize(WidgetTester tester) =>
        tester.getSize(find.ancestor(of: find.byType(FcKeyValueTable), matching: find.byType(Container)).last);

    testWidgets('окно не выходит за поля в 120 точек от краёв', (tester) async {
      const screen = Size(1400, 900);
      await openHelp(tester, size: screen);

      final size = frameSize(tester);
      expect(size.width, lessThanOrEqualTo(screen.width - 240));
      expect(size.height, lessThanOrEqualTo(screen.height - 240));
    });

    testWidgets('на просторном экране окно облегает таблицу, а не разъезжается', (tester) async {
      await openHelp(tester, size: const Size(1900, 1200));

      // Столбцы считаются по содержимому, поэтому лишней ширины у окна нет.
      expect(frameSize(tester).width, lessThan(1900 - 240));
    });

    testWidgets('на тесном экране окно упирается в поля, а не вылезает', (tester) async {
      await openHelp(tester, size: const Size(700, 600));

      expect(frameSize(tester).width, lessThanOrEqualTo(700 - 240));
    });

    testWidgets('на маленьком экране таблица прокручивается, а не обрезается', (tester) async {
      await openHelp(tester, size: const Size(802, 621));

      final scroll = tester.widget<SingleChildScrollView>(find.byType(SingleChildScrollView).first);
      final position = scroll.controller!.position;

      // Строк заведомо больше, чем помещается: справка листается.
      expect(position.maxScrollExtent, greaterThan(0));
      expect(position.pixels, 0);
    });

    testWidgets('стрелки и PgDn листают таблицу', (tester) async {
      await openHelp(tester);
      final controller = tester.widget<SingleChildScrollView>(find.byType(SingleChildScrollView).first).controller!;

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(controller.offset, greaterThan(0));

      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      expect(controller.offset, controller.position.maxScrollExtent);
    });
  });

  group('содержимое', () {
    testWidgets('показывает каталоги обеих панелей', (tester) async {
      await openHelp(tester);

      expect(valueOf(tester, 'Left panel'), '/home');
      expect(valueOf(tester, 'Right panel'), '/home/bin');
    });

    testWidgets('совпадающие настройки панелей не удваиваются', (tester) async {
      await openHelp(tester);

      // Сортировка у обеих одна — показывать её дважды незачем.
      expect(valueOf(tester, 'Sort'), 'Name ↑');
    });

    testWidgets('различие панелей видно', (tester) async {
      await pumpApp(tester);
      await app.left.setShowHidden(true);
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.f1);
      await tester.pumpAndSettle();

      expect(valueOf(tester, 'Hidden files'), 'left — shown, right — hidden');
    });

    testWidgets('геометрия окна показывается, когда она известна', (tester) async {
      await openHelp(tester);

      expect(valueOf(tester, 'Window'), '1024×700 at 40, 20');
    });

    testWidgets('команда показана названием, клавишами и описанием', (tester) async {
      await openHelp(tester);

      // Не идентификаторы: `file.copy` пользователю ни о чём не говорит.
      expect(rowOf(tester, 'Copy'), ['F5', 'Copy the selected items to the other panel']);
      expect(inHelp(find.text('file.copy')), findsNothing);
    });

    testWidgets('у команды с несколькими клавишами показаны все', (tester) async {
      await openHelp(tester);

      // На macOS F-клавиши заняты системой, и рядом стоят привычные сочетания.
      // Платформа в widget-тестах не macOS, поэтому `Cmd` печатается как
      // `Ctrl` — ровно то, во что его сворачивает `KeyCombination`.
      expect(rowOf(tester, 'Delete').first, 'F8, Ctrl-Bsp');
    });

    testWidgets('привязка к любому символу названа по-человечески', (tester) async {
      await openHelp(tester);

      // Настоящей клавиши «AnyChar» не существует.
      expect(rowOf(tester, 'Go to name').first, 'any letter');
      expect(inHelp(find.text('AnyChar')), findsNothing);
    });

    testWidgets('нереализованные команды не притворяются рабочими', (tester) async {
      await openHelp(tester);

      // `F2` пока за заглушкой: клавиша закреплена, а меню ещё нет.
      expect(rowOf(tester, 'Menu'), ['F2', 'Not implemented yet']);
    });

    testWidgets('пришедший модулем занимает место заглушки', (tester) async {
      await openHelp(tester);

      // `F3` и `F4` держали заглушки, пока не появились просмотрщик и
      // редактор: у команд те же идентификаторы, и клавиши достались им вместе
      // с местом в справке.
      expect(rowOf(tester, 'View'), ['F3', 'Show the file under the cursor as text']);
      expect(rowOf(tester, 'Edit'), ['F4', 'Open the file under the cursor for editing']);
    });

    testWidgets('команде без описания пустая колонка не мешает', (tester) async {
      await openHelp(tester);

      // Объяснять «Cursor up» нечем, и придумывать текст ради колонки незачем.
      expect(rowOf(tester, 'Cursor up'), ['Up', '']);
    });

    testWidgets('команды сгруппированы по модулям, в порядке их объявления', (tester) async {
      await openHelp(tester, size: const Size(1400, 1400));

      final titles = ['Application shell', 'Terminal', 'Navigation', 'File operations'];
      final tops = [for (final title in titles) tester.getTopLeft(inHelp(find.text(title)).first).dy];

      // Порядок тот же, что в списке модулей: им же задан приоритет привязок.
      // Просмотрщик, занявший место заглушки `F3`, наверх не всплывает.
      expect(tops, orderedEquals([...tops]..sort()));
      // И команда лежит в разделе своего модуля, а не в общей куче.
      final copy = tester.getTopLeft(inHelp(find.text('Copy')).first).dy;
      final fileOps = tester.getTopLeft(inHelp(find.text('File operations')).first).dy;
      expect(copy, greaterThan(fileOps));
    });

    testWidgets('справка знает и о самой себе', (tester) async {
      await openHelp(tester);

      expect(rowOf(tester, 'Help').first, 'F1');
    });
  });
}
