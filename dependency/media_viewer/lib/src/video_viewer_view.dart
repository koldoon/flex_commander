import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'media_controls.dart';
import 'video_viewer_screen.dart';

/// Показ ролика: та же рама и та же плашка пути, что у прочих показов, внутри —
/// кадр и плашка управления в духе QuickTime (`docs/spec/video-viewer.md`, §6).
///
/// Вид один на оба места — во весь экран и в области панели. Разница в раме и
/// в том, кому достаются клавиши; и то и другое спрашивается у области.
class VideoViewerView extends StatefulWidget {
  const VideoViewerView({super.key, required this.screen});

  final VideoViewerScreen screen;

  @override
  State<VideoViewerView> createState() => _VideoViewerViewState();
}

class _VideoViewerViewState extends State<VideoViewerView> {
  VideoViewerScreen get screen => widget.screen;

  final FocusNode _focus = FocusNode(debugLabel: 'VideoViewerView');
  bool _focused = false;

  /// Полный экран (§6а): ролик в корневой накладке, поверх всего окна.
  OverlayEntry? _overlay;
  final FocusNode _overlayFocus = FocusNode(debugLabel: 'VideoViewerView.fullScreen');

  @override
  void initState() {
    super.initState();
    screen.addListener(_syncOverlay);
  }

  @override
  void didUpdateWidget(VideoViewerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.screen != widget.screen) {
      oldWidget.screen.removeListener(_syncOverlay);
      widget.screen.addListener(_syncOverlay);
      _syncOverlay();
    }
  }

  @override
  void dispose() {
    screen.removeListener(_syncOverlay);
    _removeOverlay();
    _overlayFocus.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Накладка ходит за признаком полного экрана.
  ///
  /// В корневую накладку, а не в область: область — это место панели, а ролик
  /// во весь экран обязан закрыть и вкладки, и ряд функциональных клавиш, и
  /// командную строку. Ставится после кадра: посреди сборки дерево менять
  /// нельзя.
  void _syncOverlay() {
    final want = screen.fullScreen;
    if (want == (_overlay != null)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || screen.fullScreen != want || want == (_overlay != null)) {
        return;
      }
      if (want) {
        final overlay = Overlay.of(context, rootOverlay: true);
        _overlay = OverlayEntry(
          builder:
              (context) => ListenableBuilder(
                listenable: screen,
                // Накладка стоит вне `Scaffold`, и стиля текста по умолчанию
                // здесь нет: без него подписи плашки выходили подчёркнутыми.
                builder:
                    (context, _) => DefaultTextStyle(
                      style: FcTheme.of(context).uiStyle,
                      child: Focus(
                        focusNode: _overlayFocus,
                        autofocus: true,
                        onKeyEvent: _onKey,
                        child: _stage(focusNode: _overlayFocus),
                      ),
                    ),
              ),
        );
        overlay.insert(_overlay!);
        _overlayFocus.requestFocus();
      } else {
        _removeOverlay();
        _focus.requestFocus();
      }
    });
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay?.dispose();
    _overlay = null;
  }

  /// Фокус ходит за областью — как у показа PDF: вошли — он наш, ушли —
  /// отдаём.
  void _followFocus(bool focused) {
    if (focused == _focused) {
      return;
    }
    _focused = focused;
    // После кадра: до него узла ещё нет в дереве фокуса, и просьба отклоняется
    // молча (`text_view.dart`).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (_focused) {
        _focus.requestFocus();
      } else {
        _focus.unfocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Приложение нужно только в панели: во весь экран рама и фокус известны и
    // так.
    final app = screen.place == ViewerPlace.panel ? AppScope.read(context) : null;

    return ListenableBuilder(
      listenable: Listenable.merge([screen, if (app != null) app.view]),
      builder: (context, _) {
        final focused = app == null || app.view.takesKeys(screen);
        // В полном экране фокус у накладки: отдавать его раме нельзя.
        if (!screen.fullScreen) {
          _followFocus(focused);
        }
        final player = screen.player;

        return FcPanelFrame(
          outerEdge: _edgeOf(app),
          fillsFrame: true,
          header: FcPathPlate(
            path: screen.entry.path,
            trailing: '${player.size.width.round()}×${player.size.height.round()} · ${formatClock(player.duration)}',
            active: focused,
          ),
          child: Focus(
            focusNode: _focus,
            onKeyEvent: _onKey,
            // В полном экране ролик — в накладке; здесь только чёрное место,
            // чтобы одна текстура не рисовалась дважды.
            child: screen.fullScreen ? const ColoredBox(color: MediaColors.backdrop) : _stage(focusNode: _focus),
          ),
        );
      },
    );
  }

  /// Сцена: кадр на чёрном и плашка управления поверх. Одна на оба места —
  /// в раме показа и во весь экран.
  Widget _stage({required FocusNode focusNode}) {
    final player = screen.player;
    return MouseRegion(
      // Плашка спрятана — спрятан и указатель: смотрят кадр.
      cursor: screen.controlsVisible ? MouseCursor.defer : SystemMouseCursors.none,
      onHover: (_) => screen.poke(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          focusNode.requestFocus();
          screen.poke();
        },
        child: ColoredBox(
          color: MediaColors.backdrop,
          child: Stack(
            children: [
              Positioned.fill(
                // Двойной щелчок по кадру — во весь экран и обратно, как в
                // QuickTime. Только по кадру: на плашке ожидание второго
                // щелчка задерживало бы каждое нажатие на полосу перемотки.
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: screen.toggleFullScreen,
                  child: Center(child: _frame(player)),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 16,
                child: IgnorePointer(
                  ignoring: !screen.controlsVisible,
                  child: AnimatedOpacity(
                    opacity: screen.controlsVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Center(
                      // Позиция будит только плашку (`audio-viewer.md`, §7.5).
                      child: ValueListenableBuilder<Duration>(
                        valueListenable: screen.positionListenable,
                        builder:
                            (context, position, _) => MediaControls(
                              playing: screen.playing,
                              position: position,
                              duration: screen.player.duration,
                              muted: screen.settings.muted,
                              volume: screen.settings.volume,
                              onPlayPause: screen.togglePlay,
                              onSeek: screen.seekTo,
                              onToggleMute: screen.toggleMute,
                              onVolume: screen.setVolume,
                              fullScreen: screen.fullScreen,
                              onFullScreen: screen.toggleFullScreen,
                            ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Кадр по пропорции — записанной или выбранной (§6б); поворот —
  /// четвертями, как записан в ролике.
  Widget _frame(SystemVideoPlayer player) {
    final size = player.size;
    if (size.width <= 0 || size.height <= 0) {
      return const SizedBox.shrink();
    }
    return AspectRatio(
      aspectRatio: screen.aspect.ratio ?? size.width / size.height,
      child: RotatedBox(quarterTurns: player.quarterTurns, child: Texture(textureId: player.textureId)),
    );
  }

  /// Клавиши внутри показа (§7). Команды с `Cmd` идут мимо — их разбирает
  /// реестр (`Cmd-I`).
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || HardwareKeyboard.instance.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final key = event.logicalKey;
    final handled = switch (key) {
      LogicalKeyboardKey.space => () => screen.togglePlay(),
      LogicalKeyboardKey.arrowLeft when shift => () => screen.step(-1),
      LogicalKeyboardKey.arrowRight when shift => () => screen.step(1),
      LogicalKeyboardKey.arrowLeft => () => screen.seekBy(-VideoViewerScreen.seekStep),
      LogicalKeyboardKey.arrowRight => () => screen.seekBy(VideoViewerScreen.seekStep),
      LogicalKeyboardKey.arrowUp => () => screen.changeVolume(VideoViewerScreen.volumeStep),
      LogicalKeyboardKey.arrowDown => () => screen.changeVolume(-VideoViewerScreen.volumeStep),
      LogicalKeyboardKey.keyM => () => screen.toggleMute(),
      LogicalKeyboardKey.home => () => screen.seekTo(Duration.zero),
      LogicalKeyboardKey.end => () => screen.seekTo(screen.player.duration),
      _ => null,
    };
    if (handled == null) {
      return KeyEventResult.ignored;
    }
    handled();
    screen.poke();
    return KeyEventResult.handled;
  }

  PanelOuterEdge _edgeOf(Application? app) {
    if (app == null) {
      return PanelOuterEdge.both;
    }
    return switch (app.view.positionOf(screen)) {
      ViewportPosition.left => PanelOuterEdge.left,
      ViewportPosition.right => PanelOuterEdge.right,
      _ => PanelOuterEdge.both,
    };
  }
}
