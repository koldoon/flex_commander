import 'package:fc_api/fc_api.dart';
import 'package:fc_navigation/fc_navigation.dart';
import 'package:fc_terminal/fc_terminal.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Обводка и курсор стоят там, куда попадёт следующее нажатие, — и только там.
///
/// Полос набора на экране бывает несколько: своя под каждой панелью, да ещё
/// командная строка в режиме `mc`. Клавиши при этом достаются ровно одной, и
/// показывать «сюда идёт ввод» должна тоже одна: две горящие обводки означают,
/// что человек не знает, куда он печатает.
void main() {
  late AppRuntime runtime;

  Application app() => runtime.app;

  CommandLineState line() => app().view.contentAt(ViewportPosition.bottom)! as CommandLineState;

  setUp(() async {
    runtime = await testApp(
      provider: InMemoryTreeProvider([
        FakeEntry.directory('/home'),
        FakeEntry.directory('/home/docs'),
        FakeEntry.file('/home/alpha.txt', size: 10),
      ])..home = '/home',
      modules: featureModules(),
    );
    await runtime.app.start();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();
  }

  bool press(String keys) => runtime.commands.dispatch(KeyCombination.parse(keys));

  /// Сколько полос набора горят обводкой фокуса.
  int litRings(WidgetTester tester) {
    return tester
        .widgetList<Container>(find.descendant(of: find.byType(QuickSearchView), matching: find.byType(Container)))
        .where((box) => box.foregroundDecoration != null)
        .map((box) => ((box.foregroundDecoration! as BoxDecoration).border!.top).color)
        .where((color) => color.a > 0)
        .length;
  }

  testWidgets('поиск открыт в обеих панелях — обводка и курсор одни', (tester) async {
    await pumpApp(tester);

    press('Ctrl-S');
    await tester.pumpAndSettle();
    press('Tab');
    await tester.pumpAndSettle();
    press('Ctrl-S');
    await tester.pumpAndSettle();

    // Полосы две — это правда, каждая про свою панель.
    expect(find.byType(QuickSearchView), findsNWidgets(2));

    // А набор идёт в одну.
    expect(litRings(tester), 1, reason: 'обводка на экране одна');
    expect(find.byType(FcCaret), findsOneWidget, reason: 'и курсор один');

    // Курсор — под активной панелью, то есть под правой.
    final caret = tester.getRect(find.byType(FcCaret));
    final split = tester.getRect(find.byType(QuickSearchView).first);
    expect(caret.left, greaterThan(split.right), reason: 'ввод у правой панели');

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('Tab переносит обводку на другую сторону', (tester) async {
    await pumpApp(tester);

    press('Ctrl-S');
    await tester.pumpAndSettle();
    press('Tab');
    await tester.pumpAndSettle();
    press('Ctrl-S');
    await tester.pumpAndSettle();

    final right = tester.getRect(find.byType(FcCaret));

    press('Tab');
    await tester.pumpAndSettle();

    expect(litRings(tester), 1, reason: 'по-прежнему одна');
    final left = tester.getRect(find.byType(FcCaret));
    expect(left.left, lessThan(right.left), reason: 'курсор уехал к левой панели');

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('в режиме mc курсор строки гаснет, пока буквы забрал поиск', (tester) async {
    // Режим включается **до** первого кадра: настройка меняется молча, и от
    // неё одной строка не перерисовалась бы.
    line().settings.typingGoesToLine = true;
    await pumpApp(tester);

    /// Цвет курсора-блока в строке: он часть набранного текста, а не виджет.
    Color blockColor() {
      final rich = tester
          .widgetList<Text>(find.descendant(of: find.byType(CommandLineView), matching: find.byType(Text)))
          .firstWhere((text) => (text.textSpan as TextSpan?)?.children?.length == 2);
      return ((rich.textSpan! as TextSpan).children!.last as TextSpan).style!.color!;
    }

    final typing = blockColor();
    expect(typing.a, greaterThan(0), reason: 'буквы идут в строку — курсор виден');

    press('Ctrl-S');
    await tester.pumpAndSettle();

    // Теперь буквы принадлежат поиску, и курсор обязан быть там, а не здесь.
    expect(blockColor().a, 0, reason: 'строка курсор погасила');
    expect(find.byType(FcCaret), findsOneWidget, reason: 'а поиск — зажёг');

    press('Esc');
    await tester.pumpAndSettle();

    expect(blockColor().a, greaterThan(0), reason: 'вышли из поиска — курсор вернулся в строку');

    await tester.pump(const Duration(milliseconds: 20));
  });
}
