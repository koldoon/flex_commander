import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/widgets.dart';

/// Иконки оформления по умолчанию — глифы FontAwesome, как в референсе
/// (`resources/styles/icon.as`).
class DefaultIcons extends FcIcons {
  const DefaultIcons({this.fontFamily = defaultFontFamily});

  /// Шрифт иконок по умолчанию — тот же, что в референсе.
  static const String defaultFontFamily = 'FontAwesome';

  @override
  final String fontFamily;

  @override
  IconData get folder => _icon(0xf07b);

  @override
  IconData get folderOpen => _icon(0xf114);

  @override
  IconData get link => _icon(0xf0c1);

  @override
  IconData get asterisk => _icon(0xf069);

  @override
  IconData get check => _icon(0xf00c);

  @override
  IconData get angleRight => _icon(0xf105);

  @override
  IconData get caretUp => _icon(0xf0d8);

  @override
  IconData get caretDown => _icon(0xf0d7);

  @override
  IconData get circleOutline => _icon(0xf10c);

  @override
  IconData get exclamation => _icon(0xf12a);

  // Анализатор предлагает сделать IconData константой — но именно этого мы и
  // не хотим: шрифт берётся у темы, а она известна только во время работы.
  // ignore: non_const_argument_for_const_parameter
  IconData _icon(int codePoint) => IconData(codePoint, fontFamily: fontFamily);
}
