import 'dart:io';
import 'dart:ui' as ui;

import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Сетка строк в просмотрщике и редакторе.
///
/// `re_editor` раскладывает абзац со струной (`forceStrutHeight: true`), а
/// разносит абзацы по вертикали шагом `TextPainter.preferredLineHeight`. В
/// апстриме этот шаг мерился **без** струны, и две величины расходились:
/// строки стояли реже, чем занимали место, — между ними оставалась полоса
/// фона, которую видно при выделении мышью. Наша копия библиотеки меряет шаг
/// той же струной (`dependency/re_editor/README.md`), а высоту строки
/// приложение задаёт само — [codeFontHeight].
///
/// Тест меряет настоящим шрифтом приложения: у тестового шрифта метрики свои,
/// и на нём расхождения не видно вовсе.
void main() {
  const String family = 'Consolas';
  final double fontSize = const DefaultMetrics().fontSize;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final FontLoader loader = FontLoader(family)
      ..addFont(File('assets/fonts/consola.ttf').readAsBytes().then(ByteData.sublistView));
    await loader.load();
  });

  TextStyle styleWith(double height) => TextStyle(fontFamily: family, fontSize: fontSize, height: height);

  StrutStyle strutWith(double height) =>
      StrutStyle(fontSize: fontSize, fontFamily: family, height: height, forceStrutHeight: true);

  /// Шаг сетки: так его меряет наша копия библиотеки.
  double gridStep(double height) =>
      (TextPainter(textDirection: TextDirection.ltr, strutStyle: strutWith(height))
        ..text = TextSpan(text: '0', style: styleWith(height))).preferredLineHeight;

  /// Абзац из трёх строк, построенный ровно как в библиотеке.
  ui.Paragraph paragraphWith(double height) {
    final ui.ParagraphBuilder builder = ui.ParagraphBuilder(
      styleWith(
        height,
      ).getParagraphStyle(textAlign: TextAlign.left, textDirection: TextDirection.ltr, strutStyle: strutWith(height)),
    );
    TextSpan(text: 'aaa\nbbb\nccc', style: styleWith(height)).build(builder);
    return builder.build()..layout(const ui.ParagraphConstraints(width: 400));
  }

  test('сетка сходится с раскладкой: шаг равен высоте строки в абзаце', () {
    expect(gridStep(codeFontHeight), closeTo(paragraphWith(codeFontHeight).height / 3, 0.01));
  });

  test('интервал остался прежним: тот же шаг, что до починки', () {
    // Как шаг мерился в апстриме: без струны и с его умолчанием `1.4`.
    final double before =
        (TextPainter(textDirection: TextDirection.ltr)
          ..text = TextSpan(text: '0', style: styleWith(1.4))).preferredLineHeight;
    expect(gridStep(codeFontHeight), before);
  });

  test('глифы укладываются в строку сетки', () {
    // Прямоугольник выделения наша копия растягивает на всю строку сетки.
    // Это верно, только если глифы из неё не торчат.
    final ui.Paragraph paragraph = paragraphWith(codeFontHeight);
    final double step = gridStep(codeFontHeight);

    for (int line = 0; line < 3; line++) {
      final int start = line * 4;
      final Rect box =
          paragraph.getBoxesForRange(start, start + 3, boxHeightStyle: ui.BoxHeightStyle.max).first.toRect();
      expect(box.top, greaterThanOrEqualTo(line * step - 0.01));
      expect(box.bottom, lessThanOrEqualTo((line + 1) * step + 0.01));
    }
  });
}
