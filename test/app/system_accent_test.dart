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

  // Как отвечает раннер: три цвета на внешность (`spec/macos-themes.md`, §6а).
  const light = SystemAccentColors(accent: pink, selection: Color(0xFFD6224A), textSelection: Color(0xFFFFC2CF));
  const dark = SystemAccentColors(accent: brightPink, selection: Color(0xFFC4183F), textSelection: Color(0xFF7A3445));
  Map<String, Object?> wire(SystemAccentColors colors) => {
    'accent': colors.accent.toARGB32(),
    'selection': colors.selection.toARGB32(),
    'textSelection': colors.textSelection.toARGB32(),
  };
  final answer = <String, Object?>{'light': wire(light), 'dark': wire(dark)};

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('акцент приезжает ответом на вопрос', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'accent');
      return answer;
    });

    final accent = ChannelSystemAccent();
    var notifications = 0;
    accent.addListener(() => notifications++);

    await accent.refresh();

    expect(accent.light, light);
    expect(accent.dark, dark);
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
    await _fromRunner(messenger, answer);

    expect(accent.light, light);
    expect(accent.dark, dark);
    expect(notifications, 1);

    // Присылок об одном событии бывает две: AppKit и распределённое уведомление.
    // Второй раз о том же будить незачем — темы перевыкладывались бы впустую.
    await _fromRunner(messenger, answer);
    expect(notifications, 1);
  });

  test('неполный набор — как молчание: оформлению полнабора не нужно', () async {
    // Так ответил бы раннер, собранный до §6а: один акцент на внешность.
    final accent = ChannelSystemAccent();

    await _fromRunner(messenger, <String, Object?>{'light': pink.toARGB32(), 'dark': brightPink.toARGB32()});

    expect(accent.light, isNull);
    expect(accent.dark, isNull);
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
