import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'video_viewer_screen.dart';

/// Показ ролика: та же рама и та же плашка пути, что у прочих показов, внутри —
/// кадр и плашка управления в духе QuickTime (`docs/spec/video-viewer.md`, §6).
///
/// Вид один на оба места — во весь экран и в области панели. Разница в раме и
/// в том, кому достаются клавиши; и то и другое спрашивается у области.
class VideoViewerView extends StatefulWidget {
  const VideoViewerView({super.key, required this.screen});

  final VideoViewerScreen screen;

  /// Цвета кадра и плашки — не из оформления: видео смотрят на чёрном в любом
  /// оформлении, а плашка лежит на кадре, а не на окне, и обязана читаться на
  /// любом кадре — тёмная полупрозрачная с белым, как в QuickTime.
  static const Color backdrop = Color(0xFF000000);
  static const Color plateColor = Color(0xA6202020);
  static const Color ink = Color(0xFFFFFFFF);
  static const Color track = Color(0x4DFFFFFF);

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
            child: screen.fullScreen ? const ColoredBox(color: VideoViewerView.backdrop) : _stage(focusNode: _focus),
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
          color: VideoViewerView.backdrop,
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
                    child: Center(child: _VideoControls(screen: screen)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Кадр по пропорции; поворот — четвертями, как записан в ролике.
  Widget _frame(SystemVideoPlayer player) {
    final size = player.size;
    if (size.width <= 0 || size.height <= 0) {
      return const SizedBox.shrink();
    }
    return AspectRatio(
      aspectRatio: size.width / size.height,
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

/// Плашка управления: пуск, время, перемотка, громкость.
class _VideoControls extends StatelessWidget {
  const _VideoControls({required this.screen});

  final VideoViewerScreen screen;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final icons = theme.icons;
    final metrics = theme.metrics;
    final text = theme.uiStyle.copyWith(color: VideoViewerView.ink, fontFeatures: const [FontFeature.tabularFigures()]);
    final duration = screen.player.duration;
    final played = duration.inMicroseconds <= 0 ? 0.0 : screen.position.inMicroseconds / duration.inMicroseconds;

    return Container(
      constraints: const BoxConstraints(maxWidth: 560),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: EdgeInsets.symmetric(horizontal: metrics.dialogPadding, vertical: metrics.dialogGap),
      decoration: BoxDecoration(color: VideoViewerView.plateColor, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          _IconButton(
            key: const ValueKey('video.playPause'),
            icon: screen.playing ? icons.pause : icons.play,
            onTap: screen.togglePlay,
          ),
          SizedBox(width: metrics.dialogGap),
          Text(formatClock(screen.position), style: text),
          SizedBox(width: metrics.dialogGap),
          Expanded(
            child: _Bar(
              key: const ValueKey('video.scrub'),
              value: played,
              onChanged: (fraction) => screen.seekTo(duration * fraction),
            ),
          ),
          SizedBox(width: metrics.dialogGap),
          Text(formatClock(duration), style: text),
          SizedBox(width: metrics.dialogGap * 2),
          _IconButton(
            key: const ValueKey('video.mute'),
            icon: screen.settings.muted ? icons.soundOff : icons.soundOn,
            onTap: screen.toggleMute,
          ),
          SizedBox(width: metrics.dialogGap),
          SizedBox(
            width: 72,
            child: _Bar(
              key: const ValueKey('video.volume'),
              value: screen.settings.muted ? 0 : screen.settings.volume,
              onChanged: screen.setVolume,
            ),
          ),
          SizedBox(width: metrics.dialogGap * 2),
          _IconButton(
            key: const ValueKey('video.fullScreen'),
            icon: screen.fullScreen ? icons.exitFullScreen : icons.enterFullScreen,
            onTap: screen.toggleFullScreen,
          ),
        ],
      ),
    );
  }
}

/// Значок-кнопка на плашке.
class _IconButton extends StatelessWidget {
  const _IconButton({super.key, required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final size = FcTheme.of(context).metrics.fontSize * 1.3;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: size + 8,
          height: size + 8,
          child: Center(child: Icon(icon, size: size, color: VideoViewerView.ink)),
        ),
      ),
    );
  }
}

/// Полоса с бегунком: перемотка и громкость. Щелчок переносит, протяжка ведёт.
class _Bar extends StatelessWidget {
  const _Bar({super.key, required this.value, required this.onChanged});

  /// Где бегунок, от 0 до 1.
  final double value;

  final ValueChanged<double> onChanged;

  static const double _height = 18;
  static const double _thickness = 4;
  static const double _knob = 6;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // Полоса — внутри на радиус бегунка с обеих сторон: на краю бегунок
        // иначе вылезал за неё половиной и упирался в край плашки.
        final span = width - _knob * 2;
        void report(double x) => onChanged(span <= 0 ? 0 : ((x - _knob) / span).clamp(0.0, 1.0));
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => report(details.localPosition.dx),
            onHorizontalDragStart: (details) => report(details.localPosition.dx),
            onHorizontalDragUpdate: (details) => report(details.localPosition.dx),
            child: SizedBox(
              height: _height,
              width: width,
              child: CustomPaint(painter: _BarPainter(value.clamp(0.0, 1.0))),
            ),
          ),
        );
      },
    );
  }
}

class _BarPainter extends CustomPainter {
  const _BarPainter(this.value);

  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    const left = _Bar._knob;
    final right = size.width - _Bar._knob;
    final track = RRect.fromLTRBR(
      left,
      y - _Bar._thickness / 2,
      right,
      y + _Bar._thickness / 2,
      const Radius.circular(_Bar._thickness / 2),
    );
    canvas.drawRRect(track, Paint()..color = VideoViewerView.track);
    final x = left + (right - left) * value;
    canvas.drawRRect(
      RRect.fromLTRBR(left, track.top, x, track.bottom, const Radius.circular(_Bar._thickness / 2)),
      Paint()..color = VideoViewerView.ink,
    );
    canvas.drawCircle(Offset(x, y), _Bar._knob, Paint()..color = VideoViewerView.ink);
  }

  @override
  bool shouldRepaint(_BarPainter old) => old.value != value;
}
