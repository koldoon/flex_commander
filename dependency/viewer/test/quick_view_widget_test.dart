import 'dart:convert';

import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_panels/fc_panels.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_text_kit/fc_text_kit.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:fc_viewer/fc_viewer.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Быстрый просмотр на настоящем приложении: он и правда занимает область
/// панели, а не открывается во весь экран.
void main() {
  late AppRuntime runtime;

  setUp(() async {
    runtime = await testApp(
      provider: InMemoryContentProvider([
        FakeEntry.directory('/home'),
        FakeEntry.file('/home/notes.txt', content: utf8.encode('раз\nдва\nтри')),
        FakeEntry.directory('/home/docs'),
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

  testWidgets(
    'показ встаёт рядом с файлами, а не поверх них',
    (tester) async => withDesktopPlatform(() async {
      await pumpApp(tester);
      runtime.app.left.setCursorToName('notes.txt');

      runtime.commands.dispatch(KeyCombination.parse('Shift-F3'));
      await tester.pump(QuickViewHost.defaultDelay * 2);
      await tester.pumpAndSettle();

      // Список файлов на месте — просмотр занял только соседнюю область.
      expect(find.byType(FileTable), findsOneWidget);
      expect(find.byType(FcTextView), findsOneWidget);
      // Текст рисует `re_editor` своим слоем, и виджетами его не найти —
      // спрашиваем то, что ему передано.
      expect(tester.widget<FcTextView>(find.byType(FcTextView)).controller.text, 'раз\nдва\nтри');

      // Рамка внешняя со своей стороны: показ встал на место правой панели и
      // обязан выглядеть так же, как она.
      final text = tester.widget<FcTextView>(find.byType(FcTextView));
      expect(text.outerEdge, PanelOuterEdge.right);
      expect(text.focused, isFalse, reason: 'ввод остался у файловой панели');

      // И стоит он правее списка.
      expect(tester.getCenter(find.byType(FcTextView)).dx, greaterThan(tester.getCenter(find.byType(FileTable)).dx));
    }),
  );

  testWidgets(
    'яркая плашка одна: у того, кому достаются клавиши',
    (tester) async => withDesktopPlatform(() async {
      await pumpApp(tester);
      runtime.app.left.setCursorToName('notes.txt');
      runtime.commands.dispatch(KeyCombination.parse('Shift-F3'));
      await tester.pump(QuickViewHost.defaultDelay * 2);
      await tester.pumpAndSettle();

      /// Плашка по адресу в ней: у панели — каталог, у показа — файл.
      bool bright(String path) =>
          tester.widget<FcPathPlate>(find.byWidgetPredicate((w) => w is FcPathPlate && w.path == path)).active;

      // Ввод у файлов: горит их плашка, показ приглушён.
      expect(bright('/home'), isTrue);
      expect(bright('/home/notes.txt'), isFalse);

      runtime.app.toggleActivePanel();
      await tester.pumpAndSettle();

      // Ввод ушёл в показ — и это видно, хотя курсор в списке остался: он
      // говорит про источник операции, а плашка про клавиши.
      expect(bright('/home'), isFalse);
      expect(bright('/home/notes.txt'), isTrue);
    }),
  );

  testWidgets(
    'вошли в показ — фокус его, вышли — снова файлов',
    (tester) async => withDesktopPlatform(() async {
      await pumpApp(tester);
      runtime.app.left.setCursorToName('notes.txt');
      runtime.commands.dispatch(KeyCombination.parse('Shift-F3'));
      await tester.pump(QuickViewHost.defaultDelay * 2);
      await tester.pumpAndSettle();

      runtime.app.toggleActivePanel();
      await tester.pumpAndSettle();

      expect(tester.widget<FcTextView>(find.byType(FcTextView)).focused, isTrue);

      runtime.commands.dispatch(KeyCombination.parse('Tab'));
      await tester.pumpAndSettle();

      expect(tester.widget<FcTextView>(find.byType(FcTextView)).focused, isFalse);
    }),
  );

  testWidgets(
    'под курсором каталог — о нём и рассказывают, а не отговариваются словом',
    (tester) async => withDesktopPlatform(() async {
      await pumpApp(tester);
      runtime.app.left.setCursorToName('docs');

      runtime.commands.dispatch(KeyCombination.parse('Shift-F3'));
      await tester.pump(QuickViewHost.defaultDelay * 2);
      await tester.pumpAndSettle();

      // Заглушка «Directory» была временной — до модуля сведений. Текста в
      // каталоге нет, а сведения есть: имя, путь, тип. Кто именно их
      // рассказывает, оболочке знать незачем — это дело реестра.
      expect(find.byType(FcTextView), findsNothing);
      expect(find.text('/home/docs'), findsWidgets);
    }),
  );
}
