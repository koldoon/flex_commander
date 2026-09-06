import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/state/shell_settings.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Модуль-проба: одна команда и её перевод.
///
/// Настоящие строки переводятся модуль за модулем, а механизм должен быть
/// проверен сразу и целиком — от объявления до надписи на экране.
class _Probe implements FcFrontendModule {
  const _Probe();

  @override
  String get id => 'test.language';

  @override
  String get title => 'Language probe';

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.command((context) => _GreetCommand());
    registry.command((context) => _SilentCommand());
    // Клавиша — чтобы подпись было видно в ряду кнопок: перерисовку проверяют
    // на экране, а не на геттере.
    registry.binding(KeyBinding('F5', _GreetCommand.commandId));
    registry.strings('ru', {'Greet': 'Приветствовать', 'Say hello to everyone': 'Поздороваться со всеми'});
  }
}

class _GreetCommand extends AppCommand {
  static const String commandId = 'test.greet';

  @override
  String get id => commandId;

  @override
  String get label => tr('Greet');

  @override
  String get description => tr('Say hello to everyone');

  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute(CommandContext context) async {}
}

/// Команда, перевода которой никто не объявил.
class _SilentCommand extends AppCommand {
  static const String commandId = 'test.silent';

  @override
  String get id => commandId;

  @override
  String get label => tr('Untranslated probe');

  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute(CommandContext context) async {}
}

/// Язык интерфейса: словарь модуля, настройка и смена на лету.
///
/// Спецификация — `docs/spec/localization.md`.
void main() {
  InMemoryTreeProvider provider() =>
      InMemoryTreeProvider([FakeEntry.directory('/home'), FakeEntry.file('/home/notes.txt', size: 10)])..home = '/home';

  /// Настройки с явным языком: прогон не должен зависеть от языка машины.
  AppSettings settingsIn(String language) =>
      AppSettings.defaults('/home')..modules.scope('fc.shell').section(ShellSettings.new).language = language;

  AppCommand greetIn(AppRuntime runtime) =>
      runtime.commands.installed.firstWhere((command) => command.id == _GreetCommand.commandId);

  test('команда говорит на языке приложения', () async {
    final runtime = await testApp(provider: provider(), modules: const [_Probe()], language: 'ru');

    expect(greetIn(runtime).label, 'Приветствовать');
    expect(greetIn(runtime).description, 'Поздороваться со всеми');
  });

  test('непереведённая команда остаётся английской', () async {
    final runtime = await testApp(provider: provider(), modules: const [_Probe()], language: 'ru');

    // Пустая надпись хуже непереведённой: перевода нет — берётся то, что
    // написано в коде.
    expect(runtime.commands.installed.firstWhere((c) => c.id == _SilentCommand.commandId).label, 'Untranslated probe');
  });

  test('язык берётся из настроек', () async {
    final runtime = await testApp(
      provider: provider(),
      modules: const [_Probe()],
      settings: settingsIn('ru'),
      language: null,
    );

    expect(runtime.app.strings.language, 'ru');
    expect(greetIn(runtime).label, 'Приветствовать');
  });

  testWidgets('всё приложение по-русски: ряд кнопок, панель и палитра', (tester) async {
    final runtime = await testApp(provider: provider(), modules: featureModules(), language: 'ru');
    await runtime.app.start();

    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();

    // Ряд функциональных кнопок — самое видное место в окне.
    expect(find.text('Смотреть'), findsOneWidget);
    expect(find.text('Править'), findsOneWidget);
    expect(find.text('Копировать'), findsOneWidget);
    expect(find.text('Удалить'), findsOneWidget);

    // Заголовки колонок панели.
    expect(find.text('Имя'), findsWidgets);
    expect(find.text('Размер'), findsWidgets);

    // И палитра команд — тем же языком: ищут в ней по русскому названию, а не
    // по английскому, которое человеку и не показывали.
    runtime.commands.dispatch(KeyCombination.parse('Cmd-Shift-P'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(FcTextField).first, 'наверх');
    await tester.pumpAndSettle();
    final rows = [
      for (final text in tester.widgetList<Text>(
        find.descendant(of: find.byType(FcCommandPalette), matching: find.byType(Text)),
      ))
        text.textSpan?.toPlainText() ?? text.data ?? '',
    ];
    // Строка палитры — название и описание разом; оба по-русски.
    expect(rows, contains('Наверх   Выйти в родительский каталог'));
    // И подсказка поля ввода тоже.
    expect(rows, contains('Команда'));
  });

  testWidgets('окно настроек меняет язык не закрываясь', (tester) async {
    final runtime = await testApp(
      provider: provider(),
      modules: featureModules(),
      settings: settingsIn('en'),
      language: null,
    );
    await runtime.app.start();

    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    await tester.pumpAndSettle();

    // Подписи набраны разметкой — найденное в них выделяется подложкой.
    expect(find.text('Language', findRichText: true), findsOneWidget);
    expect(find.text('Terminal'), findsWidgets);

    // Ровно то, что делает сама настройка языка.
    runtime.app.settings.modules.scope('fc.shell').section(ShellSettings.new).language = 'ru';
    runtime.app.strings.refresh();
    await tester.pumpAndSettle();

    // Схема пересобралась прямо в открытом окне: и подписи полей, и названия
    // разделов, и заголовок самого окна.
    expect(find.text('Язык', findRichText: true), findsOneWidget);
    expect(find.text('Терминал'), findsWidgets);
    expect(find.text('Настройки'), findsWidgets);
    expect(find.text('Language', findRichText: true), findsNothing);
  });

  testWidgets('оглавление настроек шире самого длинного названия', (tester) async {
    final runtime = await testApp(
      provider: provider(),
      modules: featureModules(),
      settings: settingsIn('ru'),
      language: null,
    );
    await runtime.app.start();

    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    await tester.pumpAndSettle();

    final toc = find.byType(FcPickList).first;
    final theme = FcTheme.of(tester.element(toc));
    // Текст отбит от краёв столбца с обеих сторон.
    final available = tester.getSize(toc).width - 2 * theme.metrics.dialogPadding;

    for (final text in tester.widgetList<Text>(find.descendant(of: toc, matching: find.byType(Text)))) {
      final title = text.textSpan!.toPlainText();
      // Меряется жирным: выбранный раздел набран им, и он же самый широкий.
      final painter = TextPainter(
        text: TextSpan(
          text: title,
          style: TextStyle(fontFamily: theme.fonts.ui, fontSize: theme.metrics.fontSize, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final needed = painter.maxIntrinsicWidth;
      painter.dispose();

      expect(needed, lessThanOrEqualTo(available), reason: 'обрезается: «$title»');
    }

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('смена языка перерисовывает окно без перезапуска', (tester) async {
    final runtime = await testApp(
      provider: provider(),
      modules: const [_Probe()],
      settings: settingsIn('en'),
      language: null,
    );
    await runtime.app.start();

    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();

    expect(find.text('Greet'), findsOneWidget);

    // Ровно то, что делает настройка языка в окне настроек.
    runtime.app.settings.modules.scope('fc.shell').section(ShellSettings.new).language = 'ru';
    runtime.app.strings.refresh();
    await tester.pumpAndSettle();

    expect(find.text('Приветствовать'), findsOneWidget);
    expect(find.text('Greet'), findsNothing);
  });
}
