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

  /// `fa-file-o` — лист бумаги с загнутым углом: контурный, как папка, и в
  /// одном с ней ряду по весу.
  @override
  IconData get file => _icon(0xf016);

  @override
  IconData get folderOpen => _icon(0xf114);

  @override
  IconData get link => _icon(0xf0c1);

  @override
  IconData get asterisk => _icon(0xf069);

  @override
  IconData get check => _icon(0xf00c);

  @override
  IconData get mixed => _icon(0xf068);

  @override
  IconData get angleLeft => _icon(0xf104);

  @override
  IconData get angleRight => _icon(0xf105);

  @override
  IconData get caretUp => _icon(0xf0d8);

  @override
  IconData get caretDown => _icon(0xf0d7);

  @override
  IconData get branchClosed => _icon(0xf105);

  @override
  IconData get branchOpen => _icon(0xf107);

  @override
  IconData get circleOutline => _icon(0xf10c);

  @override
  IconData get exclamation => _icon(0xf12a);

  @override
  IconData get home => _icon(0xf015);

  /// `fa-desktop` — монитор.
  @override
  IconData get desktop => _icon(0xf108);

  /// `fa-file-text-o` — контурный, в одном весе с [file].
  @override
  IconData get documents => _icon(0xf0f6);

  @override
  IconData get downloads => _icon(0xf019);

  /// `fa-th` — сетка, как Launchpad.
  @override
  IconData get applications => _icon(0xf00a);

  /// `fa-hdd-o` — диск.
  @override
  IconData get volume => _icon(0xf0a0);

  @override
  IconData get server => _icon(0xf233);

  /// `fa-archive` — ящик.
  @override
  IconData get archive => _icon(0xf187);

  // Анализатор предлагает сделать IconData константой — но именно этого мы и
  // не хотим: шрифт берётся у темы, а она известна только во время работы.
  // ignore: non_const_argument_for_const_parameter
  IconData _icon(int codePoint) => IconData(codePoint, fontFamily: fontFamily);
}
