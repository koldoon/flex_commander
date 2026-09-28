import 'package:fc_text_kit/fc_text_kit.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/re_highlight.dart';

import 'markdown_style.dart';

/// Врезка кода в свёрстанном документе — с подсветкой и, если надо, с причиной.
///
/// Рисует её этот виджет, а не библиотека: тег `pre` она заворачивает в рамку
/// безусловно, и диаграмма получила бы рамку от врезки кода
/// (`docs/spec/markdown-viewer.md`, §4). Заодно появилась подсветка, которой во
/// врезках не было **нигде**: библиотека отдаёт подсветке только текст, без
/// языка, и по языку красить ей нечем.
class FcCodeBlock extends StatelessWidget {
  const FcCodeBlock({super.key, required this.source, this.language, this.note});

  /// Текст врезки как он написан.
  final String source;

  /// Язык из info-строки; null или незнакомый — красим одним цветом.
  final String? language;

  /// Почему вместо картинки виден текст; null — врезка как врезка.
  ///
  /// Стоит **над** текстом, а не под ним: причина объясняет, почему здесь
  /// текст, и прочитать её надо до текста, а не после.
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = FcTheme.of(context);
    final style = theme.dialogTextStyle.copyWith(
      fontFamily: theme.fonts.fixed,
      fontFamilyFallback: theme.fonts.fixedFallback,
    );

    final body = Container(
      width: double.infinity,
      padding: EdgeInsets.all(theme.metrics.dialogPadding),
      decoration: fcCodeBlockDecoration(theme),
      // Длинная строка кода не переносится, а уезжает вбок: перенос в коде
      // врёт о том, где кончается строка.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text.rich(_spanOf(source, language, style, theme)),
      ),
    );

    if (note case final reason?) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: theme.metrics.dialogLineGap),
            child: Text(reason, style: theme.dialogTextStyle.copyWith(color: theme.colors.secondaryText)),
          ),
          body,
        ],
      );
    }

    return body;
  }
}

/// Подсвеченный текст врезки; язык незнаком — просто текст.
TextSpan _spanOf(String source, String? language, TextStyle base, FcTheme theme) {
  final named = language == null ? null : languageNamed(language);
  if (named == null) {
    return TextSpan(text: source, style: base);
  }

  final mode = builtinAllLanguages[named];
  if (mode == null) {
    return TextSpan(text: source, style: base);
  }

  // Языки заводятся по мере надобности: их под две сотни, и регистрировать
  // все ради одной врезки — работа на пустом месте.
  final highlight = _highlight;
  if (_registered.add(named)) {
    highlight.registerLanguage(named, mode);
  }

  final renderer = TextSpanRenderer(base, syntaxTheme(theme.colors, base));
  highlight.highlight(code: source, language: named).render(renderer);

  // Разбор мог не дать ничего — тогда показываем текст как есть, а не пустоту.
  return renderer.span ?? TextSpan(text: source, style: base);
}

final Highlight _highlight = Highlight();
final Set<String> _registered = <String>{};
