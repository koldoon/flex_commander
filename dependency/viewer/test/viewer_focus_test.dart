import 'dart:convert';

import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_viewer/fc_viewer.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// После просмотрщика приложение обязано слышать клавиши.
///
/// Живая проверка показала обратное: файл открывался, `F2` и `Esc` работали, а
/// после закрытия окно переставало отзываться вовсе. Тест повторяет ту же
/// последовательность на настоящем приложении.
void main() {
  late AppRuntime runtime;

  setUp(() async {
    runtime = await testApp(
      provider: InMemoryContentProvider([
        FakeEntry.directory('/home'),
        FakeEntry.file('/home/notes.txt', content: utf8.encode('раз\nдва\nтри')),
      ])..home = '/home',
      modules: featureModules(),
    );
    await runtime.app.start();
  });

  testWidgets(
    'открыли, закрыли — и клавиши по-прежнему доходят',
    (tester) async => withDesktopPlatform(() async {
      await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
      await tester.pumpAndSettle();

      final wasActive = runtime.app.activePanel;

      runtime.app.left.setCursorToName('notes.txt');
      await (runtime.commands.create(ViewFileCommand.commandId)!).executeWith();
      await tester.pumpAndSettle();
      expect(runtime.app.view.contentAt(ViewportPosition.fullscreen), isA<ViewerScreen>());

      runtime.commands.dispatch(KeyCombination.parse('Esc'));
      await tester.pumpAndSettle();
      expect(runtime.app.view.contentAt(ViewportPosition.fullscreen), isNull);

      // Тот самый Tab, который в живом приложении перестал работать.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();

      expect(runtime.app.activePanel, isNot(same(wasActive)), reason: 'приложение оглохло после просмотрщика');

      await tester.pump(const Duration(milliseconds: 20));
    }),
  );
}
