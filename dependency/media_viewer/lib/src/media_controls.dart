import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

/// Цвета показа видео и звука — не из оформления: видео смотрят на чёрном в
/// любом оформлении, а плашка лежит на кадре, а не на окне, и обязана читаться
/// на любом кадре — тёмная полупрозрачная с белым, как в QuickTime.
abstract final class MediaColors {
  static const Color backdrop = Color(0xFF000000);
  static const Color plate = Color(0xA6202020);
  static const Color ink = Color(0xFFFFFFFF);
  static const Color track = Color(0x4DFFFFFF);
}

/// Время как на плашке QuickTime: `0:12`, `3:45`, `1:02:03` — часы только
/// когда они есть.
String formatClock(Duration time) {
  final seconds = time.inSeconds < 0 ? 0 : time.inSeconds;
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = (seconds % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

/// Плашка управления: пуск, время, перемотка, звук и громкость, а у видео ещё
/// и полный экран (`docs/spec/video-viewer.md`, §6; `audio-viewer.md`, §1).
class MediaControls extends StatelessWidget {
  const MediaControls({
    super.key,
    required this.playing,
    required this.position,
    required this.duration,
    required this.muted,
    required this.volume,
    required this.onPlayPause,
    required this.onSeek,
    required this.onToggleMute,
    required this.onVolume,
    this.fullScreen,
    this.onFullScreen,
  });

  final bool playing;
  final Duration position;
  final Duration duration;
  final bool muted;
  final double volume;

  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onToggleMute;
  final ValueChanged<double> onVolume;

  /// Во весь экран ли сейчас; null — кнопки полного экрана нет (звук).
  final bool? fullScreen;
  final VoidCallback? onFullScreen;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final icons = theme.icons;
    final metrics = theme.metrics;
    final text = theme.uiStyle.copyWith(color: MediaColors.ink, fontFeatures: const [FontFeature.tabularFigures()]);
    final played = duration.inMicroseconds <= 0 ? 0.0 : position.inMicroseconds / duration.inMicroseconds;
    final fullScreen = this.fullScreen;

    return Container(
      constraints: const BoxConstraints(maxWidth: 560),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: EdgeInsets.symmetric(horizontal: metrics.dialogPadding, vertical: metrics.dialogGap),
      decoration: BoxDecoration(color: MediaColors.plate, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          _IconButton(
            key: const ValueKey('media.playPause'),
            icon: playing ? icons.pause : icons.play,
            onTap: onPlayPause,
          ),
          SizedBox(width: metrics.dialogGap),
          Text(formatClock(position), style: text),
          SizedBox(width: metrics.dialogGap),
          Expanded(
            child: _Bar(
              key: const ValueKey('media.scrub'),
              value: played,
              onChanged: (fraction) => onSeek(duration * fraction),
            ),
          ),
          SizedBox(width: metrics.dialogGap),
          Text(formatClock(duration), style: text),
          SizedBox(width: metrics.dialogGap * 2),
          _IconButton(
            key: const ValueKey('media.mute'),
            icon: muted ? icons.soundOff : icons.soundOn,
            onTap: onToggleMute,
          ),
          SizedBox(width: metrics.dialogGap),
          SizedBox(
            width: 72,
            child: _Bar(key: const ValueKey('media.volume'), value: muted ? 0 : volume, onChanged: onVolume),
          ),
          if (fullScreen != null) ...[
            SizedBox(width: metrics.dialogGap * 2),
            _IconButton(
              key: const ValueKey('media.fullScreen'),
              icon: fullScreen ? icons.exitFullScreen : icons.enterFullScreen,
              onTap: onFullScreen ?? () {},
            ),
          ],
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
          child: Center(child: Icon(icon, size: size, color: MediaColors.ink)),
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
    canvas.drawRRect(track, Paint()..color = MediaColors.track);
    final x = left + (right - left) * value;
    canvas.drawRRect(
      RRect.fromLTRBR(left, track.top, x, track.bottom, const Radius.circular(_Bar._thickness / 2)),
      Paint()..color = MediaColors.ink,
    );
    canvas.drawCircle(Offset(x, y), _Bar._knob, Paint()..color = MediaColors.ink);
  }

  @override
  bool shouldRepaint(_BarPainter old) => old.value != value;
}
