import 'package:fc_api/fc_api.dart';

/// Шрифты оформления по умолчанию — те же, что в референсе
/// (`resources/styles/typo.css`).
///
/// Лежат в `assets/fonts` приложения, поэтому оно выглядит одинаково на любой
/// системе, а не только там, где эти шрифты установлены. Тема со своими
/// шрифтами приносит их своими ресурсами (`packages/<имя>/fonts/...`).
class DefaultFonts extends FcFonts {
  const DefaultFonts({this.ui = 'Ubuntu', this.fixed = 'Consolas'});

  @override
  final String ui;

  @override
  final String fixed;
}
