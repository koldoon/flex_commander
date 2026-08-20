import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:fc_viewer/fc_viewer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

/// Показ файла: заголовок, режимы и фокус.
///
/// Сам текст рисует `FcCodeView` — общий с редактором. Здесь проверяется то,
/// чем распоряжается просмотрщик: что он этому показу передаёт.
void main() {
  late InMemoryContentProvider disk;

  setUp(() {
    disk = InMemoryContentProvider([FakeEntry.directory('/home'), FakeEntry.file('/home/notes.txt', size: 1234)]);
  });

  Future<FsNode> node() async => (await disk.resolvePath('/home/notes.txt').result)!;

  Future<ViewerScreen> screenWith(String text, {bool wordWrap = false}) async =>
      ViewerScreen(node: await node(), text: text, wordWrap: wordWrap);

  testWidgets('заголовок — та же плашка, что у панели, с адресом и размером', (tester) async {
    await pumpScreen(tester, await screenWith('раз\nдва'));

    // Одна плашка на всё: рамку и заголовок просмотрщик берёт у общего
    // `FcPanelFrame` — того же, которым рисуется файловая панель.
    expect(find.byType(FcPanelFrame), findsOneWidget);
    final plate = tester.widget<FcPathPlate>(find.byType(FcPathPlate));

    // Полный адрес, а не одно имя: файл может лежать в архиве или на сервере.
    expect(plate.path, '/home/notes.txt');
    expect(plate.trailing, '1.2 KB');
    expect(find.text('/home/notes.txt'), findsOneWidget);

    await disposeScreen(tester);
  });

  testWidgets('плашка облегает содержимое, а не тянется на всю ширину', (tester) async {
    await pumpScreen(tester, await screenWith('раз'));

    final plate = tester.getRect(find.byType(FcPathPlate));
    final frame = tester.getRect(find.byType(FcPanelFrame));

    expect(plate.width, lessThan(frame.width / 2));
    // И наполовину заходит на верхнюю рамку — как у панели.
    expect(plate.top, frame.top);

    await disposeScreen(tester);
  });

  testWidgets('текст показывается, но не правится', (tester) async {
    final screen = await screenWith('раз\nдва');
    await pumpScreen(tester, screen);

    final view = tester.widget<FcCodeView>(find.byType(FcCodeView));

    expect(view.readOnly, isTrue);
    expect(view.controller.text, 'раз\nдва');

    await disposeScreen(tester);
  });

  testWidgets('фокус сразу в тексте: курсор доступен без щелчка мышью', (tester) async {
    // Прокрутка, выделение и `Cmd-C` — дело самого показа, и без фокуса не
    // работает ни одно из них.
    await pumpScreen(tester, await screenWith('раз\nдва'));

    final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));

    expect(editor.focusNode?.hasFocus, isTrue);

    await disposeScreen(tester);
  });

  group('перенос строк', () {
    testWidgets('выключен — показ возит текст и по ширине', (tester) async {
      await pumpScreen(tester, await screenWith('очень длинная строка ${'—' * 300}'));

      expect(tester.widget<FcCodeView>(find.byType(FcCodeView)).wordWrap, isFalse);

      await disposeScreen(tester);
    });

    testWidgets('включён — с самого открытия, если так было в прошлый раз', (tester) async {
      await pumpScreen(tester, await screenWith('раз', wordWrap: true));

      expect(tester.widget<FcCodeView>(find.byType(FcCodeView)).wordWrap, isTrue);

      await disposeScreen(tester);
    });

    testWidgets('переключение перерисовывает показ', (tester) async {
      final screen = await screenWith('очень длинная строка ${'—' * 300}');
      await pumpScreen(tester, screen);

      screen.toggleWordWrap();
      await tester.pump();

      expect(tester.widget<FcCodeView>(find.byType(FcCodeView)).wordWrap, isTrue);

      await disposeScreen(tester);
    });
  });
}
