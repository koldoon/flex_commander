import 'package:fc_ui_api/fc_ui_api.dart';

/// Шрифты поверх темы — тем же способом, что цвета и размеры
/// ([OverlayColors]).
///
/// Ролей три, и каждая своего рода: имя шрифта интерфейса, имя шрифта списка и
/// список запасных. Картой их не сложить — списку в ней места нет.
class OverlayFonts implements FcFonts {
  const OverlayFonts(this.base, {this.uiFont, this.fixedFont, this.listFont, this.fallback});

  final FcFonts base;

  /// Своё имя шрифта; null — берётся у темы.
  ///
  /// Пустая строка — это **тоже своё**: она означает «шрифт по умолчанию, тот,
  /// что выберет система». Поэтому «своего нет» сказано null, а не пустотой.
  final String? uiFont;
  final String? fixedFont;
  final String? listFont;

  /// Свой список запасных; null — берётся у темы. Пустой список — тоже своё:
  /// «подставляй что хочешь».
  final List<String>? fallback;

  @override
  String get ui => uiFont ?? base.ui;

  @override
  String get fixed => fixedFont ?? base.fixed;

  /// Шрифт списка, если его не назвали своим, **идёт за моноширинным** — там,
  /// где у темы он выведен из моноширинного. Иначе своя тема с поправленным
  /// моноширинным сменила бы шрифт панелей сама собой: раньше это была одна
  /// роль, и правили её ради списка (`docs/spec/list-font.md`, §2).
  @override
  String get list => listFont ?? (base.list == base.fixed ? fixed : base.list);

  @override
  List<String> get fixedFallback => fallback ?? base.fixedFallback;
}
