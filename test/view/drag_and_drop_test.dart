import 'dart:convert';
import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_panels/fc_panels.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/modules/dnd/system_drag_and_drop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Перетаскивание файлов мышью — в обе стороны.
///
/// Нативной части здесь нет — она в раннере, — но весь путь после неё
/// настоящий: событие приходит тем же каналом и теми же значениями, что шлёт
/// `MainFlutterWindow`, и дальше работают те же приёмник, панель и команда
/// копирования.
late AppRuntime runtime;
late InMemoryTreeProvider provider;

Application get app => runtime.app;

void main() {
  setUp(() async {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/docs'),
      FakeEntry.file('/home/note.txt', size: 4),
      FakeEntry.directory('/outside'),
      FakeEntry.file('/outside/dropped.txt', size: 7),
    ])..home = '/home';
    runtime = await testApp(provider: provider, modules: featureModules());
    await runtime.app.start();
  });

  /// То же, что шлёт раннер: имя события, точка в логических координатах и
  /// пути.
  Future<void> sendDrop(
    WidgetTester tester,
    String event, {
    Offset? at,
    List<String> paths = const [],
    bool moves = false,
  }) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      SystemDropService.channelName,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall(event, at == null ? null : {'x': at.dx, 'y': at.dy, 'paths': paths, 'move': moves}),
      ),
      (_) {},
    );
    await tester.pumpAndSettle();
  }

  /// Точка в середине строки с таким именем — в левой панели.
  Offset rowCenter(WidgetTester tester, String name) {
    final table = tester.getRect(find.byType(FileTable).first);
    final metrics = FcTheme.of(tester.element(find.byType(FileTable).first)).metrics;
    final index = runtime.app.left.nodes.indexWhere((node) => node.name == name);
    expect(index, isNonNegative, reason: 'в панели нет строки «$name»');
    return Offset(
      table.left + table.width / 2,
      table.top + metrics.headerRowHeight + index * metrics.rowHeight + metrics.rowHeight / 2,
    );
  }

  /// Подтверждает окно работы — то самое, что открывается по `F5` и `F6`.
  ///
  /// Жест не начинает работу сам: он говорит, что и куда, а «поехали» говорит
  /// человек — успев при этом поменять приёмник или включить проход по ссылкам.
  Future<void> startWork(WidgetTester tester, String button) async {
    expect(find.widgetWithText(FcButton, button), findsOneWidget, reason: 'бросок должен открыть окно работы');
    await tester.tap(find.widgetWithText(FcButton, button));
    await tester.pumpAndSettle();
  }

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(802, 621);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();
  }

  testWidgets('брошенное на строку-каталог копируется в неё', (tester) async {
    await pumpApp(tester);

    final target = rowCenter(tester, 'docs');
    await sendDrop(tester, 'dragEntered', at: target, paths: const ['/outside/dropped.txt']);
    await sendDrop(tester, 'drop', at: target, paths: const ['/outside/dropped.txt']);
    await startWork(tester, 'Copy');

    expect(provider.entryAt('/home/docs/dropped.txt'), isNotNull, reason: 'файл должен лечь в каталог под курсором');
    // Копия, а не перенос: из Finder объекты не исчезают.
    expect(provider.entryAt('/outside/dropped.txt'), isNotNull);
  });

  testWidgets('бросок открывает окно работы и сам её не начинает', (tester) async {
    // Найдено на живом: работа шла, панель обновлялась, а окна не было вовсе —
    // приёмник, заданный параметром, уводил команду мимо него. Для сценария
    // это верно, для жеста нет: человек начал работу сам и вправе видеть ход,
    // вопросы и отмену.
    await pumpApp(tester);

    final target = rowCenter(tester, 'docs');
    await sendDrop(tester, 'drop', at: target, paths: const ['/outside/dropped.txt']);

    // Окно открылось, приёмник в нём — тот, куда бросили, а работа стоит и
    // ждёт человека: он ещё может поменять приёмник или включить ссылки.
    expect(find.widgetWithText(FcButton, 'Copy'), findsOneWidget);
    expect(find.text('/home/docs'), findsWidgets);
    expect(provider.entryAt('/home/docs/dropped.txt'), isNull, reason: 'сама работа не начинается');

    await startWork(tester, 'Copy');
    expect(provider.entryAt('/home/docs/dropped.txt'), isNotNull);
  });

  testWidgets('брошенное мимо строк копируется в каталог панели', (tester) async {
    await pumpApp(tester);

    final table = tester.getRect(find.byType(FileTable).first);
    final empty = Offset(table.left + table.width / 2, table.bottom - 4);
    await sendDrop(tester, 'drop', at: empty, paths: const ['/outside/dropped.txt']);
    await startWork(tester, 'Copy');

    expect(provider.entryAt('/home/dropped.txt'), isNotNull);
  });

  testWidgets('бросок в панель делает её активной', (tester) async {
    await pumpApp(tester);

    app.activate(app.right);
    final table = tester.getRect(find.byType(FileTable).first);
    await sendDrop(
      tester,
      'drop',
      at: Offset(table.left + table.width / 2, table.bottom - 4),
      paths: const ['/outside/dropped.txt'],
    );
    await tester.pumpAndSettle();

    expect(app.left.active, isTrue, reason: 'работа идёт в ту панель, в которую бросили — её и видно активной');
  });

  group('наружу', () {
    late List<MethodCall> asked;

    setUp(() {
      asked = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(SystemDropService.channelName),
        (call) async {
          asked.add(call);
          return true;
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(SystemDropService.channelName),
        null,
      );
    });

    /// Тянет за строку так, как это делает мышь: нажали и повели.
    Future<void> dragRow(WidgetTester tester, String name) async {
      final gesture = await tester.startGesture(
        rowCenter(tester, name),
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryMouseButton,
      );
      await gesture.moveBy(const Offset(24, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
    }

    testWidgets('строку тащат наружу настоящим путём', (tester) async {
      await pumpApp(tester);
      await dragRow(tester, 'note.txt');

      expect(asked.map((call) => call.method), ['beginDrag']);
      expect((asked.single.arguments as Map)['paths'], ['/home/note.txt']);
    });

    testWidgets('тянут помеченное — едет вся пометка', (tester) async {
      await pumpApp(tester);
      app.left.setCursorToName('note.txt');
      app.left.selection.toggle(app.left.currentNode!);
      app.left.setCursorToName('docs');
      app.left.selection.toggle(app.left.currentNode!);
      await tester.pumpAndSettle();

      await dragRow(tester, 'note.txt');

      expect((asked.single.arguments as Map)['paths'], containsAll(<String>['/home/note.txt', '/home/docs']));
    });

    testWidgets('после неудачного броска тянется снова, не отпуская кнопки', (tester) async {
      // Найдено на живом. Как только система начинает перетаскивание, мышь
      // переходит к ней, и отпускания кнопки Flutter не видит: он считает её
      // нажатой и дальше, а следующее настоящее нажатие приходит к нам уже
      // движением. Пока источник ждал именно нажатия, потянуть второй раз было
      // нельзя — приходилось отпускать кнопку и брать заново.
      await pumpApp(tester);

      final gesture = await tester.startGesture(
        rowCenter(tester, 'note.txt'),
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryMouseButton,
      );
      await gesture.moveBy(const Offset(24, 0));
      await tester.pumpAndSettle();
      expect(asked.length, 1);

      // Сессия кончилась — бросили мимо, работы не вышло. Об этом сообщает
      // раннер; отпускания кнопки при этом никто не видел.
      await sendDrop(tester, 'dragEnded');

      await gesture.moveBy(const Offset(24, 0));
      await tester.pumpAndSettle();
      await gesture.moveBy(const Offset(24, 0));
      await tester.pumpAndSettle();

      expect(asked.length, 2, reason: 'вторая попытка — в том же нажатии, без отпускания кнопки');
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('система отказала — следующее движение пробует снова', (tester) async {
      // Найдено на живом: перетаскивание начиналось через раз. Одна неудача
      // убивала всё нажатие целиком, и тащить приходилось, отпустив и взяв
      // заново.
      var answers = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(SystemDropService.channelName),
        (call) async {
          asked.add(call);
          answers += 1;
          return answers > 1;
        },
      );

      await pumpApp(tester);
      final gesture = await tester.startGesture(
        rowCenter(tester, 'note.txt'),
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryMouseButton,
      );
      // Первая попытка — и отказ. Отсчёт после него начинается заново, поэтому
      // движений нужно два: одно задаёт начало, второе выходит за порог.
      await gesture.moveBy(const Offset(24, 0));
      await tester.pumpAndSettle();
      await gesture.moveBy(const Offset(4, 0));
      await tester.pumpAndSettle();
      await gesture.moveBy(const Offset(24, 0));
      await tester.pumpAndSettle();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(asked.length, 2, reason: 'вторая попытка — в том же нажатии');
    });

    testWidgets('за «..» не тянут', (tester) async {
      await pumpApp(tester);
      await dragRow(tester, '..');

      expect(asked, isEmpty, reason: '«..» — не объект');
    });

    testWidgets('щелчок без движения перетаскивания не начинает', (tester) async {
      await pumpApp(tester);
      await tester.tapAt(rowCenter(tester, 'note.txt'));
      await tester.pumpAndSettle();

      expect(asked, isEmpty);
    });
  });

  testWidgets('с Shift — перенос, а не копия', (tester) async {
    await app.right.openPath('/home/docs');
    await pumpApp(tester);

    final right = tester.getRect(find.byType(FileTable).at(1));
    final into = Offset(right.left + right.width / 2, right.bottom - 4);
    // Признак приносит система: она же спрашивает у источника, позволено ли
    // ему расставаться с объектами, и рисует у курсора стрелку вместо плюса.
    await sendDrop(tester, 'drop', at: into, paths: const ['/outside/dropped.txt'], moves: true);
    // Окно то же самое, только за ним команда переноса, а не копирования.
    await startWork(tester, 'Move');

    expect(provider.entryAt('/home/docs/dropped.txt'), isNotNull, reason: 'объект на новом месте');
    expect(provider.entryAt('/outside/dropped.txt'), isNull, reason: 'и его больше нет на старом');
  });

  group('в свою же панель не бросают', () {
    setUp(() {
      // Система отвечает «перетаскивание началось» — с этого мгновения служба
      // знает, откуда тащат.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(SystemDropService.channelName),
        (call) async => true,
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(SystemDropService.channelName),
        null,
      );
    });

    /// Тянет строку левой панели и ведёт указатель в заданную точку.
    Future<void> dragFromLeft(WidgetTester tester, String name, Offset to) async {
      final gesture = await tester.startGesture(
        rowCenter(tester, name),
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryMouseButton,
      );
      await gesture.moveBy(const Offset(24, 0));
      await tester.pumpAndSettle();
      // Дальше мышь у системы, и события приходят каналом — как из раннера.
      await sendDrop(tester, 'dragUpdated', at: to, paths: const ['/home/note.txt']);
      await gesture.cancel();
    }

    testWidgets('панель-источник не подсвечивается и не принимает', (tester) async {
      await pumpApp(tester);
      final table = tester.getRect(find.byType(FileTable).first);
      final inside = Offset(table.left + table.width / 2, table.bottom - 4);

      await dragFromLeft(tester, 'note.txt', inside);
      await sendDrop(tester, 'drop', at: inside, paths: const ['/home/note.txt']);

      expect(
        provider.entryAt('/home/note.txt'),
        isNotNull,
        reason: 'файл на месте — но копии в той же панели быть не должно',
      );
      expect(app.left.nodes.where((node) => node.name.contains('note')).length, 1);
    });

    testWidgets('в соседнюю панель — принимает', (tester) async {
      await app.right.openPath('/home/docs');
      await pumpApp(tester);

      final right = tester.getRect(find.byType(FileTable).at(1));
      final into = Offset(right.left + right.width / 2, right.bottom - 4);
      await dragFromLeft(tester, 'note.txt', into);
      await sendDrop(tester, 'drop', at: into, paths: const ['/home/note.txt']);
      await startWork(tester, 'Copy');

      expect(provider.entryAt('/home/docs/note.txt'), isNotNull);
    });

    testWidgets('с настройкой принимает и в свою — в каталог под курсором', (tester) async {
      // Ради этого её и включают: перетащить в подкаталог, не уходя из панели.
      app.moduleSettings('fc.dnd').section(DragAndDropSettings.new).dropIntoSamePanel = true;
      await pumpApp(tester);

      final onDocs = rowCenter(tester, 'docs');
      await dragFromLeft(tester, 'note.txt', onDocs);
      await sendDrop(tester, 'drop', at: onDocs, paths: const ['/home/note.txt']);
      await startWork(tester, 'Copy');

      expect(provider.entryAt('/home/docs/note.txt'), isNotNull);
    });
  });

  testWidgets('брошенное в панель на чужом источнике находится по месту, а не у неё', (tester) async {
    // Поймано на живом: файл из Finder, брошенный в архив на сервере, ронял
    // работу. Путь-источник разбирала панель-приёмник — а она стоит на
    // сервере, и `/home/note.txt` искался **там**.
    final server = InMemoryContentProvider([FakeEntry.directory('/srv')])..home = '/srv';
    server.capabilities = const ProviderCapabilities(canRename: true, maxConcurrency: 1);

    final split = await testApp(
      // Содержимое у источника настоящее: копирование между провайдерами идёт
      // байтами, и провайдер без них не источник вовсе.
      provider: InMemoryContentProvider([
        FakeEntry.directory('/home'),
        FakeEntry.file('/home/note.txt', content: utf8.encode('заметки')),
      ])..home = '/home',
      rightProvider: server,
      modules: featureModules(),
    );
    await split.app.start();

    tester.view.physicalSize = const Size(802, 621);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(FlexCommanderApp(controller: split.app));
    await tester.pumpAndSettle();

    final right = tester.getRect(find.byType(FileTable).at(1));
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      SystemDropService.channelName,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('drop', {
          'x': right.left + right.width / 2,
          'y': right.bottom - 4,
          'paths': const ['/home/note.txt'],
          'move': false,
        }),
      ),
      (_) {},
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FcButton, 'Copy'), findsOneWidget, reason: 'бросок открыл окно работы');
    await tester.tap(find.widgetWithText(FcButton, 'Copy'));
    await tester.pumpAndSettle();

    expect(server.entryAt('/srv/note.txt'), isNotNull, reason: 'источник ищется там, где он есть');
  });

  group('обещанное', () {
    late List<MethodCall> asked;
    late AppRuntime archive;

    setUp(() async {
      asked = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(SystemDropService.channelName),
        (call) async {
          asked.add(call);
          return true;
        },
      );

      // Источник без настоящих путей — как архив или сервер: содержимое есть,
      // а показать системе нечего.
      final inside = InMemoryContentProvider([
        FakeEntry.directory('/home'),
        FakeEntry.file('/home/inside.txt', content: utf8.encode('из архива')),
      ])..home = '/home';
      inside.capabilities = archiveCapabilities;
      archive = await testApp(provider: inside, modules: featureModules());
      await archive.app.start();
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(SystemDropService.channelName),
        null,
      );
    });

    Future<void> pumpArchive(WidgetTester tester) async {
      tester.view.physicalSize = const Size(802, 621);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(FlexCommanderApp(controller: archive.app));
      await tester.pumpAndSettle();
    }

    /// Тянет строку архива — до того мгновения, когда система просит содержимое.
    Future<void> dragOut(WidgetTester tester, String name) async {
      final table = tester.getRect(find.byType(FileTable).first);
      final metrics = FcTheme.of(tester.element(find.byType(FileTable).first)).metrics;
      final index = archive.app.left.nodes.indexWhere((node) => node.name == name);
      final row = Offset(
        table.left + table.width / 2,
        table.top + metrics.headerRowHeight + index * metrics.rowHeight + metrics.rowHeight / 2,
      );
      final gesture = await tester.startGesture(row, kind: PointerDeviceKind.mouse, buttons: kPrimaryMouseButton);
      await gesture.moveBy(const Offset(24, 0));
      await tester.pumpAndSettle();
      await gesture.up();
      await tester.pumpAndSettle();
    }

    /// Просьба системы выложить обещанное — тем же каналом и с тем же путём
    /// назначения, какой даёт приёмник.
    Future<bool> askPromise(WidgetTester tester, String id, String into) async {
      var written = false;
      await tester.runAsync(() async {
        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
          SystemDropService.channelName,
          const StandardMethodCodec().encodeMethodCall(MethodCall('writePromise', {'id': id, 'path': into})),
          (reply) => written = const StandardMethodCodec().decodeEnvelope(reply!) == true,
        );
      });
      return written;
    }

    /// Куда «приёмник» просит положить: у Finder это папка броска, у редактора
    /// — свой временный каталог. Нам всё равно, и тесту тоже.
    String destination(String name) {
      final directory = Directory.systemTemp.createTempSync('fc_drag_test');
      addTearDown(() => directory.deleteSync(recursive: true));
      return '${directory.path}/$name';
    }

    Future<void> endSession(WidgetTester tester) async {
      await tester.runAsync(() async {
        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
          SystemDropService.channelName,
          const StandardMethodCodec().encodeMethodCall(const MethodCall('dragEnded')),
          (_) {},
        );
      });
    }

    testWidgets('файл без настоящего пути уходит обещанием, а не путём', (tester) async {
      await pumpArchive(tester);
      await dragOut(tester, 'inside.txt');

      final arguments = asked.single.arguments as Map;
      expect(arguments['paths'], isEmpty, reason: 'настоящего пути у него нет');
      final promises = arguments['promises'] as List;
      expect(promises, hasLength(1));
      expect((promises.single as Map)['name'], 'inside.txt');
    });

    testWidgets('обещанное пишется сразу в цель, без копии по дороге', (tester) async {
      await pumpArchive(tester);
      await dragOut(tester, 'inside.txt');

      final into = destination('inside.txt');
      expect(await askPromise(tester, 'inside.txt', into), isTrue);
      expect(File(into).readAsStringSync(), 'из архива');
    });

    testWidgets('аренда источника живёт до чтения, а не до конца жеста', (tester) async {
      // Пока обещанное не прочитано, архив обязан оставаться смонтированным —
      // даже если жест давно кончился, а человек успел из архива выйти. Ради
      // этого случая аренда и берётся: панельная тут не спасёт, она уходит
      // вместе с панелью.
      await pumpArchive(tester);
      final service = archive.app.dragAndDrop! as SystemDropService;
      final lease = _CountingLease(archive.app.left.provider);
      final node = archive.app.left.nodes.firstWhere((n) => n.name == 'inside.txt');

      await tester.runAsync(() async {
        await service.beginDrag(archive.app.left, [node], hold: () => lease);
      });

      await endSession(tester);
      expect(lease.released, isFalse, reason: 'содержимое ещё не спрашивали');

      expect(await askPromise(tester, 'inside.txt', destination('inside.txt')), isTrue);
      expect(lease.released, isTrue, reason: 'прочитали — держать больше незачем');
    });

    testWidgets('содержимое выкладывается и после конца сессии', (tester) async {
      // Найдено на живом: работало примерно раз из десяти. Система просит
      // обещанное **после** того, как сессия кончилась, — порядок этих двух
      // событий ничем не закреплён, — а уборка по концу сессии успевала
      // забыть, что мы вообще обещали.
      await pumpArchive(tester);
      await dragOut(tester, 'inside.txt');
      await endSession(tester);

      final into = destination('inside.txt');
      expect(await askPromise(tester, 'inside.txt', into), isTrue, reason: 'обещанное должно пережить конец сессии');
      expect(File(into).readAsStringSync(), 'из архива');
    });

    testWidgets('до просьбы не читается ничего', (tester) async {
      await pumpArchive(tester);
      await dragOut(tester, 'inside.txt');

      final into = destination('inside.txt');
      expect(File(into).existsSync(), isFalse, reason: 'никто ещё не просил — и читать незачем');

      expect(await askPromise(tester, 'inside.txt', into), isTrue);
      expect(File(into).existsSync(), isTrue);
    });
  });

  testWidgets('подсветка приёмника не трогает прокрутку', (tester) async {
    // Найдено на живом: стоило потащить файл наружу, как панель перематывалась
    // к началу списка. Указатель по дороге проходит над своим же окном и
    // зажигает подсветку, а та меняла строение дерева — список пересобирался
    // заново и терял прокрутку вместе с положением.
    final long = await testApp(
      provider: InMemoryTreeProvider([
        FakeEntry.directory('/home'),
        for (var i = 0; i < 60; i++) FakeEntry.file('/home/file-$i.txt', size: 10),
      ])..home = '/home',
      modules: featureModules(),
    );
    await long.app.start();

    tester.view.physicalSize = const Size(802, 621);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(FlexCommanderApp(controller: long.app));
    await tester.pumpAndSettle();

    long.app.left.setCursorIndex(55);
    await tester.pumpAndSettle();

    final scrollable = find.descendant(of: find.byType(FileTable).first, matching: find.byType(Scrollable)).first;
    final scrolled = tester.state<ScrollableState>(scrollable).position.pixels;
    expect(scrolled, greaterThan(0), reason: 'список должен быть прокручен, иначе проверять нечего');

    final table = tester.getRect(find.byType(FileTable).first);
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      SystemDropService.channelName,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('dragEntered', {
          'x': table.left + table.width / 2,
          'y': table.top + table.height / 2,
          'paths': const <String>['/home/file-1.txt'],
        }),
      ),
      (_) {},
    );
    await tester.pumpAndSettle();

    expect(tester.state<ScrollableState>(scrollable).position.pixels, scrolled);
  });

  testWidgets('без модуля перетаскивания панели работают как раньше', (tester) async {
    final plain = await testApp(
      provider: InMemoryTreeProvider([FakeEntry.directory('/home'), FakeEntry.file('/home/note.txt', size: 4)])
        ..home = '/home',
      modules: [
        for (final module in featureModules())
          if (module.id != 'fc.dnd') module,
      ],
    );
    await plain.app.start();

    await tester.pumpWidget(FlexCommanderApp(controller: plain.app));
    await tester.pumpAndSettle();

    expect(plain.app.dragAndDrop, isNull);
    expect(find.byType(FileTable), findsWidgets);
  });
}

/// Аренда, которая помнит, отпустили ли её.
class _CountingLease implements ProviderLease {
  _CountingLease(this.provider);

  @override
  final TreeProvider provider;

  bool released = false;

  @override
  Future<void> release() async => released = true;
}
