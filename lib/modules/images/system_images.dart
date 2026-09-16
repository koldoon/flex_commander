import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/services.dart';
import 'package:logecom/logecom.dart';

/// Картинки, которых не умеет Flutter, — их читает система.
///
/// Нативная часть живёт в раннере (`macos/Runner/MainFlutterWindow.swift`) и
/// делает ровно то, чего нельзя сделать из Flutter: разбирает `HEIC` и отдаёт
/// сюда то, что показать уже можно (`docs/spec/image-viewer.md`, §12).
///
/// Модуль платформенный и потому стоит рядом с перетаскиванием и значками, а не
/// в `dependency/`: без своего раннера канала не существует. Выключишь —
/// просмотрщик откажет теми же словами, что и до него.
class SystemImageDecoding implements FcFrontendModule {
  const SystemImageDecoding();

  @override
  String get id => 'fc.systemImages';

  @override
  String get title => 'System image decoding';

  @override
  void installFrontend(FrontendRegistry registry) {
    registry.strings('ru', {'System image decoding': 'Системный разбор картинок'});

    registry.service<SystemImages>((services) => ChannelSystemImages());
  }
}

/// Реализация [SystemImages] поверх канала раннера.
class ChannelSystemImages implements SystemImages {
  ChannelSystemImages({MethodChannel? channel}) : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'flex_commander/images';

  final MethodChannel _channel;

  @override
  Future<SystemImage?> readable(Uint8List bytes, {required int maxPixels}) async {
    try {
      final answer = await _channel.invokeMapMethod<String, Object?>('readable', {
        'bytes': bytes,
        'maxPixels': maxPixels,
      });
      if (answer == null) {
        return null;
      }
      final width = answer['width'];
      final height = answer['height'];
      if (width is! int || height is! int) {
        return null;
      }
      return SystemImage(
        width: width,
        height: height,
        format: answer['format'] as String? ?? '',
        bytes: answer['bytes'] as Uint8List?,
      );
    } on MissingPluginException {
      _complainOnce(
        'Канала «$channelName» в этом приложении нет: картинку, которую не '
        'умеет Flutter, показать нечем. Раннер собирается заново — горячей '
        'перезагрузки для него мало.',
      );
      return null;
    } on PlatformException catch (error) {
      _complainOnce('Раннер отказал в разборе картинки: ${error.message}');
      return null;
    }
  }

  /// Жаловаться один раз за сеанс: листание каталога снимков задаёт этот вопрос
  /// на каждый файл, и жалоба на каждый превратила бы журнал в шум.
  void _complainOnce(String message) {
    if (_complained) {
      return;
    }
    _complained = true;
    Logecom.createLogger('SystemImages').warn(message);
  }

  bool _complained = false;
}
