import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:fc_ui_api/fc_ui_api.dart';

/// Подставной [SystemVideo]: всё, о чём просили, записано.
class FakeSystemVideo implements SystemVideo {
  FakeSystemVideo({this.refuse, this.tagsOf});

  /// Чем отказать вместо плеера; null — играть.
  String? Function(String path)? refuse;

  /// Теги звукового файла по пути; null — тегов нет.
  SystemAudioTags Function(String path)? tagsOf;

  /// Плееры по порядку открытия — видео и звука вперемешку.
  final List<FakeMediaPlayer> opened = [];

  /// Пути, которые просили открыть, — и что в них лежало в тот миг: копия
  /// после закрытия удаляется, а проверить её надо.
  final List<(String, List<int>?)> paths = [];

  String? _record(String path) {
    final file = File(path);
    paths.add((path, file.existsSync() ? file.readAsBytesSync() : null));
    return refuse?.call(path);
  }

  @override
  Future<SystemVideoOpened?> open(String path) async {
    final refusal = _record(path);
    if (refusal != null) {
      return SystemVideoRefused(refusal);
    }
    final player = FakeVideoPlayer(opened.length + 100);
    opened.add(player);
    return player;
  }

  @override
  Future<SystemVideoOpened?> openAudio(String path) async {
    final refusal = _record(path);
    if (refusal != null) {
      return SystemVideoRefused(refusal);
    }
    final player = FakeAudioPlayer(path, tagsOf?.call(path) ?? const SystemAudioTags());
    opened.add(player);
    return player;
  }
}

/// Общее подставных плееров: что звали и где стоят.
abstract class FakeMediaPlayer implements SystemMediaPlayer {
  @override
  Duration get duration => const Duration(minutes: 1);

  /// Что звали, по порядку: `play`, `pause`, `seek 5000`, `step 1`, `volume 0.5`, `muted true`.
  final List<String> calls = [];

  Duration position = Duration.zero;
  bool playing = false;
  bool closed = false;

  /// Доиграл — так его видит опрос.
  bool ended = false;

  @override
  Future<void> play() async {
    calls.add('play');
    playing = true;
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    playing = false;
  }

  @override
  Future<void> seek(Duration position) async {
    calls.add('seek ${position.inMilliseconds}');
    this.position = position;
  }

  @override
  Future<void> setVolume(double volume) async => calls.add('volume ${volume.toStringAsFixed(1)}');

  @override
  Future<void> setMuted(bool muted) async => calls.add('muted $muted');

  @override
  Future<SystemVideoState?> state() async =>
      closed ? null : SystemVideoState(position: position, playing: playing, ended: ended);

  @override
  Future<void> close() async {
    calls.add('close');
    closed = true;
    playing = false;
  }
}

class FakeVideoPlayer extends FakeMediaPlayer implements SystemVideoPlayer {
  FakeVideoPlayer(this.textureId);

  @override
  final int textureId;

  @override
  Size get size => const Size(1920, 1080);

  @override
  int get quarterTurns => 0;

  @override
  SystemVideoInfo get info =>
      const SystemVideoInfo(videoCodec: 'avc1', audioCodecs: ['aac'], frameRate: 30, bitRate: 4000000);

  @override
  Future<void> step(int frames) async {
    calls.add('step $frames');
    playing = false;
  }
}

class FakeAudioPlayer extends FakeMediaPlayer implements SystemAudioPlayer {
  FakeAudioPlayer(this.path, this.tags);

  /// Откуда открыт — тест узнаёт по нему трек.
  final String path;

  @override
  final SystemAudioTags tags;

  @override
  SystemVideoInfo get info =>
      const SystemVideoInfo(audioCodecs: ['.mp3'], bitRate: 320000, sampleRate: 44100, channels: 2);

  /// Что отдаёт спектр; null — спектра нет.
  Float32List? levels;

  /// Сколько раз спектр спрашивали.
  int spectrumCalls = 0;

  @override
  Future<Float32List?> spectrum() async {
    spectrumCalls++;
    return closed ? null : levels;
  }
}

class FakeSystemVideoModule implements FcFrontendModule {
  const FakeSystemVideoModule(this.system);

  final SystemVideo system;

  @override
  String get id => 'test.video';

  @override
  String get title => 'Test video';

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.service<SystemVideo>((services) => system);
  }
}
