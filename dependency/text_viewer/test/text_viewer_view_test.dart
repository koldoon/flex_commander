import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_text_kit/fc_text_kit.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:fc_text_viewer/fc_text_viewer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

/// Показ файла: заголовок, режимы и фокус.
///
/// Сам текст рисует `FcTextView` — общий с редактором. Здесь проверяется то,
/// чем распоряжается просмотрщик: что он этому показу передаёт.
void main() {
  late InMemoryContentProvider disk;

  setUp(() {
    disk = InMemoryContentProvider([FakeEntry.directory('/home'), FakeEntry.file('/home/notes.txt', size: 1234)]);
  });

  Future<FsNode> node() async => (await disk.resolvePath().run('/home/notes.txt'))!;

  Future<TextViewerScreen> screenWith(String text, {bool wordWrap = false}) async =>
      TextViewerScreen(node: await node(), text: text, wordWrap: wordWrap);

  testWidgets(
    'заголовок — та же плашка, что у панели, с адресом и размером',
    (tester) async => withDesktopPlatform(() async {
      await pumpScreen(tester, TextViewerView(screen: await screenWith('раз\nдва')));

      // Одна плашка на всё: рамку и заголовок просмотрщик берёт у общего
      // `FcPanelFrame` — того же, которым рисуется файловая панель.
      expect(find.byType(FcPanelFrame), findsOneWidget);
      final plate = tester.widget<FcPathPlate>(find.byType(FcPathPlate));

      // Полный адрес, а не одно имя: файл может лежать в архиве или на сервере.
      expect(plate.path, '/home/notes.txt');
      expect(plate.trailing, '1.2 KB');
      expect(find.text('/home/notes.txt'), findsOneWidget);

      await disposeScreen(tester);
    }),
  );

  testWidgets(
    'плашка облегает содержимое, а не тянется на всю ширину',
    (tester) async => withDesktopPlatform(() async {
      await pumpScreen(tester, TextViewerView(screen: await screenWith('раз')));

      final plate = tester.getRect(find.byType(FcPathPlate));
      final frame = tester.getRect(find.byType(FcPanelFrame));

      expect(plate.width, lessThan(frame.width / 2));
      // И наполовину заходит на верхнюю рамку — как у панели.
      expect(plate.top, frame.top);

      await disposeScreen(tester);
    }),
  );

  testWidgets(
    'текст показывается, но не правится',
    (tester) async => withDesktopPlatform(() async {
      final screen = await screenWith('раз\nдва');
      await pumpScreen(tester, TextViewerView(screen: screen));

      final view = tester.widget<FcTextView>(find.byType(FcTextView));

      expect(view.readOnly, isTrue);
      expect(view.controller.text, 'раз\nдва');

      await disposeScreen(tester);
    }),
  );

  testWidgets(
    'фокус сразу в тексте: курсор доступен без щелчка мышью',
    (tester) async => withDesktopPlatform(() async {
      // Прокрутка, выделение и `Cmd-C` — дело самого показа, и без фокуса не
      // работает ни одно из них.
      await pumpScreen(tester, TextViewerView(screen: await screenWith('раз\nдва')));

      final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));

      expect(editor.focusNode?.hasFocus, isTrue);

      await disposeScreen(tester);
    }),
  );

  testWidgets(
    'PgDn и PgUp листают текст',
    (tester) async => withDesktopPlatform(() async {
      // Прокрутка теперь дело самого показа, а не команд просмотрщика. В
      // библиотеке страница вверх и вниз не назначены ни на одну клавишу —
      // клавиши им даёт `FcTextShortcuts`.
      final screen = await screenWith(List.generate(500, (i) => 'строка $i').join('\n'));
      await pumpScreen(tester, TextViewerView(screen: screen));
      expect(screen.controller.selection.baseIndex, 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pump();
      final afterDown = screen.controller.selection.baseIndex;

      expect(afterDown, greaterThan(5), reason: 'PgDn не долистала');

      await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
      await tester.pump();

      expect(screen.controller.selection.baseIndex, lessThan(afterDown));
      await disposeScreen(tester);
    }),
  );

  group('перенос строк', () {
    testWidgets(
      'выключен — показ возит текст и по ширине',
      (tester) async => withDesktopPlatform(() async {
        await pumpScreen(tester, TextViewerView(screen: await screenWith('очень длинная строка ${'—' * 300}')));

        expect(tester.widget<FcTextView>(find.byType(FcTextView)).wordWrap, isFalse);

        await disposeScreen(tester);
      }),
    );

    testWidgets(
      'включён — с самого открытия, если так было в прошлый раз',
      (tester) async => withDesktopPlatform(() async {
        await pumpScreen(tester, TextViewerView(screen: await screenWith('раз', wordWrap: true)));

        expect(tester.widget<FcTextView>(find.byType(FcTextView)).wordWrap, isTrue);

        await disposeScreen(tester);
      }),
    );

    testWidgets(
      'переключение перерисовывает показ',
      (tester) async => withDesktopPlatform(() async {
        final screen = await screenWith('очень длинная строка ${'—' * 300}');
        await pumpScreen(tester, TextViewerView(screen: screen));

        screen.toggleWordWrap();
        await tester.pump();

        expect(tester.widget<FcTextView>(find.byType(FcTextView)).wordWrap, isTrue);

        await disposeScreen(tester);
      }),
    );
  });
}
