import 'dart:io';

import 'package:flutter/widgets.dart';

/// Картинки с диска — те, что назвали правилами.
///
/// Растр и только растр (`png`, `jpeg`, `webp`, `bmp`): их декодирует сам
/// Flutter, и новых зависимостей работа не приносит
/// (`docs/spec/file-icons.md`, §4).
class PictureFiles {
  PictureFiles({String? home}) : _home = home ?? _homeOfSystem();

  final String? _home;

  /// Путь → чем рисовать; null — файла нет, и правило с ним пропускается.
  ///
  /// Ответ запоминается, в том числе отрицательный: строка перерисовывается по
  /// многу раз в секунду при прокрутке, и стучаться на диск на каждую
  /// перерисовку нельзя. Цена — появившаяся картинка подхватится со следующего
  /// запуска; для файла, названного в настройках, это честный размен.
  ImageProvider? of(String path) {
    final known = _cache[path];
    if (known != null || _cache.containsKey(path)) {
      return known;
    }

    final file = File(expand(path));
    final picture = file.existsSync() ? FileImage(file) : null;
    _cache[path] = picture;
    return picture;
  }

  /// `~` в начале — домашний каталог.
  ///
  /// Писать `/Users/koldoon/...` в файле, который человек носит между
  /// машинами, — значит один раз переехать и потерять все иконки.
  String expand(String path) {
    final home = _home;
    if (home == null || home.isEmpty || !path.startsWith('~')) {
      return path;
    }
    if (path == '~') {
      return home;
    }
    return path.startsWith('~/') ? '$home${path.substring(1)}' : path;
  }

  final Map<String, ImageProvider?> _cache = {};

  static String? _homeOfSystem() {
    final environment = Platform.environment;
    return environment['HOME'] ?? environment['USERPROFILE'];
  }
}
