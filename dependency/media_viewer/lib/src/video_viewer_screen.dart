import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/foundation.dart';

import 'media_screen.dart';
import 'media_source.dart';
import 'video_aspect.dart';
import 'video_viewer_commands.dart';
import 'video_viewer_settings.dart';

/// Показ ролика: плеер в раннере, время, громкость и плашка управления
/// (`docs/spec/video-viewer.md`).
class VideoViewerScreen extends ChangeNotifier implements MediaScreen, ViewerUnwinds {
  VideoViewerScreen({
    required FileEntry entry,
    required this.player,
    required this.source,
    required this.settings,
    required this.onSettingsChanged,
    this.place = ViewerPlace.fullscreen,
    this.window,
    this.memory,
    bool autoplay = true,
  }) : _entry = entry,
       _aspect = memory?.read<VideoAspect>(entry, aspectKey) ?? VideoAspect.original {
    // Состояние шлёт плеер сам — опроса нет (`audio-viewer.md`, §7.5).
    _states = player.states.listen(_onState);
    unawaited(_start(autoplay));
  }

  /// Имя в реестре просмотрщиков.
  static const String viewerId = 'video';

  /// Под каким ключом соотношение лежит в памяти показа (§6б).
  static const String aspectKey = 'video.aspect';

  /// Шаг перемотки стрелкой.
  static const Duration seekStep = Duration(seconds: 5);

  /// Шаг громкости стрелкой.
  static const double volumeStep = 0.1;

  /// Через сколько покоя плашка прячется, пока ролик играет.
  static const Duration hideAfter = Duration(seconds: 2);

  /// Такт, которым считается покой: плашка прячется не раньше [hideAfter] и
  /// не позже [hideAfter] и одного такта после последнего движения.
  static const Duration hideTick = Duration(milliseconds: 250);

  final SystemVideoPlayer player;
  final MediaSource source;
  @override
  final VideoViewerSettings settings;
  final void Function() onSettingsChanged;

  @override
  final ViewerPlace place;

  /// Окно приложения: полный экран ролика — это и полный экран окна (§6а).
  /// null — окна нет (тесты вида), и полный экран только внутри приложения.
  final WindowService? window;

  /// Память хозяина: соотношение помнится, пока открыт быстрый просмотр
  /// (§6б). null — открыт во весь экран, и помнить незачем.
  final ViewerMemory? memory;

  /// Ролик закрывает окно целиком (§6а).
  bool get fullScreen => _fullScreen;
  bool _fullScreen = false;

  /// Окно перевели в полный экран **мы** — значит, мы и вернём. Было в нём и
  /// до того — выходя, его не трогаем.
  bool _windowMadeFull = false;

  @override
  FileEntry get entry => _entry;
  final FileEntry _entry;

  late final StreamSubscription<SystemVideoState> _states;

  /// Такт покоя — один на всё время, пока ролик играет и плашка видна. Не
  /// таймер на каждое движение: мышь шлёт до 120 событий в секунду, и столько
  /// же таймеров создавалось бы и выбрасывалось.
  Timer? _hide;

  /// Шевелили с прошлого такта.
  bool _moved = false;

  /// Сколько тактов подряд без движения.
  int _quietTicks = 0;

  /// Где плеер. Пока ответ раннера не пришёл, — то, куда его послали: иначе
  /// полоса перемотки отпрыгивала бы назад до следующего состояния от плеера.
  Duration get position => _position.value;

  /// Позиция — отдельно от прочего: она сдвигается 4 раза в секунду, а будить
  /// ей нужно только плашку, а не весь вид (`audio-viewer.md`, §7.5).
  ValueListenable<Duration> get positionListenable => _position;
  final ValueNotifier<Duration> _position = ValueNotifier(Duration.zero);

  @override
  bool get playing => _playing;
  bool _playing = false;

  /// Доиграл до конца: следующий пуск начнёт сначала.
  bool get ended => _ended;
  bool _ended = false;

  /// Соотношение сторон кадра (§6б). Не настройка: новый файл начинает с
  /// исходного, а помнит его только хозяин, пока открыт ([memory]).
  VideoAspect get aspect => _aspect;
  VideoAspect _aspect;

  set aspect(VideoAspect value) {
    if (value == _aspect || _disposed) {
      return;
    }
    _aspect = value;
    memory?.write(entry, aspectKey, value == VideoAspect.original ? null : value);
    notifyListeners();
  }

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

  void _onState(SystemVideoState state) {
    if (_disposed) {
      return;
    }
    final changed = state.playing != _playing || state.ended != _ended;
    _position.value = state.position;
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

  @override
  Future<void> pause() async {
    _playing = false;
    _scheduleHide();
    notifyListeners();
    await player.pause();
  }

  @override
  Future<void> togglePlay() => _playing ? pause() : play();

  Future<void> seekTo(Duration target) async {
    final duration = player.duration;
    final clamped = target < Duration.zero ? Duration.zero : (target > duration ? duration : target);
    _position.value = clamped;
    _ended = false;
    poke();
    notifyListeners();
    await player.seek(clamped);
  }

  Future<void> seekBy(Duration delta) => seekTo(_position.value + delta);

  /// На кадр вперёд или назад — плеер встаёт на паузу.
  Future<void> step(int frames) async {
    _playing = false;
    poke();
    notifyListeners();
    await player.step(frames);
    // Встал на кадр — где именно, спрашивается сразу.
    final state = await player.state();
    if (state != null) {
      _onState(state);
    }
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

  @override
  Future<void> toggleMute() async {
    settings.muted = !settings.muted;
    onSettingsChanged();
    poke();
    notifyListeners();
    await player.setMuted(settings.muted);
  }

  /// Показать плашку: шевельнули мышью или нажали клавишу (§6).
  ///
  /// Зовётся на каждое событие мыши, поэтому дёшево: только отметка, а такт
  /// заводится, лишь когда его нет.
  void poke() {
    if (!_controlsVisible) {
      _controlsVisible = true;
      notifyListeners();
    }
    _moved = true;
    _scheduleHide();
  }

  /// Спрятать плашку через [hideAfter] покоя — если ролик играет. На паузе она
  /// видна всегда.
  void _scheduleHide() {
    if (!_playing) {
      _hide?.cancel();
      _hide = null;
      if (!_controlsVisible) {
        _controlsVisible = true;
        notifyListeners();
      }
      return;
    }
    if (_hide != null) {
      // Такт уже идёт — движение он заметит сам.
      return;
    }
    _moved = false;
    _quietTicks = 0;
    _hide = Timer.periodic(hideTick, (_) => _tickHide());
  }

  void _tickHide() {
    if (_moved) {
      _moved = false;
      _quietTicks = 0;
      return;
    }
    _quietTicks++;
    if (hideTick * _quietTicks < hideAfter) {
      return;
    }
    _hide?.cancel();
    _hide = null;
    if (_playing && !_disposed) {
      _controlsVisible = false;
      notifyListeners();
    }
  }

  /// Во весь экран или обратно: клавиша `F`, двойной щелчок по кадру, кнопка
  /// на плашке.
  Future<void> toggleFullScreen() => _fullScreen ? _leaveFullScreen() : _enterFullScreen();

  Future<void> _enterFullScreen() async {
    _fullScreen = true;
    poke();
    notifyListeners();
    final window = this.window;
    if (window != null && !await window.isFullScreen()) {
      _windowMadeFull = true;
      await window.setFullScreen(true);
    }
  }

  Future<void> _leaveFullScreen() async {
    _fullScreen = false;
    poke();
    if (!_disposed) {
      notifyListeners();
    }
    if (_windowMadeFull) {
      _windowMadeFull = false;
      await window?.setFullScreen(false);
    }
  }

  /// `Esc` в полном экране выходит из него, а не закрывает показ.
  @override
  bool unwind() {
    if (!_fullScreen) {
      return false;
    }
    unawaited(_leaveFullScreen());
    return true;
  }

  @override
  FcTableSection infoSection(Strings strings) => videoInfoSection(this, strings);

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
    unawaited(_states.cancel());
    _hide?.cancel();
    // Закрыли из полного экрана (курсор быстрого просмотра ушёл, F10) — окно
    // возвращается таким, каким было.
    if (_fullScreen) {
      unawaited(_leaveFullScreen());
    }
    // Закрыли показ — звук смолкает сразу, плеер отпускается, копия убирается
    // (§4, §7).
    unawaited(player.close().whenComplete(source.dispose));
    _position.dispose();
    super.dispose();
  }
}
