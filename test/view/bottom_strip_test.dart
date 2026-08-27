import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/view/function_bar/function_bar.dart';
import 'package:flex_commander/view/split_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Полоса под панелями: место для командной строки и владелец ввода.
///
/// Проверяется ядро, а не терминал: полоса — обычное содержимое области, и всё,
/// что нужно от ядра, это показать её и уметь отдать ей ввод. Модуля здесь нет
/// вовсе — вместо него подставка, объявляющая свой вид и свою привязку.
late AppRuntime runtime;

ApplicationView get view => runtime.app.view;

void showLine() => view.setViewportContent(ViewportPosition.bottom, _StubLine());

String? commandOn(String keys) => runtime.commands.commandFor(KeyCombination.parse(keys))?.id;

bool dispatch(String keys) => runtime.commands.dispatch(KeyCombination.parse(keys));

void main() {
  setUp(() async {
    runtime = await testApp(
      provider: InMemoryTreeProvider([
        FakeEntry.directory('/home'),
        FakeEntry.file('/home/alpha.txt', size: 10),
        FakeEntry.file('/home/beta.txt', size: 10),
      ])..home = '/home',
      // Без модуля терминала: проверяется механизм ядра, и полосу ставит
      // подставка. Заодно видно, что приложение без него собирается.
      modules: [...featureModules().where((module) => module.id != 'fc.terminal'), const _StubLineModule()],
    );
    await runtime.app.start();
  });

  group('место', () {
    testWidgets('пусто — полосы нет вовсе', (tester) async {
      await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
      await tester.pumpAndSettle();

      expect(find.text('Stub line'), findsNothing);
    });

    testWidgets('поставили содержимое — полоса видна между панелями и рядом кнопок', (tester) async {
      await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
      await tester.pumpAndSettle();
      showLine();
      await tester.pumpAndSettle();

      expect(find.text('Stub line'), findsOneWidget);

      final strip = tester.getRect(find.text('Stub line'));
      final panels = tester.getRect(find.byType(SplitView));
      final buttons = tester.getRect(find.byType(FunctionBar));
      expect(strip.top, greaterThanOrEqualTo(panels.bottom));
      expect(strip.bottom, lessThanOrEqualTo(buttons.top));
    });

    testWidgets('под полноэкранным содержимым полосы нет', (tester) async {
      await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
      await tester.pumpAndSettle();
      showLine();
      await tester.pumpAndSettle();
      expect(find.text('Stub line'), findsOneWidget);

      view.pushViewportContent(ViewportPosition.fullscreen, _StubScreen());
      await tester.pumpAndSettle();

      // В полноэкранный терминал и так печатают: две строки ввода в одну и ту
      // же оболочку — это вопрос «а в какую из них сейчас?», на который нечего
      // ответить.
      expect(find.text('Stub line'), findsNothing);
      expect(find.text('Stub screen'), findsOneWidget);

      view.popViewportContent(ViewportPosition.fullscreen);
      await tester.pumpAndSettle();

      // Полоса возвращается сама: её никто не убирал, она была закрыта.
      expect(find.text('Stub line'), findsOneWidget);
    });
  });

  group('владелец ввода', () {
    test('ввод отдаётся полосе, а панель-источник остаётся прежней', () {
      showLine();
      expect(view.activeArea, ViewportPosition.left);

      view.setFocus(ViewportPosition.bottom);

      expect(view.activeArea, ViewportPosition.bottom);
      // Копировать по-прежнему из левой в правую: строка — не панель и
      // источником быть не может.
      expect(view.sourceArea, ViewportPosition.left);
    });

    test('полноэкранное перебивает полосу, а снятие — возвращает', () {
      showLine();
      view.setFocus(ViewportPosition.bottom);

      view.pushViewportContent(ViewportPosition.fullscreen, _StubLine());
      expect(view.activeArea, ViewportPosition.fullscreen);

      view.popViewportContent(ViewportPosition.fullscreen);
      // Ввод вернулся строке сам: её никто не отпускал.
      expect(view.activeArea, ViewportPosition.bottom);
    });

    test('пустой полосе ввод не отдаётся', () {
      // Модуля терминала нет — показывать внизу нечего, и держать ввод нечему.
      // Иначе клавиши уходили бы в никуда: панель их уже не получает, а поля,
      // которое их примет, не существует.
      view.setFocus(ViewportPosition.bottom);

      expect(view.activeArea, ViewportPosition.left);
    });

    test('щелчок по уже активной панели забирает ввод обратно', () {
      showLine();
      view.setFocus(ViewportPosition.bottom);

      // Ровно та панель, которая и была активной: раньше здесь стоял ранний
      // выход «она и так активна», и из строки было бы не выйти мышью.
      runtime.app.activate(runtime.app.left);

      expect(view.activeArea, ViewportPosition.left);
    });
  });

  group('кому принадлежат клавиши', () {
    test('пока ввод у панели, буква ищет файл', () {
      expect(commandOn('B'), isNotNull);
    });

    test('ввод у полосы — буква не достаётся никому: она уйдёт в поле', () {
      showLine();
      view.setFocus(ViewportPosition.bottom);

      expect(commandOn('B'), isNull);
      // И курсор от неё не двигается: команды под клавишей нет.
      final before = runtime.app.left.cursorIndex;
      expect(dispatch('B'), isFalse);
      expect(runtime.app.left.cursorIndex, before);
    });

    test('Enter и Bsp тоже принадлежат полосе, а не панели', () {
      showLine();
      view.setFocus(ViewportPosition.bottom);

      expect(commandOn('Enter'), isNull);
      expect(commandOn('Bsp'), isNull);
    });

    test('функциональные клавиши достаются панели', () {
      final inPanel = commandOn('F5');
      expect(inPanel, isNotNull);

      showLine();
      view.setFocus(ViewportPosition.bottom);

      expect(commandOn('F5'), inPanel);
    });

    test('стрелки вверх и вниз тоже: в однострочном поле им ходить некуда', () {
      final up = commandOn('Up');
      expect(up, isNotNull);

      showLine();
      view.setFocus(ViewportPosition.bottom);

      expect(commandOn('Up'), up);
      expect(commandOn('Down'), isNotNull);
    });

    test('своя привязка полосы важнее отката к панели', () {
      showLine();
      view.setFocus(ViewportPosition.bottom);

      // `F1` полоса объявила за собой — панельная справка молчит.
      expect(commandOn('F1'), 'stub.line');
    });

    test('полноэкранное отката не получает: панелей на экране нет', () {
      showLine();
      view.pushViewportContent(ViewportPosition.fullscreen, _StubScreen());

      expect(commandOn('F5'), isNull);
    });
  });
}

/// Содержимое полосы: подставка вместо модуля терминала.
class _StubLine extends ChangeNotifier implements ViewportState {
  @override
  bool get takesKeyboard => true;

  @override
  void close() {}
}

/// Полноэкранная подставка — чтобы проверить, что откат её не касается.
class _StubScreen extends ChangeNotifier implements ViewportState {
  @override
  bool get takesKeyboard => true;

  @override
  void close() {}
}

class _StubLineModule implements FcModule {
  const _StubLineModule();

  @override
  String get id => 'test.stub_line';

  @override
  String get title => 'Stub line';

  @override
  void install(FcRegistry registry) {
    registry.view<_StubLine>((context, state) => const Text('Stub line'));
    registry.view<_StubScreen>((context, state) => const Text('Stub screen'));
    registry.command((context) => _StubLineCommand());
    registry.binding(KeyBinding.inState<_StubLine>('F1', 'stub.line'));
  }
}

class _StubLineCommand extends AppCommand {
  @override
  String get id => 'stub.line';

  @override
  String get label => 'Stub line';

  @override
  bool isExecutable(CommandContext context) => true;

  @override
  Future<void> execute(CommandContext context) async {}
}
