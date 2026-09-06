import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/state/shell_settings.dart';
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
