import 'dart:ui' as ui;

import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_ui_api/fc_ui_api.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Поле цвета: образец, `#AARRGGBB` и палитра за образцом
/// (`docs/spec/theme-editor.md`, §4).
void main() {
  late TextEditingController editor;

  setUp(() => editor = TextEditingController());
  tearDown(() => editor.dispose());

  Future<Color?> pump(WidgetTester tester, Color value, {List<Color> palette = const [], double? fieldWidth}) async {
    Color? chosen;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: const [
            FcTheme(colors: DefaultColors(), metrics: DefaultMetrics(), icons: DefaultIcons(), fonts: DefaultFonts()),
          ],
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: StatefulBuilder(
                builder:
                    (context, setState) => FcColorField(
                      controller: editor..text = editor.text.isEmpty ? formatColor(value) : editor.text,
                      value: chosen ?? value,
                      palette: palette,
                      fieldWidth: fieldWidth,
                      onChanged: (color) => setState(() => chosen = color),
                    ),
              ),
            ),
          ),
        ),
      ),
    );
    return chosen;
  }

  /// Образец — квадрат слева: щёлкать по полю ввода незачем, там набирают.
  Future<void> tapSwatch(WidgetTester tester) async {
    await tester.tapAt(tester.getTopLeft(find.byType(FcColorField)) + const Offset(8, 8));
    await tester.pumpAndSettle();
  }

  testWidgets('набранный цвет применяется, недописанный — нет', (tester) async {
    await pump(tester, const Color(0xFF2D6CDF));

    await tester.enterText(find.byType(FcTextField), '#FF2');
    await tester.pump();
    // Недописанное значение цветом не стало: ругаться посреди набора хуже, чем
    // подождать.
    expect(find.byType(FcColorField), findsOneWidget);

    await tester.enterText(find.byType(FcTextField), '#80FFFFFF');
    await tester.pump();

    expect(tester.widget<FcColorField>(find.byType(FcColorField)).value, const Color(0x80FFFFFF));
  });

  testWidgets('щелчок по образцу раскрывает палитру, выбранное едет в поле', (tester) async {
    const palette = [Color(0xFF2D6CDF), Color(0xFFDE1D2E)];
    await pump(tester, const Color(0xFF2D6CDF), palette: palette);

    await tapSwatch(tester);

    // Цвет и есть своя запись: имени у него нет, и в палитре он назван собой.
    expect(find.text('#FFDE1D2E', findRichText: true), findsOneWidget);

    await tester.tap(find.text('#FFDE1D2E', findRichText: true));
    await tester.pumpAndSettle();

    expect(tester.widget<FcColorField>(find.byType(FcColorField)).value, const Color(0xFFDE1D2E));
    // Набранное показывает выбранное: иначе в поле осталось бы прежнее.
    expect(editor.text, '#FFDE1D2E');
  });

  testWidgets('палитра шириной с поле, а не с образец и не с колонку', (tester) async {
    const palette = [Color(0xFF2D6CDF), Color(0xFFDE1D2E)];
    await pump(tester, const Color(0xFF2D6CDF), palette: palette, fieldWidth: 100);

    await tapSwatch(tester);

    final dropdown = find.ancestor(of: find.byType(FcPickList), matching: find.byType(Container)).first;
    final width = tester.getSize(dropdown).width;

    // Под образцом в строку палитры помещалось три знака из девяти; во всю
    // строку — палитра раскрывалась на всю колонку окна.
    expect(width, greaterThan(100));
    expect(width, lessThan(tester.getSize(find.byType(FcColorField)).width));
    // От левого края образца до правого края поля.
    expect(tester.getTopLeft(dropdown).dx, closeTo(tester.getTopLeft(find.byType(FcColorField)).dx, 0.5));
  });

  /// Образец, нарисованный в картинку: только так видно, что вылезает по краям.
  Future<List<int>> swatchPixels(WidgetTester tester, {double side = 28}) async {
    final painter = tester.widget<CustomPaint>(
      find.descendant(of: find.byType(FcColorField), matching: find.byType(CustomPaint)).first,
    );
    final bytes = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      painter.painter!.paint(Canvas(recorder), Size(side, side));
      final image = await recorder.endRecording().toImage(side.round(), side.round());
      final data = await image.toByteData();
      image.dispose();
      return data!.buffer.asUint8List();
    });
    return bytes!;
  }

  testWidgets('под непрозрачным цветом белой подложки нет — даже в углах', (tester) async {
    // Скругление образца рисует кисть, а не обрезка снаружи: сглаженная обрезка
    // берёт покрытие наполовину **каждым слоем порознь**, и белая подложка
    // шахматки проступала сквозь цвет светлыми уголками — их и принимали за
    // обводку.
    await pump(tester, const Color(0xFF011130));

    final pixels = await swatchPixels(tester);
    for (var at = 0; at < pixels.length; at += 4) {
      final (r, g, b, a) = (pixels[at], pixels[at + 1], pixels[at + 2], pixels[at + 3]);
      if (a == 0) {
        continue;
      }
      // Ничего светлее самого цвета: белое здесь могло взяться только из-под
      // него. Сравнение на непрозрачных пикселях — прозрачные это край
      // скругления, там просто ничего не нарисовано.
      expect(r + g + b, lessThanOrEqualTo(0x01 + 0x11 + 0x30), reason: 'белое просвечивает сквозь цвет');
    }
  });

  testWidgets('под просвечивающим цветом шахматка остаётся: иначе он неотличим от чёрного', (tester) async {
    await pump(tester, const Color(0x00000000));

    final pixels = await swatchPixels(tester);
    // В середине образца — белая клетка или серая: `#00000000` и `#FF000000`
    // обязаны выглядеть по-разному.
    final middle = ((28 ~/ 2) * 28 + 28 ~/ 2) * 4;
    expect(pixels[middle] + pixels[middle + 1] + pixels[middle + 2], greaterThan(0x80 * 3));
  });

  testWidgets('без палитры образец не нажимается: нажатие без ответа — промах', (tester) async {
    await pump(tester, const Color(0xFF2D6CDF));

    await tapSwatch(tester);

    expect(find.byType(FcPickList), findsNothing);
  });
}
