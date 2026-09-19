import 'package:fc_api/fc_api.dart';
import 'package:fc_file_ops/fc_file_ops.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_navigation/fc_navigation.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Вставка из буфера (`docs/spec/file-clipboard.md`, §4).
///
/// Проверяется целиком — от нажатия до изменившейся панели: вставка не делает
/// своей работы, она начинает ту же, что `F5` и `F6`, а та рисует своё окно.
void main() {
  late InMemoryTreeProvider provider;
  late FakeFileClipboard files;
  late AppController app;

  setUp(() async {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/target'),
      FakeEntry.file('/home/notes.txt', size: 10),
      FakeEntry.file('/home/report.md', size: 20),
    ]);
    files = FakeFileClipboard();
    final settings = AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home/target'));
    app =
        (await testApp(
          provider: provider,
          modules: [const Navigation(), const FileOps()],
          settings: settings,
          fileClipboard: files,
        )).app;
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(802, 621);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: app));
    await app.start();
    await tester.pumpAndSettle();
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
  }

  /// Нажимает сочетание с `Cmd` — так, как это делает клавиатура.
  ///
  /// Платформа в виджетных тестах не macOS, поэтому «командная» клавиша здесь
  /// `Ctrl`: ровно то, во что `KeyCombination` сворачивает `Cmd` вне macOS.
  Future<void> press(WidgetTester tester, LogicalKeyboardKey key, {bool alt = false}) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    if (alt) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    }
    await tester.sendKeyEvent(key);
    if (alt) {
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pumpAndSettle();
  }

  List<String> namesIn(Session panel) => panel.entries.map((entry) => entry.name).toList();

  /// Берёт объект под курсором в буфер и уходит в правую панель.
  Future<void> takeAndGoRight(WidgetTester tester, {required bool cut}) async {
    app.left.setCursorToName('notes.txt');
    await tester.pump();
    await press(tester, cut ? LogicalKeyboardKey.keyX : LogicalKeyboardKey.keyC);
    app.activate(app.right);
    await tester.pumpAndSettle();
  }

  testWidgets('Cmd-V открывает окно копирования с каталогом активной панели', (tester) async {
    await pumpApp(tester);
    await takeAndGoRight(tester, cut: false);

    await press(tester, LogicalKeyboardKey.keyV);

    // Та же работа, что `F5`: то же окно и тот же заголовок.
    expect(find.text('Copy «notes.txt»'), findsOneWidget);

    await tester.tap(find.widgetWithText(FcButton, 'Copy'));
    await settle(tester);

    expect(namesIn(app.right), contains('notes.txt'));
    expect(namesIn(app.left), contains('notes.txt'), reason: 'копирование не должно трогать источник');
  });

  testWidgets('Cmd-X ничего не трогает, а вставка переносит', (tester) async {
    await pumpApp(tester);
    await takeAndGoRight(tester, cut: true);

    // «Вырезать» — намерение, а не действие (§5).
    expect(namesIn(app.left), contains('notes.txt'));

    await press(tester, LogicalKeyboardKey.keyV);
    expect(find.text('Move «notes.txt»'), findsOneWidget, reason: 'вставка не узнала о намерении переносить');

    await tester.tap(find.widgetWithText(FcButton, 'Move'));
    await settle(tester);

    expect(namesIn(app.right), contains('notes.txt'));
    expect(namesIn(app.left), isNot(contains('notes.txt')));
  });

  testWidgets('чужая запись в буфер роняет перенос до копии', (tester) async {
    await pumpApp(tester);
    await takeAndGoRight(tester, cut: true);

    // Между «вырезать» и «вставить» в буфер написали снаружи (§5).
    files.putForeign(['/home/report.md']);

    await press(tester, LogicalKeyboardKey.keyV);

    expect(find.text('Copy «report.md»'), findsOneWidget, reason: 'чужой буфер не даёт права переносить');
  });

  testWidgets('Alt-Cmd-V переносит и то, что копировали', (tester) async {
    await pumpApp(tester);
    await takeAndGoRight(tester, cut: false);

    await press(tester, LogicalKeyboardKey.keyV, alt: true);

    expect(find.text('Move «notes.txt»'), findsOneWidget);
  });
}
