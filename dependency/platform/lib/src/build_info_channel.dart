import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:flutter/services.dart';
import 'package:logecom/logecom.dart';
import 'package:path/path.dart' as p;

/// Сведения о сборке — спрошенные у раннера.
///
/// Версия лежит в `Info.plist`, путь к бандлу знает только сам бандл, а
/// архитектуру — тот двоичный файл, который собрали. Из Flutter не видно ни
/// одного из трёх, поэтому здесь канал (`docs/spec/build-info.md`).
///
/// Спрашивается **один раз за запуск**: между запусками сведения не меняются, а
/// на ходу меняться им и вовсе не с чего.
class BuildInfoChannel {
  const BuildInfoChannel({MethodChannel channel = const MethodChannel(channelName)}) : _channel = channel;

  static const String channelName = 'flex_commander/build';

  final MethodChannel _channel;

  /// Где мы лежим — по пути исполняемого файла, без всякого канала.
  ///
  /// `…/flex_commander.app/Contents/MacOS/flex_commander` — значит бандл на три
  /// уровня выше. Пусто — приложение запущено не из бандла: так живут проверки
  /// и `flutter run`.
  static String bundleOf(String executable) {
    final parts = p.split(executable);
    final at = parts.lastIndexWhere((part) => part.endsWith('.app'));
    return at < 0 ? '' : p.joinAll(parts.take(at + 1));
  }

  /// Спросить раннера.
  ///
  /// **Канал зовётся только из бандла.** Вне его раннера нет вовсе, и вопрос
  /// остался бы без ответа: в проверках такой вызов не отвечает никогда, а
  /// ждать его — значит подвесить запуск.
  Future<BuildInfo> read() async {
    final bundlePath = bundleOf(Platform.resolvedExecutable);
    if (bundlePath.isEmpty) {
      return BuildInfo.unknown;
    }

    try {
      final info = await _channel.invokeMapMethod<String, Object?>('info');
      if (info == null) {
        return BuildInfo(bundlePath: bundlePath);
      }
      return BuildInfo(
        version: info['version'] as String? ?? '',
        build: info['build'] as String? ?? '',
        // Путь из раннера точнее нашего счёта по частям: его он знает у себя.
        bundlePath: (info['bundlePath'] as String?)?.isNotEmpty == true ? info['bundlePath']! as String : bundlePath,
        architecture: info['architecture'] as String? ?? '',
      );
    } on PlatformException catch (error) {
      // Раннер без канала — это сборка, собранная не нами: обновляться ей
      // неоткуда, но работать это не мешает.
      Logecom.createLogger('BuildInfo').warn('Сведения о сборке недоступны: ${error.message}');
    } on MissingPluginException {
      Logecom.createLogger('BuildInfo').warn('Канал сведений о сборке не отвечает');
    }
    return BuildInfo(bundlePath: bundlePath);
  }
}
