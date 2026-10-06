import 'dart:io';
import 'dart:typed_data';

import 'package:fc_api/fc_api.dart';
import 'package:fc_media_viewer/fc_media_viewer.dart';
import 'package:fc_test_kit/fc_test_kit.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_viewer/fc_viewer.dart';
import 'package:flex_commander/bootstrap/app_modules.dart';
import 'package:flex_commander/bootstrap/app_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_video.dart';

/// Звук в собранном приложении (`docs/spec/audio-viewer.md`): `F3` играет,
/// теги видны, доиграл — следующий трек альбома, отказы — словами.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppRuntime runtime;
  late InMemoryContentProvider provider;
  late FakeSystemVideo system;
  const right = ViewportPosition.right;
  final song = List<int>.generate(2048, (i) => i % 251);
  final cover = Uint8List.fromList([1, 2, 3, 4]);

  Future<void> start({bool autoplayQuickView = false}) async {
    provider = InMemoryContentProvider([
      FakeEntry.directory('/music'),
      FakeEntry.file('/music/01 Intro.mp3', content: song),
      FakeEntry.file('/music/02 Song.mp3', content: song),
      // Обложка и записка рядом с альбомом — не треки.
      FakeEntry.file('/music/03 cover.jpg', content: [0xFF, 0xD8, 0xFF]),
      FakeEntry.file('/music/04 Bonus.ogg', content: song),
      FakeEntry.file('/music/05 Outro.mp3', content: song),
      FakeEntry.file('/music/06 notes.txt', content: 'текст'.codeUnits),
      FakeEntry.file('/music/clip.mp4', content: song),
    ])..home = '/music';
    system = FakeSystemVideo(
      refuse: (path) => path.endsWith('.ogg') ? SystemVideoRefused.unplayable : null,
      tagsOf:
          (path) =>
              path.endsWith('01 Intro.mp3')
                  ? SystemAudioTags(title: 'Intro', artist: 'Band', album: 'Record', year: '2019', artwork: cover)
                  : const SystemAudioTags(),
    );
    final settings = AppSettings(left: PanelSettings.defaults('/music'), right: PanelSettings.defaults('/music'));
    settings.modules.scope(const MediaViewer().id).section(VideoViewerSettings.new).autoplayQuickView =
        autoplayQuickView;
    runtime = await testApp(
      provider: provider,
      modules: [...featureModules(), FakeSystemVideoModule(system)],
      settings: settings,
    );
    await runtime.app.start();
  }

  tearDown(() async {
    for (final position in [ViewportPosition.fullscreen, right]) {
      runtime.app.view.contentAt(position)?.close();
    }
  });

  Future<void> view(String name) async {
    runtime.app.left.setCursorToName(name);
    await runtime.commands.create(ViewFileCommand.commandId)!.executeWith();
    await pumpEventQueue();
  }

  AudioViewerScreen shown() => runtime.app.view.contentAt(ViewportPosition.fullscreen)! as AudioViewerScreen;

  FakeAudioPlayer playerOf(int index) => system.opened[index] as FakeAudioPlayer;

  /// Дождаться опроса плеера: он ходит по таймеру.
  Future<void> poll() async {
    await Future<void>.delayed(AudioViewerScreen.pollEvery * 2);
    await pumpEventQueue();
  }

  test('mp3 открывается звуковым показом с тегами и играет сразу', () async {
    await start();
    await view('01 Intro.mp3');

    final screen = shown();
    expect(screen.player.tags.title, 'Intro');
    expect(screen.player.tags.artwork, cover);
    expect(playerOf(0).calls, contains('play'));
    expect(system.paths.single.$1, '/music/01 Intro.mp3', reason: 'файл с диска не копируется');
  });

  test('доиграл — следующий трек альбома, прежний плеер закрыт', () async {
    await start();
    await view('01 Intro.mp3');
    final screen = shown();

    playerOf(0).ended = true;
    await poll();

    expect(screen.entry.name, '02 Song.mp3', reason: 'обложка и записки в альбом не входят');
    expect(playerOf(0).closed, isTrue, reason: 'звук прежнего трека играл бы поверх');
    expect(playerOf(1).calls, contains('play'));
    expect(runtime.app.left.currentEntry?.name, '01 Intro.mp3', reason: 'курсор панели не двигается');
  });

  test('трек, который система не играет, пропускается', () async {
    await start();
    await view('02 Song.mp3');
    final screen = shown();

    expect(await screen.next(), isTrue);

    expect(screen.entry.name, '05 Outro.mp3');
    expect(system.paths.map((path) => path.$1), contains('/music/04 Bonus.ogg'));
  });

  test('последний доиграл — стоит', () async {
    await start();
    await view('05 Outro.mp3');
    final screen = shown();

    playerOf(0).ended = true;
    await poll();

    expect(screen.entry.name, '05 Outro.mp3');
    expect(system.opened, hasLength(1));
    expect(await screen.next(), isFalse);
  });

  test('PgUp — предыдущий трек', () async {
    await start();
    await view('02 Song.mp3');
    final screen = shown();

    expect(await screen.previous(), isTrue);
    expect(screen.entry.name, '01 Intro.mp3');
    expect(await screen.previous(), isFalse, reason: 'раньше первого некуда');
  });

  test('ogg открыт напрямую — отказ словами', () async {
    await start();
    await view('04 Bonus.ogg');

    expect(runtime.app.view.contentAt(ViewportPosition.fullscreen), isNull);
    expect(runtime.app.toasts.current?.message, contains('ogg'));
  });

  test('громкость общая с видео', () async {
    await start();
    await view('01 Intro.mp3');
    await shown().changeVolume(-AudioViewerScreen.volumeStep);
    expect(runtime.commands.dispatch(KeyCombination.parse('Esc')), isTrue);
    await pumpEventQueue();

    await view('clip.mp4');

    expect(system.opened.last, isA<FakeVideoPlayer>());
    expect(system.opened.last.calls, contains('volume 0.9'));
  });

  test('F2 и Cmd-I — те же команды, что у видео', () async {
    await start();
    await view('01 Intro.mp3');
    final screen = shown();

    expect(runtime.commands.dispatch(KeyCombination.parse('F2')), isTrue);
    await pumpEventQueue();
    expect(screen.playing, isFalse);

    expect(runtime.commands.dispatch(KeyCombination.parse('Cmd-I')), isTrue);
    await pumpEventQueue();
    expect(runtime.app.view.dialogs.single.title, '01 Intro.mp3');
  });

  test('быстрый просмотр сам не играет, а с флажком — играет', () async {
    for (final autoplay in [false, true]) {
      await start(autoplayQuickView: autoplay);
      runtime.app.left.setCursorToName('01 Intro.mp3');
      expect(runtime.commands.dispatch(KeyCombination.parse('Shift-F3')), isTrue);
      await Future<void>.delayed(QuickViewHost.defaultDelay * 2);
      await pumpEventQueue();

      final host = runtime.app.view.contentAt(right)! as QuickViewHost;
      expect(innermost(host), isA<AudioViewerScreen>());
      expect(playerOf(0).calls.contains('play'), autoplay);
      // Показ первого прогона закрывается здесь — второй закроет `tearDown`.
      if (!autoplay) {
        host.close();
      }
    }
  });

  test('файл не с диска — копией, и копия прежнего трека убирается при смене', () async {
    await start();
    provider.capabilities = const ProviderCapabilities(canSeek: true);
    await view('01 Intro.mp3');
    final screen = shown();
    final first = system.paths.single.$1;
    expect(first, isNot('/music/01 Intro.mp3'));
    expect(first, endsWith('01 Intro.mp3'));

    expect(await screen.next(), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(system.paths.last.$1, endsWith('02 Song.mp3'));
    expect(File(first).existsSync(), isFalse, reason: 'копия прежнего трека осталась во временном каталоге');
  });
}
