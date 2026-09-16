import 'package:fc_api/fc_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';

/// Самое длинное имя каталога, померенное один раз на список.
///
/// По нему считают ширину столбца краткого вида и ширину плитки в сетке: оба
/// раза вопрос один — «сколько места просят имена». Общим местом, а не по
/// копии в каждом виде: два одинаковых замера однажды разойдутся, и разойдутся
/// они молча — просто столбцы станут разной ширины.
///
/// **Мерить на каждую отрисовку нельзя**: в каталоге бывают тысячи имён.
/// Список приходит значением и на каждое чтение новый — по нему и видно, что
/// мерить пора заново.
class WidestName {
  /// Дальше этого мерить незачем: имена такой длины всё равно обрежутся, а
  /// считать их — пробегать список до конца.
  static const double limit = 4000;

  List<FileEntry>? _list;
  double _width = 0;

  /// Ширина самого длинного имени — тем же набором, каким его нарисуют.
  double of(BuildContext context, List<FileEntry> entries, {required TextStyle style}) {
    if (identical(_list, entries)) {
      return _width;
    }
    _list = entries;
    _width = widestLabel(context, [for (final entry in entries) entry.name], style: style, limit: limit);
    return _width;
  }
}
