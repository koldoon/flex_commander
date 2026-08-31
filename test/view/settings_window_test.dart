import 'package:fc_api/fc_api.dart';
import 'package:fc_terminal/fc_terminal.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Окно настроек: то, что человек выбирает, — в одном месте.
void main() {
  late AppRuntime runtime;

  setUp(() async {
    runtime = await testApp(
      provider: InMemoryTreeProvider([FakeEntry.directory('/home')])..home = '/home',
      modules: featureModules(),
    );
    await runtime.app.start();
  });

  Future<void> openSettings(WidgetTester tester, {Size size = const Size(900, 1400)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pumpAndSettle();
  }

  TerminalSettings terminal() => (runtime.app.view.contentAt(ViewportPosition.bottom)! as CommandLineState).settings;

  /// Подпись настройки целиком: «Категория: Имя».
  ///
  /// Набрана разметкой — приставка с названием модуля приглушена, имя жирное, —
  /// поэтому обычный `find.text` её не видит: он сверяет строку целиком, а
  /// `Text.rich` отдаёт её только через `findRichText`.
  Finder setting(String category, String title) => find.text('$category: $title', findRichText: true);

  testWidgets('F2 открывает настройки, разделы — по модулям', (tester) async {
    await openSettings(tester);

    expect(find.byType(FcSettingsForm), findsOneWidget);
    // Заголовки — названия модулей, как в справке.
    expect(find.text('Terminal'), findsWidgets);
    expect(find.text('Text viewer'), findsWidgets);
    // И поля под ними — с приставкой модуля в подписи. Она там не для красоты:
    // «Wrap long lines» есть и у редактора, и у просмотрщика текста, и без
    // приставки эти две настройки в окне неразличимы.
    expect(setting('Terminal', 'Typing goes to the command line'), findsOneWidget);
    expect(setting('Text editor', 'Wrap long lines'), findsOneWidget);
    expect(setting('Text viewer', 'Wrap long lines'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('настройка — блок: подпись, объяснение, оговорка, управление', (tester) async {
    await openSettings(tester);

    final title = tester.getRect(setting('Terminal', 'Shell'));
    final description = tester.getRect(find.text('Empty means the shell you work in'));
    final note = tester.getRect(find.text('Applies to the next session (⌃O)').first);
    final field = tester.getRect(find.ancestor(of: find.text(r'$SHELL'), matching: find.byType(FcTextField)).first);

    // Сверху вниз и в одном порядке: сначала что это, потом что оно значит,
    // потом оговорка, и только потом — чем это менять.
    expect(description.top, greaterThan(title.top));
    expect(note.top, greaterThan(description.top));
    expect(field.top, greaterThan(note.top));

    // И всё по одной левой границе. Столбца подписей больше нет — с ним
    // подпись стояла бы справа, управление слева, а объяснение под
    // управлением, и читать пришлось бы по диагонали.
    expect(description.left, closeTo(title.left, 0.5));
    expect(note.left, closeTo(title.left, 0.5));
    expect(field.left, closeTo(title.left, 0.5));

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('у флага квадрат стоит на строке подписи', (tester) async {
    await openSettings(tester);

    final label = setting('Terminal', 'Typing goes to the command line');
    final title = tester.getRect(label);
    final box = tester.getRect(find.ancestor(of: label, matching: find.byType(FcCheckbox)).first);
    final description = tester.getRect(find.text('The mc habit: no jump-to-name by the first letter'));

    // У флага подпись и есть управление: поставь квадрат под подписью — и она
    // повторится дважды, заголовком и меткой рядом с квадратом.
    expect(box.left, lessThan(title.left));
    expect(title.center.dy, closeTo(box.center.dy, 2));

    // А объяснение равняется по подписи, а не по квадрату: оно относится к
    // настройке, а не к галочке.
    expect(description.top, greaterThan(title.bottom));
    expect(description.left, closeTo(title.left, 0.5));

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('флаг переключается и доезжает до раздела настроек', (tester) async {
    await openSettings(tester);
    expect(terminal().typingGoesToLine, isFalse);

    await tester.tap(setting('Terminal', 'Typing goes to the command line'));
    await tester.pumpAndSettle();

    expect(terminal().typingGoesToLine, isTrue, reason: 'применяется сразу, без кнопки «Применить»');

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('число берётся из поля, а не из головы', (tester) async {
    await openSettings(tester);

    final scrollback = find.ancestor(of: find.text('lines'), matching: find.byType(Row)).first;
    await tester.enterText(find.descendant(of: scrollback, matching: find.byType(TextField)), '4096');
    await tester.pumpAndSettle();

    expect(terminal().maxLines, 4096);

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('оглавление перечисляет разделы и уводит к ним', (tester) async {
    await openSettings(tester);

    final toc = find.byType(FcPickList);
    final pages = runtime.resolve<SettingsCatalog>().pages;
    expect(pages.length, greaterThan(1));

    // Все разделы на месте и в том же порядке, что и в списке.
    for (final page in pages) {
      expect(find.descendant(of: toc, matching: find.text(page.title, findRichText: true)), findsOneWidget);
    }
    expect(tester.widget<FcPickList>(toc).selected, 0, reason: 'открылось на первом разделе');

    // Последний раздел лежит ниже обзора; щелчок по нему в оглавлении должен
    // поднять его наверх, а не просто подсветить строку.
    final last = pages.last;
    final field = last.build().fields.first;
    final before = tester.getRect(setting(last.title, field.title)).top;

    await tester.tap(find.descendant(of: toc, matching: find.text(last.title, findRichText: true)));
    await tester.pumpAndSettle();

    expect(tester.getRect(setting(last.title, field.title)).top, lessThan(before));
    expect(tester.widget<FcPickList>(toc).selected, pages.length - 1);

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('прокрутка сама подсвечивает раздел в оглавлении', (tester) async {
    await openSettings(tester);

    final toc = find.byType(FcPickList);
    expect(tester.widget<FcPickList>(toc).selected, 0);

    // Прокручивают список настроек, а не оглавление: подсветка идёт следом.
    await tester.drag(find.byType(FcSettingsForm), const Offset(0, -600), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(tester.widget<FcPickList>(toc).selected, greaterThan(0), reason: 'подсвечен раздел, до которого добрались');

    await tester.pump(const Duration(milliseconds: 20));
  });

  /// Набрать в поиске: он стоит первым полем ввода в окне.
  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(FcTextField).first, query);
    await tester.pumpAndSettle();
  }

  testWidgets('поиск отбирает по подписи и считает найденное', (tester) async {
    await openSettings(tester);
    await search(tester, 'wrap');

    // «Wrap long lines» есть у двоих — обе и остаются.
    expect(setting('Text editor', 'Wrap long lines'), findsOneWidget);
    expect(setting('Text viewer', 'Wrap long lines'), findsOneWidget);
    expect(setting('Terminal', 'Shell'), findsNothing);
    expect(find.text('2 settings'), findsOneWidget);

    // И оглавление показывает только те разделы, где что-то нашлось.
    final toc = find.byType(FcPickList);
    expect(find.descendant(of: toc, matching: find.text('Text editor', findRichText: true)), findsOneWidget);
    expect(find.descendant(of: toc, matching: find.text('Terminal', findRichText: true)), findsNothing);

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('поиск смотрит и в объяснение, и в ключ', (tester) async {
    await openSettings(tester);

    // Слова из объяснения человек помнит точно, а вот в какой оно подписи —
    // нет.
    await search(tester, 'administrator');
    expect(setting('Application shell', 'Allow elevated writes'), findsOneWidget);
    expect(find.text('1 setting'), findsOneWidget);

    await search(tester, 'sizeScanConcurrency');
    expect(setting('Application shell', 'Directory size scans'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('совпало название раздела — раздел показан целиком', (tester) async {
    await openSettings(tester);
    await search(tester, 'terminal');

    // Спросили про терминал — значит про все его настройки, а не про те, где
    // это слово ещё раз написано в подписи.
    expect(setting('Terminal', 'Shell'), findsOneWidget);
    expect(setting('Terminal', 'Scrollback'), findsOneWidget);
    expect(setting('Text editor', 'Wrap long lines'), findsNothing);

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('ничего не нашлось — одно сообщение, а не два пустых столбца', (tester) async {
    await openSettings(tester);
    await search(tester, 'квакозябра');

    expect(find.text('Nothing found'), findsOneWidget);
    expect(find.byType(FcPickList), findsNothing);
    expect(find.text('0 settings'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('состояние в настройках не показывается', (tester) async {
    terminal().history.add('ls -la');
    await openSettings(tester);

    // История команд, пути панелей и геометрия окна — это память приложения, а
    // не выбор человека: показать их полем значило бы предложить их править.
    Finder inForm(Finder finder) => find.descendant(of: find.byType(FcSettingsForm), matching: finder);
    expect(inForm(find.text('ls -la')), findsNothing);
    expect(inForm(find.text('history')), findsNothing);
    // Пути панелей за окном видны, а в самих настройках их нет.
    expect(inForm(find.textContaining('/home')), findsNothing);

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('в тесное окно всё умещается прокруткой, а не через край', (tester) async {
    // Окно ниже, чем список полей: без прокрутки колонка вылезла бы за экран,
    // и Flutter сообщил бы о переполнении прямо из отрисовки.
    await openSettings(tester, size: const Size(900, 420));

    expect(find.byType(Scrollable), findsWidgets);
    expect(tester.takeException(), isNull);

    // Кнопка «Close» остаётся видимой: прокручивается список, а не окно
    // целиком.
    expect(find.widgetWithText(FcButton, 'Close'), findsOneWidget);
    expect(tester.getRect(find.widgetWithText(FcButton, 'Close')).bottom, lessThanOrEqualTo(420));

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('Esc закрывает', (tester) async {
    await openSettings(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(FcSettingsForm), findsNothing);

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('у каждого поля схемы есть ключ в разделе настроек', (tester) async {
    // Схема, разошедшаяся с данными, разошлась бы молча: поле писало бы в
    // объект, которого в файле нет, и настройка не пережила бы перезапуск.
    final pages = runtime.resolve<SettingsCatalog>().pages;
    expect(pages, isNotEmpty);

    // Окно открывается **до** снимка: раздел модуля заводится при первом
    // обращении к нему, а незаведённый в файл и не попадёт. Открытое окно
    // прочитало все поля — значит, все разделы на месте.
    await openSettings(tester);

    // Все ключи, которые приложение действительно пишет: свои и разделов
    // модулей.
    final saved = <String, dynamic>{};
    runtime.app.settings.toMap(saved);
    final keys = <String>{
      ...saved.keys,
      for (final section in (saved['modules'] as Map).values) ...(section as Map).keys.cast<String>(),
    };

    for (final page in pages) {
      for (final field in page.build().fields) {
        expect(field.title, isNotEmpty, reason: 'поле без подписи не покажешь');
        expect(
          keys,
          contains(field.id),
          reason: 'поле «${field.title}» пишет в ${field.id}, а такого ключа в настройках нет',
        );
      }
    }

    await tester.pump(const Duration(milliseconds: 20));
  });
}
