import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:fc_file_ops/fc_file_ops.dart';
import 'package:fc_navigation/fc_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Провайдер, у которого копирование можно замедлить.
///
/// В памяти оно мгновенное, и окно хода работы не успевает попасть ни в один
/// кадр — проверить его было бы нечем. Замедляется примитив, а не операция:
/// операция теперь одна на все провайдеры и живёт в движке.
class _SlowCopyProvider extends InMemoryTreeProvider {
  _SlowCopyProvider(super.entries);

  /// Один поток: этот провайдер изображает медленный источник, по которому
  /// работа идёт объект за объектом. Проверка «не просили ли прервать» стоит
  /// между ними, и на нескольких сразу проверять было бы уже негде — а речь
  /// здесь именно о ней.
  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(maxConcurrency: 1);

  bool slow = false;

  /// Медленное чтение каталога — это хвост работы: сама операция кончилась, а
  /// команда ещё перечитывает обе панели, и окно всё это время открыто.
  bool slowListing = false;

  @override
  Future<bool> copyEntry(
    FsNode node,
    DirectoryNode destination,
    String name, {
    bool Function(int bytes)? onBytes,
  }) async {
    if (slow) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return super.copyEntry(node, destination, name, onBytes: onBytes);
  }

  @override
  Operation<ListingParams, List<FsNode>> getDirectoryListing() {
    if (!slowListing) {
      return super.getDirectoryListing();
    }
    return TaskOperation<ListingParams, List<FsNode>>((op, params) async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return super.getDirectoryListing().run(params);
    });
  }
}

/// Файловые команды рисуют свои окна сами, поэтому и проверяются целиком:
/// от нажатия клавиши до изменившейся панели.
void main() {
  late _SlowCopyProvider provider;
  late AppController app;

  setUp(() async {
    provider = _SlowCopyProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/bin'),
      FakeEntry.file('/home/notes.txt', size: 10),
      FakeEntry.file('/home/report.xlsx', size: 20),
      FakeEntry.file('/home/a-very-long-name-that-would-have-stretched-the-dialog.txt', size: 30),
    ]);

    final settings = AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home'));
    app = (await testApp(provider: provider, modules: [const Navigation(), const FileOps()], settings: settings)).app;
  });

  /// Поле, в которое вводят. В окнах есть и выключенные поля — «откуда»
  /// у переноса и «внутри» у создания каталога, — и они не в счёт.
  final input = find.byWidgetPredicate((widget) => widget is TextField && widget.enabled != false);

  Future<void> pumpApp(WidgetTester tester, {Size size = const Size(802, 621)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: app));
    await app.start();
    await tester.pumpAndSettle();
  }

  /// Даёт доработать асинхронной части команды: операция, перечитывание панели.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  List<String> namesOf() => app.left.nodes.map((node) => node.name).toList();

  group('создание каталога', () {
    testWidgets('F7 открывает окно команды с полем ввода', (tester) async {
      await pumpApp(tester);
      await press(tester, LogicalKeyboardKey.f7);

      // Заголовок окна — название самой команды.
      expect(find.text('Mk Dir'), findsWidgets);
      expect(input, findsOneWidget);
      expect(tester.widget<TextField>(input).autofocus, isTrue);
    });

    testWidgets('фокус сразу в поле ввода', (tester) async {
      await pumpApp(tester);
      await press(tester, LogicalKeyboardKey.f7);

      // Имя можно набирать сразу, без клика по полю.
      final editable = tester.widget<EditableText>(find.descendant(of: input, matching: find.byType(EditableText)));
      expect(editable.focusNode.hasFocus, isTrue);
    });

    testWidgets('«внутри» — такое же поле, только выключенное', (tester) async {
      await pumpApp(tester);
      await press(tester, LogicalKeyboardKey.f7);

      final fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
      expect(fields, hasLength(2));

      // Каталог показан полем, а не текстом: форма из одинаковых полей.
      final inside = fields.singleWhere((field) => field.enabled == false);
      expect(inside.controller?.text, '/home');
    });

    testWidgets('введённое имя создаёт каталог и закрывает окно', (tester) async {
      await pumpApp(tester);
      await press(tester, LogicalKeyboardKey.f7);

      await tester.enterText(input, 'docs');
      await tester.tap(find.widgetWithText(FcButton, 'Create'));
      await settle(tester);

      expect(input, findsNothing);
      expect(namesOf(), contains('docs'));
      expect(app.left.currentNode?.name, 'docs');
    });

    testWidgets('Enter подтверждает ввод', (tester) async {
      await pumpApp(tester);
      await press(tester, LogicalKeyboardKey.f7);

      // Enter обрабатывает ядро: параметр уже задан вводом, а не подтверждением.
      await tester.enterText(input, 'docs');
      await press(tester, LogicalKeyboardKey.enter);
      await settle(tester);

      expect(namesOf(), contains('docs'));
    });

    testWidgets('Esc закрывает окно, ничего не создавая', (tester) async {
      await pumpApp(tester);
      await press(tester, LogicalKeyboardKey.f7);

      await tester.enterText(input, 'docs');
      await press(tester, LogicalKeyboardKey.escape);
      await settle(tester);

      expect(input, findsNothing);
      expect(namesOf(), isNot(contains('docs')));
    });

    testWidgets('отмена ничего не создаёт', (tester) async {
      await pumpApp(tester);
      await press(tester, LogicalKeyboardKey.f7);

      await tester.enterText(input, 'docs');
      await tester.tap(find.widgetWithText(FcButton, 'Cancel'));
      await settle(tester);

      expect(input, findsNothing);
      expect(namesOf(), isNot(contains('docs')));
    });

    testWidgets('ошибка показывается в том же окне, а имя остаётся', (tester) async {
      await pumpApp(tester);
      await press(tester, LogicalKeyboardKey.f7);

      await tester.enterText(input, 'bin');
      await tester.tap(find.widgetWithText(FcButton, 'Create'));
      await settle(tester);

      // Окно не закрылось: имя можно исправить и попробовать снова.
      expect(input, findsOneWidget);
      expect(find.textContaining('Already exists'), findsOneWidget);

      await tester.enterText(input, 'docs');
      await tester.tap(find.widgetWithText(FcButton, 'Create'));
      await settle(tester);

      expect(namesOf(), contains('docs'));
    });

    testWidgets('кнопка F7 в нижней панели делает то же самое', (tester) async {
      await pumpApp(tester);

      await tester.tap(find.text('Mk Dir'));
      await tester.pumpAndSettle();

      expect(input, findsOneWidget);
    });
  });

  group('удаление', () {
    testWidgets('F8 спрашивает подтверждение и удаляет', (tester) async {
      await pumpApp(tester);
      app.left.setCursorToName('notes.txt');
      await tester.pump();

      await press(tester, LogicalKeyboardKey.f8);
      expect(find.textContaining('Move «notes.txt» to Trash?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FcButton, 'Delete'));
      await settle(tester);

      expect(namesOf(), isNot(contains('notes.txt')));
    });

    testWidgets('отказ оставляет объект на месте', (tester) async {
      await pumpApp(tester);
      app.left.setCursorToName('notes.txt');
      await tester.pump();

      await press(tester, LogicalKeyboardKey.f8);
      await tester.tap(find.widgetWithText(FcButton, 'Cancel'));
      await settle(tester);

      expect(namesOf(), contains('notes.txt'));
    });

    testWidgets('удаляются все помеченные объекты', (tester) async {
      await pumpApp(tester);
      app.left.setCursorToName('notes.txt');
      app.left.toggleCurrentMark();
      app.left.toggleCurrentMark();
      await tester.pump();

      await press(tester, LogicalKeyboardKey.f8);
      expect(find.textContaining('Move 2 items to Trash?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FcButton, 'Delete'));
      await settle(tester);

      expect(namesOf(), isNot(contains('notes.txt')));
      expect(namesOf(), isNot(contains('report.xlsx')));
      expect(app.left.selection.isEmpty, isTrue);
    });

    testWidgets('Shift-F8 предупреждает, что удаление безвозвратное', (tester) async {
      await pumpApp(tester);
      app.left.setCursorToName('notes.txt');
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f8);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();

      expect(find.text('Delete permanently'), findsWidgets);
      expect(find.textContaining('cannot be undone'), findsOneWidget);
    });

    testWidgets('ошибка предлагает пропустить, пропустить все или отменить', (tester) async {
      await pumpApp(tester);
      app.left.setCursorToName('notes.txt');
      await tester.pump();
      // Объект исчез уже после того, как панель его показала.
      provider.removeEntry('/home/notes.txt');

      await press(tester, LogicalKeyboardKey.f8);
      await tester.tap(find.widgetWithText(FcButton, 'Delete'));
      await settle(tester);

      expect(find.textContaining('Not found'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      expect(find.text('Skip all'), findsOneWidget);

      await tester.tap(find.widgetWithText(FcButton, 'Skip'));
      await settle(tester);

      // Ответили — окно закрылось само.
      expect(find.text('Skip'), findsNothing);
    });

    testWidgets('на «..» команда недоступна', (tester) async {
      await pumpApp(tester);
      app.left.setCursorToFirst();
      await tester.pump();

      await press(tester, LogicalKeyboardKey.f8);

      expect(find.textContaining('to Trash?'), findsNothing);
    });
  });

  group('копирование и перенос', () {
    /// Обе панели в этих тестах показывают один каталог, поэтому приёмник
    /// задаётся вводом — как это и делает пользователь, когда ему нужно не то,
    /// что в соседней панели.
    Future<void> openTransfer(WidgetTester tester, LogicalKeyboardKey key, {String? destination}) async {
      await press(tester, key);
      if (destination != null) {
        await tester.enterText(input, destination);
        await tester.pumpAndSettle();
      }
    }

    testWidgets('F5 открывает окно с каталогом пассивной панели', (tester) async {
      await pumpApp(tester);
      app.left.setCursorToName('notes.txt');
      await tester.pump();

      await press(tester, LogicalKeyboardKey.f5);

      // Заголовок окна говорит, что и куда, — как в референсе.
      expect(find.text('Copy «notes.txt»'), findsOneWidget);
      // Путь уже подставлен: обычно копируют именно в соседнюю панель.
      expect(tester.widget<TextField>(input).controller?.text, '/home');
    });

    testWidgets('фокус сразу в поле ввода', (tester) async {
      await pumpApp(tester);
      app.left.setCursorToName('notes.txt');
      await tester.pump();

      await press(tester, LogicalKeyboardKey.f5);

      final editable = tester.widget<EditableText>(find.descendant(of: input, matching: find.byType(EditableText)));
      expect(editable.focusNode.hasFocus, isTrue);
    });

    testWidgets('«откуда» — такое же поле, только выключенное', (tester) async {
      await pumpApp(tester);
      app.left.setCursorToName('notes.txt');
      await tester.pump();

      await press(tester, LogicalKeyboardKey.f5);

      final fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
      expect(fields, hasLength(2));

      // Источник задан выбором в панели: показать — показываем, менять нечего.
      final source = fields.singleWhere((field) => field.enabled == false);
      expect(source.controller?.text, '/home');
    });

    testWidgets('Enter копирует в указанный каталог', (tester) async {
      await pumpApp(tester);
      app.left.setCursorToName('notes.txt');
      await tester.pump();

      await openTransfer(tester, LogicalKeyboardKey.f5, destination: '/home/bin');
      await press(tester, LogicalKeyboardKey.enter);
      await settle(tester);

      expect(input, findsNothing);
      expect(await provider.resolvePath().run('/home/bin/notes.txt'), isNotNull);
      expect(namesOf(), contains('notes.txt'));
    });

    testWidgets('F6 переносит: в источнике объекта не остаётся', (tester) async {
      await pumpApp(tester);
      app.left.setCursorToName('notes.txt');
      await tester.pump();

      await openTransfer(tester, LogicalKeyboardKey.f6, destination: '/home/bin');
      expect(find.text('Move «notes.txt»'), findsOneWidget);

      await tester.tap(find.widgetWithText(FcButton, 'Move'));
      await settle(tester);

      expect(namesOf(), isNot(contains('notes.txt')));
      expect(await provider.resolvePath().run('/home/bin/notes.txt'), isNotNull);
    });

    testWidgets('помеченные объекты видны в заголовке окна', (tester) async {
      await pumpApp(tester);
      app.left.setCursorToName('notes.txt');
      app.left.toggleCurrentMark();
      app.left.toggleCurrentMark();
      await tester.pump();

      await press(tester, LogicalKeyboardKey.f5);

      expect(find.text('Copy 2 items'), findsOneWidget);
    });

    testWidgets('о занятом имени спрашивают, и «пропустить» ничего не меняет', (tester) async {
      provider.add(FakeEntry.file('/home/bin/notes.txt', size: 1));
      await pumpApp(tester);
      app.left.setCursorToName('notes.txt');
      await tester.pump();

      await openTransfer(tester, LogicalKeyboardKey.f5, destination: '/home/bin');
      await tester.tap(find.widgetWithText(FcButton, 'Copy'));
      await settle(tester);

      expect(find.textContaining('Already exists'), findsOneWidget);
      expect(find.text('Overwrite'), findsOneWidget);

      await tester.tap(find.widgetWithText(FcButton, 'Skip'));
      await settle(tester);

      expect(find.textContaining('Already exists'), findsNothing);
    });

    testWidgets('кнопки стоят в одну строку, даже когда их пять', (tester) async {
      provider.add(FakeEntry.file('/home/bin/notes.txt', size: 1));
      await pumpApp(tester);
      app.left.setCursorToName('notes.txt');
      await tester.pump();

      await openTransfer(tester, LogicalKeyboardKey.f5, destination: '/home/bin');
      await tester.tap(find.widgetWithText(FcButton, 'Copy'));
      await settle(tester);

      // Вопрос о занятом имени — самый широкий набор кнопок: пять штук.
      expect(find.byType(FcButton), findsNWidgets(5));
      final tops = tester.widgetList<FcButton>(find.byType(FcButton)).map((button) {
        return tester.getTopLeft(find.byWidget(button)).dy;
      });

      // Все на одной высоте: ряд не переносится на вторую строку.
      expect(tops.toSet(), hasLength(1));
    });

    testWidgets('Esc закрывает окно, ничего не копируя', (tester) async {
      await pumpApp(tester);
      app.left.setCursorToName('notes.txt');
      await tester.pump();

      await openTransfer(tester, LogicalKeyboardKey.f5, destination: '/home/bin');
      await press(tester, LogicalKeyboardKey.escape);
      await settle(tester);

      expect(input, findsNothing);
      expect(await provider.resolvePath().run('/home/bin/notes.txt'), isNull);
    });

    testWidgets('ошибка в пути показывается в том же окне', (tester) async {
      await pumpApp(tester);
      app.left.setCursorToName('notes.txt');
      await tester.pump();

      await openTransfer(tester, LogicalKeyboardKey.f5, destination: '/nowhere');
      await press(tester, LogicalKeyboardKey.enter);
      await settle(tester);

      expect(input, findsOneWidget);
      expect(find.textContaining('Not found'), findsOneWidget);
    });

    testWidgets('до запуска окно облегает содержимое', (tester) async {
      // Окно пошире: при узком половина окна почти равна нижнему пределу,
      // и два поведения было бы не различить.
      await pumpApp(tester, size: const Size(1400, 800));
      app.left.setCursorToName('notes.txt');
      await tester.pump();

      await press(tester, LogicalKeyboardKey.f5);

      final width = tester.getSize(find.byType(CommandDialogBody)).width;
      expect(width, lessThan(1400 / 2));
    });

    testWidgets('во время работы ширина фиксирована', (tester) async {
      provider.slow = true;
      await pumpApp(tester, size: const Size(1400, 800));
      app.left.setCursorToName('notes.txt');
      await tester.pump();

      await openTransfer(tester, LogicalKeyboardKey.f5, destination: '/home/bin');
      await tester.tap(find.widgetWithText(FcButton, 'Copy'));
      await tester.pump();

      // Пошла работа: по ходу неё в окне меняются имена файлов, и от них окно
      // «прыгало» бы на каждом.
      expect(find.byType(FcProgressBar), findsNWidgets(2));
      expect(tester.getSize(find.byType(CommandDialogBody)).width, closeTo(1400 / 2, 1));

      await tester.pump(const Duration(milliseconds: 300));
      await settle(tester);
    });

    testWidgets('во время работы видно объём задания', (tester) async {
      provider.slow = true;
      await pumpApp(tester);
      app.left.setCursorToName('notes.txt');
      await tester.pump();

      await openTransfer(tester, LogicalKeyboardKey.f5, destination: '/home/bin');
      await tester.tap(find.widgetWithText(FcButton, 'Copy'));
      await tester.pump();

      // Объём задания известен ещё до того, как перенесён первый байт.
      // Дважды: общий объём работы и объём текущего файла — это разные строки.
      expect(find.textContaining('of 10 B'), findsNWidgets(2));
      expect(find.text('File'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 300));
      await settle(tester);
    });

    group('конец работы', () {
      /// Доводит копирование до **хвоста**: операция кончилась, а команда ещё
      /// перечитывает обе панели, и окно всё это время открыто.
      ///
      /// Раньше в этот промежуток окно откатывалось к форме с параметрами —
      /// `isRunning` гас в конце операции, а форма стояла в окне веткой
      /// «иначе». На локальном диске это было мигание в несколько кадров,
      /// по сети — секунды.
      Future<void> copyIntoTail(WidgetTester tester) async {
        await pumpApp(tester);
        app.left.setCursorToName('notes.txt');
        await tester.pump();

        await openTransfer(tester, LogicalKeyboardKey.f5, destination: '/home/bin');
        // Копирование мгновенное, а перечитывание панелей — нет: хвост длиннее
        // самой работы, ровно как по сети.
        provider.slowListing = true;
        await tester.tap(find.widgetWithText(FcButton, 'Copy'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));
      }

      /// Отпускает хвост доработать: иначе тест кончится с висящим таймером.
      Future<void> finish(WidgetTester tester) async {
        await tester.pump(const Duration(milliseconds: 500));
        await settle(tester);
      }

      testWidgets('форма с параметрами больше не выскакивает', (tester) async {
        await copyIntoTail(tester);

        // Ни поля «куда», ни кнопки «Copy» — окно осталось окном хода работы.
        expect(input, findsNothing);
        expect(find.widgetWithText(FcButton, 'Copy'), findsNothing);
        expect(find.byType(FcProgressBar), findsNWidgets(2));

        await finish(tester);
        expect(find.byType(FcButton), findsNothing);
      });

      testWidgets('кнопки гаснут, но с места не девается ни одна', (tester) async {
        await copyIntoTail(tester);

        // Прерывать нечего и прятать нечего, но ряд кнопок не переставляется:
        // окно не должно дёргаться на прощание.
        expect(find.widgetWithText(FcButton, 'Background'), findsOneWidget);
        expect(tester.widget<FcButton>(find.widgetWithText(FcButton, 'Background')).onPressed, isNull);
        expect(tester.widget<FcButton>(find.widgetWithText(FcButton, 'Cancel')).onPressed, isNull);

        await finish(tester);
      });

      testWidgets('Enter в хвосте не запускает работу заново', (tester) async {
        await copyIntoTail(tester);

        // Раньше охрана подтверждения смотрела на идущую операцию, а её в
        // хвосте уже нет: копирование шло вторым заходом — и упиралось в файл,
        // который само же и создало.
        await press(tester, LogicalKeyboardKey.enter);
        await finish(tester);

        expect(find.textContaining('Already exists'), findsNothing);
        expect(find.byType(FcButton), findsNothing);
      });

      testWidgets('Esc в хвосте окно не закрывает', (tester) async {
        await copyIntoTail(tester);

        // Работа сделана, окно уйдёт само; закрывать его раньше — значит
        // потерять ошибку, если хвост ещё успеет её принести.
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();

        expect(find.byType(FcProgressBar), findsNWidgets(2));

        await finish(tester);
        expect(find.byType(FcButton), findsNothing);
      });
    });

    group('прерывание работы', () {
      // Порядок работы — как в панели, по имени: длинное имя идёт первым,
      // «report.xlsx» последним.
      const firstFile = 'a-very-long-name-that-would-have-stretched-the-dialog.txt';
      const lastFile = 'report.xlsx';

      /// Запускает медленное копирование трёх объектов и доводит его до хода
      /// работы.
      ///
      /// Объектов именно несколько: проверка «не просили ли прервать» стоит
      /// между ними, и на одном файле спрашивать было бы уже негде. Трёх хватает
      /// на два вопроса подряд — отказаться от первого и подтвердить второй.
      Future<void> startSlowCopy(WidgetTester tester) async {
        provider.slow = true;
        await pumpApp(tester);
        for (final name in [firstFile, 'notes.txt', lastFile]) {
          app.left.setCursorToName(name);
          app.left.toggleCurrentMark();
        }
        await tester.pump();

        await openTransfer(tester, LogicalKeyboardKey.f5, destination: '/home/bin');
        await tester.tap(find.widgetWithText(FcButton, 'Copy'));
        await tester.pump();
        expect(find.byType(FcProgressBar), findsNWidgets(2));
      }

      /// Просит прервать и ждёт вопроса: он появится, когда работа дойдёт до
      /// ближайшей проверки — то есть закончит текущий файл.
      Future<void> askAbort(WidgetTester tester, {LogicalKeyboardKey? key}) async {
        if (key != null) {
          await tester.sendKeyEvent(key);
        }
        await tester.pump(const Duration(milliseconds: 250));
      }

      /// Ждёт конца работы вместе с оставшимися медленными файлами.
      Future<void> finish(WidgetTester tester) async {
        await tester.pump(const Duration(milliseconds: 800));
        await settle(tester);
      }

      testWidgets('Esc во время работы спрашивает подтверждение', (tester) async {
        await startSlowCopy(tester);

        await askAbort(tester, key: LogicalKeyboardKey.escape);

        expect(find.textContaining('Abort the operation?'), findsOneWidget);
        expect(find.widgetWithText(FcButton, 'Abort'), findsOneWidget);
        expect(find.widgetWithText(FcButton, 'Cancel'), findsOneWidget);
        // Работа не прервана и не закончена: она ждёт ответа.
        expect(await provider.resolvePath().run('/home/bin/$lastFile'), isNull);

        await tester.tap(find.widgetWithText(FcButton, 'Abort'));
        await finish(tester);
      });

      testWidgets('пока ответа нет, работа стоит', (tester) async {
        await startSlowCopy(tester);
        await askAbort(tester, key: LogicalKeyboardKey.escape);

        // Заведомо дольше, чем занял бы весь остаток задания.
        await tester.pump(const Duration(seconds: 2));

        expect(find.widgetWithText(FcButton, 'Abort'), findsOneWidget);
        expect(await provider.resolvePath().run('/home/bin/$lastFile'), isNull);

        await tester.tap(find.widgetWithText(FcButton, 'Abort'));
        await finish(tester);
      });

      testWidgets('«Cancel» возвращает к работе, и она доходит до конца', (tester) async {
        await startSlowCopy(tester);
        await askAbort(tester, key: LogicalKeyboardKey.escape);

        await tester.tap(find.widgetWithText(FcButton, 'Cancel'));
        await finish(tester);

        // Окно закрылось само: работа кончилась, а не прервалась.
        expect(find.byType(FcProgressBar), findsNothing);
        expect(await provider.resolvePath().run('/home/bin/$lastFile'), isNotNull);
      });

      testWidgets('«Abort» прекращает работу на том, что успели', (tester) async {
        await startSlowCopy(tester);
        await askAbort(tester, key: LogicalKeyboardKey.escape);

        await tester.tap(find.widgetWithText(FcButton, 'Abort'));
        await finish(tester);

        expect(find.byType(FcProgressBar), findsNothing);
        // Сделанное остаётся сделанным, остальное не начиналось.
        expect(await provider.resolvePath().run('/home/bin/$firstFile'), isNotNull);
        expect(await provider.resolvePath().run('/home/bin/$lastFile'), isNull);
      });

      testWidgets('Esc отказывается прерывать, Enter прерывает', (tester) async {
        await startSlowCopy(tester);
        await askAbort(tester, key: LogicalKeyboardKey.escape);

        // Esc: отказ от прерывания — работа продолжается.
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(find.widgetWithText(FcButton, 'Abort'), findsNothing);
        expect(find.byType(FcProgressBar), findsNWidgets(2));

        // Enter: подтверждение — «Abort» стоит вариантом по умолчанию.
        await askAbort(tester, key: LogicalKeyboardKey.escape);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await finish(tester);

        expect(find.byType(FcProgressBar), findsNothing);
        expect(await provider.resolvePath().run('/home/bin/$lastFile'), isNull);
      });

      testWidgets('кнопка «Cancel» в окне хода работы спрашивает так же', (tester) async {
        await startSlowCopy(tester);

        // Тот же смысл, что и у Esc, — и тот же вопрос.
        await tester.tap(find.widgetWithText(FcButton, 'Cancel'));
        await askAbort(tester);

        expect(find.widgetWithText(FcButton, 'Abort'), findsOneWidget);

        await tester.tap(find.widgetWithText(FcButton, 'Abort'));
        await finish(tester);
      });
    });

    testWidgets('кнопки нижней панели делают то же самое', (tester) async {
      await pumpApp(tester);
      app.left.setCursorToName('notes.txt');
      await tester.pump();

      // Кнопка нижней панели: подпись на ней — просто «Copy».
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();

      expect(find.text('Copy «notes.txt»'), findsOneWidget);
    });
  });

  group('окна команд', () {
    testWidgets('Enter подтверждает и там, где вводить нечего', (tester) async {
      await pumpApp(tester);
      app.left.setCursorToName('notes.txt');
      await tester.pump();

      await press(tester, LogicalKeyboardKey.f8);
      expect(find.textContaining('to Trash?'), findsOneWidget);

      // В окне удаления нет поля ввода — фокус на самом окне, и Enter всё равно
      // доходит до ядра.
      await press(tester, LogicalKeyboardKey.enter);
      await settle(tester);

      expect(namesOf(), isNot(contains('notes.txt')));
    });

    testWidgets('Esc закрывает окно подтверждения', (tester) async {
      await pumpApp(tester);
      app.left.setCursorToName('notes.txt');
      await tester.pump();

      await press(tester, LogicalKeyboardKey.f8);
      await press(tester, LogicalKeyboardKey.escape);
      await settle(tester);

      expect(find.textContaining('to Trash?'), findsNothing);
      expect(namesOf(), contains('notes.txt'));
    });

    testWidgets('пока окно открыто, панели не отвечают на клавиши', (tester) async {
      await pumpApp(tester);
      final cursor = app.left.cursorIndex;

      await press(tester, LogicalKeyboardKey.f7);
      await press(tester, LogicalKeyboardKey.arrowDown);

      expect(app.left.cursorIndex, cursor);
    });

    testWidgets('после закрытия окна клавиши снова работают', (tester) async {
      await pumpApp(tester);

      await press(tester, LogicalKeyboardKey.f7);
      await tester.tap(find.widgetWithText(FcButton, 'Cancel'));
      await settle(tester);

      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(app.left.cursorIndex, 1);
    });
  });
}
