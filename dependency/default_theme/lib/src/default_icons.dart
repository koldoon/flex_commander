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

  /// `x` из Phosphor Light, а не `fa-times` из FontAwesome: рядом стоит
  /// [help], и пара должна быть одной высоты и одной толщины линии. У Phosphor
  /// значки построены одной линией на общей сетке — у FontAwesome вопрос и
  /// крестик нарисованы под разную ширину и при одном кегле разъезжаются.
  /// Шрифт у обоих свой, из этого пакета, а не [fontFamily] темы.
  @override
  IconData get close => const IconData(0xe4f6, fontFamily: phosphorFamily, fontPackage: 'fc_default_theme');

  /// `question-mark` из Phosphor Light — пара к [close]; голый знак, а не
  /// `question` в круге. Номер — по шрифту, а не с сайта Phosphor: там
  /// нумерация другая, и U+E3E8 в этом шрифте — как раз `question` в круге.
  @override
  IconData get help => const IconData(0xe3e9, fontFamily: phosphorFamily, fontPackage: 'fc_default_theme');

  /// `fa-play`.
  @override
  IconData get play => _icon(0xf04b);

  /// `fa-pause`.
  @override
  IconData get pause => _icon(0xf04c);

  /// `fa-volume-up`.
  @override
  IconData get soundOn => _icon(0xf028);

  /// `fa-volume-off`.
  @override
  IconData get soundOff => _icon(0xf026);

  /// `fa-expand`.
  @override
  IconData get enterFullScreen => _icon(0xf065);

  /// `fa-compress`.
  @override
  IconData get exitFullScreen => _icon(0xf066);

  /// `fa-music`.
  @override
  IconData get music => _icon(0xf001);

  /// Семейство Phosphor Light в `pubspec.yaml` пакета.
  static const String phosphorFamily = 'PhosphorLight';

  // Анализатор предлагает сделать IconData константой — но именно этого мы и
  // не хотим: шрифт берётся у темы, а она известна только во время работы.
  // ignore: non_const_argument_for_const_parameter
  IconData _icon(int codePoint) => IconData(codePoint, fontFamily: fontFamily);
}
