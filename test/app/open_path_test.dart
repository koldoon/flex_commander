import 'package:fc_api/fc_api.dart';
import 'package:fc_navigation/fc_navigation.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/view/dialogs/dialog_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Открытие произвольного пути и адреса.
///
/// SSH ещё нет, а механика уже есть — и проверяется на подставном источнике,
/// объявленном по схеме `mem`. Ровно так же встанет и настоящий: модуль
/// объявляет схему, панель встаёт на неё целиком.
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

  Future<AppRuntime> app({List<FcModule> extra = const []}) async {
    final local = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/docs'),
      FakeEntry.directory('/etc'),
      FakeEntry.file('/home/notes.txt', size: 10),
    ])..home = '/home';

    return testApp(
      provider: local,
      modules: [...featureModules(), ...extra],
      settings: AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home')),
    );
  }

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
      final command = runtime.commands.create(OpenPathCommand.commandId)!..setParam(OpenPathCommand.panelParam, 'left');

      expect(command.dialogTitle, 'Open path (left panel)');
      // Середина левой панели при разделителе посередине — четверть ширины.
      expect((command as OpenPathCommand).dialogArea, const DialogArea(end: 0.5));

      // Отложенной записи настроек даём сработать: таймер не должен пережить
      // тест.
      await tester.pump(const Duration(milliseconds: 20));
    });

    testWidgets('окно правой панели встаёт справа', (tester) async {
      final runtime = await app();
      await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
      await runtime.app.start();
      await tester.pumpAndSettle();

      final command =
          runtime.commands.create(OpenPathCommand.commandId)! as OpenPathCommand
            ..setParam(OpenPathCommand.panelParam, 'right');

      expect(command.dialogTitle, 'Open path (right panel)');
      expect(command.dialogArea, const DialogArea(start: 0.5));
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
        runtime.commands.run(OpenPathCommand.commandId, parameters: {OpenPathCommand.panelParam: entry.key});
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

      runtime.commands.run(OpenPathCommand.commandId, parameters: {OpenPathCommand.panelParam: 'left'});
      await tester.pumpAndSettle();

      expect(find.text('Open path (left panel)'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller?.text, '/home');
    });

    testWidgets('введённый путь открывается, и панель становится активной', (tester) async {
      final runtime = await app();
      await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
      await runtime.app.start();
      await tester.pumpAndSettle();

      runtime.app.activate(runtime.app.left);
      runtime.commands.run(OpenPathCommand.commandId, parameters: {OpenPathCommand.panelParam: 'right'});
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

      runtime.commands.run(OpenPathCommand.commandId, parameters: {OpenPathCommand.panelParam: 'left'});
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'ssh://user@host/srv');
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // «Путь не найден» тут врёт: путь-то мы даже не смотрели, потому что не
      // умеем такой протокол.
      // Строка попадает и в окно, и в статус панели — важно, что она эта.
      expect(find.textContaining('Not supported'), findsWidgets);
      expect(find.textContaining('Not found'), findsNothing);

      await tester.pump(const Duration(milliseconds: 20));
    });

    testWidgets('домашний каталог подставляется вместо тильды', (tester) async {
      final runtime = await app();
      await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
      await runtime.app.start();
      await tester.pumpAndSettle();

      runtime.commands.run(OpenPathCommand.commandId, parameters: {OpenPathCommand.panelParam: 'left'});
      await tester.pumpAndSettle();

      // `~` — это соглашение о записи пути, и знает о доме сам источник.
      await tester.enterText(find.byType(TextField), '~/docs');
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(runtime.app.left.directory?.pathString, '/home/docs');

      await tester.pump(const Duration(milliseconds: 20));
    });

    testWidgets('недоступный путь оставляет окно открытым', (tester) async {
      final runtime = await app();
      await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
      await runtime.app.start();
      await tester.pumpAndSettle();

      runtime.commands.run(OpenPathCommand.commandId, parameters: {OpenPathCommand.panelParam: 'left'});
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
    registry.addressProvider('mem', (address) async => factory(address));
  }
}
