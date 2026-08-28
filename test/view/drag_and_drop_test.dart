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
    await tester.pumpAndSettle();

    expect(provider.entryAt('/home/docs/dropped.txt'), isNotNull, reason: 'файл должен лечь в каталог под курсором');
    // Копия, а не перенос: из Finder объекты не исчезают.
    expect(provider.entryAt('/outside/dropped.txt'), isNotNull);
  });

  testWidgets('бросок показывает то же окно работы, что и F5', (tester) async {
    // Найдено на живом: работа шла, панель обновлялась, а окна не было вовсе —
    // приёмник, заданный параметром, уводил команду мимо него. Для сценария
    // это верно, для жеста нет: человек начал работу сам и вправе видеть ход,
    // вопросы и отмену.
    await pumpApp(tester);

    // Окно ловится подпиской, а не взглядом в нужный кадр: в памяти работа
    // успевает кончиться раньше, чем тест успевает посмотреть.
    var raised = false;
    void watch() {
      raised = raised || app.view.dialogs.isNotEmpty;
    }

    app.view.addListener(watch);
    addTearDown(() => app.view.removeListener(watch));

    final target = rowCenter(tester, 'docs');
    await sendDrop(tester, 'drop', at: target, paths: const ['/outside/dropped.txt']);
    await tester.pumpAndSettle();

    expect(raised, isTrue, reason: 'окно хода работы должно подняться, как по F5');
    expect(provider.entryAt('/home/docs/dropped.txt'), isNotNull);
  });

  testWidgets('брошенное мимо строк копируется в каталог панели', (tester) async {
    await pumpApp(tester);

    final table = tester.getRect(find.byType(FileTable).first);
    final empty = Offset(table.left + table.width / 2, table.bottom - 4);
    await sendDrop(tester, 'drop', at: empty, paths: const ['/outside/dropped.txt']);
    await tester.pumpAndSettle();

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
    await tester.pumpAndSettle();

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
      await tester.pumpAndSettle();

      expect(provider.entryAt('/home/docs/note.txt'), isNotNull);
    });

    testWidgets('с настройкой принимает и в свою — в каталог под курсором', (tester) async {
      // Ради этого её и включают: перетащить в подкаталог, не уходя из панели.
      app.moduleSettings('fc.dnd').section(DragAndDropSettings.new).dropIntoSamePanel = true;
      await pumpApp(tester);

      final onDocs = rowCenter(tester, 'docs');
      await dragFromLeft(tester, 'note.txt', onDocs);
      await sendDrop(tester, 'drop', at: onDocs, paths: const ['/home/note.txt']);
      await tester.pumpAndSettle();

      expect(provider.entryAt('/home/docs/note.txt'), isNotNull);
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
