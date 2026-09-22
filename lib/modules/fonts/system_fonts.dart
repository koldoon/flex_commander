import 'dart:async';

import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/services.dart';
import 'package:logecom/logecom.dart';

/// Перечень установленных шрифтов — тем же способом, что значки и картинки:
/// каналом раннера.
///
/// Модуль платформенный, поэтому стоит рядом с ними, а не в `dependency/`: без
/// своего раннера канала не существует. Выключишь — шрифт в редакторе тем
/// набирают руками, и это по-прежнему работает
/// (`docs/spec/theme-editor.md`, §12).
class SystemFontList implements FcFrontendModule {
  const SystemFontList();

  @override
  String get id => 'fc.systemFonts';

  @override
  String get title => 'System fonts';

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.strings('ru', {'System fonts': 'Системные шрифты'});

    registry.service<SystemFonts>((services) => ChannelSystemFonts());

    // Спрашиваем один раз при запуске: набор шрифтов за время работы не
    // меняется, а ждать ответа посреди раскрытия списка было бы нечем.
    registry.startup((context) => _AskFontsCommand(context));
  }
}

/// Реализация [SystemFonts] поверх канала раннера.
class ChannelSystemFonts implements SystemFonts {
  ChannelSystemFonts({MethodChannel? channel}) : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'flex_commander/fonts';

  final MethodChannel _channel;

  List<SystemFont> _installed = const [];

  @override
  List<SystemFont> get installed => _installed;

  @override
  Future<void> refresh() async {
    final answer = await _ask();
    if (answer == null) {
      return;
    }
    _installed = [
      for (final item in answer)
        if (item is Map && item['family'] is String)
          SystemFont(family: item['family'] as String, fixedPitch: item['fixedPitch'] == true),
    ];
  }

  /// Спросить раннер. Молчание — тоже ответ: перечня нет, и поле останется
  /// обычной строкой.
  ///
  /// Канала может не быть вовсе — на другой платформе или в тесте, — и это не
  /// ошибка: [MissingPluginException] значит ровно «спросить некого».
  Future<List<Object?>?> _ask() async {
    try {
      // Без срока: срок — это таймер, а таймер, переживший окно, роняет
      // виджетные тесты. Ждать нечему: ответа никто не ждёт, а молчание канала
      // и значит «перечня нет».
      return await _channel.invokeMethod<List<Object?>>('families');
    } on MissingPluginException {
      return null;
    } catch (error) {
      Logecom.createLogger('SystemFonts').warn('Перечень шрифтов не спросить: $error');
      return null;
    }
  }
}

/// Стартовая команда: спросить систему и запомнить ответ.
class _AskFontsCommand extends AppCommand {
  _AskFontsCommand(this.env);

  final FcContext env;

  @override
  String get id => 'fc.fonts.refresh';

  @override
  String get label => tr('System fonts');

  @override
  bool isExecutable(CommandContext context) => true;

  /// Запуска не держит: спросить систему — дело не срочное, а ждать ответа
  /// канала посреди открытия приложения незачем. Ответа нет вовсе — шрифт
  /// набирают руками (`docs/spec/theme-editor.md`, §12).
  @override
  Future<void> execute(CommandContext context) async {
    unawaited(env.resolve<SystemFonts>().refresh());
  }
}
