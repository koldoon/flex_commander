import 'package:fc_api/fc_api.dart';
import 'package:fc_file_icons/fc_file_icons.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/state/app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Прокрутка списка при смене каталога.
///
/// Проверяется не «докуда прокрутили», а **когда**: новый каталог должен
/// появиться уже прокрученным. Прокрутка после кадра — это видимый рывок,
/// и заметнее всего он при выходе наверх из длинного списка.
void main() {
  late InMemoryTreeProvider provider;
  late AppController app;

  setUp(() async {
    provider = InMemoryTreeProvider([
      FakeEntry.directory('/home'),
      FakeEntry.directory('/home/near'),
      FakeEntry.file('/home/near/inside.txt', size: 1),
      // Длинный список, в конце которого стоит каталог: возврат в него — это
      // и есть тот случай, когда список успевал мелькнуть началом.
      for (var i = 0; i < 60; i++) FakeEntry.directory('/home/dir-${i.toString().padLeft(2, '0')}'),
      FakeEntry.file('/home/dir-59/note.txt', size: 1),
    ]);
    final settings = AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home'));
    app = (await testApp(provider: provider, modules: featureModules(), settings: settings)).app;
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(802, 621);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(FlexCommanderApp(controller: app));
    await app.start();
    await tester.pumpAndSettle();
  }

  /// Смещение списка левой панели.
  double offsetOf(WidgetTester tester) => tester.widget<ListView>(find.byType(ListView).first).controller!.offset;

  /// Живой дефект: при крупных иконках курсор уезжал за нижний край.
  ///
  /// Прокрутку к курсору считали кеглем темы, а список размечен шагом, который
  /// зависит от размера иконки, — и промах рос вместе с ним.
  testWidgets('крупные иконки не роняют курсор за нижний край', (tester) async {
    final settings = AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home'));
    settings.modules.scope('fc.icons').section(FileIconSettings.new).size = 24;
    app = (await testApp(provider: provider, modules: featureModules(), settings: settings)).app;

    await pumpApp(tester);
    for (var i = 0; i < 40; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    }
    await tester.pumpAndSettle();

    final list = find.byType(ListView).first;
    final row = find.descendant(of: list, matching: find.text(app.left.currentEntry!.name));
    expect(row, findsOneWidget, reason: 'строки под курсором нет на экране вовсе');

    final viewport = tester.getRect(list);
    expect(
      tester.getRect(row).bottom,
      lessThanOrEqualTo(viewport.bottom),
      reason: 'строка под курсором вылезла за нижний край списка',
    );

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('возврат наверх ставит список туда, где стоит курсор', (tester) async {
    await pumpApp(tester);
    app.left.setCursorToName('dir-59');
    await tester.pumpAndSettle();

    // Вошли в каталог в конце длинного списка и сразу вернулись.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(app.leftSession.directory?.name, 'dir-59');

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    expect(app.left.currentEntry?.name, 'dir-59');
    expect(offsetOf(tester), greaterThan(0));

    // Отложенная запись настроек не должна остаться висеть после теста.
    await tester.pump(const Duration(milliseconds: 20));
  });

  /// Тот самый дефект: список рисовался началом, и только следующим кадром
  /// прокручивался к курсору. Проверяется не смещение (к моменту, когда его
  /// можно спросить, отложенная прокрутка уже сработала бы), а то, **нарисована
  /// ли** строка под курсором в этом кадре: при прокрутке после кадра её здесь
  /// нет вовсе.
  testWidgets('курсор виден в первом же кадре нового каталога', (tester) async {
    await pumpApp(tester);
    app.left.setCursorToName('dir-59');
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    // Строка под курсором нарисована, а не осталась за нижним краем.
    final row = find.descendant(of: find.byType(ListView).first, matching: find.text('dir-59'));
    expect(row, findsOneWidget);
    expect(tester.getBottomLeft(row).dy, lessThanOrEqualTo(tester.view.physicalSize.height));

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('короткий каталог не прокручивается вовсе', (tester) async {
    await pumpApp(tester);
    app.left.setCursorToName('near');
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    // Внутри всё помещается — прокручивать нечего.
    expect(offsetOf(tester), 0);

    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('внутри каталога прокрутка следует за курсором', (tester) async {
    await pumpApp(tester);
    expect(offsetOf(tester), 0);

    app.left.setCursorToLast();
    await tester.pumpAndSettle();

    expect(offsetOf(tester), greaterThan(0));
  });
}
