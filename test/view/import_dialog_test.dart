import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flex_commander/modules/dnd/system_drag_and_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Окно загрузки: файл выбирают в дереве и бросают в него мышью
/// (`docs/spec/settings-presets.md`, §7, `docs/spec/theme-editor.md`, §10).
void main() {
  late AppRuntime runtime;

  setUp(() async {
    runtime = await testApp(
      provider: InMemoryTreeProvider([
        FakeEntry.directory('/home'),
        FakeEntry.file('/home/work.json', size: 10),
        FakeEntry.file('/home/notes.txt', size: 10),
        FakeEntry.directory('/home/docs'),
        FakeEntry.file('/home/docs/dark.json', size: 10),
      ])..home = '/home',
      modules: featureModules(),
    );
    await runtime.app.start();
  });

  Future<void> openImport(WidgetTester tester, String setting) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    await tester.pumpAndSettle();

    final button = find.descendant(
      of: find.ancestor(of: find.text(setting, findRichText: true), matching: find.byType(Column)).first,
      matching: find.widgetWithText(FcButton, 'Import'),
    );
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  /// Строка дерева — в панелях те же имена, и без оговорки находятся они.
  Finder inTree(String name) => find.descendant(of: find.byType(FcDirectoryTree), matching: find.text(name));

  /// Что набрано в поле имени окна: поле ввода в нём одно.
  String nameField(WidgetTester tester) =>
      tester
          .widget<FcTextField>(
            find.descendant(of: find.byType(CommandDialogForm), matching: find.byType(FcTextField)).first,
          )
          .controller
          .text;

  /// То же, что шлёт раннер: имя события, точка и пути.
  Future<void> sendDrop(WidgetTester tester, String event, {Offset? at, List<String> paths = const []}) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      SystemDropService.channelName,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall(event, at == null ? null : {'x': at.dx, 'y': at.dy, 'paths': paths, 'move': false}),
      ),
      (_) {},
    );
    await tester.pumpAndSettle();
  }

  testWidgets('в дереве видны файлы, из которых окно читает, — и только они', (tester) async {
    await openImport(tester, 'Bring a set from a file');

    // Набор лежит в json: искать его среди картинок и архивов незачем.
    expect(inTree('work.json'), findsOneWidget);
    expect(inTree('notes.txt'), findsNothing);
    // Ветви на месте: в них тоже заходят.
    expect(inTree('docs'), findsOneWidget);

    await tester.pumpAndSettle();
  });

  testWidgets('выбранный в дереве файл сам встаёт в поле имени', (tester) async {
    await openImport(tester, 'Bring a set from a file');

    expect(nameField(tester), isNot('work.json'), reason: 'подставлено умолчание — проверять нечего');

    await tester.tap(inTree('work.json'));
    await tester.pumpAndSettle();

    // Набирать имя руками, когда файл виден в том же дереве, незачем.
    expect(nameField(tester), 'work.json');
    // И место — то, где он лежит.
    expect(find.text('/home'), findsWidgets);

    await tester.pumpAndSettle();
  });

  testWidgets('в файл не заходят: щелчок по нему только выбирает', (tester) async {
    await openImport(tester, 'Bring a set from a file');

    await tester.tap(inTree('work.json'));
    await tester.pumpAndSettle();
    await tester.tap(inTree('work.json'));
    await tester.pumpAndSettle();

    expect(nameField(tester), 'work.json');
    // Вложенного у файла нет, и строк от второго щелчка не прибавилось: в
    // дереве по-прежнему дом, каталог и файл.
    expect(find.descendant(of: find.byType(FcDirectoryTree), matching: find.byType(GestureDetector)), findsNWidgets(3));

    await tester.pumpAndSettle();
  });

  testWidgets('брошенный в дерево файл — тот же выбор', (tester) async {
    await openImport(tester, 'Bring a theme from a file');

    final tree = tester.getCenter(find.byType(FcDirectoryTree));
    await sendDrop(tester, 'dragEntered', at: tree, paths: const ['/home/docs/dark.json']);
    await sendDrop(tester, 'drop', at: tree, paths: const ['/home/docs/dark.json']);

    // Перетащить файл в окно короче, чем искать его в дереве.
    expect(nameField(tester), 'dark.json');
    expect(find.text('/home/docs'), findsWidgets, reason: 'место взято у брошенного');

    await tester.pumpAndSettle();
  });
}
