import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/app.dart';
import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flex_commander/view/function_bar/function_button.dart';
import 'package:flex_commander/state/commands/help_command.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Команда, которая только отмечается о запуске: так видно, какую именно
/// отправила кнопка нижней панели.
class _RecordingCommand extends AppCommand {
  _RecordingCommand({required this.id, required this.label, required this.runs});

  final List<String> runs;

  @override
  final String id;

  @override
  final String label;

  @override
  String get description => 'Records its own run';

  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute(CommandContext context) async => runs.add(id);
}

/// Открытие объекта системой: в тесте вместо запуска программы — запись в
/// список.
///
/// Экранный модуль: отдать файл системе — действие, за которым человек уходит
/// из приложения, и дереву оно ни к чему.
class _RecordingOpener implements FcFrontendModule {
  const _RecordingOpener(this.opened);

  final List<String> opened;

  @override
  String get id => 'test.opener';

  @override
  String get title => 'Recording opener';

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.service<SystemOpener>((services) => (path) async => opened.add(path));
  }
}

void main() {
  late InMemoryTreeProvider provider;
  late AppController app;
  late List<String> opened;

  // Платформа в widget-тестах не macOS, поэтому «командная» клавиша здесь —
  // Ctrl: ровно то, во что KeyCombination сворачивает Cmd вне macOS.
  const commandKey = LogicalKeyboardKey.control;

  setUp(() async {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/bin'),
      FakeEntry.directory('/home/docs'),
      FakeEntry.file('/home/notes.txt', size: 10),
      FakeEntry.file('/home/report.xlsx', size: 20),
      FakeEntry.file('/home/.hidden', size: 1),
      FakeEntry.file('/home/docs/readme.md', size: 30),
    ]);
    opened = [];

    final settings = AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home/docs'));
    // Команды подменяются, а привязки остаются штатными: они ссылаются на
    // команды по идентификатору, поэтому подмена реализации их не касается.
    // Открытие системой подменяется записью в список: команды создаются
    // фабриками, поэтому подставить свою реализацию — это подставить фабрику.
    // Открытие системой подменяется модулем: службу объявляет тот, кто её
    // умеет, — а в тесте её умеет вот этот список.
    app =
        (await testApp(
          provider: provider,
          modules: [...featureModules(), _RecordingOpener(opened)],
          settings: settings,
        )).app;
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(802, 621);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: app));
    await app.start();
    await tester.pumpAndSettle();
  }

  /// Возвращает, взял ли каркас нажатие себе.
  ///
  /// `false` означает «ушло дальше, в систему»: именно этого ответа ждёт
  /// `Cmd+Q` и не должен дождаться `Escape`.
  Future<bool> press(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    List<LogicalKeyboardKey> modifiers = const [],
  }) async {
    for (final modifier in modifiers) {
      await tester.sendKeyDownEvent(modifier);
    }
    final handled = await tester.sendKeyEvent(key);
    for (final modifier in modifiers.reversed) {
      await tester.sendKeyUpEvent(modifier);
    }
    await tester.pumpAndSettle();
    // Даём сработать отложенной записи настроек, если команда её запланировала.
    await tester.pump(const Duration(milliseconds: 20));
    return handled;
  }

  group('курсор', () {
    testWidgets('стрелки двигают курсор', (tester) async {
      await pumpApp(tester);
      expect(app.left.cursorIndex, 0);

      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(app.left.cursorIndex, 1);

      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(app.left.cursorIndex, 0);
    });

    testWidgets('удержание стрелки повторяет нажатие', (tester) async {
      await pumpApp(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      expect(app.left.cursorIndex, 3);
    });

    testWidgets('Home и End прыгают к краям списка', (tester) async {
      await pumpApp(tester);

      await press(tester, LogicalKeyboardKey.end);
      expect(app.left.cursorIndex, app.left.entries.length - 1);

      await press(tester, LogicalKeyboardKey.home);
      expect(app.left.cursorIndex, 0);
    });

    testWidgets('стрелки влево и вправо тоже прыгают к краям', (tester) async {
      await pumpApp(tester);

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(app.left.cursorIndex, app.left.entries.length - 1);

      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(app.left.cursorIndex, 0);
    });

    testWidgets('PgDn сдвигает на страницу по числу видимых строк', (tester) async {
      await pumpApp(tester);
      // В каталоге меньше строк, чем помещается на экране: курсор упирается в конец.
      await press(tester, LogicalKeyboardKey.pageDown);

      expect(app.left.pageSize, greaterThan(1));
      expect(app.left.cursorIndex, app.left.entries.length - 1);
    });
  });

  group('переход к имени', () {
    testWidgets('буква ставит курсор на имя, которое с неё начинается', (tester) async {
      await pumpApp(tester);

      await press(tester, LogicalKeyboardKey.keyN);

      expect(app.left.currentEntry?.name, 'notes.txt');
    });

    testWidgets('разные буквы ведут к разным именам', (tester) async {
      await pumpApp(tester);

      await press(tester, LogicalKeyboardKey.keyD);
      expect(app.left.currentEntry?.name, 'docs');

      await press(tester, LogicalKeyboardKey.keyR);
      expect(app.left.currentEntry?.name, 'report.xlsx');
    });

    testWidgets('пробел по-прежнему помечает, а не ищет', (tester) async {
      await pumpApp(tester);
      app.left.setCursorToName('notes.txt');
      await tester.pump();

      await press(tester, LogicalKeyboardKey.space);

      expect(app.left.marked, contains('notes.txt'));
    });
  });

  group('панели', () {
    testWidgets('Tab переключает панель и не уводит фокус на кнопки', (tester) async {
      await pumpApp(tester);
      expect(app.activePanel, app.left);

      await press(tester, LogicalKeyboardKey.tab);
      expect(app.activePanel, app.right);

      await press(tester, LogicalKeyboardKey.tab);
      expect(app.activePanel, app.left);

      // Фокус остался у обработчика клавиатуры: кнопки его не перехватили.
      final focused = FocusManager.instance.primaryFocus;
      expect(focused?.context?.widget, isNot(isA<FunctionButton>()));
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(app.left.cursorIndex, 1);
    });
  });

  group('навигация по дереву', () {
    testWidgets('Enter входит в каталог', (tester) async {
      await pumpApp(tester);
      app.left.setCursorToName('bin');

      await press(tester, LogicalKeyboardKey.enter);

      expect(app.left.path, '/home/bin');
      expect(opened, isEmpty);
    });

    testWidgets('Enter на файле отдаёт его системе', (tester) async {
      await pumpApp(tester);
      app.left.setCursorToName('notes.txt');

      await press(tester, LogicalKeyboardKey.enter);

      expect(opened, ['/home/notes.txt']);
      expect(app.left.path, '/home');
    });

    testWidgets('файл из источника без настоящих путей системе не отдаётся', (tester) async {
      // Так выглядит файл внутри архива или на сервере: пути, который поймёт
      // внешняя программа, у него нет, и открывать его будет свой просмотрщик.
      provider.capabilities = readOnlyCapabilities;
      await pumpApp(tester);
      app.left.setCursorToName('notes.txt');

      await press(tester, LogicalKeyboardKey.enter);

      expect(opened, isEmpty);
      // Панель осталась на месте: войти в файл всё равно нельзя.
      expect(app.left.path, '/home');
    });

    testWidgets('Cmd-/ уводит в корень из любого каталога', (tester) async {
      await pumpApp(tester);
      expect(app.left.path, '/home');

      await press(tester, LogicalKeyboardKey.slash, modifiers: [commandKey]);

      expect(app.leftSession.directory, provider.rootDirectory);
    });

    testWidgets('Backspace поднимает наверх и ставит курсор на покинутый каталог', (tester) async {
      await pumpApp(tester);
      app.left.setCursorToName('docs');
      await press(tester, LogicalKeyboardKey.enter);
      expect(app.left.path, '/home/docs');

      await press(tester, LogicalKeyboardKey.backspace);

      expect(app.left.path, '/home');
      expect(app.left.currentEntry?.name, 'docs');
    });

    testWidgets('Enter на ".." эквивалентен Backspace', (tester) async {
      await pumpApp(tester);
      app.left.setCursorToName('docs');
      await press(tester, LogicalKeyboardKey.enter);

      app.left.setCursorToFirst();
      await press(tester, LogicalKeyboardKey.enter);

      expect(app.left.path, '/home');
    });

    testWidgets('Cmd-Shift-H показывает скрытые объекты', (tester) async {
      await pumpApp(tester);
      expect(app.left.entries.map((node) => node.name), isNot(contains('.hidden')));

      await press(tester, LogicalKeyboardKey.keyH, modifiers: const [commandKey, LogicalKeyboardKey.shiftLeft]);

      expect(app.left.showHidden, isTrue);
      expect(app.left.entries.map((node) => node.name), contains('.hidden'));

      await press(tester, LogicalKeyboardKey.keyH, modifiers: const [commandKey, LogicalKeyboardKey.shiftLeft]);

      expect(app.left.showHidden, isFalse);
      expect(app.left.entries.map((node) => node.name), isNot(contains('.hidden')));
    });
  });

  group('пометка', () {
    testWidgets('Space помечает объект и сдвигает курсор', (tester) async {
      await pumpApp(tester);
      app.left.setCursorToName('notes.txt');

      await press(tester, LogicalKeyboardKey.space);

      expect(app.left.marked, {'notes.txt'});
      expect(app.left.currentEntry?.name, 'report.xlsx');
    });

    testWidgets('Space на ".." ничего не помечает', (tester) async {
      await pumpApp(tester);
      app.left.setCursorToFirst();

      await press(tester, LogicalKeyboardKey.space);

      expect(app.left.marked.isEmpty, isTrue);
    });

    testWidgets('Esc снимает пометку', (tester) async {
      await pumpApp(tester);
      app.left.setCursorToName('notes.txt');
      await press(tester, LogicalKeyboardKey.space);

      await press(tester, LogicalKeyboardKey.escape);

      expect(app.left.marked.isEmpty, isTrue);
    });

    testWidgets('Cmd-A помечает всё, кроме ".."', (tester) async {
      await pumpApp(tester);

      await press(tester, LogicalKeyboardKey.keyA, modifiers: const [commandKey]);

      expect(app.left.marked.length, app.left.entries.length - 1);
      expect(app.left.marked, isNot(contains('..')));

      // Пометка каталогов запускает фоновый подсчёт их размера — даём ему
      // отработать, иначе тест закончится с недоделанной работой.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
    });

    testWidgets('Cmd-Shift-A помечает файлы, не трогая каталоги', (tester) async {
      await pumpApp(tester);

      await press(tester, LogicalKeyboardKey.keyA, modifiers: const [commandKey, LogicalKeyboardKey.shiftLeft]);

      final marked = app.left.marked;
      expect(marked, isNotEmpty);
      final directories = {
        for (final entry in app.left.entries)
          if (entry.isDirectory) entry.name,
      };
      expect(marked.intersection(directories), isEmpty, reason: 'каталоги остались нетронутыми');
      expect(app.left.marked, isNot(contains('..')));

      // Каталоги в списке есть — значит помечено не всё подряд.
      expect(directories, isNotEmpty);
      expect(marked.length, lessThan(app.left.entries.length - 1));
    });
  });

  group('нижняя панель', () {
    testWidgets('подписи берутся из реестра команд', (tester) async {
      await pumpApp(tester);

      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      final f5 = tester.widget<FunctionButton>(
        find.ancestor(of: find.text('Copy'), matching: find.byType(FunctionButton)),
      );
      expect(f5.number, 5);
      // Файловые операции ещё не реализованы: кнопка показана, но неактивна.
      expect(f5.enabled, isFalse);
    });

    testWidgets('команда, поставленная после запуска, появляется на кнопке', (tester) async {
      await pumpApp(tester);
      expect(find.text('Later'), findsNothing);

      // Так команду ставит модуль: приложение уже собрано и нарисовано.
      app.commands.install(() => PlaceholderCommand(id: 'test.later', label: 'Later'));
      app.commands.bind(KeyBinding('F10', 'test.later'));
      await tester.pump();

      final button = tester.widget<FunctionButton>(
        find.ancestor(of: find.text('Later'), matching: find.byType(FunctionButton)),
      );
      expect(button.number, 10);
    });
  });

  group('слой зажатого модификатора', () {
    /// Подпись на кнопке с этим номером.
    String labelOf(WidgetTester tester, int number) {
      final buttons = tester.widgetList<FunctionButton>(find.byType(FunctionButton));
      return buttons.firstWhere((button) => button.number == number).label;
    }

    FunctionButton buttonOf(WidgetTester tester, int number) =>
        tester.widgetList<FunctionButton>(find.byType(FunctionButton)).firstWhere((button) => button.number == number);

    /// Зажимает модификатор, не отпуская его.
    Future<void> hold(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(key);
      await tester.pumpAndSettle();
    }

    Future<void> release(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyUpEvent(key);
      await tester.pumpAndSettle();
    }

    testWidgets('пока зажат Shift, ряд показывает его слой', (tester) async {
      await pumpApp(tester);
      expect(labelOf(tester, 5), 'Copy');

      await hold(tester, LogicalKeyboardKey.shift);

      // За Shift-F5 и Shift-F7 стоят упаковщики, за Shift-F8 — удаление мимо
      // корзины. Всё это ставят модули, ряд о них не знает.
      expect(labelOf(tester, 5), 'Mk Zip');
      expect(labelOf(tester, 7), 'Mk 7z');
      expect(labelOf(tester, 8), isNot('Delete'));

      await release(tester, LogicalKeyboardKey.shift);
      expect(labelOf(tester, 5), 'Copy');
    });

    testWidgets('клавиша без команды в слое — прочерк и приглушена', (tester) async {
      await pumpApp(tester);
      expect(labelOf(tester, 1), 'Help');

      await hold(tester, LogicalKeyboardKey.shift);

      // Ряд говорит о том, что клавиша сделает сейчас: за Shift-F1 не стоит
      // ничего, и показывать «Help» значило бы врать.
      expect(labelOf(tester, 1), '-');
      expect(buttonOf(tester, 1).enabled, isFalse);
    });

    testWidgets('слой без единой привязки не показывается', (tester) async {
      await pumpApp(tester);
      expect(labelOf(tester, 5), 'Copy');

      // За Alt-Shift нет ни одной F-привязки: ряд из десяти прочерков ничего
      // не сообщает, а выглядит как поломка. Показывается базовый слой — и
      // именно базовый, а не слой Shift, который под ним же и зажат.
      await hold(tester, LogicalKeyboardKey.shift);
      expect(labelOf(tester, 5), 'Mk Zip');

      await hold(tester, LogicalKeyboardKey.alt);

      expect(labelOf(tester, 5), 'Copy');
      expect(labelOf(tester, 1), 'Help');

      await release(tester, LogicalKeyboardKey.alt);
      await release(tester, LogicalKeyboardKey.shift);
    });

    testWidgets('слой Alt показывает поиск', (tester) async {
      await pumpApp(tester);

      await hold(tester, LogicalKeyboardKey.alt);

      // `Alt-F7` — привычка Total Commander; ставит её модуль поиска.
      expect(labelOf(tester, 7), 'Find files');
      expect(labelOf(tester, 5), '-');

      await release(tester, LogicalKeyboardKey.alt);
      expect(labelOf(tester, 5), 'Copy');
    });

    testWidgets('слой командной клавиши показывает открытие пути', (tester) async {
      await pumpApp(tester);

      // `Cmd-F1` и `Cmd-F2` открывают путь в левой и правой панели; вне macOS
      // «командная» клавиша — Ctrl, во что `KeyCombination` её и сворачивает.
      await hold(tester, LogicalKeyboardKey.control);

      expect(labelOf(tester, 1), 'Address');
      expect(labelOf(tester, 2), 'Address');

      await release(tester, LogicalKeyboardKey.control);
      expect(labelOf(tester, 1), 'Help');
    });

    testWidgets('первая же привязка в слое показывает его целиком', (tester) async {
      await pumpApp(tester);
      await hold(tester, LogicalKeyboardKey.shift);
      await hold(tester, LogicalKeyboardKey.alt);
      expect(labelOf(tester, 5), 'Copy', reason: 'слоя ещё нет');

      // Модуль поставил команду на Alt-Shift-F9 — слой появился, и остальные
      // клавиши в нём честно пустые.
      app.commands
        ..install(() => _RecordingCommand(id: 'test.layered', label: 'Layered', runs: []))
        ..bind(KeyBinding('Alt-Shift-F9', 'test.layered'));
      await tester.pumpAndSettle();

      expect(labelOf(tester, 9), 'Layered');
      expect(labelOf(tester, 5), '-');

      await release(tester, LogicalKeyboardKey.alt);
      await release(tester, LogicalKeyboardKey.shift);
      expect(labelOf(tester, 5), 'Copy');
    });

    testWidgets('нажатие мышью в слое отправляет комбинацию слоя', (tester) async {
      await pumpApp(tester);

      // Две команды на одной клавише, в разных слоях: так видно, какую из них
      // отправила кнопка.
      final runs = <String>[];
      app.commands
        ..install(() => _RecordingCommand(id: 'test.plain', label: 'Plain', runs: runs))
        ..install(() => _RecordingCommand(id: 'test.layered', label: 'Layered', runs: runs))
        ..bind(KeyBinding('F9', 'test.plain'))
        ..bind(KeyBinding('Shift-F9', 'test.layered'));
      await tester.pump();

      await hold(tester, LogicalKeyboardKey.shift);
      expect(labelOf(tester, 9), 'Layered');

      await tester.tap(find.text('Layered'));
      await tester.pumpAndSettle();

      // Кнопка и клавиша не расходятся и во втором слое.
      expect(runs, ['test.layered']);
    });

    testWidgets('уход фокуса возвращает базовый слой', (tester) async {
      await pumpApp(tester);
      await hold(tester, LogicalKeyboardKey.shift);
      expect(labelOf(tester, 5), 'Mk Zip');

      // Отпускание случится уже в чужом окне и до нас не дойдёт — иначе ряд
      // остался бы в слое навсегда.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      expect(labelOf(tester, 5), 'Copy');
    });

    testWidgets('пока открыто окно команды, слой не показывается', (tester) async {
      await pumpApp(tester);
      app.commands.run(HelpCommand.commandId);
      await tester.pumpAndSettle();

      await hold(tester, LogicalKeyboardKey.shift);

      // Клавиши сейчас принадлежат окну, и обещать Shift-F5 нельзя. Заодно ряд
      // не мигает, когда Shift зажимают ради заглавной буквы в поле имени.
      expect(labelOf(tester, 5), 'Copy');
    });
  });

  group('клавиши не уходят мимо приложения', () {
    /// Граница «ушло наружу» — это ответ каркаса, а не виджет над приложением.
    ///
    /// Виджет-предок увидел бы событие раньше и дерева фокуса, и позднего
    /// перехвата `Escape`, то есть проверял бы не то. Каркас отвечает
    /// последним, и его «не обработано» — ровно то, что уходит в систему.
    Future<void> pumpApp(WidgetTester tester) async {
      tester.view.physicalSize = const Size(802, 621);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(FlexCommanderApp(controller: app));
      await app.start();
      await tester.pumpAndSettle();
    }

    testWidgets('клавиша без команды уходит дальше — к системе', (tester) async {
      // F10 ни за кем не закреплена. Съедать такое нельзя: `Cmd+Q`, `Cmd+W` и
      // прочие сочетания меню Flutter спрашивает у приложения раньше, чем
      // строку меню, и «обработано» их отменяет — приложение перестаёт
      // закрываться по Cmd+Q.
      await pumpApp(tester);

      expect(await press(tester, LogicalKeyboardKey.f10), isFalse);
    });

    testWidgets('клавиша с командой дальше не идёт', (tester) async {
      await pumpApp(tester);

      expect(await press(tester, LogicalKeyboardKey.f1), isTrue);
    });

    testWidgets('Escape приложение наружу не выпускает', (tester) async {
      // Отменять нечего, пометки нет — команда не выполнится. Но выпускать
      // Escape нельзя всё равно: AppKit понимает `Cmd+.` как «отменить» и
      // присылает Escape в ответ, а неразобранный Escape уходит к нему
      // обратно — и так по кругу, десятками тысяч событий подряд.
      //
      // Забирает его поздний перехват — после дерева фокуса, а не до: сначала
      // `Escape` принадлежит тому, кто на экране.
      await pumpApp(tester);

      expect(await press(tester, LogicalKeyboardKey.escape), isTrue);
    });

    testWidgets('пока открыто окно команды, клавиши принадлежат ему', (tester) async {
      await pumpApp(tester);
      app.commands.run(HelpCommand.commandId);
      await tester.pumpAndSettle();

      // F1 закреплена за справкой, но из-под чужого окна панели не отвечают:
      // событие должно уйти дальше — к самому окну, а не быть съеденным.
      expect(await press(tester, LogicalKeyboardKey.f1), isFalse);
    });
  });
}
