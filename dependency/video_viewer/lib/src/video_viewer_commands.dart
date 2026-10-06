import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'video_viewer_screen.dart';

/// Показ видео, которому сейчас принадлежит ввод.
///
/// Разворот до внутреннего: в области может стоять быстрый просмотр, а показан
/// в нём — этот показ.
VideoViewerScreen? videoViewerInFocus(Application? app) {
  final view = app?.view;
  if (view == null) {
    return null;
  }
  final shown = view.contentAt(view.activeArea);
  final content = shown == null ? null : innermost(shown);
  return content is VideoViewerScreen ? content : null;
}

/// Пуск и пауза (`docs/spec/video-viewer.md`, §7).
class PlayPauseVideoCommand extends AppCommand {
  static const String commandId = 'videoViewer.playPause';

  /// Приложение для **прототипа**: подпись у него спрашивают и без запуска —
  /// ряд кнопок читает её прямо у него.
  Application? _app;

  @override
  bool init(Application app) {
    _app = app;
    return true;
  }

  @override
  String get id => commandId;

  /// Подпись говорит, что клавиша сделает **сейчас**.
  @override
  String get label => videoViewerInFocus(_app)?.playing == true ? tr('Pause') : tr('Play');

  @override
  Set<String> get keywords => const {'video', 'start', 'stop'};

  @override
  String get description => tr('Start or pause the video');

  @override
  bool isExecutable(CommandContext context) => videoViewerInFocus(context.app) != null;

  @override
  Future<void> execute(CommandContext context) async => videoViewerInFocus(context.app)?.togglePlay();
}

/// Без звука и со звуком.
class MuteVideoCommand extends AppCommand {
  static const String commandId = 'videoViewer.mute';

  Application? _app;

  @override
  bool init(Application app) {
    _app = app;
    return true;
  }

  @override
  String get id => commandId;

  @override
  String get label => videoViewerInFocus(_app)?.settings.muted == true ? tr('Unmute') : tr('Mute');

  @override
  Set<String> get keywords => const {'video', 'sound', 'volume', 'silent'};

  @override
  String get description => tr('Turn the sound of the video off or on');

  @override
  bool isExecutable(CommandContext context) => videoViewerInFocus(context.app) != null;

  @override
  Future<void> execute(CommandContext context) async => videoViewerInFocus(context.app)?.toggleMute();
}

/// Во весь экран и обратно (§6а).
class ToggleVideoFullScreenCommand extends AppCommand {
  static const String commandId = 'videoViewer.fullScreen';

  Application? _app;

  @override
  bool init(Application app) {
    _app = app;
    return true;
  }

  @override
  String get id => commandId;

  @override
  String get label => videoViewerInFocus(_app)?.fullScreen == true ? tr('Exit full screen') : tr('Full screen');

  @override
  Set<String> get keywords => const {'video', 'expand', 'maximize'};

  @override
  String get description => tr('Show the video over the whole screen');

  @override
  bool isExecutable(CommandContext context) => videoViewerInFocus(context.app) != null;

  @override
  Future<void> execute(CommandContext context) async => videoViewerInFocus(context.app)?.toggleFullScreen();
}

/// Сведения о ролике — окном, как `Cmd-I` в QuickTime (§6).
class VideoInfoCommand extends AppCommand {
  static const String commandId = 'videoViewer.info';

  @override
  String get id => commandId;

  @override
  String get label => tr('Video info');

  @override
  Set<String> get keywords => const {'codec', 'details', 'inspector'};

  @override
  String get description => tr('Show the size, length and codecs of the video');

  @override
  bool isExecutable(CommandContext context) => videoViewerInFocus(context.app) != null;

  @override
  Future<void> execute(CommandContext context) async {
    final screen = videoViewerInFocus(context.app);
    if (screen == null) {
      return;
    }
    // Окно сведений живёт под накладкой полного экрана — сперва выйти из него,
    // иначе окно открылось бы невидимым.
    if (screen.fullScreen) {
      await screen.toggleFullScreen();
    }
    final view = context.app.view;
    late final String dialogId;
    void close() => view.closeDialog(dialogId);
    dialogId = view.showDialog(
      DialogSpec(
        title: screen.entry.name,
        takesFocus: true,
        content: Builder(builder: (context) => FcKeyValueTable(sections: [videoInfoSection(screen, context.strings)])),
        onSubmit: close,
        onDismiss: close,
      ),
    );
  }
}

/// Сведения о ролике строками.
FcTableSection videoInfoSection(VideoViewerScreen screen, Strings strings) {
  final player = screen.player;
  final info = player.info;
  return FcTableSection(strings.tr('Video'), [
    FcTableRow(strings.tr('Size'), '${player.size.width.round()} × ${player.size.height.round()}'),
    FcTableRow(strings.tr('Length'), formatClock(player.duration)),
    if (info.videoCodec.isNotEmpty) FcTableRow(strings.tr('Video codec'), info.videoCodec),
    if (info.frameRate > 0) FcTableRow(strings.tr('Frame rate'), '${info.frameRate.toStringAsFixed(2)} fps'),
    if (info.bitRate > 0) FcTableRow(strings.tr('Bit rate'), '${(info.bitRate / 1000).round()} kbit/s'),
    if (info.audioCodecs.isNotEmpty) FcTableRow(strings.tr('Audio'), info.audioCodecs.join(', ')),
    FcTableRow(strings.tr('File size'), formatBytesLong(screen.entry.size)),
  ]);
}
