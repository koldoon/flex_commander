import 'package:fc_api/fc_api.dart';
import 'package:fc_image_viewer/fc_image_viewer.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_text_viewer/fc_text_viewer.dart';
import 'package:fc_viewer/fc_viewer.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'images.dart';

/// Картинки в собранном приложении: `F3` открывает их, а не текст, и то же
/// самое видно в быстром просмотре.
void main() {
  // Распаковка картинок идёт движком показа, а он живёт в связке с Flutter.
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppRuntime runtime;
  const right = ViewportPosition.right;

  setUp(() async {
    runtime = await testApp(
      provider: InMemoryContentProvider([
        FakeEntry.directory('/home'),
        FakeEntry.file('/home/a.png', content: imageOf(pngData)),
        FakeEntry.file('/home/b.gif', content: imageOf(gifData)),
        FakeEntry.file('/home/c.bmp', content: imageOf(bmpData)),
        FakeEntry.file('/home/notes.txt', content: 'просто текст'.codeUnits),
      ])..home = '/home',
      modules: featureModules(),
    );
    await runtime.app.start();
  });

  /// Открывает то, что под курсором, — тем же путём, каким это делает `F3`.
  Future<void> view(String name) async {
    runtime.app.left.setCursorToName(name);
    await runtime.commands.create(ViewFileCommand.commandId)!.executeWith();
    await pumpEventQueue();
  }

  ViewportState? shownFullscreen() => runtime.app.view.contentAt(ViewportPosition.fullscreen);

  group('чем открывается', () {
    test('картинку открывает просмотрщик изображений', () async {
      await view('a.png');

      final screen = shownFullscreen();
      expect(screen, isA<ImageViewerScreen>());
      expect((screen! as ImageViewerScreen).document.format, 'PNG');
      expect((screen as ImageViewerScreen).document.width, 6);
    });

    test('текст по-прежнему открывает текстовый: реестр не перепутал', () async {
      await view('notes.txt');

      expect(shownFullscreen(), isA<TextViewerScreen>());
    });

    test('картинка внутри чужого источника читается так же', () async {
      // Провайдер в памяти — такой же «не диск», как архив или сервер: байты
      // приходят контрактом, и просмотрщику всё равно, откуда.
      await view('c.bmp');

      expect((shownFullscreen()! as ImageViewerScreen).document.format, 'BMP');
    });
  });

  group('листание каталога', () {
    test('стрелка показывает соседнюю картинку, не трогая курсор панели', () async {
      await view('a.png');
      final cursor = runtime.app.left.currentNode?.name;

      expect(runtime.commands.dispatch(KeyCombination.parse('Right')), isTrue);
      await pumpEventQueue();

      final screen = shownFullscreen()! as ImageViewerScreen;
      expect(screen.node.name, 'b.gif');
      expect(screen.document.format, 'GIF');
      expect(runtime.app.left.currentNode?.name, cursor, reason: 'показ — не навигация');
    });

    test('следующая распакована до подмены: чужих пропорций не мелькает', () async {
      await view('a.png');
      final screen = shownFullscreen()! as ImageViewerScreen;

      // У соседа другое соотношение сторон (6×4 против 4×2) — на нём это и
      // было видно: полсекунды прежняя картинка стояла растянутой в новую
      // коробку, пока шла распаковка.
      await screen.step(1);

      expect(screen.document.width, 4);
      expect(screen.document.height, 2);
      expect(
        PaintingBinding.instance.imageCache.containsKey(screen.document.image),
        isTrue,
        reason: 'показ обязан нарисовать её первым же кадром',
      );
    });

    test('текст соседом не считается', () async {
      await view('c.bmp');

      // За `c.bmp` идёт `notes.txt` — но листается альбом, а не каталог.
      expect((shownFullscreen()! as ImageViewerScreen).hasNext, isFalse);
    });

    test('в конце списка стрелка молчит: по кругу не ходим', () async {
      await view('c.bmp');

      expect(runtime.commands.dispatch(KeyCombination.parse('Right')), isFalse);
      expect((shownFullscreen()! as ImageViewerScreen).node.name, 'c.bmp');
    });

    test('назад — та же дорога', () async {
      await view('b.gif');

      expect(runtime.commands.dispatch(KeyCombination.parse('Left')), isTrue);
      await pumpEventQueue();

      expect((shownFullscreen()! as ImageViewerScreen).node.name, 'a.png');
    });
  });

  group('масштаб', () {
    test('F2 переключает «вписать» и «точка в точку»', () async {
      await view('a.png');
      final screen = shownFullscreen()! as ImageViewerScreen;
      final fitted = screen.fitToWindow;

      expect(runtime.commands.dispatch(KeyCombination.parse('F2')), isTrue);
      await pumpEventQueue();

      expect(screen.fitToWindow, !fitted);
    });

    test('«+» приближает, «−» отдаляет', () async {
      await view('a.png');
      final screen = shownFullscreen()! as ImageViewerScreen;

      expect(runtime.commands.dispatch(KeyCombination.parse('+')), isTrue);
      await pumpEventQueue();
      expect(screen.zoom, greaterThan(1));

      final zoomed = screen.zoom;
      expect(runtime.commands.dispatch(KeyCombination.parse('-')), isTrue);
      await pumpEventQueue();
      expect(screen.zoom, lessThan(zoomed));
    });

    test('дальше предела не приближается', () async {
      await view('a.png');
      final screen = shownFullscreen()! as ImageViewerScreen;

      for (var i = 0; i < 40; i++) {
        screen.zoomBy(ImageViewerScreen.zoomStep);
      }

      expect(screen.zoom, ImageViewerScreen.maxZoom);
    });
  });

  group('быстрый просмотр', () {
    test('показывает картинку и меняет её на шаг курсора', () async {
      runtime.app.left.setCursorToName('a.png');
      expect(runtime.commands.dispatch(KeyCombination.parse('Shift-F3')), isTrue);
      await Future<void>.delayed(QuickViewHost.defaultDelay * 2);
      await pumpEventQueue();

      final host = runtime.app.view.contentAt(right)! as QuickViewHost;
      expect(innermost(host), isA<ImageViewerScreen>());

      runtime.app.left.setCursorToName('notes.txt');
      await Future<void>.delayed(QuickViewHost.defaultDelay * 2);
      await pumpEventQueue();

      // Меняется не файл, а сам просмотрщик — ради этого хозяин и заводился.
      expect(innermost(host), isA<TextViewerScreen>());
    });
  });
}
