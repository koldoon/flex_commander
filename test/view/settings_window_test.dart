import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
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
    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    await tester.pumpAndSettle();
  }

  TerminalSettings terminal() => (runtime.app.view.contentAt(ViewportPosition.bottom)! as CommandLineState).settings;

  /// Подпись настройки.
  ///
  /// Набрана разметкой — найденное в ней выделяется подложкой, — поэтому
  /// обычный `find.text` её не видит: `Text.rich` отдаёт строку только через
  /// `findRichText`.
  Finder setting(String title) => find.text(title, findRichText: true);

  testWidgets('F9 открывает настройки, разделы — по модулям', (tester) async {
    await openSettings(tester);

    expect(find.byType(FcSettingsForm), findsOneWidget);
    // Заголовки — названия модулей, как в справке.
    expect(find.text('Terminal'), findsWidgets);
    expect(find.text('Text viewer'), findsWidgets);
    // И поля под ними. Приставки с названием модуля в подписи нет: раздел и так
    // всегда идёт под своим заголовком, и «Wrap long lines» у редактора от
    // такого же у просмотрщика текста отличает заголовок, а не повтор в каждой
    // строке.
    expect(setting('Typing goes to the command line'), findsOneWidget);
    expect(setting('Wrap long lines'), findsNWidgets(2));

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('настройка — блок: подпись, объяснение, оговорка, управление', (tester) async {
    await openSettings(tester);

    final title = tester.getRect(setting('Shell'));
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

    final label = setting('Typing goes to the command line');
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

    await tester.tap(setting('Typing goes to the command line'));
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

  testWidgets('тронутая настройка помечена и возвращается к умолчанию', (tester) async {
    await openSettings(tester);

    // Нетронутому «Reset» предлагал бы ничего не делать, поэтому его нет вовсе.
    expect(find.text('Reset'), findsNothing);
    expect(terminal().typingGoesToLine, isFalse);

    await tester.tap(setting('Typing goes to the command line'));
    await tester.pumpAndSettle();
    expect(terminal().typingGoesToLine, isTrue);
    expect(find.text('Reset'), findsOneWidget);

    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();

    expect(terminal().typingGoesToLine, isFalse, reason: 'вернулось умолчание');
    expect(find.text('Reset'), findsNothing, reason: 'и пометка снялась вместе с ним');

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('«Reset» возвращает умолчание и в поле ввода, а не только в настройку', (tester) async {
    await openSettings(tester);

    final scans =
        find.ancestor(of: find.text('How many directories are measured at once'), matching: find.byType(Column)).first;
    final input = find.descendant(of: scans, matching: find.byType(TextField));
    await tester.enterText(input, '20');
    await tester.pumpAndSettle();
    expect(runtime.app.settings.sizeScanConcurrency, 20);

    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();

    // Поле ввода живёт столько же, сколько окно, и о том, что значение
    // сменилось помимо набора, само не узнает: пометка снималась бы, а в поле
    // оставалось набранное.
    expect(runtime.app.settings.sizeScanConcurrency, AppSettings.defaultSizeScanConcurrency);
    expect(tester.widget<TextField>(input).controller?.text, '${AppSettings.defaultSizeScanConcurrency}');

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
    // Последнее совпадение: подпись в последнем разделе может повторять подпись
    // в раннем («Wrap long lines» есть и у редактора, и у просмотрщика), а
    // разделы идут в списке по порядку.
    final field = setting(last.build().fields.first.title).last;
    final before = tester.getRect(field).top;

    await tester.tap(find.descendant(of: toc, matching: find.text(last.title, findRichText: true)));
    await tester.pumpAndSettle();

    expect(tester.getRect(field).top, lessThan(before));
    expect(tester.widget<FcPickList>(toc).selected, pages.length - 1);

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('подсветка не пробегает по разделам, пока идёт ход к выбранному', (tester) async {
    await openSettings(tester);

    final toc = find.byType(FcPickList);
    final pages = runtime.resolve<SettingsCatalog>().pages;
    final last = pages.length - 1;
    int selected() => tester.widget<FcPickList>(toc).selected;

    await tester.tap(find.descendant(of: toc, matching: find.text(pages.last.title, findRichText: true)));
    await tester.pump();
    expect(selected(), last);

    // Середина хода. Прокрутка идёт плавно, и под верхом обзора сейчас стоит
    // какой-то промежуточный раздел — но выбран не он: щелчок в оглавлении
    // это намерение, а не следствие геометрии. Иначе подсветка пробегала бы по
    // всем разделам разом, а оглавление дёргалось следом за ней.
    await tester.pump(const Duration(milliseconds: 60));
    expect(selected(), last, reason: 'подсветка держится на выбранном, пока список едет');

    await tester.pumpAndSettle();
    expect(selected(), last, reason: 'и остаётся на нём, даже если раздел не доехал до верха');

    // А тронули список — и подсветка снова следит за прокруткой.
    await tester.drag(find.byType(FcSettingsForm), const Offset(0, 2000), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(selected(), 0);

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

    // «Wrap long lines» есть у двоих — обе и остаются, каждая под своим
    // заголовком.
    expect(setting('Wrap long lines'), findsNWidgets(2));
    expect(setting('Shell'), findsNothing);
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
    expect(setting('Allow elevated writes'), findsOneWidget);
    expect(find.text('1 setting'), findsOneWidget);

    await search(tester, 'sizeScanConcurrency');
    expect(setting('Directory size scans'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('совпало название раздела — раздел показан целиком', (tester) async {
    await openSettings(tester);
    await search(tester, 'terminal');

    // Спросили про терминал — значит про все его настройки, а не про те, где
    // это слово ещё раз написано в подписи.
    expect(setting('Shell'), findsOneWidget);
    expect(setting('Scrollback'), findsOneWidget);
    expect(setting('Wrap long lines'), findsNothing);

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

  testWidgets('прокрученные настройки не подлезают под поиск', (tester) async {
    await openSettings(tester);

    // Обе прокрутки: сперва оглавление, за ним настройки.
    final viewports = find.descendant(of: find.byType(FcSettingsForm), matching: find.byType(SingleChildScrollView));
    expect(viewports, findsNWidgets(2));

    // Отступ от поля поиска стоит **снаружи** прокрутки — как у оглавления.
    // Внутри он уезжал бы вместе с содержимым, и настройки подлезали бы под
    // поле, пока оглавление рядом держало бы свой отступ.
    expect(tester.getRect(viewports.last).top, closeTo(tester.getRect(viewports.first).top, 0.5));

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('настройка ядра доживает до закрытия окна и попадает в запись', (tester) async {
    await openSettings(tester);
    expect(runtime.app.settings.sizeScanConcurrency, AppSettings.defaultSizeScanConcurrency);

    // Поле числа стоит под своей подписью — единственное в этом блоке.
    final scans =
        find.ancestor(of: find.text('How many directories are measured at once'), matching: find.byType(Column)).first;
    await tester.enterText(find.descendant(of: scans, matching: find.byType(TextField)), '20');
    await tester.pumpAndSettle();

    // Записать надо туда, откуда `settings` его и берёт. Через сам `settings`
    // не выйдет: он собирает новый объект на каждый запрос, и правка ушла бы в
    // одноразовую копию — окно закрылось, и от неё ничего не осталось.
    expect(runtime.app.settings.sizeScanConcurrency, 20);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    await tester.pumpAndSettle();

    expect(find.text('20'), findsOneWidget, reason: 'окно открылось заново и показывает своё же значение');
    expect(runtime.app.settings.sizeScanConcurrency, 20);

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
        // Умолчание схема называет сама, а раздел настроек — своим
        // конструктором. Разойдись они, окно помечало бы тронутой настройку,
        // которой никто не касался, и предлагало бы «вернуть» то, что и так
        // стоит. Приложение только что запустилось на пустых настройках —
        // значит, всё до одного поля стоит на умолчании.
        expect(
          field.isDefault,
          isTrue,
          reason:
              'поле «${field.title}» (${field.id}) на свежих настройках не равно своему умолчанию: '
              'схема и раздел разошлись',
        );
      }
    }

    await tester.pump(const Duration(milliseconds: 20));
  });
}
