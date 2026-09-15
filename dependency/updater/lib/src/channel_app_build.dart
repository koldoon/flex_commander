import 'dart:io';

import 'package:fc_api/fc_api.dart';
import 'package:fc_platform/fc_platform.dart';

import 'app_build.dart';
import 'app_version.dart';

/// Что приложение знает о себе — глазами обновления.
///
/// Сами сведения читает платформа (`BuildInfoChannel`): версия лежит в
/// `Info.plist`, путь знает бандл, архитектуру — собранный двоичный файл
/// (`docs/spec/build-info.md`). Здесь к ним добавляется то, что нужно только
/// обновлению: разбор версии числами и право подменить себя.
class ChannelAppBuild implements AppBuild {
  ChannelAppBuild({BuildInfoChannel channel = const BuildInfoChannel()}) : _channel = channel;

  final BuildInfoChannel _channel;

  BuildInfo _info = BuildInfo.unknown;
  bool _asked = false;

  /// Спросить платформу. Без этого остальное отвечает «не знаю» — и обновление
  /// честно не предлагается.
  ///
  /// [known] — то, что приложение уже узнало о себе при запуске: второй раз
  /// канал не зовём, сведения между запросами не меняются.
  Future<void> load({BuildInfo known = BuildInfo.unknown}) async {
    if (_asked) {
      return;
    }
    _asked = true;
    _info = known.isKnown ? known : await _channel.read();
  }

  /// Прочитанное — как есть: его же показывают в справке и в отчёте об ошибке.
  BuildInfo get info => _info;

  @override
  AppVersion? get version => AppVersion.parse(_info.version);

  @override
  String get bundlePath => _info.bundlePath;

  @override
  String get architecture => _info.architecture;

  /// Можно ли подменить себя.
  ///
  /// Проверяется право писать в **родительский каталог**, а не в сам бандл:
  /// подмена — это переименование каталога целиком, и решает его тот, в ком он
  /// лежит. Приложение в `/Applications` обычно наше, а запущенное прямо из
  /// dmg — на томе только для чтения, и обновляться ему некуда.
  @override
  bool get canReplaceItself {
    final bundlePath = _info.bundlePath;
    if (bundlePath.isEmpty) {
      return false;
    }
    final parent = Directory(bundlePath).parent;
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
