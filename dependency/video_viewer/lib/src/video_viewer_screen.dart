import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/foundation.dart';

import 'video_source.dart';
import 'video_viewer_settings.dart';

/// Показ ролика: плеер в раннере, время, громкость и плашка управления
/// (`docs/spec/video-viewer.md`).
class VideoViewerScreen extends ChangeNotifier implements ViewerContent {
  VideoViewerScreen({
    required FileEntry entry,
    required this.player,
    required this.source,
    required this.settings,
    required this.onSettingsChanged,
    this.place = ViewerPlace.fullscreen,
    bool autoplay = true,
  }) : _entry = entry {
    unawaited(_start(autoplay));
    _poll = Timer.periodic(pollEvery, (_) => unawaited(_refresh()));
  }

  /// Имя в реестре просмотрщиков.
  static const String viewerId = 'video';

  /// Шаг перемотки стрелкой.
  static const Duration seekStep = Duration(seconds: 5);

  /// Шаг громкости стрелкой.
  static const double volumeStep = 0.1;

  /// Через сколько покоя плашка прячется, пока ролик играет.
  static const Duration hideAfter = Duration(seconds: 2);

  /// Как часто спрашивать плеер, где он: времени на плашке точнее не нужно.
  static const Duration pollEvery = Duration(milliseconds: 250);

  final SystemVideoPlayer player;
  final VideoSource source;
  final VideoViewerSettings settings;
  final void Function() onSettingsChanged;

  @override
  final ViewerPlace place;

  @override
  FileEntry get entry => _entry;
  final FileEntry _entry;

  late final Timer _poll;
  Timer? _hide;

  /// Где плеер. Пока ответ раннера не пришёл, — то, куда его послали: иначе
  /// полоса перемотки отпрыгивала бы назад до следующего опроса.
  Duration get position => _position;
  Duration _position = Duration.zero;

  bool get playing => _playing;
  bool _playing = false;

  /// Доиграл до конца: следующий пуск начнёт сначала.
  bool get ended => _ended;
  bool _ended = false;

  /// Видна ли плашка управления (§6).
  bool get controlsVisible => _controlsVisible;
  bool _controlsVisible = true;

  Future<void> _start(bool autoplay) async {
    await player.setVolume(settings.volume);
    await player.setMuted(settings.muted);
    if (autoplay && !_disposed) {
      await play();
    }
  }

  Future<void> _refresh() async {
    final state = await player.state();
    if (state == null || _disposed) {
      return;
    }
    final changed = state.position != _position || state.playing != _playing || state.ended != _ended;
    _position = state.position;
    _ended = state.ended;
    if (state.playing != _playing) {
      _playing = state.playing;
      // Встал сам — доиграл: плашка показывается, как на любой паузе.
      _scheduleHide();
    }
    if (changed) {
      notifyListeners();
    }
  }

  Future<void> play() async {
    if (_ended) {
      // Доиграл — пуск начинает сначала, как в QuickTime.
      await seekTo(Duration.zero);
    }
    _playing = true;
    _ended = false;
    _scheduleHide();
    notifyListeners();
    await player.play();
  }

  Future<void> pause() async {
    _playing = false;
    _scheduleHide();
    notifyListeners();
    await player.pause();
  }

  Future<void> togglePlay() => _playing ? pause() : play();

  Future<void> seekTo(Duration target) async {
    final duration = player.duration;
    final clamped = target < Duration.zero ? Duration.zero : (target > duration ? duration : target);
    _position = clamped;
    _ended = false;
    poke();
    notifyListeners();
    await player.seek(clamped);
  }

  Future<void> seekBy(Duration delta) => seekTo(_position + delta);

  /// На кадр вперёд или назад — плеер встаёт на паузу.
  Future<void> step(int frames) async {
    _playing = false;
    poke();
    notifyListeners();
    await player.step(frames);
    await _refresh();
  }

  Future<void> changeVolume(double delta) async {
    settings.volume = (settings.volume + delta).clamp(0.0, 1.0);
    if (delta > 0 && settings.muted) {
      // Прибавили громкость — значит, хотят слышать.
      settings.muted = false;
      await player.setMuted(false);
    }
    onSettingsChanged();
    poke();
    notifyListeners();
    await player.setVolume(settings.volume);
  }

  Future<void> setVolume(double volume) async {
    settings.volume = volume.clamp(0.0, 1.0);
    onSettingsChanged();
    poke();
    notifyListeners();
    await player.setVolume(settings.volume);
  }

  Future<void> toggleMute() async {
    settings.muted = !settings.muted;
    onSettingsChanged();
    poke();
    notifyListeners();
    await player.setMuted(settings.muted);
  }

  /// Показать плашку: шевельнули мышью или нажали клавишу (§6).
  void poke() {
    if (!_controlsVisible) {
      _controlsVisible = true;
      notifyListeners();
    }
    _scheduleHide();
  }

  /// Спрятать плашку через [hideAfter] покоя — если ролик играет. На паузе она
  /// видна всегда.
  void _scheduleHide() {
    _hide?.cancel();
    if (!_playing) {
      if (!_controlsVisible) {
        _controlsVisible = true;
        notifyListeners();
      }
      return;
    }
    _hide = Timer(hideAfter, () {
      if (_playing && !_disposed) {
        _controlsVisible = false;
        notifyListeners();
      }
    });
  }

  @override
  bool get takesKeyboard => true;

  @override
  void close() => dispose();

  bool _disposed = false;

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _poll.cancel();
    _hide?.cancel();
    // Закрыли показ — звук смолкает сразу, плеер отпускается, копия убирается
    // (§4, §7).
    unawaited(player.close().whenComplete(source.dispose));
    super.dispose();
  }
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
