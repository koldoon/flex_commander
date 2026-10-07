import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

import 'media_controls.dart';
import 'media_screen.dart';
import 'video_aspect.dart';
import 'video_viewer_screen.dart';

/// Показ, которому сейчас принадлежит ввод, — если он играет (видео или звук).
///
/// Разворот до внутреннего: в области может стоять быстрый просмотр, а показан
/// в нём — этот показ.
MediaScreen? mediaInFocus(Application? app) {
  final view = app?.view;
  if (view == null) {
    return null;
  }
  final shown = view.contentAt(view.activeArea);
  final content = shown == null ? null : innermost(shown);
  return content is MediaScreen ? content : null;
}

/// Показ видео, которому сейчас принадлежит ввод.
VideoViewerScreen? videoViewerInFocus(Application? app) {
  final screen = mediaInFocus(app);
  return screen is VideoViewerScreen ? screen : null;
}

/// Пуск и пауза — видео и звука (`docs/spec/video-viewer.md`, §7).
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
  String get label => mediaInFocus(_app)?.playing == true ? tr('Pause') : tr('Play');

  @override
  Set<String> get keywords => const {'video', 'audio', 'music', 'start', 'stop'};

  @override
  String get description => tr('Start or pause playback');

  @override
  bool isExecutable(CommandContext context) => mediaInFocus(context.app) != null;

  @override
  Future<void> execute(CommandContext context) async => mediaInFocus(context.app)?.togglePlay();
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
  String get label => mediaInFocus(_app)?.settings.muted == true ? tr('Unmute') : tr('Mute');

  @override
  Set<String> get keywords => const {'video', 'audio', 'sound', 'volume', 'silent'};

  @override
  String get description => tr('Turn the sound off or on');

  @override
  bool isExecutable(CommandContext context) => mediaInFocus(context.app) != null;

  @override
  Future<void> execute(CommandContext context) async => mediaInFocus(context.app)?.toggleMute();
}

/// Во весь экран и обратно — только видео (§6а).
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

/// Сведения о файле — окном, как `Cmd-I` в QuickTime (§6).
class VideoInfoCommand extends AppCommand {
  static const String commandId = 'videoViewer.info';

  @override
  String get id => commandId;

  @override
  String get label => tr('Info');

  @override
  Set<String> get keywords => const {'codec', 'details', 'inspector', 'tags'};

  @override
  String get description => tr('Show the length, codecs and tags of the file');

  @override
  bool isExecutable(CommandContext context) => mediaInFocus(context.app) != null;

  @override
  Future<void> execute(CommandContext context) async {
    final screen = mediaInFocus(context.app);
    if (screen == null) {
      return;
    }
    // Окно сведений живёт под накладкой полного экрана — сперва выйти из него,
    // иначе окно открылось бы невидимым.
    if (screen is VideoViewerScreen && screen.fullScreen) {
      await screen.toggleFullScreen();
    }
    final view = context.app.view;
    late final String dialogId;
    void close() => view.closeDialog(dialogId);
    dialogId = view.showDialog(
      DialogSpec(
        title: screen.entry.name,
        takesFocus: true,
        content: Builder(builder: (context) => FcKeyValueTable(sections: [screen.infoSection(context.strings)])),
        onSubmit: close,
        onDismiss: close,
      ),
    );
  }
}

/// Соотношение сторон кадра — окном со списком (§6б).
class VideoAspectCommand extends AppCommand {
  static const String commandId = 'videoViewer.aspect';

  @override
  String get id => commandId;

  @override
  String get label => tr('Aspect');

  @override
  Set<String> get keywords => const {'video', 'aspect ratio', 'proportions', 'stretch', 'anamorphic'};

  @override
  String get description => tr('Stretch the frame to another aspect ratio');

  @override
  bool isExecutable(CommandContext context) => videoViewerInFocus(context.app) != null;

  @override
  Future<void> execute(CommandContext context) async {
    final screen = videoViewerInFocus(context.app);
    if (screen == null) {
      return;
    }
    // Окно живёт под накладкой полного экрана — как и сведения.
    if (screen.fullScreen) {
      await screen.toggleFullScreen();
    }
    final view = context.app.view;
    final state = VideoAspectPickerState(screen);
    late final String dialogId;
    void close() => view.closeDialog(dialogId);
    state.apply = close;
    state.cancel = () {
      state.revert();
      close();
    };
    dialogId = view.showDialog(
      DialogSpec(
        title: tr('Aspect ratio'),
        takesFocus: true,
        hugsContent: true,
        content: _AspectPicker(state: state),
        onSubmit: state.apply,
        onDismiss: state.cancel,
      ),
    );
  }
}

/// Что выбрано в окне соотношений.
///
/// Выбранное ставится показу **сразу**: кадр под окном перестраивается на
/// каждый шаг курсора, а отмена возвращает то, что было до окна (§6б).
class VideoAspectPickerState extends ChangeNotifier {
  VideoAspectPickerState(this.screen) : _before = screen.aspect, _index = VideoAspect.all.indexOf(screen.aspect);

  final VideoViewerScreen screen;
  final VideoAspect _before;

  int get index => _index;
  int _index;

  set index(int value) {
    if (value == _index || value < 0 || value >= VideoAspect.all.length) {
      return;
    }
    _index = value;
    screen.aspect = VideoAspect.all[value];
    notifyListeners();
  }

  /// Вернуть то, что стояло до окна.
  void revert() => screen.aspect = _before;

  /// Оставить выбранное: `Enter` и «OK».
  VoidCallback apply = _nothing;

  /// Вернуть прежнее и закрыть: `Esc` и «Cancel».
  VoidCallback cancel = _nothing;

  static void _nothing() {}
}

/// Список соотношений — тем же устройством, что окно выбора вида панели.
class _AspectPicker extends StatefulWidget {
  const _AspectPicker({required this.state});

  final VideoAspectPickerState state;

  @override
  State<_AspectPicker> createState() => _AspectPickerState();
}

class _AspectPickerState extends State<_AspectPicker> {
  /// Свой узел фокуса: фокус открытого окна забирает рама, и `autofocus` до
  /// списка не доходит. Стрелки остаются здесь, `Enter` и `Esc` — раме.
  final FocusNode _focus = FocusNode(debugLabel: 'video aspect');

  final FcPickPage _page = FcPickPage();

  @override
  void initState() {
    super.initState();
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final moved = FcPickList.moveSelection(
      event,
      selected: widget.state.index,
      count: VideoAspect.all.length,
      page: _page,
    );
    if (moved == null || moved < 0) {
      return KeyEventResult.ignored;
    }
    widget.state.index = moved;
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final theme = FcTheme.of(context);
    final state = widget.state;

    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: ListenableBuilder(
        listenable: state,
        builder:
            (context, _) => CommandDialogForm(
              onCancel: state.cancel,
              onSubmit: state.apply,
              submitLabel: strings.tr('OK'),
              children: [
                CommandDialogField.bleed(
                  child: SizedBox(
                    height: (theme.metrics.rowHeight + theme.metrics.rowGap) * VideoAspect.all.length,
                    child: FcPickList(
                      hugged: true,
                      textInset: theme.metrics.dialogHorizontalPadding,
                      rows: [
                        for (final aspect in VideoAspect.all)
                          FcPickRow(
                            id: aspect.label,
                            // Числа не переводятся; «Original» — слово.
                            title: aspect.ratio == null ? strings.tr(aspect.label) : aspect.label,
                          ),
                      ],
                      query: '',
                      selected: state.index,
                      page: _page,
                      onTap: (id) => state.index = VideoAspect.all.indexWhere((aspect) => aspect.label == id),
                    ),
                  ),
                ),
              ],
            ),
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
