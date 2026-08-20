import 'dart:io';
import 'dart:ui' as ui;

import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_text_kit/fc_text_kit.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Сетка строк в просмотрщике и редакторе.
///
/// `re_editor` раскладывает абзац со струной (`forceStrutHeight: true`), а
/// разносит абзацы по вертикали шагом `TextPainter.preferredLineHeight`. В
/// апстриме этот шаг мерился **без** струны, причём в двух местах сразу, и обе
/// величины расходились со строкой: она стояла реже, чем занимала место. Отсюда
/// и полосы в выделении, и отскок прокрутки — разница копилась в поправку к
/// положению. Наша копия меряет шаг той же струной
/// (`dependency/re_editor/README.md`), а высоту строки приложение задаёт само —
/// [textLineHeight].
///
/// Меряется настоящими шрифтами приложения: у тестового шрифта метрики свои, и
/// на нём расхождения не видно вовсе.
void main() {
  // Оба шрифта, что лежат в проекте: моноширинный для текста и обычный — на
  // случай, если однажды тему переведут на него. Согласованность сетки от
  // шрифта зависеть не должна, и этот перебор проверяет именно её.
  const Map<String, String> fonts = {'Consolas': 'consola.ttf', 'Ubuntu': 'Ubuntu-R.ttf'};
  final double fontSize = const DefaultMetrics().fontSize;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final MapEntry<String, String> entry in fonts.entries) {
      final FontLoader loader = FontLoader(entry.key)
        ..addFont(File('assets/fonts/${entry.value}').readAsBytes().then(ByteData.sublistView));
      await loader.load();
    }
  });

  TextStyle styleWith(String family, double? height) =>
      TextStyle(fontFamily: family, fontSize: fontSize, height: height);

  StrutStyle strutWith(String family, double height) =>
      StrutStyle(fontSize: fontSize, fontFamily: family, height: height, forceStrutHeight: true);

  /// Шаг сетки: так его меряет наша копия библиотеки — обеими мерками.
  double gridStep(String family, double height) =>
      (TextPainter(textDirection: TextDirection.ltr, strutStyle: strutWith(family, height))
        ..text = TextSpan(text: '0', style: styleWith(family, height))).preferredLineHeight;

  /// Абзац из трёх строк, построенный ровно как в библиотеке.
  ui.Paragraph paragraphWith(String family, double height) {
    final ui.ParagraphBuilder builder = ui.ParagraphBuilder(
      styleWith(family, height).getParagraphStyle(
        textAlign: TextAlign.left,
        textDirection: TextDirection.ltr,
        strutStyle: strutWith(family, height),
      ),
    );
    TextSpan(text: 'aaa\nbbb\nccc', style: styleWith(family, height)).build(builder);
    return builder.build()..layout(const ui.ParagraphConstraints(width: 400));
  }

  for (final String family in fonts.keys) {
    group(family, () {
      test('сетка сходится с раскладкой: шаг равен высоте строки в абзаце', () {
        // Главное свойство починки, и оно не про шрифт: обе величины меряются
        // одной струной, а `forceStrutHeight` делает строку ровно такой.
        expect(gridStep(family, textLineHeight), closeTo(paragraphWith(family, textLineHeight).height / 3, 0.01));
      });

      test('глифы не убегают из строки сетки', () {
        // Прямоугольник выделения наша копия растягивает на всю строку сетки, и
        // важно, что глифы держатся в ней: у Consolas — с запасом
        // ([0.11..18.00] в сетке [0..18]), у Ubuntu — с выходом на 0.43 точки
        // вверх. Выход в доли точки безобиден и, главное, **не копится**: он
        // одинаков в каждой строке. Копилось бы — поехала бы вся раскладка, и
        // это ловит соседний тест.
        final ui.Paragraph paragraph = paragraphWith(family, textLineHeight);
        final double step = gridStep(family, textLineHeight);

        for (int line = 0; line < 3; line++) {
          final int start = line * 4;
          final Rect box =
              paragraph.getBoxesForRange(start, start + 3, boxHeightStyle: ui.BoxHeightStyle.max).first.toRect();

          expect(box.top - line * step, greaterThan(-1));
          expect(box.bottom - (line + 1) * step, lessThan(1));
        }
      });

      test('наш множитель просторнее естественной строки шрифта', () {
        // `forceStrutHeight` делает строку ровно такой, как сказано, и шрифту с
        // высокой собственной строкой срежет верх и низ. Запас нужен любому
        // шрифту, на который однажды переведут тему.
        final double natural =
            (TextPainter(textDirection: TextDirection.ltr)
              ..text = TextSpan(text: '0', style: styleWith(family, null))).preferredLineHeight;

        expect(gridStep(family, textLineHeight), greaterThanOrEqualTo(natural));
      });
    });
  }

  test('интервал остался прежним: тот же шаг, что до починки', () {
    // Как шаг мерился в апстриме: без струны и с его умолчанием `1.4`.
    final double before =
        (TextPainter(textDirection: TextDirection.ltr)
          ..text = TextSpan(text: '0', style: styleWith('Consolas', 1.4))).preferredLineHeight;

    expect(gridStep('Consolas', textLineHeight), before);
  });
}
