import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_navigation/fc_navigation.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('поле поиска видно в строке состояния', (tester) async {
    // Подставлять платформу не нужно: команды здесь запускаются напрямую, а не
    // через разбор нажатий.
    final runtime = await testApp(
      provider: InMemoryTreeProvider([
        FakeEntry.directory('/home'),
        FakeEntry.directory('/home/docs'),
        FakeEntry.file('/home/notes.txt', size: 10),
      ])..home = '/home',
      modules: featureModules(),
    );
    await runtime.app.start();
    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();

    expect(find.text('Search'), findsNothing);

    runtime.commands.dispatch(KeyCombination.parse('Ctrl-S'));
    runtime.commands.dispatch(const KeyCombination('D'));
    await tester.pumpAndSettle();

    expect(find.text('Search'), findsOneWidget);
    // В поле стоит то, что набрали, — как набрали.
    final pattern = QuickSearchCommand.searchIn(runtime.app)!.pattern;
    expect(find.text(pattern), findsOneWidget);
    expect(find.text('Esc to leave'), findsOneWidget);

    // Поле той же высоты, что поля в окнах: иначе оно читается как что-то
    // другое, ненастоящее.
    final theme = FcTheme.of(tester.element(find.text('Search')));
    final field = tester.getRect(find.ancestor(of: find.text(pattern), matching: find.byType(Container)).first);
    expect(field.height, greaterThanOrEqualTo(theme.metrics.inputHeight));

    runtime.commands.dispatch(KeyCombination.parse('Esc'));
    await tester.pumpAndSettle();

    expect(find.text('Search'), findsNothing, reason: 'вышли — поле убрано');
    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('ненайденное показывается выделением, а найденное — нет', (tester) async {
    // Ответ на нажатие обязан быть виден: звонка у нас нет, и молчащее поле
    // выглядит сломанным приложением. Чаще всего виновата раскладка.
    final runtime = await testApp(
      provider: InMemoryTreeProvider([
        FakeEntry.directory('/home'),
        FakeEntry.directory('/home/docs'),
        FakeEntry.file('/home/notes.txt', size: 10),
      ])..home = '/home',
      modules: featureModules(),
    );
    await runtime.app.start();
    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();

    runtime.commands.dispatch(KeyCombination.parse('Ctrl-S'));
    runtime.commands.dispatch(const KeyCombination('D'));
    runtime.commands.dispatch(const KeyCombination('Z'));
    await tester.pumpAndSettle();

    final state = QuickSearchCommand.searchIn(runtime.app)!;
    expect(state.matched, isNotEmpty, reason: 'первая буква нашлась');
    expect(state.tail, isNotEmpty, reason: 'вторая — нет');

    final colors = FcTheme.of(tester.element(find.byType(QuickSearchView))).colors;
    final field = tester
        .widgetList<Text>(find.descendant(of: find.byType(QuickSearchView), matching: find.byType(Text)))
        .firstWhere((text) => text.textSpan != null);
    final parts = (field.textSpan! as TextSpan).children!.cast<TextSpan>();

    expect(parts.first.text, state.matched);
    expect(parts.first.style?.backgroundColor, isNull, reason: 'найденное — обычным текстом');
    expect(parts.last.text, state.tail);
    // Тем же красным, каким выделяют текст в настоящих полях: это и есть
    // выделение, только ставит его поиск, а не человек.
    expect(parts.last.style?.backgroundColor, colors.inputSelection);

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('курсор и обводка — общие, а не свои', (tester) async {
    // Полоса поиска выглядит как поле ввода и обязана выглядеть **как
    // остальные**: своя обводка была вдвое тоньше, а курсор рисовался мимо
    // общей меры.
    final runtime = await testApp(
      provider: InMemoryTreeProvider([FakeEntry.directory('/home'), FakeEntry.directory('/home/docs')])..home = '/home',
      modules: featureModules(),
    );
    await runtime.app.start();
    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();

    runtime.commands.dispatch(KeyCombination.parse('Ctrl-S'));
    await tester.pumpAndSettle();

    final theme = FcTheme.of(tester.element(find.byType(QuickSearchView)));

    // Курсор — тот же, что рисуют все, кто рисует его сам.
    final caret = tester.getSize(find.byType(FcCaret));
    expect(caret.width, theme.metrics.caretWidth);

    // И **ростом со строку**, как курсор настоящего поля, а не с кегль: взяв
    // кегль, полоска выходит заметно ниже, чем в соседних полях.
    expect(caret.height, greaterThan(theme.metrics.fontSize));
    expect(caret.height, FcCaret.lineHeightOf(tester.element(find.byType(FcCaret)), theme.inputStyle));

    // Обводка фокуса — поверх, а не рамкой, и той же толщины, что у полей в
    // окнах: рамка входит в размер и сдвигала бы содержимое.
    final field = tester
        .widgetList<Container>(find.descendant(of: find.byType(QuickSearchView), matching: find.byType(Container)))
        .firstWhere((box) => box.foregroundDecoration != null);
    final ring = (field.foregroundDecoration! as BoxDecoration).border!.top;

    expect(ring.width, theme.metrics.focusRingWidth);
    expect(ring.color, theme.colors.focusRing);

    await tester.pump(const Duration(milliseconds: 20));
  });
}
