import 'dart:async';

import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/foundation.dart';

import 'media_controls.dart';
import 'media_screen.dart';
import 'media_source.dart';
import 'video_viewer_settings.dart';

/// Показ звукового файла: плеер в раннере, теги и альбом
/// (`docs/spec/audio-viewer.md`).
///
/// Альбом — звуковые файлы того же списка панели: доиграл — следующий,
/// `PgUp`/`PgDn` — вручную. Курсор панели при этом не двигается.
class AudioViewerScreen extends ChangeNotifier implements MediaScreen {
  AudioViewerScreen({
    required FileEntry entry,
    required SystemAudioPlayer player,
    required MediaSource source,
    required this.settings,
    required this.onSettingsChanged,
    required this.system,
    required this.tracks,
    required this.contentOf,
    required this.localPathOf,
    this.place = ViewerPlace.fullscreen,
    this.say,
    bool autoplay = true,
  }) : _entry = entry,
       _player = player,
       _source = source {
    _listen();
    unawaited(_start(autoplay));
  }

  /// Имя в реестре просмотрщиков.
  static const String viewerId = 'audio';

  static const Duration seekStep = Duration(seconds: 5);
  static const double volumeStep = 0.1;

  @override
  final VideoViewerSettings settings;
  final void Function() onSettingsChanged;

  /// Чем открыть следующий трек.
  final SystemVideo system;

  /// Альбом: звуковые файлы списка панели по порядку; в нём и открытый.
  final List<FileEntry> tracks;

  final Content Function(FileEntry entry) contentOf;
  final String? Function(FileEntry entry) localPathOf;

  /// Сказать человеку словами: следующий трек не открылся.
  final void Function(String message)? say;

  @override
  final ViewerPlace place;

  /// Что играет сейчас — сменяется с треком.
  @override
  FileEntry get entry => _entry;
  FileEntry _entry;

  SystemAudioPlayer get player => _player;
  SystemAudioPlayer _player;
  MediaSource _source;

  /// Состояние шлёт плеер сам — опроса нет (`audio-viewer.md`, §7.5).
  StreamSubscription<SystemVideoState>? _states;

  Duration get position => _position.value;

  /// Позиция — отдельно от прочего: она сдвигается 4 раза в секунду, а будить
  /// ей нужно только плашку, а не весь вид (`audio-viewer.md`, §7.5).
  ValueListenable<Duration> get positionListenable => _position;
  final ValueNotifier<Duration> _position = ValueNotifier(Duration.zero);

  @override
  bool get playing => _playing;
  bool _playing = false;

  bool get ended => _ended;
  bool _ended = false;

  /// Идёт смена трека: состояние в это время конец не толкует.
  bool _switching = false;

  int get _index => tracks.indexWhere((track) => track.path == _entry.path);

  bool get hasNext => _index >= 0 && _index < tracks.length - 1;
  bool get hasPrevious => _index > 0;

  Future<void> _start(bool autoplay) async {
    await _player.setVolume(settings.volume);
    await _player.setMuted(settings.muted);
    if (autoplay && !_disposed) {
      await play();
    }
  }

  void _listen() {
    unawaited(_states?.cancel());
    _states = _player.states.listen((state) => unawaited(_onState(state)));
  }

  Future<void> _onState(SystemVideoState state) async {
    if (_disposed || _switching) {
      return;
    }
    if (state.ended && _playing && hasNext) {
      // Доиграл — следующий, как альбом (§3).
      await next();
      return;
    }
    final changed = state.playing != _playing || state.ended != _ended;
    _position.value = state.position;
    _playing = state.playing;
    _ended = state.ended;
    if (changed) {
      notifyListeners();
    }
  }

  Future<void> play() async {
    if (_ended) {
      await seekTo(Duration.zero);
    }
    _playing = true;
    _ended = false;
    notifyListeners();
    await _player.play();
  }

  @override
  Future<void> pause() async {
    _playing = false;
    notifyListeners();
    await _player.pause();
  }

  @override
  Future<void> togglePlay() => _playing ? pause() : play();

  Future<void> seekTo(Duration target) async {
    final duration = _player.duration;
    final clamped = target < Duration.zero ? Duration.zero : (target > duration ? duration : target);
    _position.value = clamped;
    _ended = false;
    notifyListeners();
    await _player.seek(clamped);
  }

  Future<void> seekBy(Duration delta) => seekTo(_position.value + delta);

  Future<void> changeVolume(double delta) async {
    settings.volume = (settings.volume + delta).clamp(0.0, 1.0);
    if (delta > 0 && settings.muted) {
      settings.muted = false;
      await _player.setMuted(false);
    }
    onSettingsChanged();
    notifyListeners();
    await _player.setVolume(settings.volume);
  }

  Future<void> setVolume(double volume) async {
    settings.volume = volume.clamp(0.0, 1.0);
    onSettingsChanged();
    notifyListeners();
    await _player.setVolume(settings.volume);
  }

  @override
  Future<void> toggleMute() async {
    settings.muted = !settings.muted;
    onSettingsChanged();
    notifyListeners();
    await _player.setMuted(settings.muted);
  }

  /// Следующий трек альбома; false — его нет или ни один дальше не открылся.
  Future<bool> next() => _step(1);

  /// Предыдущий трек альбома.
  Future<bool> previous() => _step(-1);

  Future<bool> _step(int direction) async {
    if (_switching || _disposed) {
      return false;
    }
    _switching = true;
    try {
      // Трек, который система не играет, пропускается: альбом не должен
      // вставать посреди из-за одного `.ogg`.
      for (var at = _index + direction; at >= 0 && at < tracks.length; at += direction) {
        if (await _open(tracks[at])) {
          return true;
        }
      }
      return false;
    } finally {
      _switching = false;
    }
  }

  /// Открыть [track] вместо нынешнего. Прежний плеер закрывается — звук
  /// смолкает сразу, — прежняя копия убирается.
  Future<bool> _open(FileEntry track) async {
    final MediaSource source;
    try {
      final local = localPathOf(track);
      source = await MediaSource.prepareFile(track, local == null ? contentOf(track) : null, localPath: local);
    } on Object {
      say?.call(track.name);
      return false;
    }
    final opened = await system.openAudio(source.path);
    if (opened is! SystemAudioPlayer) {
      if (opened is SystemMediaPlayer) {
        await opened.close();
      }
      await source.dispose();
      return false;
    }
    if (_disposed) {
      await opened.close();
      await source.dispose();
      return false;
    }

    final (oldPlayer, oldSource) = (_player, _source);
    _player = opened;
    _source = source;
    _listen();
    _entry = track;
    _position.value = Duration.zero;
    _ended = false;
    unawaited(oldPlayer.close().whenComplete(oldSource.dispose));

    await opened.setVolume(settings.volume);
    await opened.setMuted(settings.muted);
    // Сменил трек — играет: и по концу прежнего, и по `PgDn`.
    _playing = true;
    notifyListeners();
    await opened.play();
    return true;
  }

  @override
  FcTableSection infoSection(Strings strings) {
    final info = _player.info;
    final tags = _player.tags;
    return FcTableSection(strings.tr('Audio'), [
      FcTableRow(strings.tr('Length'), formatClock(_player.duration)),
      if (info.audioCodecs.isNotEmpty) FcTableRow(strings.tr('Codec'), info.audioCodecs.join(', ')),
      if (info.bitRate > 0) FcTableRow(strings.tr('Bit rate'), '${(info.bitRate / 1000).round()} kbit/s'),
      if (info.sampleRate > 0)
        FcTableRow(strings.tr('Sample rate'), '${(info.sampleRate / 1000).toStringAsFixed(1)} kHz'),
      if (info.channels > 0) FcTableRow(strings.tr('Channels'), '${info.channels}'),
      if (tags.title.isNotEmpty) FcTableRow(strings.tr('Title'), tags.title),
      if (tags.artist.isNotEmpty) FcTableRow(strings.tr('Artist'), tags.artist),
      if (tags.album.isNotEmpty) FcTableRow(strings.tr('Album'), tags.album),
      if (tags.year.isNotEmpty) FcTableRow(strings.tr('Year'), tags.year),
      FcTableRow(strings.tr('File size'), formatBytesLong(_entry.size)),
    ]);
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
    unawaited(_states?.cancel());
    // Закрыли показ — звук смолкает сразу, плеер отпускается, копия убирается.
    unawaited(_player.close().whenComplete(_source.dispose));
    _position.dispose();
    super.dispose();
  }
}
