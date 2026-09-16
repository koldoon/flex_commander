import 'package:fc_default_theme/fc_default_theme.dart';
import 'package:fc_ui_kit/fc_ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Плашка пути обрезает **сама**, значит и мерить обязана тем, чем рисует.
void main() {
  const metrics = DefaultMetrics();
  const path = '/Users/koldoon/Library/Application Support/AIR/Volumes/Data/Applications/AIRSDKManager.app';

  /// Окружение материальное и со своей разрядкой — как в живом приложении:
  /// `Text` со стилем-наследником подмешивает её к нашему стилю.
  Future<void> pumpPlate(
    WidgetTester tester, {
    required double width,
    double letterSpacing = 2,
    Widget? leading,
    double leadingWidth = 0,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          textTheme: TextTheme(bodyMedium: TextStyle(letterSpacing: letterSpacing)),
          extensions: const [
            FcTheme(colors: DefaultColors(), metrics: metrics, icons: DefaultIcons(), fonts: DefaultFonts()),
          ],
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              height: 300,
              child: FcPanelFrame(
                header: FcPathPlate(path: path, leading: leading, leadingWidth: leadingWidth),
                child: const SizedBox(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('длинный путь не вылезает за плашку', (tester) async {
    await pumpPlate(tester, width: 393);

    final plate = tester.getRect(find.byType(FcPathPlate));
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: find.byType(FcPathPlate), matching: find.byType(Text)),
    );

    // Ширина **набранной** строки, а не коробки: вылезший текст обрезается по
    // коробке, и по ней беда не видна. Помещается — значит помещается вместе с
    // полями плашки и её обводкой.
    final inner = plate.width - 2 * (metrics.labelPadding + metrics.strokeWidth);
    expect(paragraph.getMaxIntrinsicWidth(double.infinity), lessThanOrEqualTo(inner + 0.01));
  });

  testWidgets('обрезается голова, а не хвост: текущий каталог виден целиком', (tester) async {
    await pumpPlate(tester, width: 393);

    final shown =
        (tester.widget(find.descendant(of: find.byType(FcPathPlate), matching: find.byType(Text))) as Text).data!;
    // Корень остаётся впереди многоточия: по нему видно, о каком месте речь
    // (`docs/spec/panel-crumbs.md`, §2).
    expect(shown, startsWith('/…'));
    expect(path, endsWith(shown.substring(2)), reason: 'конец пути потерян');
  });

  group('со слотом слева', () {
    /// Место под стрелки истории: плашка о них не знает, но ширину ей
    /// называют — иначе она отмерит путь по всей плашке, и конец пути уйдёт
    /// за край (`docs/spec/session-history.md`, §9).
    const slot = SizedBox(width: 40, height: 12);

    testWidgets('путь по-прежнему обрезается с головы', (tester) async {
      await pumpPlate(tester, width: 393, leading: slot, leadingWidth: 40);

      final shown =
          (tester.widget(find.descendant(of: find.byType(FcPathPlate), matching: find.byType(Text))) as Text).data!;
      expect(shown, startsWith('/…'), reason: 'обрезали хвост вместо головы');
      expect(path, endsWith(shown.substring(2)), reason: 'конец пути потерян');
    });

    testWidgets('путь со слотом вместе не вылезают за плашку', (tester) async {
      await pumpPlate(tester, width: 393, leading: slot, leadingWidth: 40);

      final plate = tester.getRect(find.byType(FcPathPlate));
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: find.byType(FcPathPlate), matching: find.byType(Text)),
      );

      final inner = plate.width - 2 * (metrics.labelPadding + metrics.strokeWidth) - 40 - metrics.labelPadding;
      expect(paragraph.getMaxIntrinsicWidth(double.infinity), lessThanOrEqualTo(inner + 0.01));
    });
  });

  group('с припиской справа', () {
    /// Что просмотрщик картинок пишет о снимке.
    const about = '2560×1600';

    /// Имя длиннее, чем влезает, и **одним звеном**: так выглядит снимок с
    /// обоев — звенья отбросить уже нечего, и путь режется по буквам.
    const long = '/Users/koldoon/Pictures/beautiful-mountains-nature-wallpaper-hd-widescreen-original-3840.jpg';

    Future<void> pumpWithSuffix(WidgetTester tester, {required double width}) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: const [
              FcTheme(colors: DefaultColors(), metrics: metrics, icons: DefaultIcons(), fonts: DefaultFonts()),
            ],
          ),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                height: 300,
                child: const FcPanelFrame(header: FcPathPlate(path: long, trailing: about), child: SizedBox()),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('путь занимает всё, что осталось от приписки', (tester) async {
      // Прежде путь и приписка были гибкими оба, и плашка делилась пополам:
      // имя обрывалось на полуслове посреди свободного места.
      await pumpWithSuffix(tester, width: 1000);

      final texts = find.descendant(of: find.byType(FcPathPlate), matching: find.byType(Text));
      final shownPath = tester.getRect(texts.first);
      final shownAbout = tester.getRect(texts.last);
      final plate = tester.getRect(find.byType(FcPathPlate));

      final inner = plate.width - 2 * (metrics.labelPadding + metrics.strokeWidth);
      expect(
        shownPath.width + shownAbout.width,
        closeTo(inner, 2),
        reason: 'вдвоём они занимают плашку целиком, а не половину на каждого',
      );
      expect(
        shownPath.width,
        closeTo(inner - shownAbout.width, 2),
        reason: 'пути досталось всё остальное, а не половина плашки',
      );
    });

    testWidgets('набранный путь не вылезает за отведённое', (tester) async {
      await pumpWithSuffix(tester, width: 1000);

      final texts = find.descendant(of: find.byType(FcPathPlate), matching: find.byType(Text));
      final paragraph = tester.renderObject<RenderParagraph>(texts.first);
      final box = tester.getRect(texts.first);

      // Набранная строка шире коробки — это и есть обрыв на полуслове: текст
      // обрезается по краю, и многоточия у него нет.
      expect(paragraph.getMaxIntrinsicWidth(double.infinity), lessThanOrEqualTo(box.width + 0.5));
    });
  });

  testWidgets('короткому пути многоточие ни к чему', (tester) async {
    await pumpPlate(tester, width: 393);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: const [
            FcTheme(colors: DefaultColors(), metrics: metrics, icons: DefaultIcons(), fonts: DefaultFonts()),
          ],
        ),
        home: const Scaffold(
          body: Center(
            child: SizedBox(
              width: 393,
              height: 300,
              child: FcPanelFrame(header: FcPathPlate(path: '/home'), child: SizedBox()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('/home'), findsOneWidget);
  });
}
