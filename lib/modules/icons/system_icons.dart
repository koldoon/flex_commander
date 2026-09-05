import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/services.dart';
import 'package:logecom/logecom.dart';

/// Значки, которые об объектах знает система.
///
/// Нативная часть живёт в раннере (`macos/Runner/MainFlutterWindow.swift`) и
/// делает ровно то, чего нельзя сделать из Flutter: спрашивает `NSWorkspace` и
/// отдаёт сюда картинку. **Какому** объекту какой значок и когда его вообще
/// спрашивать, решают правила иконок и никто другой.
///
/// Модуль платформенный, поэтому и стоит рядом с перетаскиванием, а не в
/// `dependency/`: без своего раннера канала не существует. Выключишь — правила
/// с `system` перестанут совпадать, и иконка возьмётся следующим правилом.
class SystemFileIcons implements FcFrontendModule {
  const SystemFileIcons();

  @override
  String get id => 'fc.systemIcons';

  @override
  String get title => 'System icons';

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.service<SystemIcons>((services) => ChannelSystemIcons());
  }
}

/// Реализация [SystemIcons] поверх канала раннера.
class ChannelSystemIcons implements SystemIcons {
  ChannelSystemIcons({MethodChannel? channel}) : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'flex_commander/icons';

  final MethodChannel _channel;

  @override
  Future<Uint8List?> forPath(String path, {required int pixels}) =>
      _ask('iconForPath', {'path': path, 'pixels': pixels});

  @override
  Future<Uint8List?> forExtension(String extension, {required int pixels}) =>
      _ask('iconForExtension', {'extension': extension, 'pixels': pixels});

  @override
  Future<Uint8List?> forKind(SystemIconKind kind, {required int pixels}) =>
      _ask('iconForKind', {'kind': kind.name, 'pixels': pixels});

  /// Спросить раннер. Молчание — тоже ответ: значка нет.
  ///
  /// Канала может не быть вовсе — на другой платформе или в тесте, — и это не
  /// ошибка: [MissingPluginException] значит ровно «спросить некого».
  ///
  /// **Но сказать об этом надо.** Молча вернуть null здесь значит показать
  /// человеку список без единой системной иконки и не дать ни одной зацепки,
  /// почему включённая настройка ничего не изменила. Особенно на живой правке:
  /// горячая перезагрузка обновляет Dart, но не раннер, и канала в уже
  /// запущенном приложении просто нет.
  Future<Uint8List?> _ask(String method, Map<String, Object?> arguments) async {
    try {
      return await _channel.invokeMethod<Uint8List>(method, arguments);
    } on MissingPluginException {
      _complainOnce(
        'Канала «$channelName» в этом приложении нет: системные иконки '
        'показать нечем. Раннер собирается заново — горячей перезагрузки '
        'для него мало.',
      );
      return null;
    } on PlatformException catch (error) {
      _complainOnce('Раннер отказал в значке ($method): ${error.message}');
      return null;
    }
  }

  /// Жаловаться один раз за сеанс: строк в каталоге тысячи, и жалоба на каждую
  /// превратила бы журнал в шум, в котором её же и не найти.
  void _complainOnce(String message) {
    if (_complained) {
      return;
    }
    _complained = true;
    Logecom.createLogger('SystemIcons').warn(message);
  }

  bool _complained = false;
}
