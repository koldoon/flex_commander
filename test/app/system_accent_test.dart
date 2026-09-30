import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flex_commander/modules/accent/system_accent.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(ChannelSystemAccent.channelName);
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  const pink = Color(0xFFFF2D55);
  const brightPink = Color(0xFFFF375F);

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('акцент приезжает ответом на вопрос', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'accent');
      return <String, Object?>{'light': pink.toARGB32(), 'dark': brightPink.toARGB32()};
    });

    final accent = ChannelSystemAccent();
    var notifications = 0;
    accent.addListener(() => notifications++);

    await accent.refresh();

    expect(accent.light, pink);
    expect(accent.dark, brightPink);
    expect(notifications, 1);
  });

  test('канала нет — это «спросить некого», а не падение', () async {
    // Ни обработчика, ни раннера: так бывает на другой платформе и в тесте.
    final accent = ChannelSystemAccent();

    await accent.refresh();

    expect(accent.light, isNull);
    expect(accent.dark, isNull);
  });

  test('раннер сообщает о смене сам, и оформления об этом узнают', () async {
    final accent = ChannelSystemAccent();
    var notifications = 0;
    accent.addListener(() => notifications++);

    // Событие «из раннера»: канал двусторонний, и это первый в приложении,
    // который заговаривает сам.
    await _fromRunner(messenger, <String, Object?>{'light': pink.toARGB32(), 'dark': brightPink.toARGB32()});

    expect(accent.light, pink);
    expect(notifications, 1);

    // Присылок об одном событии бывает две: AppKit и распределённое уведомление.
    // Второй раз о том же будить незачем — темы перевыкладывались бы впустую.
    await _fromRunner(messenger, <String, Object?>{'light': pink.toARGB32(), 'dark': brightPink.toARGB32()});
    expect(notifications, 1);
  });

  test('служба объявлена контрактом, а не своим классом', () {
    // Модуль можно выключить, и тогда некому будет спросить — но и знать о
    // канале никто не обязан: потребители видят только контракт.
    expect(ChannelSystemAccent(), isA<SystemAccent>());
  });
}

/// Подать событие так, как его подаёт раннер.
Future<void> _fromRunner(TestDefaultBinaryMessenger messenger, Map<String, Object?> arguments) async {
  await messenger.handlePlatformMessage(
    ChannelSystemAccent.channelName,
    const StandardMethodCodec().encodeMethodCall(MethodCall('changed', arguments)),
    (_) {},
  );
}
