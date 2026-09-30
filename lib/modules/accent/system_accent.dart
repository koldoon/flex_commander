import 'dart:async';

import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:logecom/logecom.dart';

/// Акцентный цвет системы — каналом раннера, как значки, картинки и шрифты.
///
/// Модуль платформенный, поэтому стоит рядом с ними, а не в `dependency/`: без
/// своего раннера канала не существует. Выключишь — оформления macOS остаются с
/// постоянным синим, и это по-прежнему работает
/// (`docs/spec/macos-themes.md`, §5).
class SystemAccentColor implements FcFrontendModule {
  const SystemAccentColor();

  @override
  String get id => 'fc.systemAccent';

  @override
  String get title => 'System accent';

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.strings('ru', {'System accent': 'Системный акцент'});

    registry.service<SystemAccent>((services) => ChannelSystemAccent());

    // Спрашиваем при запуске, а дальше нас будят: акцент меняют в системных
    // настройках когда угодно.
    registry.startup((context) => _AskAccentCommand(context));
  }
}

/// Реализация [SystemAccent] поверх канала раннера.
///
/// Канал **двусторонний**, и этим он первый в приложении: пять прежних только
/// отвечали на вопрос. Здесь раннер ещё и заговаривает сам — иначе смену акцента
/// пришлось бы опрашивать таймером, а таймер, переживший окно, роняет виджетные
/// тесты.
class ChannelSystemAccent extends ChangeNotifier implements SystemAccent {
  ChannelSystemAccent({MethodChannel? channel}) : _channel = channel ?? const MethodChannel(channelName) {
    _channel.setMethodCallHandler(_fromRunner);
  }

  static const String channelName = 'flex_commander/accent';

  final MethodChannel _channel;

  Color? _light;
  Color? _dark;

  @override
  Color? get light => _light;

  @override
  Color? get dark => _dark;

  @override
  Future<void> refresh() async => _remember(await _ask());

  /// Раннер сообщил, что акцент сменили.
  Future<Object?> _fromRunner(MethodCall call) async {
    if (call.method == 'changed') {
      _remember(call.arguments);
    }
    return null;
  }

  /// Ответ и событие — одного вида: `{'light': 0xAARRGGBB, 'dark': …}`.
  ///
  /// Молчание — тоже ответ: акцента нет, и оформления остаются с постоянным
  /// синим.
  void _remember(Object? answer) {
    if (answer is! Map) {
      return;
    }
    final light = _color(answer['light']);
    final dark = _color(answer['dark']);
    if (light == _light && dark == _dark) {
      // Уведомление о том же самом заставило бы перевыложить темы впустую.
      // Присылок может быть две: AppKit и распределённое уведомление говорят об
      // одном событии каждый по-своему.
      return;
    }
    _light = light;
    _dark = dark;
    notifyListeners();
  }

  Color? _color(Object? value) => value is int ? Color(value) : null;

  /// Спросить раннер.
  ///
  /// Канала может не быть вовсе — на другой платформе или в тесте, — и это не
  /// ошибка: [MissingPluginException] значит ровно «спросить некого».
  Future<Object?> _ask() async {
    try {
      // Без срока: срок — это таймер, а таймер, переживший окно, роняет
      // виджетные тесты.
      return await _channel.invokeMethod<Map<Object?, Object?>>('accent');
    } on MissingPluginException {
      return null;
    } catch (error) {
      Logecom.createLogger('SystemAccent').warn('Акцент не спросить: $error');
      return null;
    }
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }
}

/// Стартовая команда: спросить систему и запомнить ответ.
class _AskAccentCommand extends AppCommand {
  _AskAccentCommand(this.env);

  final FcContext env;

  @override
  String get id => 'fc.accent.refresh';

  @override
  String get label => tr('System accent');

  @override
  bool isExecutable(CommandContext context) => true;

  /// Запуска **держит**, в отличие от перечня шрифтов. Причина в том, что видно
  /// глазом: не дождавшись ответа, окно откроется синим и перекрасится в
  /// настоящий акцент через кадр — то есть мигнёт у всех, у кого акцент не
  /// синий. Зависнуть тут не на чем: чтение цвета у системы мгновенно, а без
  /// канала вызов падает сразу.
  @override
  Future<void> execute(CommandContext context) async {
    await env.resolve<SystemAccent>().refresh();
  }
}
