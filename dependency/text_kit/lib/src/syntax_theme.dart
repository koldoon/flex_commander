import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:flutter/painting.dart';

/// Класс токена highlight.js → стиль оформления.
///
/// Живёт в наборе, а не в модуле просмотрщика: подсвеченный текст показывают
/// двое — просмотрщик и редактор, — и краситься он обязан одинаково. Ключи
/// здесь строковые, поэтому знать про саму библиотеку подсветки набору не
/// нужно.
///
/// Названо только то, что действительно различается на глаз: просмотрщик не
/// среда разработки, и сорок видов токенов в нём различать незачем. Всё
/// остальное рисуется обычным цветом строки.
Map<String, TextStyle> syntaxTheme(FcColors colors, TextStyle base) {
  TextStyle of(Color color) => base.copyWith(color: color);

  final keyword = of(colors.syntaxKeyword);
  final type = of(colors.syntaxType);
  final literal = of(colors.syntaxLiteral);
  final meta = of(colors.syntaxMeta);
  final string = of(colors.syntaxString);
  final comment = of(colors.syntaxComment);

  return {
    'keyword': keyword,
    'selector-tag': keyword,
    'section': keyword,
    'string': string,
    'meta-string': string,
    'regexp': string,
    'char.escape': string,
    'number': of(colors.syntaxNumber),
    'comment': comment,
    'quote': comment,
    'doctag': comment,
    'type': type,
    'title': type,
    'title.class_': type,
    'title.function_': type,
    'class-title': type,
    'name': type,
    'literal': literal,
    'built_in': literal,
    'symbol': literal,
    'variable.language_': literal,
    'meta': meta,
    'attr': meta,
    'attribute': meta,
    'selector-attr': meta,
    'selector-class': meta,
    'selector-id': meta,
    'template-variable': meta,
    'subst': base,
  };
}
