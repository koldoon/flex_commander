import 'dart:convert';
import 'dart:typed_data';

import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_markdown_kit/fc_markdown_kit.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

/// Картинка 1×1 в png — настоящая, чтобы её было чем распаковать.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

const String _svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 8 8"><rect width="8" height="8"/></svg>';

/// Картинки в документе: читаются через источник, а не через `dart:io`.
void main() {
  Future<void> pump(WidgetTester tester, String source, {FcImageResolver? resolve}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [
            FcTheme(colors: DefaultColors(), metrics: DefaultMetrics(), icons: DefaultIcons(), fonts: DefaultFonts()),
          ],
        ),
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: FcMarkdownView(document: FcMarkdownDocument.parse(source), resolveImage: resolve),
          ),
        ),
      ),
    );
    // Чтение у разрешителя асинхронное: даём ему договорить.
    await tester.pumpAndSettle();
  }

  testWidgets('относительный путь читается разрешителем', (tester) async {
    String? asked;
    await pump(
      tester,
      '![схема](doc/shot.png)\n',
      resolve: (path) async {
        asked = path;

        return _png;
      },
    );

    expect(asked, 'doc/shot.png');
    // `skipOffstage: false`: картинка в тесте 1×1, абзац с ней почти нулевой
    // высоты, и обычный поиск считает её невидимой.
    expect(find.byType(Image, skipOffstage: false), findsOneWidget);
  });

  testWidgets('вектор рисуется вектором, а не рамкой', (tester) async {
    await pump(tester, '![значок](logo.svg)\n', resolve: (path) async => Uint8List.fromList(utf8.encode(_svg)));

    expect(find.byType(SvgPicture), findsOneWidget);
  });

  testWidgets('прочесть не удалось — подпись, а не пустое место', (tester) async {
    await pump(tester, '![схема сборки](missing.png)\n', resolve: (path) async => throw StateError('нет такого'));

    expect(find.text('схема сборки'), findsOneWidget);
  });

  testWidgets('читать нечем — тоже подпись', (tester) async {
    await pump(tester, '![схема сборки](missing.png)\n');

    expect(find.text('схема сборки'), findsOneWidget);
  });

  testWidgets('удалённую картинку не забираем: показ файла не ходит в сеть', (tester) async {
    var asked = false;
    await pump(
      tester,
      '![значок](https://img.shields.io/badge.svg)\n',
      resolve: (path) async {
        asked = true;

        return _png;
      },
    );

    expect(asked, isFalse, reason: 'за сеть никто не просил');
    expect(find.textContaining('img.shields.io'), findsOneWidget);
  });

  testWidgets('без подписи видно хотя бы адрес', (tester) async {
    await pump(tester, '![](missing.png)\n', resolve: (path) async => throw StateError('нет такого'));

    expect(find.text('missing.png'), findsOneWidget);
  });
}
