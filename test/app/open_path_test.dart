import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_navigation/fc_navigation.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/view/dialogs/dialog_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Открытие произвольного пути и адреса.
///
/// Механика проверяется на подставном источнике, объявленном по схеме `mem`:
/// настоящий (`ssh`) стоит на ней же — модуль объявляет схему, панель встаёт
/// на неё целиком, — но тянуть в тест ядра сеть незачем.
void main() {
  /// Сколько раз открывали адрес и какие источники при этом создали.
  late List<Uri> opened;
  late List<InMemoryAddressProvider> created;

  /// Модуль с источником по адресу: `mem://имя/путь`.
  FcModule memoryAddresses() => _AddressModule((address) {
    opened.add(address);
    final provider = InMemoryAddressProvider(
      address: address,
      entries: [FakeEntry.directory('/srv'), FakeEntry.file('/srv/${address.host}.txt', size: 4)],
    );
    created.add(provider);
    return provider;
  });

  setUp(() {
    opened = [];
    created = [];
  });

  Future<AppRuntime> app({List<FcModule> extra = const [], String leftPath = '/home'}) async {
    final local = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/docs'),
      FakeEntry.directory('/etc'),
      FakeEntry.file('/home/notes.txt', size: 10),
    ])..home = '/home';

    return testApp(
      provider: local,
      modules: [...featureModules(), ...extra],
      settings: AppSettings(left: PanelSettings.defaults(leftPath), right: PanelSettings.defaults('/home')),
    );
  }

  group('запуск', () {
    test('сохранённый адрес соединения не поднимает', () async {
      final runtime = await app(extra: [memoryAddresses()], leftPath: 'mem://alpha/srv');

      await runtime.app.start();

      // Восстановление состояния в сеть не ходит: иначе каждый запуск начинался
      // бы с вопроса о пароле поверх пустых панелей, а недоступный сервер
      // задерживал бы его до истечения времени подключения.
      expect(opened, isEmpty);
      expect(runtime.app.left.directory?.pathString, '/home');
    });

    test('обычный сохранённый путь по-прежнему открывается', () async {
      final runtime = await app(extra: [memoryAddresses()], leftPath: '/home/docs');

      await runtime.app.start();

      expect(runtime.app.left.directory?.pathString, '/home/docs');
    });

    test('а руками адрес открывается сразу же', () async {
      final runtime = await app(extra: [memoryAddresses()], leftPath: 'mem://alpha/srv');
      await runtime.app.start();

      expect(await runtime.app.left.openPath('mem://alpha/srv'), isTrue);

      expect(opened.single.host, 'alpha');
      expect(runtime.app.left.nodes.map((node) => node.name), contains('alpha.txt'));
    });
  });

  group('панель на своём корне', () {
    test('адрес известной схемы поднимает свой источник', () async {
      final runtime = await app(extra: [memoryAddresses()]);
      await runtime.app.start();

      expect(await runtime.app.left.openPath('mem://alpha/srv'), isTrue);

      expect(opened.single.host, 'alpha');
      expect(runtime.app.left.nodes.map((node) => node.name), contains('alpha.txt'));
      // Вторая панель осталась там, где стояла: корень у каждой свой.
      expect(runtime.app.right.directory?.pathString, '/home');
    });

    test('путь без схемы возвращает панель на общий корень', () async {
      final runtime = await app(extra: [memoryAddresses()]);
      await runtime.app.start();
      await runtime.app.left.openPath('mem://alpha/srv');

      expect(await runtime.app.left.openPath('/etc'), isTrue);

      expect(runtime.app.left.directory?.pathString, '/etc');
      // Ушли с адреса — источник закрыт: соединение держать больше некому.
      expect(created.single.closed, isTrue);
    });

    test('другой адрес той же схемы — другое подключение', () async {
      final runtime = await app(extra: [memoryAddresses()]);
      await runtime.app.start();

      await runtime.app.left.openPath('mem://alpha/srv');
      await runtime.app.left.openPath('mem://beta/srv');

      expect(opened.map((address) => address.host), ['alpha', 'beta']);
      expect(created.first.closed, isTrue, reason: 'прежнее подключение закрыто');
      expect(created.last.closed, isFalse);
    });

    test('тот же адрес заново не подключается', () async {
      final runtime = await app(extra: [memoryAddresses()]);
      await runtime.app.start();

      await runtime.app.left.openPath('mem://alpha/srv');
      await runtime.app.left.openPath('mem://alpha/');

      expect(opened, hasLength(1), reason: 'второе подключение разошлось бы состоянием с первым');
      expect(created.single.closed, isFalse);
    });

    test('незнакомая схема — отказ, а не пустая панель', () async {
      final runtime = await app();
      await runtime.app.start();

      expect(await runtime.app.left.openPath('ftp://host/pub'), isFalse);
      expect(runtime.app.left.directory?.pathString, '/home', reason: 'панель осталась где была');
    });

    test('обе панели могут стоять на своих адресах', () async {
      final runtime = await app(extra: [memoryAddresses()]);
      await runtime.app.start();

      await runtime.app.left.openPath('mem://alpha/srv');
      await runtime.app.right.openPath('mem://beta/srv');

      expect(runtime.app.left.nodes.map((n) => n.name), contains('alpha.txt'));
      expect(runtime.app.right.nodes.map((n) => n.name), contains('beta.txt'));
      expect(created.every((provider) => !provider.closed), isTrue);
    });

    test('адрес переживает перезапуск', () async {
      final runtime = await app(extra: [memoryAddresses()]);
      await runtime.app.start();
      await runtime.app.left.openPath('mem://alpha/srv');

      // Панель сохраняет полный путь — вместе со схемой и хостом.
      expect(runtime.app.left.settings.path, startsWith('mem://alpha'));
    });
  });

  group('окно', () {
    testWidgets('Cmd-F1 открывает окно над левой панелью, даже когда активна правая', (tester) async {
      final runtime = await app();
      await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
      await runtime.app.start();
      await tester.pumpAndSettle();

      runtime.app.activate(runtime.app.right);
      final command = runtime.commands.find(OpenPathCommand.commandId)! as OpenPathCommand;
      // Панель называет вызов, а не активность: команда одна на обе клавиши.
      final context = CommandContext.of(
        runtime.app,
        const CommandInvocation(parameters: {OpenPathCommand.panelParam: 'left'}),
      );

      expect(command.titleOf(context), 'Open path (left panel)');
      // Середина левой панели при разделителе посередине — четверть ширины.
      expect(command.areaOf(context), const DialogArea(end: 0.5));

      // Отложенной записи настроек даём сработать: таймер не должен пережить
      // тест.
      await tester.pump(const Duration(milliseconds: 20));
    });

    testWidgets('окно правой панели встаёт справа', (tester) async {
      final runtime = await app();
      await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
      await runtime.app.start();
      await tester.pumpAndSettle();

      final command = runtime.commands.find(OpenPathCommand.commandId)! as OpenPathCommand;
      final context = CommandContext.of(
        runtime.app,
        const CommandInvocation(parameters: {OpenPathCommand.panelParam: 'right'}),
      );

      expect(command.titleOf(context), 'Open path (right panel)');
      expect(command.areaOf(context), const DialogArea(start: 0.5));
    });

    testWidgets('окно нарисовано над своей панелью, а не посередине экрана', (tester) async {
      final runtime = await app();
      tester.view.physicalSize = const Size(1000, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
      await runtime.app.start();
      await tester.pumpAndSettle();

      for (final entry in {'left': 250.0, 'right': 750.0}.entries) {
        runtime.commands.run(
          OpenPathCommand.commandId,
          CommandInvocation(parameters: {OpenPathCommand.panelParam: entry.key}),
        );
        await tester.pumpAndSettle();

        // Меряется само окно, а не рама: рама — это ещё и затемнение во весь
        // экран. Доля ширины задаёт середину окна, а не выравнивание по
        // свободному месту, и на широком экране разница видна.
        final dialog = tester.getRect(
          find.descendant(of: find.byType(DialogFrame), matching: find.byType(IntrinsicWidth)),
        );
        expect(dialog.center.dx, closeTo(entry.value, 1), reason: 'окно ${entry.key} панели');

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
      }

      await tester.pump(const Duration(milliseconds: 20));
    });

    testWidgets('поле заполнено текущим путём панели', (tester) async {
      final runtime = await app();
      await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
      await runtime.app.start();
      await tester.pumpAndSettle();

      runtime.commands.run(
        OpenPathCommand.commandId,
        CommandInvocation(parameters: {OpenPathCommand.panelParam: 'left'}),
      );
      await tester.pumpAndSettle();

      expect(find.text('Open path (left panel)'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller?.text, '/home');
    });

    testWidgets('на чужом источнике поле показывает протокол, а не «//alpha»', (tester) async {
      final runtime = await app(extra: [memoryAddresses()]);
      await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
      await runtime.app.start();
      expect(await runtime.app.left.openPath('mem://alpha/srv'), isTrue);
      await tester.pumpAndSettle();

      runtime.commands.run(
        OpenPathCommand.commandId,
        CommandInvocation(parameters: {OpenPathCommand.panelParam: 'left'}),
      );
      await tester.pumpAndSettle();

      // Человек правит то, что видит в заголовке панели. `//alpha/srv` там
      // было бы ни адресом, ни путём.
      final shown = tester.widget<TextField>(find.byType(TextField)).controller?.text;
      expect(shown, 'mem://alpha/srv');

      // И эта же строка обязана открыться обратно.
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(runtime.app.left.directory?.displayPath, 'mem://alpha/srv');
      await tester.pump(const Duration(milliseconds: 20));
    });

    testWidgets('введённый путь открывается, и панель становится активной', (tester) async {
      final runtime = await app();
      await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
      await runtime.app.start();
      await tester.pumpAndSettle();

      runtime.app.activate(runtime.app.left);
      runtime.commands.run(
        OpenPathCommand.commandId,
        CommandInvocation(parameters: {OpenPathCommand.panelParam: 'right'}),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '/etc');
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(runtime.app.right.directory?.pathString, '/etc');
      expect(runtime.app.activePanel, runtime.app.right, reason: 'пользователь смотрит туда, куда пришёл');
      expect(find.text('Open path (right panel)'), findsNothing);

      await tester.pump(const Duration(milliseconds: 20));
    });

    testWidgets('незнакомый протокол называет себя, а не «путь не найден»', (tester) async {
      final runtime = await app();
      await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
      await runtime.app.start();
      await tester.pumpAndSettle();

      runtime.commands.run(
        OpenPathCommand.commandId,
        CommandInvocation(parameters: {OpenPathCommand.panelParam: 'left'}),
      );
      await tester.pumpAndSettle();

      // Протокол, которого в приложении действительно нет: `ssh` с недавних
      // пор умеет свой модуль, и на нём эта проверка проверяла бы уже не то.
      await tester.enterText(find.byType(TextField), 'ftp://user@host/srv');
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // «Путь не найден» тут врёт: путь-то мы даже не смотрели, потому что не
      // умеем такой протокол.
      expect(find.textContaining('Protocol ftp is not supported'), findsWidgets);
      expect(find.textContaining('Not found'), findsNothing);

      await tester.pump(const Duration(milliseconds: 20));
    });

    testWidgets('домашний каталог подставляется вместо тильды', (tester) async {
      final runtime = await app();
      await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
      await runtime.app.start();
      await tester.pumpAndSettle();

      runtime.commands.run(
        OpenPathCommand.commandId,
        CommandInvocation(parameters: {OpenPathCommand.panelParam: 'left'}),
      );
      await tester.pumpAndSettle();

      // `~` — это соглашение о записи пути, и знает о доме сам источник.
      await tester.enterText(find.byType(TextField), '~/docs');
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(runtime.app.left.directory?.pathString, '/home/docs');

      await tester.pump(const Duration(milliseconds: 20));
    });

    testWidgets('на неудаче панель показывает прежнее содержимое', (tester) async {
      final runtime = await app();
      // Размер как у остальных проверок вида: на умолчании строки не влезают.
      tester.view.physicalSize = const Size(802, 621);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
      await runtime.app.start();
      await tester.pumpAndSettle();

      final before = runtime.app.left.nodes.map((node) => node.name).toList();
      expect(before, isNotEmpty);

      runtime.commands.run(
        OpenPathCommand.commandId,
        CommandInvocation(parameters: {OpenPathCommand.panelParam: 'left'}),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Blah');
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Панель меняется только после успешного открытия: за опечатку не
      // наказывают потерей того, на что человек смотрел.
      expect(runtime.app.left.nodes.map((node) => node.name), before);
      expect(runtime.app.left.status, PanelStatus.idle);
      // Имя в таблице разложено по колонкам, поэтому ищется каталог: у него
      // расширения нет.
      expect(find.text('docs'), findsWidgets, reason: 'список файлов на месте');

      await tester.pump(const Duration(milliseconds: 20));
    });

    testWidgets('на что похож ввод, о том и ошибка', (tester) async {
      final runtime = await app(extra: [memoryAddresses()]);
      await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
      await runtime.app.start();
      await tester.pumpAndSettle();

      // Ввод → что должно быть сказано.
      const answers = {
        'Blah': 'Wrong URI',
        'ftp://user@host/srv': 'Protocol ftp is not supported',
        '/такого/нет': 'Not found',
        'mem://alpha/нет-такого': 'Not found',
      };

      for (final entry in answers.entries) {
        runtime.commands.run(
          OpenPathCommand.commandId,
          CommandInvocation(parameters: {OpenPathCommand.panelParam: 'left'}),
        );
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), entry.key);
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.textContaining(entry.value), findsWidgets, reason: 'на «${entry.key}»');

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
      }

      await tester.pump(const Duration(milliseconds: 20));
    });

    testWidgets('недоступный путь оставляет окно открытым', (tester) async {
      final runtime = await app();
      await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
      await runtime.app.start();
      await tester.pumpAndSettle();

      runtime.commands.run(
        OpenPathCommand.commandId,
        CommandInvocation(parameters: {OpenPathCommand.panelParam: 'left'}),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '/такого/нет');
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Путь правится тут же: окно осталось и говорит, что не так.
      expect(find.text('Open path (left panel)'), findsOneWidget);
      expect(find.textContaining('Not found'), findsOneWidget);
      expect(runtime.app.left.directory?.pathString, '/home');

      await tester.pump(const Duration(milliseconds: 20));
    });
  });

  group('окно во время работы', () {
    /// Подключение, которое само не кончается: тест держит его открытым ровно
    /// столько, сколько нужно, чтобы посмотреть на окно.
    late Completer<void> gate;

    setUp(() => gate = Completer<void>());

    tearDown(() {
      // Тело операции стоит на этом ожидании — отпустить его надо и после
      // отмены, иначе оно переживёт сам тест.
      if (!gate.isCompleted) {
        gate.complete();
      }
    });

    /// Собранное приложение с начатым, но не законченным подключением.
    Future<AppRuntime> connecting(WidgetTester tester) async {
      final runtime = await app(extra: [_SlowAddressModule(gate: gate, opened: opened)]);
      await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
      await runtime.app.start();
      await tester.pumpAndSettle();

      runtime.commands.run(
        OpenPathCommand.commandId,
        CommandInvocation(parameters: {OpenPathCommand.panelParam: 'left'}),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'slow://alpha/srv');
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      return runtime;
    }

    testWidgets('окно рассказывает, чем занята панель', (tester) async {
      await connecting(tester);

      // Строку состояния панели закрывает затенение окна, поэтому веха
      // показывается в самом окне — и это веха источника, а не общее «Loading…».
      expect(find.text('Status'), findsOneWidget);
      // Именно в окне: в строке состояния панели эта же веха есть и сейчас, но
      // её закрывает затенение — с неё вся работа и началась.
      expect(
        find.descendant(of: find.byType(DialogFrame), matching: find.text('Connecting to slow://alpha…')),
        findsOneWidget,
      );
      // Работа уже идёт: подтверждать нечего.
      expect(tester.widget<FcButton>(find.widgetWithText(FcButton, 'Open')).onPressed, isNull);
    });

    testWidgets('Esc прерывает работу, но окна не закрывает', (tester) async {
      final runtime = await connecting(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      // Прервали, но не ушли: набранный адрес на месте, и его можно поправить.
      expect(find.text('Open path (left panel)'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller?.text, 'slow://alpha/srv');
      // Отмена — не отказ: «Not found» здесь был бы враньём.
      expect(find.textContaining('Not found'), findsNothing);
      expect(find.text('Status'), findsNothing, reason: 'работа кончилась — говорить не о чем');
      expect(runtime.app.left.directory?.pathString, '/home', reason: 'панель осталась где была');
      expect(runtime.app.left.busy, isFalse);

      // А второй Esc закрывает: прерывать больше нечего.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Open path (left panel)'), findsNothing);

      await tester.pump(const Duration(milliseconds: 20));
    });

    testWidgets('кнопка «Cancel» во время работы делает то же самое', (tester) async {
      final runtime = await connecting(tester);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Open path (left panel)'), findsOneWidget);
      expect(runtime.app.left.directory?.pathString, '/home');
      expect(runtime.app.left.busy, isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 20));
    });

    testWidgets('Enter во время работы не начинает вторую попытку', (tester) async {
      await connecting(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(opened, hasLength(1), reason: 'подключение уже идёт — второе к тому же адресу лишнее');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 20));
    });
  });
}

/// Модуль, объявляющий источник по схеме `mem`.
class _AddressModule implements FcModule {
  const _AddressModule(this.factory);

  final TreeProvider Function(Uri address) factory;

  @override
  String get id => 'test.addresses';

  @override
  String get title => 'Memory addresses';

  @override
  void install(FcRegistry registry) {
    registry.addressProvider('mem', (address) => TaskOperation<TreeProvider>((op) async => factory(address)));
  }
}

/// Модуль с источником, подключение к которому длится, пока его держит тест.
///
/// Настоящее подключение — это секунды ожидания, а с недоступным сервером и
/// минуты; `Completer` даёт ровно это, не заводя в тесте ни сети, ни таймеров.
class _SlowAddressModule implements FcModule {
  const _SlowAddressModule({required this.gate, required this.opened});

  final Completer<void> gate;

  /// Куда ходили: по длине списка видно, не начали ли вторую попытку.
  final List<Uri> opened;

  @override
  String get id => 'test.slow';

  @override
  String get title => 'Slow addresses';

  @override
  void install(FcRegistry registry) {
    registry.addressProvider(
      'slow',
      (address) => TaskOperation<TreeProvider>((op) async {
        opened.add(address);
        // Веху формулирует тот, кто работает: панель о рукопожатии не знает.
        op.message('Connecting to slow://${address.host}…');
        await gate.future;
        op.checkCanceled();
        return InMemoryAddressProvider(address: address, entries: [FakeEntry.directory('/srv')]);
      }),
    );
  }
}
