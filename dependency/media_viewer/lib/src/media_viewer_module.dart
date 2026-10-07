import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

import 'audio_viewer_screen.dart';
import 'audio_viewer_view.dart';
import 'media_source.dart';
import 'video_viewer_commands.dart';
import 'video_viewer_screen.dart';
import 'video_viewer_settings.dart';
import 'video_viewer_view.dart';

/// Просмотрщики видео и звука — два из.
///
/// Играет система (`SystemVideo`), а показ, плашка и сведения — их
/// (`docs/spec/video-viewer.md`, `docs/spec/audio-viewer.md`). Про `F3` и
/// быстрый просмотр модуль не знает: он объявляет `ViewerSpec` в общий реестр.
///
/// Модуль один на оба показа: громкость, «без звука» и флажок автозапуска у
/// них общие, а настройки живут в разделе модуля. Идентификатор остался от
/// видео — в нём сохранённые настройки.
class MediaViewer implements FcFrontendModule {
  const MediaViewer();

  @override
  String get id => 'fc.videoViewer';

  @override
  String get title => 'Video and audio viewer';

  /// Ролики, за которые просмотрщик берётся по имени. В том числе те, что
  /// система не играет (`mkv`, `webm`): их он берёт, чтобы отказать словами, а
  /// не отдать текстовому просмотрщику байты (§5).
  static const Set<String> extensions = {
    'mp4',
    'm4v',
    'mov',
    'qt',
    'avi',
    'mkv',
    'webm',
    'flv',
    'wmv',
    '3gp',
    '3g2',
    'mpg',
    'mpeg',
    'mts',
    'm2ts',
    // `ts` нарочно нет: так же называются исходники TypeScript, и показ видео
    // перехватил бы их у текстового. Настоящий MPEG-TS узнаётся по содержимому.
  };

  /// Звуковые файлы, за которые берётся показ звука. Играет ли — решает
  /// система (`.ogg` с opus macOS 27 играет); что не берёт, получает отказ
  /// словами (`docs/spec/audio-viewer.md`, §2).
  static const Set<String> audioExtensions = {
    'mp3',
    'm4a',
    'm4b',
    'aac',
    'flac',
    'wav',
    'aif',
    'aiff',
    'alac',
    'caf',
    'ogg',
    'oga',
    'opus',
    'wma',
  };

  /// Звуковой файл — по имени.
  static bool isAudio(FileEntry entry) =>
      !entry.isDirectory && !entry.isParent && audioExtensions.contains(extensionOf(entry.name).toLowerCase());

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.strings('ru', _russian);

    registry.view<VideoViewerScreen>((context, state) => VideoViewerView(screen: state));
    registry.view<AudioViewerScreen>((context, state) => AudioViewerView(screen: state));

    final settings = registry.settings;
    VideoViewerSettings settingsOf() => settings.section(VideoViewerSettings.new);

    registry.settingsSchema(() {
      final strings = registry.services.resolve<Strings>();
      return SettingsSchema([
        SettingsField.flag(
          'autoplayQuickView',
          defaultValue: false,
          title: strings.tr('Autoplay video and audio in quick preview'),
          read: () => settingsOf().autoplayQuickView,
          write: (value) => settingsOf().autoplayQuickView = value,
        ),
      ], save: settings.save);
    });

    registry.viewer(
      ViewerSpec(
        id: VideoViewerScreen.viewerId,
        title: 'Video',
        // Выше текстового, как картинки и PDF: тот берётся за всё.
        priority: 100,
        accepts:
            (entry, type) =>
                !entry.isDirectory &&
                !entry.isParent &&
                (extensions.contains(extensionOf(entry.name).toLowerCase()) || type?.group == ContentGroup.video),
        open: (request) => _openVideo(request, settingsOf(), settings.save, _optional<SystemVideo>(registry.services)),
      ),
    );

    registry.viewer(
      ViewerSpec(
        id: AudioViewerScreen.viewerId,
        title: 'Audio',
        priority: 100,
        accepts:
            (entry, type) =>
                isAudio(entry) || (!entry.isDirectory && !entry.isParent && type?.group == ContentGroup.audio),
        open: (request) => _openAudio(request, settingsOf(), settings.save, _optional<SystemVideo>(registry.services)),
      ),
    );

    registry.command((context) => PlayPauseVideoCommand());
    registry.command((context) => MuteVideoCommand());
    registry.command((context) => VideoInfoCommand());
    registry.command((context) => ToggleVideoFullScreenCommand());
    registry.command((context) => VideoAspectCommand());

    // `F2` — главное дело показа, как «вписать» у картинок и PDF; `F7` свободна.
    // `Cmd-I` — сведения, как в QuickTime (§7).
    registry.binding(
      KeyBinding.inState<VideoViewerScreen>('F2', PlayPauseVideoCommand.commandId, context: KeyContext.videoViewer),
    );
    registry.binding(
      KeyBinding.inState<VideoViewerScreen>('F7', MuteVideoCommand.commandId, context: KeyContext.videoViewer),
    );
    // `F5` — переключатель показа, как «Format / Raw» у текста и «Text» у PDF.
    registry.binding(
      KeyBinding.inState<VideoViewerScreen>('F5', VideoAspectCommand.commandId, context: KeyContext.videoViewer),
    );
    registry.binding(
      KeyBinding.inState<VideoViewerScreen>('Cmd-I', VideoInfoCommand.commandId, context: KeyContext.videoViewer),
    );
    // Звук — те же клавиши и те же команды, свой раздел в окне клавиш
    // (`docs/spec/audio-viewer.md`, §4).
    for (final (key, command, id) in [
      ('F2', PlayPauseVideoCommand.commandId, 'audioViewer.playPause'),
      ('F7', MuteVideoCommand.commandId, 'audioViewer.mute'),
      ('Cmd-I', VideoInfoCommand.commandId, 'audioViewer.info'),
    ]) {
      registry.binding(KeyBinding.inState<AudioViewerScreen>(key, command, id: id, context: KeyContext.audioViewer));
    }
    // `F` — во весь экран, как в QuickTime и в проигрывателях вообще (§6а).
    registry.binding(
      KeyBinding.inState<VideoViewerScreen>(
        'F',
        ToggleVideoFullScreenCommand.commandId,
        context: KeyContext.videoViewer,
      ),
    );
  }

  /// Служба, без которой модуль умеет обойтись; null — её никто не объявил.
  static T? _optional<T>(FcServices services) {
    final found = services.resolveAll<T>();
    return found.isEmpty ? null : found.first;
  }

  static Future<ViewerContent> _openVideo(
    ViewerRequest request,
    VideoViewerSettings settings,
    void Function() onSettingsChanged,
    SystemVideo? system,
  ) async {
    final strings = request.app.strings;
    final unavailable = strings.tr('Video playback is not available — open it with the system (Cmd-O)');
    if (system == null) {
      throw ViewerRefused(unavailable);
    }

    final source = await MediaSource.prepare(request);
    SystemVideoOpened? opened;
    try {
      opened = await system.open(source.path);
      await request.checkpoint();
    } catch (_) {
      // Курсор ушёл, пока система открывала: плеер и копию — отпустить.
      if (opened is SystemMediaPlayer) {
        await opened.close();
      }
      await source.dispose();
      rethrow;
    }

    switch (opened) {
      case null:
        await source.dispose();
        throw ViewerRefused(unavailable);
      case SystemVideoRefused(:final reason):
        await source.dispose();
        throw ViewerRefused(switch (reason) {
          SystemVideoRefused.noVideo => strings.tr('There is no video in this file, only sound'),
          _ => _unplayable(strings, request.entry),
        });
      case final SystemVideoPlayer player:
        return VideoViewerScreen(
          entry: request.entry,
          player: player,
          source: source,
          settings: settings,
          onSettingsChanged: onSettingsChanged,
          place: request.place,
          window: request.app.window,
          memory: request.memory,
          // Быстрый просмотр сам не играет, пока не попросили: ход курсора по
          // каталогу роликов включал бы звук на каждом шаге (§8).
          autoplay: request.place == ViewerPlace.fullscreen || settings.autoplayQuickView,
        );
      case final SystemMediaPlayer other:
        // На ролик раннер ответил плеером без кадров — показать нечего.
        await other.close();
        await source.dispose();
        throw ViewerRefused(unavailable);
    }
  }

  /// Открыть звуковой файл (`docs/spec/audio-viewer.md`).
  static Future<ViewerContent> _openAudio(
    ViewerRequest request,
    VideoViewerSettings settings,
    void Function() onSettingsChanged,
    SystemVideo? system,
  ) async {
    final strings = request.app.strings;
    final unavailable = strings.tr('Audio playback is not available — open it with the system (Cmd-O)');
    if (system == null) {
      throw ViewerRefused(unavailable);
    }

    final source = await MediaSource.prepare(request);
    SystemVideoOpened? opened;
    try {
      opened = await system.openAudio(source.path);
      await request.checkpoint();
    } catch (_) {
      if (opened is SystemMediaPlayer) {
        await opened.close();
      }
      await source.dispose();
      rethrow;
    }

    switch (opened) {
      case final SystemAudioPlayer player:
        // Альбом — звуковые файлы того же списка, в том порядке, в каком их
        // видит человек (§3).
        final tracks = [
          for (final sibling in request.siblings)
            if (isAudio(sibling)) sibling,
        ];
        return AudioViewerScreen(
          entry: request.entry,
          player: player,
          source: source,
          settings: settings,
          onSettingsChanged: onSettingsChanged,
          system: system,
          tracks: tracks.any((track) => track.path == request.entry.path) ? tracks : [request.entry],
          contentOf: request.contentFor,
          localPathOf: request.localPathOf,
          place: request.place,
          say: request.app.toasts.show,
          autoplay: request.place == ViewerPlace.fullscreen || settings.autoplayQuickView,
        );
      case null:
        await source.dispose();
        throw ViewerRefused(unavailable);
      case SystemVideoRefused(:final reason):
        await source.dispose();
        throw ViewerRefused(switch (reason) {
          SystemVideoRefused.noAudio => strings.tr('There is no sound in this file'),
          _ => _unplayable(strings, request.entry),
        });
      case final SystemMediaPlayer other:
        await other.close();
        await source.dispose();
        throw ViewerRefused(unavailable);
    }
  }

  static String _unplayable(Strings strings, FileEntry entry) => strings.tr(
    'macOS does not play this format ({format}) — Cmd-O opens it with the system',
    args: {'format': extensionOf(entry.name).toLowerCase()},
  );
}

/// Русские строки просмотра видео и звука.
const Map<String, String> _russian = {
  'Video and audio viewer': 'Видео и звук',
  'Autoplay video and audio in quick preview': 'Запускать видео и звук в быстром просмотре сразу',
  'Play': 'Пуск',
  'Pause': 'Пауза',
  'Start or pause playback': 'Запустить или остановить',
  'Mute': 'Без звука',
  'Unmute': 'Со звуком',
  'Turn the sound off or on': 'Выключить или включить звук',
  'Info': 'Сведения',
  'Full screen': 'Во весь экран',
  'Aspect': 'Пропорции',
  'Aspect ratio': 'Соотношение сторон',
  'Stretch the frame to another aspect ratio': 'Растянуть кадр под другое соотношение сторон',
  'Original': 'Исходное',
  'Exit full screen': 'Выйти из полного экрана',
  'Show the video over the whole screen': 'Показать ролик на весь экран',
  'Show the length, codecs and tags of the file': 'Показать длительность, кодеки и теги файла',
  'Video': 'Видео',
  'Size': 'Размер',
  'Length': 'Длительность',
  'Video codec': 'Кодек видео',
  'Frame rate': 'Частота кадров',
  'Bit rate': 'Битрейт',
  'Audio': 'Звук',
  'File size': 'Размер файла',
  'Codec': 'Кодек',
  'Sample rate': 'Частота',
  'Channels': 'Каналы',
  'Title': 'Название',
  'Artist': 'Исполнитель',
  'Album': 'Альбом',
  'Year': 'Год',

  // Отказы.
  'Video playback is not available — open it with the system (Cmd-O)':
      'Проигрывать видео нечем; откройте файл системой (Cmd-O)',
  'Audio playback is not available — open it with the system (Cmd-O)':
      'Проигрывать звук нечем; откройте файл системой (Cmd-O)',
  'macOS does not play this format ({format}) — Cmd-O opens it with the system':
      'macOS не проигрывает этот формат ({format}); Cmd-O откроет файл системой',
  'There is no video in this file, only sound': 'В этом файле нет видео, только звук',
  'There is no sound in this file': 'В этом файле нет звука',
};
