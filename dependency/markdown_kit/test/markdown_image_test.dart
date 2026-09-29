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

  group('картинка не схлопывается на прокрутке', () {
    /// Настоящая картинка 40×30: у однопиксельной высоту не измерить.
    final Uint8List wide = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAACgAAAAeCAIAAADRv8uKAAAAKklEQVR4nO3NMQ0AAAgDsAmb/yALGXA0'
      '6d9MeyJisVgsFovFYrFYLP4bL9HP3Ew1mJ9PAAAAAElFTkSuQmCC',
    );

    /// Длинный документ: картинка сверху, под ней есть куда уехать.
    final source = '![схема](shot.png)\n\n${[for (var i = 0; i < 60; i++) 'Абзац \$i.'].join('\n\n')}';

    testWidgets('читается один раз на документ, а не на каждый показ', (tester) async {
      var reads = 0;
      await pump(
        tester,
        source,
        resolve: (path) async {
          reads++;

          return wide;
        },
      );

      expect(reads, 1);

      final position = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      position.jumpTo(900);
      await tester.pumpAndSettle();
      position.jumpTo(0);
      await tester.pumpAndSettle();

      expect(reads, 1, reason: 'блок вернулся в окно — читать заново нечего');
    });

    testWidgets('вернувшись в окно, занимает своё место тем же кадром', (tester) async {
      await pump(tester, source, resolve: (path) async => wide);

      final position = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      position.jumpTo(900);
      await tester.pumpAndSettle();

      position.jumpTo(0);
      // Один кадр, без ожидания: без хранилища здесь была бы пустота нулевой
      // высоты, и всё, что ниже, прыгнуло бы вверх.
      await tester.pump();

      expect(find.byType(Image, skipOffstage: false), findsOneWidget);
      expect(tester.getSize(find.byType(Image, skipOffstage: false)).height, greaterThan(0));
    });
  });

  group('хранилище картинок', () {
    test('читает один раз на ключ', () async {
      final store = FcImageStore();
      var reads = 0;
      Future<Uint8List> read() async {
        reads++;

        return Uint8List(1);
      }

      await store.read('a', read);
      await store.read('a', read);

      expect(reads, 1);
      expect(store.ready('a'), isNotNull);
    });

    test('помнит занятую высоту, а нулевую не помнит', () {
      final store = FcImageStore();

      expect(store.heightOf('a'), isNull);
      store.remember('a', 120);
      expect(store.heightOf('a'), 120);
      store.remember('a', 0);
      expect(store.heightOf('a'), 120, reason: 'ноль — это ещё не показывали, а не «высота ноль»');
    });

    test('смена документа всё забывает', () async {
      final store = FcImageStore();
      await store.read('a', () async => Uint8List(1));
      store.remember('a', 120);

      store.clear();

      expect(store.ready('a'), isNull);
      expect(store.heightOf('a'), isNull);
    });
  });
}
