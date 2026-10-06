import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Движение полос спектра — отдельно от рисования (`docs/spec/audio-viewer.md`,
/// §7.2): полоса поднимается сразу и опускается плавно, пик держится и падает
/// с ускорением.
class SpectrumMotion {
  SpectrumMotion(int bands)
    : levels = Float64List(bands),
      peaks = Float64List(bands),
      _hold = Float64List(bands),
      _speed = Float64List(bands);

  /// Полная высота опадает за столько.
  static const Duration fall = Duration(milliseconds: 300);

  /// Пик держится наверху столько.
  static const Duration hold = Duration(milliseconds: 500);

  /// Ускорение падения пика — высот в секунду за секунду.
  static const double gravity = 4;

  final Float64List levels;
  final Float64List peaks;
  final Float64List _hold;
  final Float64List _speed;

  /// Шаг на [elapsed]; [target] — что пришло от плеера (null — тишина: пауза).
  void step(Duration elapsed, List<double>? target) {
    final dt = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final drop = dt * Duration.microsecondsPerSecond / fall.inMicroseconds;
    for (var i = 0; i < levels.length; i++) {
      final wanted = target == null || i >= target.length ? 0.0 : target[i].clamp(0.0, 1.0);
      levels[i] = wanted >= levels[i] ? wanted : math.max(wanted, levels[i] - drop);
      if (levels[i] >= peaks[i]) {
        peaks[i] = levels[i];
        _hold[i] = hold.inMicroseconds / Duration.microsecondsPerSecond;
        _speed[i] = 0;
      } else if (_hold[i] > 0) {
        _hold[i] -= dt;
      } else {
        _speed[i] += gravity * dt;
        peaks[i] = math.max(levels[i], peaks[i] - _speed[i] * dt);
      }
    }
  }

  /// Всё опало — двигать нечего.
  bool get resting => levels.every((level) => level <= 0) && peaks.every((peak) => peak <= 0);
}

/// Спектр того, что играет, — как в Winamp: тонкие полоски с пиками
/// (`docs/spec/audio-viewer.md`, §7).
///
/// Спрашивает плеер по тикеру **только пока играет**, не чаще 60 раз в
/// секунду, и не шлёт следующий запрос, пока не вернулся прежний. На паузе
/// полосы опадают, и тикер встаёт.
class MediaSpectrum extends StatefulWidget {
  const MediaSpectrum({super.key, required this.player, required this.playing});

  final SystemAudioPlayer player;
  final bool playing;

  /// Не чаще этого спрашивать плеер — 60 раз в секунду: раннер считает спектр
  /// по запросу, из последних сэмплов, так что свежесть задаёт этот опрос
  /// (`audio-viewer.md`, §7.1).
  static const Duration pollEvery = Duration(milliseconds: 16);

  @override
  State<MediaSpectrum> createState() => _MediaSpectrumState();
}

class _MediaSpectrumState extends State<MediaSpectrum> with SingleTickerProviderStateMixin {
  final SpectrumMotion _motion = SpectrumMotion(spectrumBands);
  final ValueNotifier<int> _frame = ValueNotifier(0);
  late final Ticker _ticker = createTicker(_tick);

  Duration _last = Duration.zero;
  Duration _askedAt = -MediaSpectrum.pollEvery;
  bool _asking = false;
  List<double>? _target;

  @override
  void initState() {
    super.initState();
    _wake();
  }

  @override
  void didUpdateWidget(MediaSpectrum oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.player, widget.player)) {
      // Сменился трек: прежние полосы — уже не про него.
      _target = null;
    }
    _wake();
  }

  /// Играет — тикер идёт; встал — идёт, пока не опадёт.
  void _wake() {
    if (!_ticker.isActive && (widget.playing || !_motion.resting)) {
      _last = Duration.zero;
      _askedAt = -MediaSpectrum.pollEvery;
      unawaited(_ticker.start());
    }
  }

  void _tick(Duration elapsed) {
    final dt = elapsed - _last;
    _last = elapsed;
    if (widget.playing && !_asking && elapsed - _askedAt >= MediaSpectrum.pollEvery) {
      _askedAt = elapsed;
      _asking = true;
      final player = widget.player;
      widget.player.spectrum().then((levels) {
        _asking = false;
        if (mounted && identical(player, widget.player)) {
          _target = levels;
        }
      });
    }
    _motion.step(dt, widget.playing ? _target : null);
    _frame.value++;
    if (!widget.playing && _motion.resting) {
      _target = null;
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = FcTheme.of(context).colors.spectrumBar;
    return RepaintBoundary(child: CustomPaint(painter: _SpectrumPainter(_motion, color, _frame), size: Size.infinite));
  }
}

class _SpectrumPainter extends CustomPainter {
  _SpectrumPainter(this.motion, this.color, Listenable repaint) : super(repaint: repaint);

  final SpectrumMotion motion;
  final Color color;

  /// Просвет между полосками.
  static const double gap = 2;

  /// Толщина чёрточки пика.
  static const double peakThickness = 2;

  @override
  void paint(Canvas canvas, Size size) {
    final bands = motion.levels.length;
    if (size.isEmpty || bands == 0) {
      return;
    }
    final width = (size.width - gap * (bands - 1)) / bands;
    if (width <= 0) {
      return;
    }
    // К вершине светлее: один градиент на всю высоту — полоска светлеет по мере
    // роста, как в Winamp.
    final bar =
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [color, Color.lerp(color, const Color(0xFFFFFFFF), 0.35)!],
          ).createShader(Offset.zero & size);
    final peak = Paint()..color = Color.lerp(color, const Color(0xFFFFFFFF), 0.2)!;
    final room = size.height - peakThickness;
    for (var i = 0; i < bands; i++) {
      final x = i * (width + gap);
      final level = motion.levels[i];
      if (level > 0) {
        final height = level * room;
        canvas.drawRect(Rect.fromLTWH(x, size.height - height, width, height), bar);
      }
      final top = motion.peaks[i];
      if (top > 0.01) {
        final y = size.height - top * room - peakThickness;
        canvas.drawRect(Rect.fromLTWH(x, y, width, peakThickness), peak);
      }
    }
  }

  @override
  bool shouldRepaint(_SpectrumPainter old) => old.color != color || !identical(old.motion, motion);
}
