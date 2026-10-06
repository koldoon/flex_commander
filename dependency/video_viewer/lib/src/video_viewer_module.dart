import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';

import 'video_source.dart';
import 'video_viewer_commands.dart';
import 'video_viewer_screen.dart';
import 'video_viewer_settings.dart';
import 'video_viewer_view.dart';

/// Просмотрщик видео — один из.
///
/// Играет система (`SystemVideo`), а показ, плашка и сведения — его
/// (`docs/spec/video-viewer.md`). Про `F3` и быстрый просмотр модуль не знает:
/// он объявляет `ViewerSpec` в общий реестр.
class VideoViewer implements FcFrontendModule {
  const VideoViewer();

  @override
  String get id => 'fc.videoViewer';

  @override
  String get title => 'Video viewer';

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

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.strings('ru', _russian);

    registry.view<VideoViewerScreen>((context, state) => VideoViewerView(screen: state));

    final settings = registry.settings;
    VideoViewerSettings settingsOf() => settings.section(VideoViewerSettings.new);

    registry.settingsSchema(() {
      final strings = registry.services.resolve<Strings>();
      return SettingsSchema([
        SettingsField.flag(
          'autoplayQuickView',
          defaultValue: false,
          title: strings.tr('Autoplay videos in quick preview'),
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
        open: (request) => _open(request, settingsOf(), settings.save, _optional<SystemVideo>(registry.services)),
      ),
    );

    registry.command((context) => PlayPauseVideoCommand());
    registry.command((context) => MuteVideoCommand());
    registry.command((context) => VideoInfoCommand());
    registry.command((context) => ToggleVideoFullScreenCommand());

    // `F2` — главное дело показа, как «вписать» у картинок и PDF; `F7` свободна.
    // `Cmd-I` — сведения, как в QuickTime (§7).
    registry.binding(
      KeyBinding.inState<VideoViewerScreen>('F2', PlayPauseVideoCommand.commandId, context: KeyContext.videoViewer),
    );
    registry.binding(
      KeyBinding.inState<VideoViewerScreen>('F7', MuteVideoCommand.commandId, context: KeyContext.videoViewer),
    );
    registry.binding(
      KeyBinding.inState<VideoViewerScreen>('Cmd-I', VideoInfoCommand.commandId, context: KeyContext.videoViewer),
    );
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

  static Future<ViewerContent> _open(
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

    final source = await VideoSource.prepare(request);
    SystemVideoOpened? opened;
    try {
      opened = await system.open(source.path);
      await request.checkpoint();
    } catch (_) {
      // Курсор ушёл, пока система открывала: плеер и копию — отпустить.
      if (opened is SystemVideoPlayer) {
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
          _ => strings.tr(
            'macOS does not play this format ({format}) — Cmd-O opens it with the system',
            args: {'format': extensionOf(request.entry.name).toLowerCase()},
          ),
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
          // Быстрый просмотр сам не играет, пока не попросили: ход курсора по
          // каталогу роликов включал бы звук на каждом шаге (§8).
          autoplay: request.place == ViewerPlace.fullscreen || settings.autoplayQuickView,
        );
    }
  }
}

/// Русские строки просмотра видео.
const Map<String, String> _russian = {
  'Video viewer': 'Видео',
  'Autoplay videos in quick preview': 'Запускать ролики в быстром просмотре сразу',
  'Play': 'Пуск',
  'Pause': 'Пауза',
  'Start or pause the video': 'Запустить или остановить ролик',
  'Mute': 'Без звука',
  'Unmute': 'Со звуком',
  'Turn the sound of the video off or on': 'Выключить или включить звук ролика',
  'Video info': 'Сведения о ролике',
  'Full screen': 'Во весь экран',
  'Exit full screen': 'Выйти из полного экрана',
  'Show the video over the whole screen': 'Показать ролик на весь экран',
  'Show the size, length and codecs of the video': 'Показать размер, длительность и кодеки ролика',
  'Video': 'Видео',
  'Size': 'Размер',
  'Length': 'Длительность',
  'Video codec': 'Кодек видео',
  'Frame rate': 'Частота кадров',
  'Bit rate': 'Битрейт',
  'Audio': 'Звук',
  'File size': 'Размер файла',

  // Отказы.
  'Video playback is not available — open it with the system (Cmd-O)':
      'Проигрывать видео нечем; откройте файл системой (Cmd-O)',
  'macOS does not play this format ({format}) — Cmd-O opens it with the system':
      'macOS не проигрывает этот формат ({format}); Cmd-O откроет файл системой',
  'There is no video in this file, only sound': 'В этом файле нет видео, только звук',
};
