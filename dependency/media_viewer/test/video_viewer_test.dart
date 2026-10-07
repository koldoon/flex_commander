import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_media_viewer/fc_media_viewer.dart';
import 'package:fc_viewer/fc_viewer.dart';
import 'package:flex_commander/app.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_video.dart';

/// Видео в собранном приложении (`docs/spec/video-viewer.md`): `F3` играет,
/// откуда бы ни был файл, отказы говорятся словами, быстрый просмотр сам не
/// играет и отпускает плееры.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppRuntime runtime;
  late InMemoryContentProvider provider;
  late FakeSystemVideo system;
  late FakeWindowService window;
  const right = ViewportPosition.right;
  final clip = List<int>.generate(4096, (i) => i % 251);

  Future<void> start({bool withSystem = true, bool autoplayQuickView = false, bool onDisk = true}) async {
    provider = InMemoryContentProvider([
      FakeEntry.directory('/home'),
      FakeEntry.file('/home/a.mp4', content: clip),
      FakeEntry.file('/home/b.mov', content: clip),
      FakeEntry.file('/home/c.mkv', content: clip),
      FakeEntry.file('/home/notes.txt', content: 'просто текст'.codeUnits),
      FakeEntry.file('/home/app.ts', content: 'export const a = 1;'.codeUnits),
    ])..home = '/home';
    system = FakeSystemVideo();
    window = FakeWindowService();
    final settings = AppSettings(left: PanelSettings.defaults('/home'), right: PanelSettings.defaults('/home'));
    settings.modules.scope(const MediaViewer().id).section(VideoViewerSettings.new).autoplayQuickView =
        autoplayQuickView;
    if (!onDisk) {
      // Источник без настоящих путей — как архив или сервер. До запуска:
      // настоящий путь строка получает при чтении каталога.
      provider.capabilities = const ProviderCapabilities(canSeek: true);
    }
    runtime = await testApp(
      provider: provider,
      modules: [...featureModules(), if (withSystem) FakeSystemVideoModule(system)],
      settings: settings,
      window: window,
    );
    await runtime.app.start();
  }

  tearDown(() async {
    // Показ держит таймеры опроса и плашки: закрыть всё, что осталось.
    for (final position in [ViewportPosition.fullscreen, right]) {
      runtime.app.view.contentAt(position)?.close();
    }
  });

  Future<void> view(String name) async {
    runtime.app.left.setCursorToName(name);
    await runtime.commands.create(ViewFileCommand.commandId)!.executeWith();
    await pumpEventQueue();
  }

  ViewportState? shownFullscreen() => runtime.app.view.contentAt(ViewportPosition.fullscreen);

  test('файл с диска играет с места и сразу', () async {
    await start();
    await view('a.mp4');

    expect(shownFullscreen(), isA<VideoViewerScreen>());
    expect(system.paths.single.$1, '/home/a.mp4', reason: 'настоящий файл не копируется');
    expect(system.opened.single.calls, contains('play'), reason: 'F3 играет сразу');
  });

  test('файл не с диска — копией с расширением, и копия убирается при закрытии', () async {
    await start(onDisk: false);

    await view('a.mp4');

    final (path, bytes) = system.paths.single;
    expect(path, isNot('/home/a.mp4'));
    expect(path, endsWith('a.mp4'), reason: 'по расширению система узнаёт формат');
    expect(bytes, clip, reason: 'в копии то, что в файле');

    expect(runtime.commands.dispatch(KeyCombination.parse('Esc')), isTrue);
    await pumpEventQueue();
    // Уборка идёт следом за закрытием плеера.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(system.opened.single.closed, isTrue);
    expect(File(path).existsSync(), isFalse, reason: 'копия осталась во временном каталоге');
  });

  test('формат, который система не играет, — отказ словами, а не байты текстом', () async {
    await start();
    system.refuse = (path) => path.endsWith('.mkv') ? SystemVideoRefused.unplayable : null;

    await view('c.mkv');

    expect(shownFullscreen(), isNull);
    expect(runtime.app.toasts.current?.message, contains('mkv'));
  });

  test('видео нет, только звук — так и сказано', () async {
    await start();
    system.refuse = (_) => SystemVideoRefused.noVideo;

    await view('a.mp4');

    expect(shownFullscreen(), isNull);
    expect(runtime.app.toasts.current?.message, contains('only sound'));
  });

  test('службы нет — отказ с советом открыть системой', () async {
    await start(withSystem: false);

    await view('a.mp4');

    expect(shownFullscreen(), isNull);
    expect(runtime.app.toasts.current?.message, contains('Cmd-O'));
  });

  test('текст по-прежнему открывает текстовый: реестр не перепутал', () async {
    await start();
    await view('notes.txt');

    expect(shownFullscreen(), isNot(isA<VideoViewerScreen>()));
    expect(system.paths, isEmpty);
  });

  test('`.ts` — исходник TypeScript, а не MPEG-TS: его берёт текстовый', () async {
    await start();
    await view('app.ts');

    expect(shownFullscreen(), isNot(isA<VideoViewerScreen>()));
    expect(system.paths, isEmpty);
  });

  test('F2 — пауза и пуск, F7 — звук, громкость помнится', () async {
    await start();
    await view('a.mp4');
    final player = system.opened.single;
    final screen = shownFullscreen()! as VideoViewerScreen;
    expect(screen.playing, isTrue);

    expect(runtime.commands.dispatch(KeyCombination.parse('F2')), isTrue);
    await pumpEventQueue();
    expect(screen.playing, isFalse);
    expect(player.calls.last, 'pause');

    expect(runtime.commands.dispatch(KeyCombination.parse('F7')), isTrue);
    await pumpEventQueue();
    expect(player.calls.last, 'muted true');
    expect(screen.settings.muted, isTrue);
  });

  test('F5 — окно соотношений: выбор виден сразу, Esc возвращает прежнее', () async {
    await start();
    await view('a.mp4');
    final screen = shownFullscreen()! as VideoViewerScreen;
    expect(screen.aspect, VideoAspect.original);

    expect(runtime.commands.dispatch(KeyCombination.parse('F5')), isTrue);
    await pumpEventQueue();
    final dialog = runtime.app.view.dialogs.single;
    expect(dialog.title, 'Aspect ratio');

    // То, чем окно ходит по списку: кадр меняется на каждом шаге.
    final picker = VideoAspectPickerState(screen);
    picker.index = VideoAspect.all.indexWhere((aspect) => aspect.label == '4:3');
    expect(screen.aspect.ratio, 4 / 3);
    picker.revert();
    expect(screen.aspect, VideoAspect.original);

    dialog.onDismiss!();
    expect(runtime.app.view.dialogs, isEmpty);
  });

  testWidgets('окно соотношений: стрелка меняет кадр сразу, Esc возвращает', (tester) async {
    await tester.runAsync(start);
    await tester.pumpWidget(FlexCommanderApp(controller: runtime.app));
    await tester.runAsync(() => view('a.mp4'));
    await tester.pumpAndSettle();
    final screen = shownFullscreen()! as VideoViewerScreen;

    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pumpAndSettle();
    expect(find.text('Aspect ratio'), findsOneWidget);
    expect(find.text('16:9'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(screen.aspect.label, '1:1', reason: 'выбранное видно сразу, без OK');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(runtime.app.view.dialogs, isEmpty);
    expect(screen.aspect, VideoAspect.original);
    screen.close();
    await tester.pumpAndSettle();
  });

  test('соотношение не запоминается: новый файл начинает с Original', () async {
    await start();
    await view('a.mp4');
    (shownFullscreen()! as VideoViewerScreen).aspect = VideoAspect.all.last;

    shownFullscreen()!.close();
    await view('b.mov');

    expect((shownFullscreen()! as VideoViewerScreen).aspect, VideoAspect.original);
  });

  test('в быстром просмотре соотношение помнится, пока он открыт', () async {
    await start();
    Future<VideoViewerScreen> quick(String name) async {
      runtime.app.left.setCursorToName(name);
      await Future<void>.delayed(QuickViewHost.defaultDelay * 2);
      await pumpEventQueue();
      return innermost(runtime.app.view.contentAt(right)!)! as VideoViewerScreen;
    }

    runtime.app.left.setCursorToName('a.mp4');
    expect(runtime.commands.dispatch(KeyCombination.parse('Shift-F3')), isTrue);
    final fourThirds = VideoAspect.all.firstWhere((aspect) => aspect.label == '4:3');
    (await quick('a.mp4')).aspect = fourThirds;

    expect((await quick('b.mov')).aspect, VideoAspect.original, reason: 'у соседа своё');
    expect((await quick('a.mp4')).aspect, fourThirds, reason: 'вернулись — как оставили');

    // Закрыли просмотр — забыто.
    expect(runtime.commands.dispatch(KeyCombination.parse('Shift-F3')), isTrue);
    await pumpEventQueue();
    expect(runtime.commands.dispatch(KeyCombination.parse('Shift-F3')), isTrue);
    expect((await quick('a.mp4')).aspect, VideoAspect.original);
  });

  test('Cmd-I показывает сведения окном', () async {
    await start();
    await view('a.mp4');

    expect(runtime.commands.dispatch(KeyCombination.parse('Cmd-I')), isTrue);
    await pumpEventQueue();

    expect(runtime.app.view.dialogs.single.title, 'a.mp4');
  });

  test('быстрый просмотр сам не играет и отпускает прежний плеер на шаге курсора', () async {
    await start();
    runtime.app.left.setCursorToName('a.mp4');
    expect(runtime.commands.dispatch(KeyCombination.parse('Shift-F3')), isTrue);
    await Future<void>.delayed(QuickViewHost.defaultDelay * 2);
    await pumpEventQueue();

    final host = runtime.app.view.contentAt(right)! as QuickViewHost;
    expect(innermost(host), isA<VideoViewerScreen>());
    expect(system.opened.single.calls, isNot(contains('play')), reason: 'ход по каталогу роликов включал бы звук');

    runtime.app.left.setCursorToName('b.mov');
    await Future<void>.delayed(QuickViewHost.defaultDelay * 2);
    await pumpEventQueue();

    expect((innermost(host) as VideoViewerScreen).entry.name, 'b.mov');
    expect(system.opened.first.closed, isTrue, reason: 'иначе звук прежнего ролика играл бы дальше');
    expect(system.opened.last.closed, isFalse);
  });

  test('настройка «Autoplay videos in quick preview» — быстрый просмотр играет сразу', () async {
    await start(autoplayQuickView: true);
    runtime.app.left.setCursorToName('a.mp4');
    expect(runtime.commands.dispatch(KeyCombination.parse('Shift-F3')), isTrue);
    await Future<void>.delayed(QuickViewHost.defaultDelay * 2);
    await pumpEventQueue();

    final host = runtime.app.view.contentAt(right)! as QuickViewHost;
    expect(innermost(host), isA<VideoViewerScreen>());
    expect(system.opened.single.calls, contains('play'));
  });

  test('F — во весь экран и окно в полный экран; Esc выходит, второй Esc закрывает', () async {
    await start();
    await view('a.mp4');
    final screen = shownFullscreen()! as VideoViewerScreen;

    expect(runtime.commands.dispatch(KeyCombination.parse('F')), isTrue);
    await pumpEventQueue();
    expect(screen.fullScreen, isTrue);
    expect(window.fullScreen, isTrue, reason: 'ролик во весь экран — и окно во весь экран');

    expect(runtime.commands.dispatch(KeyCombination.parse('Esc')), isTrue);
    await pumpEventQueue();
    expect(screen.fullScreen, isFalse);
    expect(window.fullScreen, isFalse, reason: 'окно возвращается каким было');
    expect(shownFullscreen(), same(screen), reason: 'первый Esc снимает полный экран, а не закрывает показ');

    expect(runtime.commands.dispatch(KeyCombination.parse('Esc')), isTrue);
    await pumpEventQueue();
    expect(shownFullscreen(), isNull);
  });

  test('окно было в полном экране и до — выход из полного экрана ролика его не трогает', () async {
    await start();
    window.fullScreen = true;
    await view('a.mp4');
    final screen = shownFullscreen()! as VideoViewerScreen;

    await screen.toggleFullScreen();
    await screen.toggleFullScreen();

    expect(screen.fullScreen, isFalse);
    expect(window.fullScreen, isTrue);
  });

  test('закрыли из полного экрана — окно вернулось', () async {
    await start();
    await view('a.mp4');
    final screen = shownFullscreen()! as VideoViewerScreen;
    await screen.toggleFullScreen();
    expect(window.fullScreen, isTrue);

    expect(runtime.commands.dispatch(KeyCombination.parse('F10')), isTrue);
    await pumpEventQueue();
    // F10 тоже сперва снимает полный экран — это та же команда закрытия.
    expect(runtime.commands.dispatch(KeyCombination.parse('F10')), isTrue);
    await pumpEventQueue();

    expect(shownFullscreen(), isNull);
    expect(window.fullScreen, isFalse);
  });

  /// Живой дефект: в находках поиска источник — не файловая система, и
  /// большой файл ехал копией через ядро. Путь берётся у строки.
  test('у строки есть настоящий путь — играет с места, даже если источник не диск', () async {
    await start();
    final request = ViewerRequest(
      app: runtime.app,
      entry: const FileEntry(
        name: 'found.mp4',
        kind: EntryKind.file,
        path: 'search:/found.mp4',
        realPath: '/disk/found.mp4',
        size: 3 * 1024,
      ),
      content: _Chunks(3),
      place: ViewerPlace.fullscreen,
      checkpoint: () async {},
    );

    final source = await MediaSource.prepare(request);

    expect(source.path, '/disk/found.mp4');
    expect(source.copied, isFalse);
  });

  test('курсор ушёл посреди копии — копия убрана, плеер не открывался', () async {
    await start();
    final root = await Directory.systemTemp.createTemp('fc-video-test-');
    addTearDown(() => root.delete(recursive: true));
    var calls = 0;
    final request = ViewerRequest(
      app: runtime.app,
      entry: const FileEntry(name: 'far.mp4', kind: EntryKind.file, path: 'ssh://host/far.mp4', size: 3 * 1024),
      content: _Chunks(3),
      place: ViewerPlace.panel,
      // Первый кусок прошёл, на втором курсор уже ушёл дальше.
      checkpoint: () async {
        if (++calls > 1) {
          throw const OperationCanceled();
        }
      },
    );

    await expectLater(MediaSource.prepare(request, under: root), throwsA(isA<OperationCanceled>()));

    expect(root.listSync(), isEmpty, reason: 'недокачанная копия осталась во временном каталоге');
    expect(system.paths, isEmpty);
  });
}

/// Содержимое из [count] кусков по килобайту.
class _Chunks implements Content {
  _Chunks(this.count);

  final int count;

  @override
  int get length => count * 1024;

  @override
  Stream<List<int>> read({int offset = 0}) async* {
    for (var i = 0; i < count; i++) {
      yield List.filled(1024, i);
    }
  }
}
