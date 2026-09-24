import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/app.dart';
import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flex_commander/view/dialogs/dialog_frame.dart';
import 'package:flex_commander/view/dialogs/help_view.dart';
import 'package:flutter_test/flutter_test.dart';

/// Справка: оглавление, поиск и разделы — текущие настройки и привязки клавиш
/// (`docs/spec/help-window.md`).
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
  Finder inHelp(Finder finder) => find.descendant(of: find.byType(HelpView), matching: finder);

  /// Набрать в поиске справки.
  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(find.descendant(of: find.byType(HelpView), matching: find.byType(FcTextField)), query);
    await tester.pumpAndSettle();
  }

  /// Названия разделов в оглавлении; пусто — оглавления нет вовсе.
  List<String> toc(WidgetTester tester) => [
    for (final list in tester.widgetList<FcPickList>(find.byType(FcPickList)))
      for (final row in list.rows) row.title,
  ];

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
      // Строки оглавления набраны кусками (`Text.rich`) — у них `data` пуст;
      // сюда они попадают, только если случайно встали на ту же высоту.
      if (text.data == null || text.data == name || (origin.dy - top).abs() >= 0.5) {
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
    testWidgets('F1 открывает справку', (tester) async {
      await openHelp(tester);

      expect(find.byType(HelpView), findsOneWidget);
      expect(find.text('Help'), findsWidgets);
      // «Settings» в справке трое: строка оглавления, заголовок раздела
      // настроек приложения и подпись команды, открывающей их окно.
      expect(inHelp(find.text('Settings')), findsNWidgets(3));
      // Команды показаны по модулям: заголовок раздела — название модуля, а не
      // общее «Commands». Первым — тот, кто объявлен первым. Дважды — потому
      // что то же название стоит строкой в оглавлении.
      expect(inHelp(find.text('Shell')), findsNWidgets(2));
      // Кнопок нет вовсе: читать справку нечем, кроме глаз, а закрывают её
      // `Esc` и крестик в заголовке.
      expect(find.byType(FcButton), findsNothing);
    });

    testWidgets('кнопок внизу нет: справка ничего не делает, её читают', (tester) async {
      await openHelp(tester, size: const Size(1400, 900));

      // Ряд ради одного слова «Close» отнимал бы у текста полосу высоты, а
      // закрывают окно `Esc` и крестик в заголовке (`docs/spec/dialog-body.md`).
      expect(find.byType(FcDialogActions), findsNothing);
      expect(find.widgetWithText(FcButton, 'Close'), findsNothing);

      // И содержимое от этого доходит до низа окна, а не оставляет полосу.
      final dialog = tester.getRect(find.byType(HelpView));
      final content = tester.getRect(find.byType(FcIndexedSections));
      expect(content.bottom, closeTo(dialog.bottom, 1));
    });

    testWidgets('крестик в заголовке закрывает окно', (tester) async {
      await openHelp(tester);

      await tester.tap(find.descendant(of: find.byType(DialogFrame), matching: find.byType(CustomPaint)).first);
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
        tester.getSize(find.ancestor(of: find.byType(HelpView), matching: find.byType(Container)).last);

    testWidgets('окно не занимает больше трёх четвертей ширины и не выходит за поля по высоте', (tester) async {
      const screen = Size(1400, 900);
      await openHelp(tester, size: screen);

      final size = frameSize(tester);
      // Ширина — долей окна: с оглавлением слева содержимое её больше не
      // назначает (`docs/spec/help-window.md`, §4).
      expect(size.width, lessThanOrEqualTo(screen.width * 0.75));
      expect(size.height, lessThanOrEqualTo(screen.height - 240));
    });

    testWidgets('на тесном экране окно упирается в свою долю, а не вылезает', (tester) async {
      await openHelp(tester, size: const Size(700, 600));

      // Панелям под окном остаётся видимый край с обеих сторон — по нему и
      // понятно, что окно временное.
      expect(frameSize(tester).width, lessThanOrEqualTo(700 * 0.75));
    });

    testWidgets('на маленьком экране справка прокручивается, а не обрезается', (tester) async {
      await openHelp(tester, size: const Size(802, 621));

      final position = _ownScroll(tester).controller!.position;

      // Строк заведомо больше, чем помещается: справка листается.
      expect(position.maxScrollExtent, greaterThan(0));
      expect(position.pixels, 0);
    });

    testWidgets('PgDn листает, стрелка из поиска уводит к следующему разделу', (tester) async {
      await openHelp(tester);
      final controller = _ownScroll(tester).controller!;

      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(0));

      // Стрелки отдаются разделам: фокус при открытии стоит в поиске, и водить
      // ими нечего (§5).
      controller.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(0), reason: 'уехали ко второму разделу');
    });
  });

  group('оглавление и поиск', () {
    testWidgets('слева стоят названия всех разделов', (tester) async {
      await openHelp(tester);

      expect(toc(tester), containsAll(['Application', 'Settings', 'File operations']));
    });

    testWidgets('поиск отбирает и разделы, и оглавление', (tester) async {
      await openHelp(tester);
      await search(tester, 'rename');

      expect(toc(tester), isNot(contains('Application')), reason: 'в разделе о сборке такого слова нет');
      expect(toc(tester), contains('File operations'));
      expect(inHelp(find.text('Multi-rename')), findsOneWidget);
    });

    testWidgets('совпало название раздела — раздел показан целиком', (tester) async {
      await openHelp(tester);
      final all = inHelp(find.byType(Text)).evaluate().length;
      await search(tester, 'terminal');

      expect(toc(tester), ['Terminal']);
      expect(inHelp(find.byType(Text)).evaluate().length, lessThan(all));
      // Команды терминала остались все, а не только та, где слово повторено.
      expect(inHelp(find.text('Command line')), findsOneWidget);
    });

    testWidgets('ищется и по клавише: «а что такое Alt-F9»', (tester) async {
      await openHelp(tester);
      await search(tester, 'alt-f9');

      expect(toc(tester), isNotEmpty);
      expect(inHelp(find.textContaining('Alt-F9')), findsWidgets);
    });

    testWidgets('не нашлось — сказано один раз, справа', (tester) async {
      await openHelp(tester);
      await search(tester, 'такого тут нет');

      expect(toc(tester), isEmpty, reason: 'пустое оглавление сказало бы то же самое вторично');
      expect(inHelp(find.text('Nothing found')), findsOneWidget);
    });

    testWidgets('щелчок по разделу в оглавлении прокручивает к нему', (tester) async {
      await openHelp(tester);
      final controller = _ownScroll(tester).controller!;

      await tester.tap(find.descendant(of: find.byType(FcPickList), matching: find.text('Terminal')));
      await tester.pumpAndSettle();

      expect(controller.offset, greaterThan(0));
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

      // Две клавиши остались там, где это **разные физические клавиши**:
      // плюс на основной клавиатуре и на цифровом блоке
      // (`docs/spec/key-presets.md`, §3). Привычки же закрываются наборами, и
      // вторых клавиш ради них больше нет.
      expect(rowOf(tester, 'Select by mask').first, 'Shift-=, +');
    });

    testWidgets('привязка к любому символу названа по-человечески', (tester) async {
      await openHelp(tester);

      // Настоящей клавиши «AnyChar» не существует.
      expect(rowOf(tester, 'Go to name').first, 'any letter');
      expect(inHelp(find.text('AnyChar')), findsNothing);
    });

    testWidgets('нереализованные команды не притворяются рабочими', (tester) async {
      // Без просмотрщика: `F3` держит заглушка оболочки, и справка обязана
      // сказать об этом прямо, а не показать клавишу как рабочую.
      app =
          (await testApp(
            provider: provider,
            modules: [
              for (final module in featureModules())
                if (module.id != 'fc.viewer') module,
            ],
          )).app;
      await openHelp(tester);

      expect(rowOf(tester, 'View'), ['F3', 'Not implemented yet']);
      // А меню больше нет вовсе: `F2` занят настройками, заглушка убрана.
      expect(inHelp(find.text('Menu')), findsNothing);
    });

    testWidgets('пришедший модулем занимает место заглушки', (tester) async {
      await openHelp(tester);

      // `F3` и `F4` держали заглушки, пока не появились просмотрщик и
      // редактор: у команд те же идентификаторы, и клавиши достались им вместе
      // с местом в справке.
      expect(rowOf(tester, 'View'), ['F3', 'Show the file under the cursor']);
      expect(rowOf(tester, 'Edit'), ['F4', 'Open the file under the cursor for editing']);
    });

    testWidgets('команде без описания пустая колонка не мешает', (tester) async {
      await openHelp(tester);

      // Объяснять «Cursor up» нечем, и придумывать текст ради колонки незачем.
      expect(rowOf(tester, 'Cursor up'), ['Up', '']);
    });

    testWidgets('команды сгруппированы по модулям, в порядке их объявления', (tester) async {
      await openHelp(tester, size: const Size(1400, 1400));

      final titles = ['Shell', 'Terminal', 'Navigation', 'File operations'];
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

/// Прокрутка **самой справки**, а не рамы окна.
///
/// Рама с некоторых пор прокручивает всё, что в неё не влезло, — иначе высокое
/// окно молча переполнялось бы. Её прокрутка своего контроллера не заводит, и
/// по нему они и различаются: справка листается клавишами и потому держит его
/// сама.
/// Прокрутка **содержимого**: своя есть и у оглавления, и идёт она первой —
/// столбец с ним стоит слева.
SingleChildScrollView _ownScroll(WidgetTester tester) => tester
    .widgetList<SingleChildScrollView>(
      find.descendant(of: find.byType(HelpView), matching: find.byType(SingleChildScrollView)),
    )
    .lastWhere((one) => one.controller != null);
