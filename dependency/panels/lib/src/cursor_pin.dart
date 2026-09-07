import 'package:fc_api/fc_api.dart';

/// Строка под курсором, запомненная с прошлого показа.
///
/// Нужна одному: узнать **перестановку**. Строк столько же и под курсором та
/// же строка, а место у неё другое — значит список переставили (сортировкой,
/// переименованием), а не сменили. Тогда вид держит эту строку на том же месте
/// экрана: перестановку человек попросил, а вот терять из виду то, на что он
/// смотрит, не просил (`docs/spec/panel-views.md`, §9).
class CursorPin {
  String? _path;
  int _index = -1;
  int _count = -1;

  /// Откуда строка под курсором уехала перестановкой; null — не перестановка.
  int? movedFrom(List<FileEntry> rows, int cursor) {
    final path = _pathAt(rows, cursor);
    if (path == null || path != _path || rows.length != _count || cursor == _index) {
      return null;
    }
    return _index;
  }

  /// Запомнить, на чём стоит курсор сейчас.
  void remember(List<FileEntry> rows, int cursor) {
    _path = _pathAt(rows, cursor);
    _index = cursor;
    _count = rows.length;
  }

  /// Адрес строки под курсором; null — строки нет или адреса у неё нет.
  ///
  /// Пути нет у «..»: две такие строки не различить, а списки без общего
  /// адреса сравнивать нечем.
  static String? _pathAt(List<FileEntry> rows, int cursor) {
    if (cursor < 0 || cursor >= rows.length) {
      return null;
    }
    final path = rows[cursor].path;
    return path.isEmpty ? null : path;
  }
}
