import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

/// Каталог, в который не пустили: панель остаётся там, где была.
///
/// Ошибка чтения — это неудача **перехода**, а не потеря содержимого. Раньше
/// список подменялся сообщением во весь рост: уйти было некуда — ни `..`, ни
/// строки под курсором на экране не оставалось.
void main() {
  late AppRuntime runtime;
  late InMemoryTreeProvider provider;

  setUp(() async {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/secret'),
      FakeEntry.file('/home/notes.txt', size: 10),
    ])..home = '/home';
    provider.denied['/home/secret'] = const FsError('/home/secret', FsErrorKind.permissionDenied);

    runtime = await testApp(provider: provider, modules: featureModules());
    await runtime.app.start();
  });

  Future<void> enterSecret(WidgetTester tester) async {
    runtime.app.left.setCursorToName('secret');
    runtime.commands.dispatch(KeyCombination.parse('Enter'));
    await tester.pumpAndSettle();
  }

  testWidgets('содержимое остаётся на экране, а об ошибке говорит строка состояния', (tester) async {
    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();

    await enterSecret(tester);

    expect(runtime.app.left.phase, PanelPhase.error);
    // Список на месте — вместе с `..`, которым отсюда и уходят.
    expect(find.text('notes'), findsWidgets);
    expect(find.text('secret'), findsWidgets);
    expect(find.text('..'), findsWidgets);
    // А сообщение — там, где ему место: в строке состояния, и только в ней.
    expect(find.textContaining('Permission denied'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('после отказа можно уйти вверх', (tester) async {
    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();

    await enterSecret(tester);
    runtime.commands.dispatch(KeyCombination.parse('Bsp'));
    await tester.pumpAndSettle();

    expect(runtime.app.left.directory?.pathString, '/');
    expect(runtime.app.left.phase, PanelPhase.idle);

    await tester.pump(const Duration(milliseconds: 20));
  });

  test('панель остаётся в прежнем каталоге, с содержимым и курсором', () async {
    final panel = runtime.app.left;
    final before = [for (final node in panel.entries) node.name];

    panel.setCursorToName('secret');
    await panel.enter(panel.entries.firstWhere((entry) => entry.name == 'secret'));

    expect(panel.path, '/home');
    expect([for (final node in panel.entries) node.name], before);
    // Курсор там же, откуда входили: повторить попытку — одно нажатие.
    expect(panel.currentEntry?.name, 'secret');
    expect(panel.statusText, contains('Permission denied'));
    expect(panel.busy, isFalse);
  });
}
