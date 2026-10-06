import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flex_commander/modules/video/system_video.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Канал плеера (`docs/spec/audio-viewer.md`, §7.5): состояние шлёт раннер сам.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(ChannelSystemVideo.channelName);
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final calls = <String>[];

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return switch (call.method) {
        'openAudio' => <String, Object?>{
          'handle': (call.arguments as Map)['path'] == '/a.mp3' ? 1 : 2,
          'duration': 60.0,
        },
        _ => null,
      };
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<SystemAudioPlayer> open(ChannelSystemVideo system, String path) async =>
      (await system.openAudio(path))! as SystemAudioPlayer;

  test('состояние от раннера доходит до своего плеера, без опроса', () async {
    final system = ChannelSystemVideo();
    final first = await open(system, '/a.mp3');
    final second = await open(system, '/b.mp3');
    final heard = <(int, SystemVideoState)>[];
    first.states.listen((state) => heard.add((1, state)));
    second.states.listen((state) => heard.add((2, state)));

    await _fromRunner(messenger, {'handle': 1, 'position': 12.5, 'playing': true, 'ended': false});
    await _fromRunner(messenger, {'handle': 2, 'position': 60.0, 'playing': false, 'ended': true});
    await pumpEventQueue();

    expect(heard, hasLength(2));
    expect(heard[0].$1, 1);
    expect(heard[0].$2.position, const Duration(milliseconds: 12500));
    expect(heard[0].$2.playing, isTrue);
    expect(heard[1].$1, 2);
    expect(heard[1].$2.ended, isTrue);
    expect(calls, isNot(contains('state')), reason: 'Dart не спрашивает — раннер шлёт сам');
  });

  test('закрытый плеер поток кончает, и запоздавшее состояние никуда не идёт', () async {
    final system = ChannelSystemVideo();
    final player = await open(system, '/a.mp3');
    var done = false;
    final heard = <SystemVideoState>[];
    player.states.listen(heard.add, onDone: () => done = true);

    await player.close();
    await _fromRunner(messenger, {'handle': 1, 'position': 1.0, 'playing': true, 'ended': false});
    await pumpEventQueue();

    expect(done, isTrue);
    expect(heard, isEmpty);
  });
}

/// Подать вызов так, как его подаёт раннер.
Future<void> _fromRunner(TestDefaultBinaryMessenger messenger, Map<String, Object?> arguments) async {
  await messenger.handlePlatformMessage(
    ChannelSystemVideo.channelName,
    const StandardMethodCodec().encodeMethodCall(MethodCall('state', arguments)),
    (_) {},
  );
}
