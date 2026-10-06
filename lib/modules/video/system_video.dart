import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/services.dart';
import 'package:logecom/logecom.dart';

/// Видео силами системы: плеер держит раннер, кадры идут в текстуру, сюда —
/// ручка и сведения (`docs/spec/video-viewer.md`, §3).
///
/// Модуль платформенный и потому стоит рядом с PDF, а не в `dependency/`: без
/// своего раннера канала не существует. Выключишь — просмотрщик видео откажет
/// и предложит открыть файл системой.
class SystemVideoPlayback implements FcFrontendModule {
  const SystemVideoPlayback();

  @override
  String get id => 'fc.systemVideo';

  @override
  String get title => 'System video playback';

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.strings('ru', {'System video playback': 'Системное проигрывание видео'});

    registry.service<SystemVideo>((services) => ChannelSystemVideo());
  }
}

/// Реализация [SystemVideo] поверх канала раннера.
class ChannelSystemVideo implements SystemVideo {
  ChannelSystemVideo({MethodChannel? channel}) : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'flex_commander/video';

  final MethodChannel _channel;

  @override
  Future<SystemVideoOpened?> open(String path) async {
    final answer = await _call<Map<Object?, Object?>>('open', {'path': path});
    if (answer == null) {
      return null;
    }
    final refusal = answer['refused'];
    if (refusal is String) {
      return SystemVideoRefused(refusal);
    }
    final handle = answer['handle'];
    final texture = answer['texture'];
    if (handle is! int || texture is! int) {
      return null;
    }
    return _ChannelVideoPlayer(
      this,
      handle,
      textureId: texture,
      size: Size(_double(answer['width']), _double(answer['height'])),
      quarterTurns: (answer['quarterTurns'] as num?)?.round() ?? 0,
      duration: _duration(answer['duration']),
      info: _infoOf(answer),
    );
  }

  @override
  Future<SystemVideoOpened?> openAudio(String path) async {
    final answer = await _call<Map<Object?, Object?>>('openAudio', {'path': path});
    if (answer == null) {
      return null;
    }
    final refusal = answer['refused'];
    if (refusal is String) {
      return SystemVideoRefused(refusal);
    }
    final handle = answer['handle'];
    if (handle is! int) {
      return null;
    }
    final artwork = answer['artwork'];
    return _ChannelAudioPlayer(
      this,
      handle,
      duration: _duration(answer['duration']),
      info: _infoOf(answer),
      tags: SystemAudioTags(
        title: answer['title'] as String? ?? '',
        artist: answer['artist'] as String? ?? '',
        album: answer['album'] as String? ?? '',
        year: answer['year'] as String? ?? '',
        artwork: artwork is Uint8List && artwork.isNotEmpty ? artwork : null,
      ),
    );
  }

  static SystemVideoInfo _infoOf(Map<Object?, Object?> answer) => SystemVideoInfo(
    videoCodec: answer['videoCodec'] as String? ?? '',
    audioCodecs: [for (final codec in answer['audioCodecs'] as List? ?? const []) '$codec'],
    frameRate: _double(answer['frameRate']),
    bitRate: (answer['bitRate'] as num?)?.round() ?? 0,
    sampleRate: _double(answer['sampleRate']),
    channels: (answer['channels'] as num?)?.round() ?? 0,
  );

  static double _double(Object? value) => value is num ? value.toDouble() : 0;

  /// Секунды числом с дробью — так их отдаёт `CMTime`.
  static Duration _duration(Object? seconds) =>
      seconds is num && seconds.isFinite ? Duration(microseconds: (seconds * 1e6).round()) : Duration.zero;

  /// Вызов, который не роняет показ: нет канала или раннер отказал — null и
  /// одна жалоба в журнал.
  Future<T?> _call<T>(String method, Map<String, Object?> arguments) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      _complainOnce(
        'Канала «$channelName» в этом приложении нет: видео и звук играть нечем. '
        'Раннер собирается заново — горячей перезагрузки для него мало.',
      );
      return null;
    } on PlatformException catch (error) {
      _complainOnce('Раннер отказал в работе с видео и звуком: ${error.message}');
      return null;
    }
  }

  /// Жаловаться один раз за сеанс: состояние опрашивается часто, и жалоба на
  /// каждый опрос превратила бы журнал в шум.
  void _complainOnce(String message) {
    if (_complained) {
      return;
    }
    _complained = true;
    Logecom.createLogger('SystemVideo').warn(message);
  }

  bool _complained = false;
}

/// Общее у плееров видео и звука: ручка и вызовы по ней.
abstract class _ChannelMediaPlayer implements SystemMediaPlayer {
  _ChannelMediaPlayer(this._owner, this._handle, {required this.duration, required this.info});

  final ChannelSystemVideo _owner;
  final int _handle;

  @override
  final Duration duration;

  @override
  final SystemVideoInfo info;

  bool _closed = false;

  Future<void> _send(String method, [Map<String, Object?> arguments = const {}]) async {
    if (_closed) {
      return;
    }
    await _owner._call<Object?>(method, {'handle': _handle, ...arguments});
  }

  @override
  Future<void> play() => _send('play');

  @override
  Future<void> pause() => _send('pause');

  @override
  Future<void> seek(Duration position) => _send('seek', {'seconds': position.inMicroseconds / 1e6});

  @override
  Future<void> setVolume(double volume) => _send('volume', {'volume': volume.clamp(0.0, 1.0)});

  @override
  Future<void> setMuted(bool muted) => _send('muted', {'muted': muted});

  @override
  Future<SystemVideoState?> state() async {
    if (_closed) {
      return null;
    }
    final answer = await _owner._call<Map<Object?, Object?>>('state', {'handle': _handle});
    if (answer == null) {
      return null;
    }
    return SystemVideoState(
      position: ChannelSystemVideo._duration(answer['position']),
      playing: answer['playing'] == true,
      ended: answer['ended'] == true,
    );
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    // Закрытым считается сразу: опрос, который придёт после, ручку уже не
    // тронет.
    _closed = true;
    await _owner._call<Object?>('close', {'handle': _handle});
  }
}

class _ChannelVideoPlayer extends _ChannelMediaPlayer implements SystemVideoPlayer {
  _ChannelVideoPlayer(
    super._owner,
    super._handle, {
    required this.textureId,
    required this.size,
    required this.quarterTurns,
    required super.duration,
    required super.info,
  });

  @override
  final int textureId;

  @override
  final Size size;

  @override
  final int quarterTurns;

  @override
  Future<void> step(int frames) => _send('step', {'frames': frames});
}

class _ChannelAudioPlayer extends _ChannelMediaPlayer implements SystemAudioPlayer {
  _ChannelAudioPlayer(super._owner, super._handle, {required super.duration, required super.info, required this.tags});

  @override
  final SystemAudioTags tags;
}
