import 'dart:io';
import 'dart:ui';

import 'package:fc_ui_api/fc_ui_api.dart';

/// Подставной [SystemVideo]: всё, о чём просили, записано.
class FakeSystemVideo implements SystemVideo {
  FakeSystemVideo({this.refuse});

  /// Чем отказать вместо плеера; null — играть.
  String? Function(String path)? refuse;

  /// Плееры по порядку открытия.
  final List<FakeVideoPlayer> opened = [];

  /// Пути, которые просили открыть, — и что в них лежало в тот миг: копия
  /// после закрытия удаляется, а проверить её надо.
  final List<(String, List<int>?)> paths = [];

  @override
  Future<SystemVideoOpened?> open(String path) async {
    final file = File(path);
    paths.add((path, file.existsSync() ? file.readAsBytesSync() : null));
    final refusal = refuse?.call(path);
    if (refusal != null) {
      return SystemVideoRefused(refusal);
    }
    final player = FakeVideoPlayer(opened.length + 100);
    opened.add(player);
    return player;
  }
}

class FakeVideoPlayer implements SystemVideoPlayer {
  FakeVideoPlayer(this.textureId);

  @override
  final int textureId;

  @override
  Size get size => const Size(1920, 1080);

  @override
  int get quarterTurns => 0;

  @override
  Duration get duration => const Duration(minutes: 1);

  @override
  SystemVideoInfo get info =>
      const SystemVideoInfo(videoCodec: 'avc1', audioCodecs: ['aac'], frameRate: 30, bitRate: 4000000);

  /// Что звали, по порядку: `play`, `pause`, `seek 5000`, `step 1`, `volume 0.5`, `muted true`.
  final List<String> calls = [];

  Duration position = Duration.zero;
  bool playing = false;
  bool closed = false;

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
  Future<void> step(int frames) async {
    calls.add('step $frames');
    playing = false;
  }

  @override
  Future<void> setVolume(double volume) async => calls.add('volume ${volume.toStringAsFixed(1)}');

  @override
  Future<void> setMuted(bool muted) async => calls.add('muted $muted');

  @override
  Future<SystemVideoState?> state() async =>
      closed ? null : SystemVideoState(position: position, playing: playing, ended: false);

  @override
  Future<void> close() async {
    calls.add('close');
    closed = true;
    playing = false;
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
