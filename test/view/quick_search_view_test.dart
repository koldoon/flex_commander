import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
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
    expect(find.text(runtime.app.left.quickSearch!), findsOneWidget);
    expect(find.text('Esc to leave'), findsOneWidget);

    runtime.commands.dispatch(KeyCombination.parse('Esc'));
    await tester.pumpAndSettle();

    expect(find.text('Search'), findsNothing, reason: 'вышли — поле убрано');
    await tester.pump(const Duration(milliseconds: 20));
  });
}
