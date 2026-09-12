import 'dart:io';

import 'package:path/path.dart' as p;

import 'app_build.dart';
import 'app_version.dart';
import 'package:flutter/services.dart';
import 'package:logecom/logecom.dart';

/// Что приложение знает о себе — спрошенное у раннера.
///
/// Версия лежит в `Info.plist`, путь к бандлу знает только сам бандл, а
/// архитектуру — тот двоичный файл, который собрали. Из Flutter не видно ни
/// одного из трёх, поэтому здесь канал (`docs/spec/self-update.md`, §7).
///
/// Сведения спрашиваются **один раз**: между запусками они не меняются, а
/// меняться на ходу им и вовсе не с чего.
class ChannelAppBuild implements AppBuild {
  ChannelAppBuild({MethodChannel? channel}) : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'flex_commander/build';

  final MethodChannel _channel;

  AppVersion? _version;
  String _bundlePath = '';
  String _architecture = '';
  bool _asked = false;

  /// Где мы лежим — по пути исполняемого файла, без всякого канала.
  ///
  /// `…/flex_commander.app/Contents/MacOS/flex_commander` — значит бандл на
  /// три уровня выше. Пусто — приложение запущено не из бандла: так живут
  /// проверки и `flutter run`.
  static String bundleOf(String executable) {
    final parts = p.split(executable);
    final at = parts.lastIndexWhere((part) => part.endsWith('.app'));
    return at < 0 ? '' : p.joinAll(parts.take(at + 1));
  }

  /// Спросить раннера. Без этого остальное отвечает «не знаю» — и обновление
  /// честно не предлагается.
  ///
  /// **Канал зовётся только из бандла.** Вне его раннера нет вовсе, и вопрос
  /// остался бы без ответа: в проверках такой вызов не отвечает никогда, а
  /// ждать его — значит подвесить запуск.
  Future<void> load() async {
    if (_asked) {
      return;
    }
    _asked = true;
    _bundlePath = bundleOf(Platform.resolvedExecutable);
    if (_bundlePath.isEmpty) {
      return;
    }
    try {
      final info = await _channel.invokeMapMethod<String, Object?>('info');
      if (info == null) {
        return;
      }
      _version = AppVersion.parse(info['version'] as String? ?? '');
      // Путь из раннера точнее нашего счёта по частям: его он знает у себя.
      _bundlePath = (info['bundlePath'] as String?)?.isNotEmpty == true ? info['bundlePath'] as String : _bundlePath;
      _architecture = info['architecture'] as String? ?? '';
    } on PlatformException catch (error) {
      // Раннер без канала — это сборка, собранная не нами: обновляться ей
      // неоткуда, но работать это не мешает.
      Logecom.createLogger('AppBuild').warn('Сведения о сборке недоступны: ${error.message}');
    } on MissingPluginException {
      Logecom.createLogger('AppBuild').warn('Канал сведений о сборке не отвечает');
    }
  }

  @override
  AppVersion? get version => _version;

  @override
  String get bundlePath => _bundlePath;

  @override
  String get architecture => _architecture;

  /// Можно ли подменить себя.
  ///
  /// Проверяется право писать в **родительский каталог**, а не в сам бандл:
  /// подмена — это переименование каталога целиком, и решает его тот, в ком он
  /// лежит. Приложение в `/Applications` обычно наше, а запущенное прямо из
  /// dmg — на томе только для чтения, и обновляться ему некуда.
  @override
  bool get canReplaceItself {
    if (_bundlePath.isEmpty) {
      return false;
    }
    final parent = Directory(_bundlePath).parent;
    // Пробным файлом, а не разбором прав: у сетевого тома, образа и защищённого
    // системой каталога права выглядят по-разному, а ответ нужен один — можно
    // или нет.
    final probe = File('${parent.path}/.flex_commander_update_probe');
    try {
      probe.writeAsStringSync('');
      probe.deleteSync();
      return true;
    } on FileSystemException {
      return false;
    }
  }
}
